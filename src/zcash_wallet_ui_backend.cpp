#include "zcash_wallet_ui_backend.h"

#include <QJsonArray>
#include <QJsonDocument>

#include "logos_sdk.h"
#include "qrcodegen.hpp"

namespace {
QJsonObject parse(const QString &s) { return QJsonDocument::fromJson(s.toUtf8()).object(); }
QString compact(const QJsonValue &v) {
    if (v.isArray()) return QString::fromUtf8(QJsonDocument(v.toArray()).toJson(QJsonDocument::Compact));
    if (v.isObject()) return QString::fromUtf8(QJsonDocument(v.toObject()).toJson(QJsonDocument::Compact));
    return {};
}
QString stripOk(const QString &reply) { QJsonObject o = parse(reply); o.remove("ok"); return compact(o); }

constexpr qint64 kZatPerZec = 100000000;
constexpr qint64 kMaxZat = 21000000 * kZatPerZec;
constexpr int kReadPollMs = 3000;
constexpr int kJobPollMs = 750;
constexpr int kSendPollMs = 700;
constexpr int kHistoryMinGapMs = 10000;
constexpr int kPendingHistoryPollMs = 15000;
// The node module re-checks servers once a minute and says so by event; this poll is the backstop.
constexpr int kHealthPollMs = 30000;
// A live migration moves at most every 30 s and says so by event; this read is the backstop.
constexpr int kMigrationPollMs = 30000;
// A local_node() read lost for this long no longer holds up the next.
constexpr int kLocalNodeReadMs = 10000;

// Zatoshis arrive as JSON integers today; accept decimal strings too.
qint64 zat(const QJsonValue &v) { return v.isString() ? v.toString().toLongLong() : v.toInteger(); }

// Up to 8 decimals, trailing zeros trimmed: 123450000 -> "1.2345".
QString zec(qint64 z) {
    const bool negative = z < 0;
    if (negative) z = -z;
    QString out = QString::number(z / kZatPerZec);
    if (const qint64 frac = z % kZatPerZec) {
        QString f = QString::number(frac).rightJustified(8, QLatin1Char('0'));
        while (f.endsWith(QLatin1Char('0'))) f.chop(1);
        out += QLatin1Char('.');
        out += f;
    }
    if (negative) out.prepend(QLatin1Char('-'));
    return out;
}

// A ZEC decimal as zatoshis: digits, at most 8 decimals, above zero, within the supply.
qint64 parseZec(const QString &text, bool *valid) {
    *valid = false;
    const QString s = text.trimmed();
    const int dot = s.indexOf(QLatin1Char('.'));
    const QString whole = dot < 0 ? s : s.left(dot);
    const QString frac = dot < 0 ? QString() : s.mid(dot + 1);
    const auto digits = [](const QString &t) {
        for (const QChar c : t) if (c < QLatin1Char('0') || c > QLatin1Char('9')) return false;
        return true;
    };
    if ((whole.isEmpty() && frac.isEmpty()) || frac.size() > 8 || whole.size() > 8 || !digits(whole) || !digits(frac))
        return 0;
    const qint64 z = whole.toLongLong() * kZatPerZec + frac.leftJustified(8, QLatin1Char('0')).toLongLong();
    if (z <= 0 || z > kMaxZat) return 0;
    *valid = true;
    return z;
}

// Adds an "<key>Zec" display string beside each listed zatoshi field.
void addZec(QJsonObject &o, std::initializer_list<const char *> keys) {
    for (const char *k : keys) {
        const QString key = QString::fromLatin1(k);
        if (o.contains(key)) o.insert(key + QStringLiteral("Zec"), zec(zat(o.value(key))));
    }
}
QJsonArray mapObjects(const QJsonArray &in, std::initializer_list<const char *> keys) {
    QJsonArray out;
    for (const QJsonValue &v : in) { QJsonObject o = v.toObject(); addZec(o, keys); out.append(o); }
    return out;
}

QJsonObject withZec(QJsonObject b) {
    QJsonObject pools = b.value("pools").toObject();
    for (auto it = pools.begin(); it != pools.end(); ++it) {
        QJsonObject p = it.value().toObject();
        const qint64 spendable = zat(p.value("spendable")), total = zat(p.value("total"));
        p.insert("spendableZec", zec(spendable));
        p.insert("pendingZec", zec(total - spendable));
        p.insert("totalZec", zec(total));
        p.insert("uneconomicZec", zec(zat(p.value("uneconomic"))));
        it.value() = p;
    }
    b.insert("pools", pools);
    // `shielded` is the balance Send spends (Ironwood + Sapling); Orchard waits apart to migrate.
    const QJsonObject sh = b.value("shielded").toObject();
    const qint64 spendable = zat(sh.value("spendable")), total = zat(sh.value("total"));
    b.insert("spendPool", QJsonObject{{"spendable", spendable}, {"total", total}, {"pending", total - spendable},
                                      {"spendableZec", zec(spendable)}, {"totalZec", zec(total)},
                                      {"pendingZec", zec(total - spendable)}});
    QJsonObject orchard = b.value("orchardToMigrate").toObject();
    addZec(orchard, {"spendable", "total"});
    b.insert("orchardToMigrate", orchard);
    b.insert("transparentAddresses", mapObjects(b.value("transparentAddresses").toArray(), {"spendable", "total", "uneconomic"}));
    addZec(b, {"total", "shieldingThreshold"});
    return b;
}

QJsonObject sendWithZec(QJsonObject s) {
    QJsonObject p = s.value("preview").toObject();
    if (p.isEmpty()) return s;
    // Totals for the approval line: what is paid, and what shielding moves into the wallet.
    const auto sum = [](const QJsonArray &a) {
        qint64 t = 0;
        for (const QJsonValue &v : a) t += zat(v.toObject().value("amount"));
        return t;
    };
    p.insert("recipientsTotalZec", zec(sum(p.value("recipients").toArray())));
    p.insert("changeTotalZec", zec(sum(p.value("change").toArray())));
    p.insert("recipients", mapObjects(p.value("recipients").toArray(), {"amount"}));
    p.insert("change", mapObjects(p.value("change").toArray(), {"amount"}));
    QJsonObject spent = p.value("spentFrom").toObject();
    for (auto it = spent.begin(); it != spent.end(); ++it) it.value() = zec(zat(it.value()));
    p.insert("spentFromZec", spent);
    addZec(p, {"fee", "amountMadePublic"});
    s.insert("preview", p);
    return s;
}

QJsonObject historyWithZec(QJsonObject h) {
    QJsonArray rows;
    for (const QJsonValue &v : h.value("rows").toArray()) {
        QJsonObject r = v.toObject();
        addZec(r, {"delta", "fee", "amountMadePublic", "sentToOthers", "sentToSelf", "shielded"});
        r.insert("to", mapObjects(r.value("to").toArray(), {"amount"}));
        r.insert("toSelf", mapObjects(r.value("toSelf").toArray(), {"amount"}));
        r.insert("from", mapObjects(r.value("from").toArray(), {"amount"}));
        rows.append(r);
    }
    h.insert("rows", rows);
    return h;
}

bool liveSend(const QString &state) { return state == "preparing" || state == "previewed" || state == "signing"; }

QJsonObject planWithZec(QJsonObject p) {
    addZec(p, {"migrating", "feeTotal", "remainder"});
    QJsonArray amounts;
    for (const QJsonValue &v : p.value("amountsMadePublic").toArray()) amounts.append(zec(zat(v)));
    p.insert("amountsMadePublicZec", amounts);
    return p;
}

QJsonObject migrationWithZec(QJsonObject m) {
    m.remove("ok");
    addZec(m, {"totalInput", "migratable", "migrated"});
    return m;
}

// Every approval error but a wrong password reached the wallet thread, which drops the plan.
bool planConsumed(const QString &error) { return !error.contains(QLatin1String("password"), Qt::CaseInsensitive); }
}

void ZcashWalletUiBackend::say(const QString &line) {
    const QString cur = lastError();
    if (cur.isEmpty()) { setLastError(line); return; }
    // The read poll repeats a lasting failure every 3 s; say it once.
    if (cur.split(QLatin1Char('\n')).contains(line)) return;
    setLastError(cur + QLatin1Char('\n') + line);
}

bool ZcashWalletUiBackend::ok(const QString &reply, const QString &context) {
    const QJsonObject o = parse(reply);
    if (o.value("ok").toBool()) return true;
    QString e = o.value("error").toString();
    if (e.isEmpty()) e = QStringLiteral("the wallet backend did not answer");
    say(context.isEmpty() ? e : QStringLiteral("%1: %2").arg(context, e));
    return false;
}

bool ZcashWalletUiBackend::walletOpen() const { return parse(statusJson()).value("open").toBool(); }

void ZcashWalletUiBackend::clearAndRefresh() {
    setLastError({});
    refresh();
}

void ZcashWalletUiBackend::onContextReady() {
    QObject::connect(&m_readPoll, &QTimer::timeout, [this] {
        const bool wasOpen = walletOpen();
        loadStatus();
        // Opened elsewhere and the event was missed: Receive would stay empty until a refresh.
        if (!wasOpen && walletOpen()) loadReceive();
        loadSync();
        loadBalances();
        if (!m_healthReadAge.isValid() || m_healthReadAge.elapsed() >= kHealthPollMs) loadServerHealth();
        if (migrationLive() && (!m_migrationReadAge.isValid() || m_migrationReadAge.elapsed() >= kMigrationPollMs))
            loadMigration();
        syncHistoryToHeight();
    });
    QObject::connect(&m_jobPoll, &QTimer::timeout, [this] { pollJob(); });
    QObject::connect(&m_sendPoll, &QTimer::timeout, [this] { pollSend(); });
    QObject::connect(&m_migrationJobPoll, &QTimer::timeout, [this] { pollMigrationJob(); });
    // Subscribe, then reconcile. Never call out from an event callback: it runs on the IPC
    // read stack and would block the thread delivering its own reply.
    auto &b = modules().zcash_wallet_backend;
    b.onWallet_state_changed([this](QString) { QTimer::singleShot(0, this, [this] { refresh(); }); });
    b.onSync_progress([this](QString) { QTimer::singleShot(0, this, [this] { loadSync(); }); });
    // A paid transparent address rotates out, so Receive follows the balance.
    b.onBalance_changed([this](QString) {
        QTimer::singleShot(0, this, [this] { loadBalances(); loadReceive(); syncHistoryToHeight(); });
    });
    // The payload is server_health()'s full reply for the backend's active network.
    b.onServer_health_changed([this](QString payload) {
        QTimer::singleShot(0, this, [this, payload] {
            const QJsonObject o = parse(payload);
            if (!o.value("ok").toBool()) { loadServerHealth(); return; }
            if (o.value("network").toString() != parse(networksJson()).value("active").toString()) return;
            setServerHealthJson(stripOk(payload));
            m_healthReadAge.restart();
        });
    });
    b.onJob_finished([this](QString id, QString) {
        QTimer::singleShot(0, this, [this, id] {
            if (id == pendingJobId()) pollJob();
            else if (id == m_migrationJobId) pollMigrationJob();
        });
    });
    b.onMigration_changed([this](QString payload) {
        QTimer::singleShot(0, this, [this, payload] { applyMigrationEvent(payload); });
    });
    b.onSend_status_changed([this](QString id, QString state) {
        QTimer::singleShot(0, this, [this, id, state] {
            if (id == sendRequestId()) { pollSend(); return; }
            // A send another module asked for comes here for approval, unless one is on screen.
            const QString cur = parse(sendStatusJson()).value("state").toString();
            const bool free = sendRequestId().isEmpty() || (!liveSend(cur) && cur != "unknown");
            if (free && (state == "preparing" || state == "previewed")) adoptSend(id);
        });
    });
    m_readPoll.start(kReadPollMs);
    refresh();
    recoverSend();
}

// Does not clear lastError: it runs right after a failed job, and from events.
void ZcashWalletUiBackend::refresh() {
    loadStatus();
    loadRegistry();
    loadServers();
    loadServerHealth();
    loadSync();
    loadBalances();
    loadReceive();
    refreshHistory();
    loadMigration();
}

void ZcashWalletUiBackend::loadStatus() {
    const QString s = modules().zcash_wallet_backend.wallet_status();
    if (!ok(s, "status")) return;
    const bool wasOpen = walletOpen();
    setStatusJson(stripOk(s));
    if (wasOpen && !walletOpen()) clearWalletReads();
}

// Nothing of a closed wallet may stay on screen for the next one.
void ZcashWalletUiBackend::clearWalletReads() {
    setSyncJson({});
    setBalancesJson({});
    setReceiveJson({});
    setShieldedQrJson({});
    setTransparentQrJson({});
    m_qrShieldedFor.clear();
    m_qrTransparentFor.clear();
    setHistoryJson({});
    setHistoryPage(0);
    m_historyHeight = -1;
    m_historyHasPending = false;
    m_historyReadAge.invalidate();
    // A plan lives in the wallet's thread and is gone with it.
    setMigrationJson({});
    setMigrationError({});
    dropPlan();
}

void ZcashWalletUiBackend::loadRegistry() {
    auto &b = modules().zcash_wallet_backend;
    const QString n = b.list_networks();
    if (ok(n, "networks")) setNetworksJson(stripOk(n));
    const QString w = b.list_wallets();
    setWalletsJson(ok(w, "wallets") ? compact(parse(w).value("wallets")) : QStringLiteral("[]"));
}

void ZcashWalletUiBackend::loadSync() {
    if (!walletOpen()) { setSyncJson({}); return; }
    // Fails only while a wallet closes, so it stays off the error line.
    const QJsonObject o = parse(modules().zcash_wallet_backend.sync_status());
    setSyncJson(o.value("ok").toBool() ? compact(o.value("sync")) : QString());
}

void ZcashWalletUiBackend::loadBalances() {
    if (!walletOpen()) { setBalancesJson({}); return; }
    const QString r = modules().zcash_wallet_backend.balances();
    QJsonObject o = parse(r);
    if (!o.value("ok").toBool()) { setBalancesJson({}); ok(r, "balances"); return; }
    o.remove("ok");
    setBalancesJson(compact(o.value("ready").toBool() ? withZec(o) : o));
}

// Not on the read poll: the first read may derive an address, which waits on the sync thread.
void ZcashWalletUiBackend::loadReceive() {
    if (!walletOpen()) {
        setReceiveJson({}); setShieldedQrJson({}); setTransparentQrJson({});
        m_qrShieldedFor.clear(); m_qrTransparentFor.clear();
        return;
    }
    const QString r = modules().zcash_wallet_backend.receive_info();
    if (!ok(r, "receive")) { setReceiveJson({}); return; }
    const QJsonObject o = parse(r);
    const QString unified = o.value("unified").toString();
    const QString transparent = o.value("transparent").toString();
    setReceiveJson(compact(QJsonObject{{"unified", unified}, {"transparent", transparent}}));
    if (unified != m_qrShieldedFor) {
        m_qrShieldedFor = unified;
        setShieldedQrJson(unified.isEmpty() ? QString() : qrModulesJson(unified));
    }
    if (transparent != m_qrTransparentFor) {
        m_qrTransparentFor = transparent;
        setTransparentQrJson(transparent.isEmpty() ? QString() : qrModulesJson(transparent));
    }
}

void ZcashWalletUiBackend::loadServers() {
    const QString r = modules().zcash_wallet_backend.servers();
    setServersJson(ok(r, "servers") ? stripOk(r) : QString());
}

// On the read poll, so quiet: the health reply describes its own failures.
void ZcashWalletUiBackend::loadServerHealth() {
    const QString r = modules().zcash_wallet_backend.server_health();
    setServerHealthJson(parse(r).value("ok").toBool() ? stripOk(r) : QString());
    m_healthReadAge.restart();
}

// A module matrix, not an image: the design system has no QR control and the ui_qml sandbox
// blocks data: URIs. nayuki's qrcodegen (MIT) is vendored.
QString ZcashWalletUiBackend::qrModulesJson(const QString &text) const {
    using qrcodegen::QrCode;
    const QrCode qr = QrCode::encodeText(text.toUtf8().constData(), QrCode::Ecc::MEDIUM);
    const int n = qr.getSize();
    QString bits;
    bits.reserve(n * n);
    for (int y = 0; y < n; ++y)
        for (int x = 0; x < n; ++x) bits += qr.getModule(x, y) ? QLatin1Char('1') : QLatin1Char('0');
    return compact(QJsonObject{{"size", n}, {"bits", bits}});
}

// ---- history -------------------------------------------------------------------------------

void ZcashWalletUiBackend::refreshHistory() { readHistory(false); }

void ZcashWalletUiBackend::showHistoryPage(int page) {
    setHistoryPage(page < 0 ? 0 : page);
    readHistory(false);
}

// Re-read on a new scanned height (at most every 10 s while scanning), and every 15 s while a
// pending row is on screen: a send can confirm or expire without the user doing anything.
void ZcashWalletUiBackend::syncHistoryToHeight() {
    if (!walletOpen()) return;
    const QJsonValue fs = parse(syncJson()).value("fullyScanned");
    if (!fs.isDouble()) return;
    const qint64 age = m_historyReadAge.isValid() ? m_historyReadAge.elapsed() : -1;
    const bool heightDue = fs.toInteger() != m_historyHeight && (age < 0 || age >= kHistoryMinGapMs);
    const bool pendingDue = m_historyHasPending && (age < 0 || age >= kPendingHistoryPollMs);
    if (heightDue || pendingDue) readHistory(true);
}

// `quiet` is a re-read nobody asked for: it keeps the rows on screen and stays off the error line.
void ZcashWalletUiBackend::readHistory(bool quiet) {
    const auto forget = [this] {
        setHistoryJson({});
        m_historyHeight = -1;
        m_historyHasPending = false;
        m_historyReadAge.invalidate();
    };
    if (!walletOpen()) { if (!quiet) forget(); return; }
    const QString r = modules().zcash_wallet_backend.history(historyPage());
    QJsonObject o = parse(r);
    if (!(quiet ? o.value("ok").toBool() : ok(r, "history"))) { if (!quiet) forget(); return; }
    o.remove("ok");
    o = historyWithZec(o);
    setHistoryJson(compact(o));
    m_historyHasPending = false;
    for (const QJsonValue &row : o.value("rows").toArray())
        if (row.toObject().value("pending").toBool()) { m_historyHasPending = true; break; }
    m_historyReadAge.restart();
    // Watermarked only on success, so a failed read is tried again on the next tick.
    const QJsonValue fs = parse(syncJson()).value("fullyScanned");
    m_historyHeight = fs.isDouble() ? fs.toInteger() : -1;
}

// ---- wallet jobs ---------------------------------------------------------------------------

void ZcashWalletUiBackend::setActiveNetwork(QString network) {
    setLastError({});
    if (ok(modules().zcash_wallet_backend.set_active_network(network), "network")) refresh();
}

// A lifecycle call answers a job id and settles later. One at a time: a second would orphan the first.
void ZcashWalletUiBackend::track(const QString &reply, const QString &kind, const QString &name) {
    if (!ok(reply, kind)) return;
    const QString id = parse(reply).value("jobId").toString();
    if (id.isEmpty()) { say(kind + ": no job id returned"); return; }
    m_pendingName = name;
    setPendingJobKind(kind);
    setPendingJobId(id);
    setBusy(true);
    m_jobPoll.start(kJobPollMs);
}

void ZcashWalletUiBackend::pollJob() {
    const QString id = pendingJobId();
    if (id.isEmpty()) { m_jobPoll.stop(); setBusy(false); return; }
    const QString r = modules().zcash_wallet_backend.job_status(id);
    if (r.isEmpty()) return;  // the call itself failed; ask again on the next tick
    const QJsonObject st = parse(r);
    // A job the backend does not know (it restarted) will never settle.
    const QString state = st.value("ok").toBool() ? st.value("state").toString() : QStringLiteral("failed");
    if (state != "done" && state != "failed" && state != "cancelled") return;
    m_jobPoll.stop();
    const QString kind = pendingJobKind();
    const QString error = st.value("error").toString();
    const QString name = st.value("result").toObject().value("name").toString();
    const QJsonObject last{{"jobId", id}, {"kind", kind}, {"state", state}, {"error", error},
                           {"name", name.isEmpty() ? m_pendingName : name}};
    if (state != "done") say(kind + ": " + (error.isEmpty() ? state : error));
    m_pendingName.clear();
    setPendingJobId({});
    setPendingJobKind({});
    setBusy(false);
    // Status first: the view reads the settled job against it.
    refresh();
    setLastJobJson(compact(last));
}

void ZcashWalletUiBackend::openWallet(QString name, QString password) {
    setLastError({});
    if (busy()) { say("open: another wallet job is still running"); return; }
    track(modules().zcash_wallet_backend.open_wallet(name, password), "open", name);
}

void ZcashWalletUiBackend::createWallet(QString name, QString password) {
    setLastError({});
    if (busy()) { say("create: another wallet job is still running"); return; }
    track(modules().zcash_wallet_backend.create_wallet(name, password), "create", name);
}

void ZcashWalletUiBackend::restoreWallet(QString name, QString password, QString phrase, int birthdayHeight) {
    setLastError({});
    if (busy()) { say("restore: another wallet job is still running"); return; }
    const QJsonObject p{{"name", name}, {"password", password}, {"phrase", phrase},
                        {"birthdayHeight", birthdayHeight}};
    track(modules().zcash_wallet_backend.restore_wallet(compact(p)), "restore", name);
}

void ZcashWalletUiBackend::changePassword(QString oldPassword, QString newPassword) {
    setLastError({});
    if (busy()) { say("change password: another wallet job is still running"); return; }
    track(modules().zcash_wallet_backend.change_password(oldPassword, newPassword), "change password",
          parse(statusJson()).value("name").toString());
}

void ZcashWalletUiBackend::closeWallet() {
    setLastError({});
    if (busy()) { say("close: another wallet job is still running"); return; }
    track(modules().zcash_wallet_backend.close_wallet(), "close", parse(statusJson()).value("name").toString());
}

// Returned, not published: the view shows it once and drops it.
QString ZcashWalletUiBackend::revealSeed(QString password) {
    setLastError({});
    const QString r = modules().zcash_wallet_backend.reveal_seed(password);
    return ok(r, "recovery phrase") ? parse(r).value("phrase").toString() : QString();
}

QString ZcashWalletUiBackend::exportViewingKey(QString password) {
    setLastError({});
    const QString r = modules().zcash_wallet_backend.export_viewing_key(password);
    return ok(r, "viewing key") ? parse(r).value("ufvk").toString() : QString();
}

// ---- spending ------------------------------------------------------------------------------

// A settled send still on screen gives way to a new one; a live one does not.
bool ZcashWalletUiBackend::clearSettledSend() {
    if (sendRequestId().isEmpty()) return true;
    if (liveSend(parse(sendStatusJson()).value("state").toString())) {
        setSendError(QStringLiteral("A send is already open: approve or cancel it first."));
        return false;
    }
    dismissSend();
    return true;
}

void ZcashWalletUiBackend::prepareSend(QString recipient, QString amountZec, QString memo, bool allowMixedPools) {
    setSendError({});
    if (!clearSettledSend()) return;
    const QString to = recipient.trimmed();
    QJsonObject request;
    if (to.startsWith(QLatin1String("zcash:"), Qt::CaseInsensitive)) {
        request.insert("uri", to);
    } else {
        bool valid = false;
        const qint64 amount = parseZec(amountZec, &valid);
        if (!valid) { setSendError(QStringLiteral("Enter an amount in ZEC, with at most 8 decimals.")); return; }
        QJsonObject r{{"address", to}, {"amount", amount}};
        if (!memo.isEmpty()) r.insert("memo", memo);
        request.insert("recipients", QJsonArray{r});
    }
    if (allowMixedPools) request.insert("allowMixedPools", true);
    startSend(modules().zcash_wallet_backend.prepare_send(compact(request)));
}

void ZcashWalletUiBackend::shieldAddress(QString address) {
    setSendError({});
    if (!clearSettledSend()) return;
    startSend(modules().zcash_wallet_backend.prepare_shielding(address));
}

void ZcashWalletUiBackend::startSend(const QString &reply) {
    const QJsonObject o = parse(reply);
    const QString id = o.value("requestId").toString();
    if (!o.value("ok").toBool() || id.isEmpty()) {
        setSendError(o.value("error").toString(QStringLiteral("the wallet backend did not answer")));
        return;
    }
    adoptSend(id);
}

void ZcashWalletUiBackend::adoptSend(const QString &id) {
    m_sendPoll.stop();
    setSendError({});
    setSendRequestId(id);
    setSendStatusJson(QStringLiteral("{\"state\":\"preparing\"}"));
    m_sendPoll.start(kSendPollMs);
    pollSend();
}

// After a view reload, pick the open send back up rather than leave it to expire unseen.
void ZcashWalletUiBackend::recoverSend() {
    if (!sendRequestId().isEmpty()) return;
    const QJsonObject o = parse(modules().zcash_wallet_backend.list_sends());
    for (const QJsonValue &v : o.value("sends").toArray()) {
        const QJsonObject s = v.toObject();
        if (liveSend(s.value("state").toString())) { adoptSend(s.value("requestId").toString()); return; }
    }
}

void ZcashWalletUiBackend::pollSend() {
    const QString id = sendRequestId();
    if (id.isEmpty()) { m_sendPoll.stop(); return; }
    const QString r = modules().zcash_wallet_backend.send_status(id);
    if (r.isEmpty()) return;  // the call itself failed; ask again on the next tick
    QJsonObject o = parse(r);
    if (!o.value("ok").toBool()) {
        // The backend lost the send. Past signing, nobody can say whether it went out.
        m_sendPoll.stop();
        const bool signing = parse(sendStatusJson()).value("state").toString() == "signing";
        const QString error = o.value("error").toString(QStringLiteral("the wallet backend did not answer"));
        setSendStatusJson(compact(QJsonObject{{"state", signing ? "unknown" : "failed"}, {"error", error}}));
        setSendError(error);
        return;
    }
    o.remove("ok");
    setSendStatusJson(compact(sendWithZec(o)));
    const QString state = o.value("state").toString();
    const QString error = o.value("error").toString();
    // needs_mixed_pools is a question for the user, not an error: the view asks it.
    if (!liveSend(state) && state != "sent" && state != "cancelled" && !error.startsWith(QLatin1String("needs_mixed_pools:")))
        setSendError(error);
    if (!liveSend(state)) {
        m_sendPoll.stop();
        // An unknown outcome may have moved money too: Activity is where the answer shows.
        if (state == "sent" || state == "unknown") { loadBalances(); readHistory(true); }
    }
}

void ZcashWalletUiBackend::approveSend(QString password) {
    setSendError({});
    const QString id = sendRequestId();
    if (id.isEmpty()) return;
    const QJsonObject o = parse(modules().zcash_wallet_backend.approve_send(id, password));
    if (!o.value("ok").toBool())
        setSendError(o.value("error").toString(QStringLiteral("the wallet backend did not answer")));
    m_sendPoll.start(kSendPollMs);
    pollSend();
}

void ZcashWalletUiBackend::cancelSend() {
    const QString id = sendRequestId();
    if (id.isEmpty()) return;
    const QJsonObject o = parse(modules().zcash_wallet_backend.cancel_send(id));
    if (!o.value("ok").toBool()) {
        // Refused once signing began: keep the send on screen rather than claim it was cancelled.
        setSendError(o.value("error").toString(QStringLiteral("the wallet backend did not answer")));
        pollSend();
        return;
    }
    dismissSend();
}

// Local only: the backend keeps its record either way.
void ZcashWalletUiBackend::dismissSend() {
    m_sendPoll.stop();
    setSendRequestId({});
    setSendStatusJson(QStringLiteral("{}"));
    setSendError({});
}

// ---- the ZIP 318 migration -----------------------------------------------------------------

bool ZcashWalletUiBackend::migrationLive() const {
    const QString s = parse(migrationJson()).value("status").toString();
    return s == "planning" || s == "committed" || s == "in_progress";
}

// Asynchronous: migration_status() waits on the wallet thread, which may be scanning or proving.
void ZcashWalletUiBackend::loadMigration() {
    if (!walletOpen()) { setMigrationJson({}); return; }
    // One read at a time; a callback lost for 30 s no longer blocks the next.
    if (m_migrationReading && m_migrationReadAge.isValid() && m_migrationReadAge.elapsed() < kMigrationPollMs) return;
    m_migrationReading = true;
    m_migrationReadAge.restart();
    const QString wallet = parse(statusJson()).value("name").toString();
    modules().zcash_wallet_backend.migration_statusAsync([this, wallet](QString r) {
        QTimer::singleShot(0, this, [this, wallet, r] {
            m_migrationReading = false;
            const QJsonObject o = parse(r);
            // A busy wallet keeps the last answer on screen; another wallet's answer is dropped.
            if (o.value("ok").toBool() && walletOpen() && parse(statusJson()).value("name").toString() == wallet)
                setMigrationJson(compact(migrationWithZec(o)));
        });
    });
}

// The payload is migration_status()'s shape, or only { needsApproval }: merged over the last
// read. paused and needsApproval come only with a full read, so one follows.
void ZcashWalletUiBackend::applyMigrationEvent(const QString &payload) {
    const QJsonObject ev = parse(payload);
    if (ev.isEmpty() || !walletOpen()) return;
    QJsonObject cur = parse(migrationJson());
    for (auto it = ev.constBegin(); it != ev.constEnd(); ++it) cur.insert(it.key(), it.value());
    setMigrationJson(compact(migrationWithZec(cur)));
    if (ev.contains("status")) loadMigration();
}

void ZcashWalletUiBackend::trackMigration(const QString &reply, const QString &kind) {
    const QJsonObject o = parse(reply);
    const QString id = o.value("jobId").toString();
    if (!o.value("ok").toBool() || id.isEmpty()) {
        setMigrationError(o.value("error").toString(QStringLiteral("the wallet backend did not answer")));
        return;
    }
    m_migrationJobId = id;
    setMigrationJobKind(kind);
    m_migrationJobPoll.start(kJobPollMs);
}

void ZcashWalletUiBackend::pollMigrationJob() {
    if (m_migrationJobId.isEmpty()) { m_migrationJobPoll.stop(); setMigrationJobKind({}); return; }
    const QString r = modules().zcash_wallet_backend.job_status(m_migrationJobId);
    if (r.isEmpty()) return;  // the call itself failed; ask again on the next tick
    const QJsonObject st = parse(r);
    const QString state = st.value("ok").toBool() ? st.value("state").toString() : QStringLiteral("failed");
    if (state != "done" && state != "failed" && state != "cancelled") return;
    m_migrationJobPoll.stop();
    const QString kind = migrationJobKind();
    m_migrationJobId.clear();
    setMigrationJobKind({});
    if (state != "done") {
        const QString error = st.value("error").toString(state);
        setMigrationError(error);
        if (kind == "approve" && planConsumed(error)) dropPlan();
    } else if (kind == "plan") {
        const QJsonObject result = st.value("result").toObject();
        const QJsonObject preview = result.value("preview").toObject();
        m_planId = result.value("planId").toString();
        m_planDigest = preview.value("digest").toString();
        setMigrationPlanJson(compact(planWithZec(preview)));
    } else if (kind == "approve") {
        dropPlan();
    }
    loadMigration();
    loadBalances();
}

void ZcashWalletUiBackend::dropPlan() {
    m_planId.clear();
    m_planDigest.clear();
    setMigrationPlanJson({});
}

// The core runs one migration step at a time; a second would race the first.
bool ZcashWalletUiBackend::migrationIdle() {
    setMigrationError({});
    if (m_migrationJobId.isEmpty()) return true;
    setMigrationError(QStringLiteral("A migration step is still running."));
    return false;
}

void ZcashWalletUiBackend::planMigration() {
    if (!migrationIdle()) return;
    dropPlan();
    trackMigration(modules().zcash_wallet_backend.prepare_migration("private"), "plan");
}

void ZcashWalletUiBackend::migrateNow() {
    setSendError({});
    if (!clearSettledSend()) return;
    startSend(modules().zcash_wallet_backend.prepare_migration("now"));
}

void ZcashWalletUiBackend::approveMigration(QString password) {
    if (!migrationIdle()) return;
    if (m_planId.isEmpty()) { setMigrationError(QStringLiteral("There is no plan to approve: plan the migration again.")); return; }
    trackMigration(modules().zcash_wallet_backend.approve_migration(m_planId, m_planDigest, password), "approve");
}

void ZcashWalletUiBackend::pauseMigration() {
    if (migrationIdle()) trackMigration(modules().zcash_wallet_backend.pause_migration(), "pause");
}

void ZcashWalletUiBackend::resumeMigration() {
    if (migrationIdle()) trackMigration(modules().zcash_wallet_backend.resume_migration(), "resume");
}

void ZcashWalletUiBackend::cancelMigration() {
    if (migrationIdle()) trackMigration(modules().zcash_wallet_backend.cancel_migration(), "cancel");
}

void ZcashWalletUiBackend::dismissMigrationPlan() {
    dropPlan();
    setMigrationError({});
}

// ---- receiving and network -----------------------------------------------------------------

// { ok, valid, kind, shielded, receivers? } or { ok, valid: false, reason } on the active network.
QString ZcashWalletUiBackend::addressValid(QString text) {
    return modules().zcash_wallet_backend.address_valid(text.trimmed());
}

void ZcashWalletUiBackend::newAddress() {
    setLastError({});
    if (ok(modules().zcash_wallet_backend.new_address(), "new address")) loadReceive();
}

void ZcashWalletUiBackend::applyPreset(QString name) {
    setLastError({});
    if (ok(modules().zcash_wallet_backend.apply_preset(name), "servers")) { loadServers(); loadServerHealth(); }
}

void ZcashWalletUiBackend::setProxy(QString proxy) {
    setLastError({});
    const QJsonObject cfg{{"proxy", proxy.trimmed()}, {"proxyRequired", true}};
    if (ok(modules().zcash_wallet_backend.set_proxy(compact(cfg)), "proxy")) { loadServers(); loadServerHealth(); }
}

// ---- the local node ------------------------------------------------------------------------

QString ZcashWalletUiBackend::setLocalNode(bool enabled) {
    const QJsonObject o = parse(modules().zcash_wallet_backend.set_local_node(enabled));
    loadServers();
    refreshLocalNode();
    return o.value("ok").toBool() ? QString() : o.value("error").toString(QStringLiteral("the wallet backend did not answer"));
}

// Asynchronous: with zebrad_module absent the node module waits 1.5 s for it.
void ZcashWalletUiBackend::refreshLocalNode() {
    if (m_localNodeReading && m_localNodeReadAge.isValid() && m_localNodeReadAge.elapsed() < kLocalNodeReadMs) return;
    m_localNodeReading = true;
    m_localNodeReadAge.restart();
    // Stamped with the network asked about, so the view drops an answer for another one.
    const QString network = parse(networksJson()).value("active").toString();
    modules().zcash_wallet_backend.local_nodeAsync([this, network](QString r) {
        QTimer::singleShot(0, this, [this, network, r] {
            m_localNodeReading = false;
            QJsonObject o = parse(r);
            if (!o.value("ok").toBool())
                o = QJsonObject{{"available", false},
                                {"error", o.value("error").toString(QStringLiteral("the wallet backend did not answer"))}};
            o.remove("ok");
            o.insert("network", network);
            setLocalNodeJson(compact(o));
        });
    });
}
