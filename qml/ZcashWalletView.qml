import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Logos.Controls
import Logos.Theme

// The Zcash wallet. Nothing open: the Wallets screen. A wallet open: Home, Send, Receive,
// Activity and Settings. Secrets cross only as SLOT arguments and return values.
// Strings this view did not author render as PlainText: LogosText is AutoText.
Item {
    id: root
    objectName: "zcashWalletRoot"
    anchors.fill: parent

    Rectangle { anchors.fill: parent; color: Theme.palette.background }

    readonly property var backend: logos.module("zcash_wallet_ui")
    property bool ready: false

    // A wallet another app asked us to open, answered when the open job settles.
    property string unlockRequestId: ""
    property string unlockWallet: ""
    property bool unlockOpenSent: false
    // A revealed secret: shown once on Settings, dropped when leaving it.
    property string shownSecret: ""
    property string secretKind: ""
    // The last send this view asked for, kept to resend it with consent to mix pools.
    property var lastRequest: null
    // The transparent address a shielding started from; the preview does not name it.
    property string shieldingFrom: ""
    // The history row expanded, by txid.
    property string openTx: ""

    Connections {
        target: logos
        function onViewModuleReadyChanged(moduleName, isReady) {
            if (moduleName === "zcash_wallet_ui") root.ready = isReady && root.backend !== null
        }
        function onIntentRequested(requestId, intent, params, requesterName) {
            if (intent === "zcash.accounts.manage") {
                if (root.walletOpen) root.selectTab(4)  // Settings holds management once open
                logos.respond(requestId, true, ({}), "")
                return
            }
            if (intent !== "zcash.wallet.unlock") return
            var w = params && params.wallet ? String(params.wallet) : ""
            if (w === "") { logos.respond(requestId, false, ({}), "bad_request"); return }
            if (root.walletOpen && root.status.name === w) { logos.respond(requestId, true, ({}), ""); return }
            if (root.walletOpen) { logos.respond(requestId, false, ({}), "another wallet is already open"); return }
            if (root.unlockRequestId !== "") logos.respond(root.unlockRequestId, false, ({}), "superseded")
            root.unlockRequestId = requestId
            root.unlockWallet = w
            root.unlockOpenSent = false
            openNameField.text = w
            openWalletSheet.open()
        }
    }
    Component.onCompleted: root.ready = root.backend !== null && logos.isViewModuleReady("zcash_wallet_ui")

    function j(t, fb) { try { return JSON.parse(t && t.length ? t : fb) } catch (e) { return JSON.parse(fb) } }
    readonly property var status: ready ? j(backend.statusJson, "{}") : ({})
    readonly property var networks: ready ? j(backend.networksJson, "{}") : ({})
    readonly property var wallets: ready ? j(backend.walletsJson, "[]") : []
    readonly property var lastJob: ready ? j(backend.lastJobJson, "{}") : ({})
    readonly property bool busy: ready && backend.busy === true
    readonly property string pendingKind: ready ? backend.pendingJobKind : ""
    readonly property bool walletOpen: status.open === true
    readonly property bool syncRead: ready && backend.syncJson !== ""
    readonly property var sync: syncRead ? j(backend.syncJson, "{}") : ({})
    readonly property bool balancesRead: ready && backend.balancesJson !== ""
    readonly property var balances: balancesRead ? j(backend.balancesJson, "{}") : ({})
    // Read, and scanned far enough for the wallet core to have a summary.
    readonly property bool balancesReady: balancesRead && balances.ready === true
    readonly property var spendPool: balancesReady ? (balances.spendPool || {}) : ({})
    readonly property var transparentPool: balancesReady ? ((balances.pools || {}).transparent || {}) : ({})
    readonly property var transparentAddresses: balancesReady && Array.isArray(balances.transparentAddresses) ? balances.transparentAddresses : []
    // Orchard funds, spend-only since NU6.3, waiting to migrate: { spendable, total } in zatoshis.
    readonly property var orchard: balancesReady ? (balances.orchardToMigrate || {}) : ({})
    // ZIP 315's un-economic balance: below this, shielding costs more than it moves.
    readonly property real shieldThreshold: balancesReady && balances.shieldingThreshold !== undefined ? zatOf(balances.shieldingThreshold) : 100000
    readonly property bool receiveRead: ready && backend.receiveJson !== ""
    readonly property var receive: receiveRead ? j(backend.receiveJson, "{}") : ({})
    readonly property var serversInfo: ready ? j(backend.serversJson, "{}") : ({})
    readonly property var serverList: Array.isArray(serversInfo.servers) ? serversInfo.servers : []
    readonly property var health: ready ? j(backend.serverHealthJson, "{}") : ({})
    readonly property string overall: health.overall || ""
    readonly property bool serversRead: ready && backend.serversJson !== ""
    readonly property bool localNodeOn: serversInfo.localNode === true
    // local_node() for the active network; {} until read, or when it answered for another one.
    readonly property var localNode: {
        var l = ready ? j(backend.localNodeJson, "{}") : ({})
        return root.activeNetwork !== "" && l.network === root.activeNetwork ? l : ({})
    }
    readonly property var localStatus: localNode.status || null
    // As the node module decides: with no enabled server taking broadcasts, the node sends them.
    readonly property bool broadcastServer: serverList.some(function (s) {
        return s.enabled === true && (!Array.isArray(s.classes) || s.classes.indexOf("broadcast") >= 0)
    })
    property string localNodeNote: ""
    // Network settings apply when a wallet opens; while one is open they show but do not change.
    readonly property bool networkLocked: walletOpen
    readonly property string defaultProxy: "socks5h://127.0.0.1:9050"
    // Public servers the user set to skip Tor; the user's own network never goes through it.
    readonly property var directServers: serverList.filter(function (s) {
        return s.enabled === true && s.direct === true && !root.isLanUrl(s.url)
    })
    // Operators of the servers in use: two or more check each other.
    readonly property var operatorsInUse: {
        var seen = [], out = []
        serverList.forEach(function (s) {
            var k = (s.operator || "").toLowerCase()
            if (s.enabled === true && k !== "" && seen.indexOf(k) < 0) { seen.push(k); out.push(s.operator) }
        })
        return out
    }
    // The server whose "without Tor" waits for the user's confirmation.
    property string torOffAskedFor: ""
    // What the proxy, a preset or a server edit refused, shown next to it ("proxy" or "servers").
    property string networkNote: ""
    property string networkNoteAt: ""
    onNetworkLockedChanged: { torOffAskedFor = ""; networkNote = "" }
    readonly property bool localNodeAvailable: localNode.available === true
    onLocalNodeAvailableChanged: if (localNodeAvailable) localNodeNote = ""
    readonly property string activeNetwork: ready ? (networks.active || "") : ""
    readonly property string displayedNetwork: walletOpen ? (status.network || activeNetwork) : activeNetwork
    readonly property var walletsOnNetwork: wallets.filter(function (w) { return !w.network || w.network === root.activeNetwork })
    readonly property real chainTip: zatOf(sync.tip) || zatOf(balances.chainTip)
    readonly property bool historyRead: ready && backend.historyJson !== ""
    readonly property var historyData: historyRead ? j(backend.historyJson, "{}") : ({})
    readonly property var historyRows: Array.isArray(historyData.rows) ? historyData.rows : []
    // Migration rows gather under one heading, placed where the newest of them was.
    readonly property var historyView: {
        var out = [], moves = [], at = -1
        for (var i = 0; i < historyRows.length; i++) {
            var r = historyRows[i]
            if (r.kind !== "migration") { out.push(r); continue }
            if (at < 0) at = out.length
            moves.push(r)
        }
        if (moves.length === 0) return out
        var header = { kind: "migrationGroup", txid: "migration-group", count: moves.length,
                       pending: moves.filter(function (r) { return r.pending }).length,
                       moved: moves.reduce(function (t, r) { return t + root.zatOf(r.amountMadePublic) }, 0) }
        return out.slice(0, at).concat([header], migrationGroupOpen ? moves : [], out.slice(at))
    }
    readonly property int historyPage: ready ? backend.historyPage : 0

    // ---- the send or shielding under review ----
    readonly property string sendId: ready ? backend.sendRequestId : ""
    readonly property bool sendOpen: sendId !== ""
    readonly property var send: ready ? j(backend.sendStatusJson, "{}") : ({})
    readonly property bool sendLive: sendOpen && (send.state === "preparing" || send.state === "previewed" || send.state === "signing")
    readonly property bool sendSettled: sendOpen && !sendLive
    readonly property var preview: send.preview ? send.preview : null
    readonly property int ttl: send.ttlSecs === undefined || send.ttlSecs === null ? -1 : send.ttlSecs
    readonly property bool ownSend: send.requester === "zcash_wallet_ui"
    readonly property bool needsMixedPools: sendOpen && send.state === "failed"
                                            && String(send.error || "").indexOf("needs_mixed_pools:") === 0
    // This send reached signing, which places a later failure on the lane.
    property bool sendSigned: false
    property string lastSendState: ""
    onSendIdChanged: {
        root.sendSigned = false
        root.lastSendState = ""
        if (root.sendId === "") { reviewSheet.close(); approveSheet.close(); mixedPoolsSheet.close() }
        else if (root.walletOpen) reviewSheet.open()
    }
    onSendChanged: {
        var s = root.send.state || ""
        if (s === root.lastSendState) return
        if (s === "signing") root.sendSigned = true
        if (s === "sent" && root.lastSendState === "signing")
            root.notify(root.preview && root.preview.migrateNow ? "Moved"
                        : root.preview && root.preview.shielding ? "Shielded" : "Sent", "It shows in Activity once mined.")
        root.lastSendState = s
    }
    onNeedsMixedPoolsChanged: if (root.needsMixedPools && root.ownSend && root.lastRequest) mixedPoolsSheet.open()

    // ---- the ZIP 318 migration ----
    readonly property var migration: ready ? j(backend.migrationJson, "{}") : ({})
    readonly property string migrationStatus: migration.status || ""
    readonly property bool migrationLive: ["planning", "committed", "in_progress"].indexOf(migrationStatus) >= 0
    readonly property bool migrationEnded: ["complete", "failed", "cancelled", "superseded"].indexOf(migrationStatus) >= 0
    readonly property var plan: ready && backend.migrationPlanJson !== "" ? j(backend.migrationPlanJson, "{}") : null
    readonly property string migrationJob: ready ? backend.migrationJobKind : ""
    readonly property string migrationError: ready ? backend.migrationError : ""
    // ZIP 318 moves nothing below 0.01 ZEC.
    readonly property real minMigratable: 1000000
    // The finished run put away by the user; the core keeps reporting the last run.
    property string dismissedRun: ""
    readonly property bool migrationShown: walletOpen && (migrationLive || (migrationEnded && migration.id !== dismissedRun)
                                                          || !!migration.needsApproval)
    // The approval dialog serves sends and migrations alike.
    property string approveMode: "send"
    property bool migrationGroupOpen: false
    onPlanChanged: {
        if (root.plan) migrationReview.open()
        else if (root.migrationError === "") migrationReview.close()
    }

    // ---- the Send form ----
    readonly property bool sendIsUri: sendTo.text.trim().toLowerCase().indexOf("zcash:") === 0
    // address_valid()'s answer for `text`; a reply for older text is dropped.
    property var recipientCheck: ({})
    readonly property bool recipientChecked: recipientCheck.text !== undefined && recipientCheck.text === sendTo.text.trim()
    readonly property string recipientKind: sendIsUri ? "payment request" : root.kindOf(recipientChecked ? recipientCheck : null)
    // ZIP 302: memos go to shielded recipients only.
    readonly property bool memoAllowed: recipientKind === "" || recipientKind === "shielded"
    readonly property int memoBytes: utf8Bytes(sendMemo.text)
    readonly property bool canReview: ready && walletOpen && !sendLive && send.state !== "unknown" && sendTo.text.trim() !== ""
                                      && (sendIsUri || (recipientChecked && (recipientCheck.valid === true || recipientCheck.failed === true)))
                                      && (sendIsUri || (sendAmount.text !== "" && sendAmount.text !== "." && zatOfZec(sendAmount.text) > 0))
                                      && (!memoAllowed || memoBytes <= 512)

    // The job already settled when the view connected is history, not news. Primed from the raw
    // PROP so either handler may run first when `ready` flips.
    property string handledJobId: ""
    property bool jobsPrimed: false
    function primeJobs() {
        if (root.jobsPrimed || !root.ready) return
        root.handledJobId = root.j(backend.lastJobJson, "{}").jobId || ""
        root.jobsPrimed = true
    }
    onReadyChanged: root.primeJobs()

    // An unlock another app asked for, or a created wallet, is answered here once its job settles.
    onLastJobChanged: {
        root.primeJobs()
        if (!lastJob.jobId || lastJob.jobId === root.handledJobId) return
        root.handledJobId = lastJob.jobId
        if (lastJob.kind === "open" && root.unlockRequestId !== "" && root.unlockOpenSent) {
            var opened = lastJob.state === "done"
            var mine = opened && lastJob.name === root.unlockWallet
            var err = !opened ? (lastJob.error || "open failed") : (mine ? "" : "a different wallet was opened")
            logos.respond(root.unlockRequestId, mine, ({}), err)
            root.unlockRequestId = ""
            root.unlockWallet = ""
            root.unlockOpenSent = false
        }
        if (lastJob.state !== "done") return
        if (lastJob.kind === "create" || lastJob.kind === "restore") {
            var created = lastJob.kind === "create"
            if (root.walletOpen) {
                root.notify(created ? "Wallet created" : "Wallet restored",
                            created ? "Write down its recovery phrase: Settings, Show recovery phrase."
                                    : "Its balance fills in as it scans.")
            } else {
                // A wallet core that does not open what it creates.
                root.notify(created ? "Wallet created" : "Wallet restored", "Enter its password to open it.")
                openNameField.text = lastJob.name || ""
                openWalletSheet.open()
            }
        } else if (lastJob.kind === "change password") {
            root.notify("Password changed", "")
        }
    }

    // 0 Home, 1 Send, 2 Receive, 3 Activity, 4 Settings. selectTab is the driver entry point.
    property int page: 0
    function selectTab(i) { root.page = i; tabs.currentIndex = i }
    function selectNetwork(network) {
        if (root.ready && !root.busy && !root.walletOpen) backend.setActiveNetwork(network)
    }
    function closeSheets() {
        openWalletSheet.close(); createSheet.close(); restoreSheet.close(); networkSheet.close()
        changePasswordSheet.close(); revealSheet.close(); exportKeySheet.close()
        reviewSheet.close(); approveSheet.close(); mixedPoolsSheet.close()
        migrationReview.close(); cancelMigrationSheet.close()
    }
    function hideSecret() { root.shownSecret = ""; root.secretKind = "" }
    onWalletOpenChanged: {
        root.hideSecret()
        root.closeSheets()
        root.openTx = ""
        // A check answers for one network; the next wallet may be on the other.
        root.recipientCheck = ({})
        if (sendTo.text.trim() !== "") recipientCheckTimer.restart()
        if (root.walletOpen) root.selectTab(0)
    }
    onPageChanged: if (root.page !== 4) root.hideSecret()

    // The reply lands only if the user is still on Settings with this wallet open.
    function reveal(kind, password) {
        root.hideSecret()
        root.secretKind = kind
        var call = kind === "phrase" ? backend.revealSeed(password) : backend.exportViewingKey(password)
        logos.watch(call,
                    function (v) { if (root.walletOpen && root.page === 4 && root.secretKind === kind) root.shownSecret = v || "" },
                    function () { root.shownSecret = "" })
    }
    function notify(title, message) { toast.show(title, message) }

    function review() {
        var uri = root.sendIsUri
        root.lastRequest = { to: sendTo.text.trim(), amount: uri ? "" : sendAmount.text,
                             memo: (uri || !root.memoAllowed) ? "" : sendMemo.text }
        backend.prepareSend(root.lastRequest.to, root.lastRequest.amount, root.lastRequest.memo, false)
    }
    function retryMixedPools() {
        var r = root.lastRequest
        if (r) backend.prepareSend(r.to, r.amount, r.memo, true)
    }
    function shield(address) {
        root.shieldingFrom = address
        root.lastRequest = null
        backend.shieldAddress(address)
    }
    // Every spendable Orchard note at once: reviewed and approved like a send.
    function migrateNow() {
        root.shieldingFrom = ""
        root.lastRequest = null
        backend.migrateNow()
    }
    // Done on a settled send. A send that went out clears the form behind it.
    function finishSend() {
        var s = root.send.state
        backend.dismissSend()
        if (s === "sent" && !(root.preview && (root.preview.shielding || root.preview.migrateNow))) {
            sendTo.text = ""; sendAmount.text = ""; sendMemo.text = ""
        }
    }

    function zatOf(v) { var n = Number(v); return isFinite(n) ? n : 0 }
    // Display only, for sums the backend does not send; amounts it sends come as ...Zec strings.
    function zecOf(z) {
        var n = Math.round(root.zatOf(z)), neg = n < 0
        n = Math.abs(n)
        var frac = String(n % 1e8)
        while (frac.length < 8) frac = "0" + frac
        frac = frac.replace(/0+$/, "")
        return (neg ? "-" : "") + Math.floor(n / 1e8) + (frac ? "." + frac : "")
    }
    // For enabling Review only; the exact conversion happens in C++.
    function zatOfZec(t) { var n = Number(t); return isFinite(n) ? Math.round(n * 1e8) : 0 }
    function utf8Bytes(s) {
        var n = 0
        for (var i = 0; i < s.length; i++) {
            var c = s.charCodeAt(i)
            if (c < 0x80) n += 1
            else if (c < 0x800) n += 2
            else if (c >= 0xD800 && c < 0xDC00) { n += 4; i++ }
            else n += 3
        }
        return n
    }
    function fmtHeight(h) {
        return (h === undefined || h === null || h === "") ? "—" : Number(h).toLocaleString(Qt.locale(), "f", 0)
    }
    // ZIP 316: a shortened address keeps at least its first 20 characters.
    function shortAddress(a) { return a && a.length > 40 ? a.slice(0, 20) + "…" + a.slice(-8) : (a || "") }
    function shortId(s) { return s && s.length > 20 ? s.slice(0, 10) + "…" + s.slice(-8) : (s || "") }
    function whenOf(t) { return t ? new Date(t * 1000).toLocaleString(Qt.locale(), Locale.ShortFormat) : "" }
    function wordCount(t) { var s = (t || "").trim(); return s === "" ? 0 : s.split(/\s+/).length }
    function normalisePhrase(t) { return (t || "").trim().split(/\s+/).join(" ").toLowerCase() }
    function poolLabel(p) {
        if (p === "ironwood") return "Ironwood"
        if (p === "sapling") return "Sapling"
        if (p === "orchard") return "Orchard"
        if (p === "transparent") return "Transparent"
        return p || ""
    }

    // The badge for an address check. An unanswered check names nothing; the backend
    // validates again when the send is prepared.
    function kindOf(c) {
        if (!c || c.failed) return ""
        if (c.valid !== true) return c.reason === "this address is for another network" ? "other network" : "not an address"
        if (c.shielded === true) return "shielded"
        return c.kind === "tex" ? "tex" : "transparent"
    }
    function checkRecipient() {
        var t = sendTo.text.trim()
        if (t === "" || root.sendIsUri || !root.ready) return
        logos.watch(backend.addressValid(t),
                    function (v) {
                        var r = root.j(v, "{}")
                        if (r.ok !== true) r = { failed: true }
                        r.text = t
                        root.recipientCheck = r
                    },
                    function () { root.recipientCheck = { text: t, failed: true } })
    }

    // Restore starts from a height: a block number, or a month (mainnet) less two weeks' margin.
    // Below the first bundled checkpoint the core starts at Sapling activation.
    function birthdayFor(input) {
        var t = (input || "").trim()
        // Sapling's activation height; a regtest chain activates it at block 1.
        var floor = root.activeNetwork === "testnet" ? 280000 : (root.activeNetwork === "regtest" ? 1 : 419200)
        if (t === "") return floor
        if (/^[0-9]+$/.test(t)) return Math.max(floor, parseInt(t, 10))
        var m = /^([0-9]{4})-([0-9]{1,2})$/.exec(t)
        if (!m || root.activeNetwork !== "mainnet") return -1
        var month = parseInt(m[2], 10)
        if (month < 1 || month > 12) return -1
        var when = Date.UTC(parseInt(m[1], 10), month - 1, 1) / 1000 - 14 * 86400
        // Blossom: block 653,600 on 2019-12-11; 150 s blocks before it, 75 s after.
        var blossomAt = 1576022400
        var h = when >= blossomAt ? 653600 + Math.floor((when - blossomAt) / 75)
                                  : 653600 - Math.ceil((blossomAt - when) / 150)
        return Math.max(floor, h)
    }
    function restoreStartLine(input) {
        var h = root.birthdayFor(input)
        if (h < 0) return root.activeNetwork === "testnet" ? "On testnet, give a block height."
                                                           : "Give a month such as 2024-05, or a block height."
        if ((input || "").trim() === "")
            return "Left empty, scanning starts at the first shielded block (" + root.fmtHeight(h) + ") and takes longer."
        return "Scanning starts at block " + root.fmtHeight(h) + "."
    }

    // Blocks left, when the core reports them: scanning is not in height order.
    function syncFraction() {
        var tip = root.sync.tip, done = root.sync.fullyScanned, from = root.sync.birthday || 0
        if (!tip || tip <= from) return 0
        var left = root.sync.blocksLeft
        if (left !== undefined && left !== null) return Math.max(0, Math.min(1, 1 - left / (tip - from + 1)))
        if (done === undefined || done === null) return 0
        return Math.max(0, Math.min(1, (done - from) / (tip - from)))
    }
    function etaText(secs) {
        if (secs === undefined || secs === null) return ""
        if (secs < 60) return "under a minute left"
        var min = Math.round(secs / 60)
        if (min < 60) return "about " + min + " min left"
        return "about " + Math.floor(min / 60) + " h " + (min % 60) + " min left"
    }
    function syncLine() {
        if (!root.syncRead) return "Sync: —"
        var s = root.sync.state || ""
        if (s === "synced") return "Synced to block " + root.fmtHeight(root.sync.tip)
        if (s === "scanning" || s === "downloading") {
            var eta = root.etaText(root.sync.etaSecs)
            return "Scanning · block " + root.fmtHeight(root.sync.fullyScanned) + " of " + root.fmtHeight(root.sync.tip)
                   + " (" + Math.floor(root.syncFraction() * 100) + "%)" + (eta ? " · " + eta : "")
        }
        if (s === "starting" || s === "connecting") return root.localNodeOn ? "Connecting to your node…" : "Connecting to servers…"
        return "Sync: " + s
    }
    function syncChip() {
        if (!root.ready) return "Connecting…"
        if (!root.walletOpen) return ""
        if (!root.syncRead) return "Sync —"
        var s = root.sync.state
        if (s === "synced") return "Synced · " + root.fmtHeight(root.sync.tip)
        if (s === "scanning" || s === "downloading") return "Syncing " + Math.floor(root.syncFraction() * 100) + "%"
        return "Connecting…"
    }
    function jobLine() {
        var k = root.pendingKind
        if (k === "open") return "Opening…"
        if (k === "create") return "Creating the wallet…"
        if (k === "restore") return "Restoring the wallet…"
        if (k === "close") return "Closing…"
        if (k === "change password") return "Changing the password…"
        return "Working…"
    }
    function overallLabel(o) {
        if (o === "ok") return "Servers OK"
        if (o === "degraded") return "Servers degraded"
        if (o === "disagreement") return "Servers disagree"
        if (o === "offline") return "Servers offline"
        if (o === "update_required") return "Update required"
        return o
    }
    function overallColor(o) {
        if (o === "ok") return Theme.palette.success
        if (o === "degraded") return Theme.palette.warning
        return Theme.palette.error
    }
    // server_health() per server, as a list of { id, ... } or a map keyed by id.
    function healthOf(id) {
        var s = root.health.servers
        if (Array.isArray(s)) {
            for (var i = 0; i < s.length; i++) if (s[i] && s[i].id === id) return s[i]
            return null
        }
        return s && s[id] ? s[id] : null
    }
    function healthLine(id) {
        var h = root.healthOf(id)
        if (!h) return "not checked yet"
        if (h.reachable !== true) return "unreachable" + (h.lastError ? ": " + h.lastError : "")
        return (h.rttMs !== undefined && h.rttMs !== null ? h.rttMs + " ms" : "reachable")
               + (h.height ? " · block " + root.fmtHeight(h.height) : "")
               + (h.lastError ? " · " + h.lastError : "")
               + (h.suspect ? " · suspect" : "")
    }
    function gauge(v) { return v === undefined || v === null || v < 0 ? "—" : root.fmtHeight(v) }
    // Regtest's tip estimate runs millions of blocks ahead (its blocks carry 2011 timestamps), so it is left out.
    function localNodeLine() {
        var l = root.localNode
        if (l.network === undefined) return "Checking your node…"
        if (!l.status) return "Not installed"
        if (l.available !== true) return "Not running for this network"
        return "Running · height " + root.gauge(l.status.height)
               + (root.activeNetwork === "regtest" ? "" : " of " + root.gauge(l.status.estimatedHeight))
               + " · " + root.gauge(l.status.peers) + (l.status.peers === 1 ? " peer" : " peers")
    }
    function localNodeDetail() {
        var l = root.localNode, s = l.status
        if (l.network === undefined) return ""
        if (!s) return (l.error ? l.error + ". " : "") + "The Zcash Node app installs and runs it."
        var st = s.state || "unknown"
        if (l.available !== true) {
            if (st === "running") return "It is running " + (s.network || "another network") + "; this wallet is on " + root.activeNetwork + "."
            if (st === "failed") return "It failed" + (s.lastError ? ": " + s.lastError : ".")
            return "It is " + st + ". Start it for " + root.activeNetwork + " in the Zcash Node app."
        }
        return root.activeNetwork !== "regtest" && Number(s.estimatedHeight) - Number(s.height) > 10
               ? "Still syncing: the wallet sees the chain only as far as your node has it." : ""
    }
    // The label the user knows a server by, or its host.
    function serverName(url) {
        for (var i = 0; i < root.serverList.length; i++)
            if (root.serverList[i].url === url) return root.serverList[i].label || url
        var m = /^[a-z]+:\/\/([^\/:]+)/.exec(url || "")
        return m ? m[1] : (url || "a server")
    }
    // sync_status's crossCheck: a server against the node, at the lower of their two tips.
    function crossCheckLine() {
        var c = root.sync.crossCheck
        if (!c || c.verdict === "differs") return ""
        var name = root.serverName(c.server), gap = root.fmtHeight(Math.abs(c.nodeTip - c.serverTip))
        if (c.verdict === "node_behind") return "On the same chain as " + name + ", " + gap + " blocks behind it."
        if (c.verdict === "server_behind") return "On the same chain as " + name + ", which is " + gap + " blocks behind."
        return "Matches " + name + " at block " + root.fmtHeight(Math.min(c.nodeTip, c.serverTip)) + "."
    }
    // Loopback, private, CGNAT and link-local addresses, and local names: as the node module decides.
    function isLanUrl(url) {
        var m = /^https?:\/\/(\[[^\]]+\]|[^\/:]+)/i.exec(url || "")
        if (!m) return false
        var h = m[1].toLowerCase().replace(/^\[|\]$/g, "").replace(/\.$/, "")
        var v4 = /^(\d+)\.(\d+)\.\d+\.\d+$/.exec(h)
        if (v4) {
            var a = +v4[1], b = +v4[2]
            return a === 127 || a === 10 || (a === 172 && b >= 16 && b < 32) || (a === 192 && b === 168)
                   || (a === 100 && b >= 64 && b < 128) || (a === 169 && b === 254)
        }
        if (h.indexOf(":") >= 0) return h === "::1" || /^f[cd]/.test(h) || /^fe[89ab]/.test(h)
        return h === "localhost" || /\.(local|lan|home\.arpa|internal)$/.test(h)
    }
    function isOnionUrl(url) { return /^http:\/\/[a-z2-7]{56}\.onion(:\d+)?\/?$/i.test(url || "") }
    // A settings SLOT's reply: "" or the refusal, shown at `at`; `refused` runs on a refusal.
    function networkCall(reply, at, refused) {
        root.networkNote = ""
        logos.watch(reply,
                    function (e) {
                        root.networkNoteAt = at
                        root.networkNote = e || ""
                        if (e && refused) refused()
                    },
                    function () {
                        root.networkNoteAt = at
                        root.networkNote = "The wallet backend did not answer."
                        if (refused) refused()
                    })
    }
    function setLocalNode(on) {
        root.localNodeNote = ""
        logos.watch(backend.setLocalNode(on),
                    function (e) { root.localNodeNote = e || "" },
                    function () { root.localNodeNote = "The wallet backend did not answer." })
    }
    // The node has its own app.
    function manageLocalNode() {
        root.localNodeNote = ""
        logos.request("zcash.node.configure", ({ network: root.activeNetwork }), function (res) {
            if (res.ok || res.error === "cancelled") return
            root.localNodeNote = res.error === "unavailable" ? "The Zcash Node app is not installed."
                                                              : "That request did not go through (" + res.error + ")."
        })
    }
    function shieldedCaption() {
        if (!root.balancesRead) return ""
        if (!root.balancesReady) return "Waiting for the first scan"
        return root.zatOf(root.spendPool.pending) > 0 ? ("+ " + root.spendPool.pendingZec + " ZEC pending") : "Spendable now"
    }
    function transparentMessage() {
        var t = root.transparentPool
        var s = (t.totalZec || "0") + " ZEC"
        if (root.zatOf(t.total) > root.zatOf(t.spendable)) s += " (" + t.pendingZec + " ZEC pending)"
        s += ". Payments to your transparent addresses are public. Shield each one to spend it privately."
        // zcash_client_sqlite leaves out any transparent coin worth no more than ZIP 317's 5,000-zatoshi marginal fee.
        if (root.zatOf(t.uneconomic) > 0)
            s += " Another " + t.uneconomicZec + " ZEC is in coins too small to spend: each is worth no more than "
                 + "the 0.00005 ZEC fee it costs to spend one."
        return s
    }

    // ---- review ----
    function sendStage() {
        var s = root.send.state
        if (s === "previewed") return 1
        if (s === "signing" || s === "unknown") return 2
        if (s === "sent") return 4
        if (s === "preparing" || !root.preview) return 0
        return root.sendSigned ? 2 : 1
    }
    // Everything this transaction makes public, one line each.
    function publicLines() {
        var p = root.preview
        if (!p) return []
        var out = []
        if (p.shielding) out.push("Shielding spends one transparent address, whose amount is already public.")
        if (p.migrateNow)
            out.push("Moving now takes one transaction from Orchard, so the whole amount, "
                     + p.amountMadePublicZec + " ZEC, becomes public. Move privately avoids that.")
        else if (root.zatOf(p.amountMadePublic) > 0)
            out.push(p.amountMadePublicZec + " ZEC crosses between pools, so that amount becomes public.")
        if (!p.shielding && (p.recipients || []).some(function (r) { return r.pool === "transparent" }))
            out.push("The amount sent to a transparent address is public.")
        if ((p.steps || 1) > 1)
            out.push("This payment takes " + p.steps + " transactions, as a TEX address requires; both are public.")
        return out
    }
    function spentFromLine() {
        var s = (root.preview && root.preview.spentFromZec) || {}
        var keys = Object.keys(s)
        return keys.length ? keys.map(function (k) { return root.poolLabel(k) + " " + s[k] + " ZEC" }).join(", ") : "—"
    }
    function changeLine() {
        var c = (root.preview && root.preview.change) || []
        return c.length ? c.map(function (x) { return x.amountZec + " ZEC to " + root.poolLabel(x.pool) }).join(", ") : "none"
    }
    function approveSummary() {
        var p = root.preview
        if (!p) return ""
        if (p.shielding) return "Shield " + p.changeTotalZec + " ZEC into your shielded balance, for a " + p.feeZec + " ZEC fee."
        return "Send " + p.recipientsTotalZec + " ZEC, plus a " + p.feeZec + " ZEC fee."
    }

    // ---- migration ----
    function startMigration() {
        backend.planMigration()
        migrationReview.open()
    }
    // Seconds until block h: 75 s a block before NU7 and 25 s from it; 75 s throughout when
    // the plan names no NU7 height.
    function secondsUntil(h, tip, nu7) {
        var blocks = Math.max(0, h - tip)
        if (!nu7) return blocks * 75
        var before = Math.max(0, Math.min(blocks, nu7 - tip))
        return before * 75 + (blocks - before) * 25
    }
    function durationText(secs) {
        if (secs < 3600) return Math.max(1, Math.round(secs / 60)) + " min"
        var hours = secs / 3600
        if (hours < 48) {
            var h = Math.floor(hours), m = Math.round((secs - h * 3600) / 60)
            return h + " h" + (m ? " " + m + " min" : "")
        }
        return Math.round(hours / 24) + " days"
    }
    function whenText(h) {
        var p = root.plan
        if (!p || h === undefined || h === null) return "—"
        return "block " + root.fmtHeight(h) + ", in about " + root.durationText(root.secondsUntil(h, p.chainTip, p.nu7Height))
    }
    // What stays in Orchard after this run: dust, or the rest for a later run.
    function remainderLine() {
        var p = root.plan
        if (!p) return ""
        var rest = root.zatOf(root.orchard.total) - root.zatOf(p.migrating)
        if (rest <= 0) return ""
        return root.zecOf(rest) + " ZEC" + (rest < root.minMigratable ? ": less than 0.01 ZEC, which ZIP 318 does not move"
                                                                    : ": it moves in a later run")
    }
    function migrationApproveSummary() {
        var p = root.plan
        if (!p) return ""
        var n = root.zatOf(p.preparationTransactions) + root.zatOf(p.transfers)
        return "Sign all " + n + " transactions of this run, moving " + p.migratingZec + " ZEC into your shielded balance."
    }
    // Preparing until the preparation is mined, then waiting for the first transfer, then migrating.
    function migrationStage() {
        if (root.migrationStatus === "complete") return 4
        if (root.zatOf(root.migration.migrated) > 0) return 2
        if (root.zatOf(root.migration.mined) > 0) return 1
        return 0
    }
    function migrationTitle() {
        var s = root.migrationStatus
        if (s === "complete") return "Migration complete"
        if (s === "cancelled") return "Migration cancelled"
        if (s === "failed") return "Migration failed"
        if (s === "superseded") return "Migration replaced by a newer plan"
        if (root.migration.paused === true) return "Migration paused"
        return "Moving Orchard funds privately"
    }
    function migrationCounts() {
        var m = root.migration
        return (m.migratedZec || "0") + " of " + (m.migratableZec || "0") + " ZEC moved · "
               + root.zatOf(m.mined) + " of " + root.zatOf(m.transactions) + " transactions mined · "
               + root.zatOf(m.inFlight) + " in flight"
    }

    // ---- activity ----
    function kindLabel(k) {
        if (k === "received") return "Received"
        if (k === "sent") return "Sent"
        if (k === "shielded") return "Shielded"
        if (k === "migration") return "Migration"
        return k || ""
    }
    function txIsTransparent(r) {
        if (r.kind === "sent") return (r.to || []).concat(r.toSelf || []).some(function (t) { return t.pool === "transparent" })
        var pools = r.pools || []
        return pools.length > 0 && pools.every(function (p) { return p === "transparent" })
    }
    // What the transaction was for, as Monero shows it. A self-send or a shielding moves an amount
    // and costs only the fee, so its balance change alone would read as just the fee.
    function intentLine(r) {
        var fee = root.zatOf(r.fee) > 0 ? " · fee " + r.feeZec + " ZEC" : ""
        if (r.kind === "shielded" && root.zatOf(r.shielded) > 0) return r.shieldedZec + " ZEC shielded" + fee
        if (r.kind === "sent") {
            var others = root.zatOf(r.sentToOthers), self = root.zatOf(r.sentToSelf)
            if (others > 0) return "−" + r.sentToOthersZec + " ZEC" + (self > 0 ? " · " + r.sentToSelfZec + " ZEC to yourself" : "") + fee
            if (self > 0) return r.sentToSelfZec + " ZEC to yourself" + fee
        }
        return root.signedZec(r.deltaZec) + " ZEC"
    }
    function signedZec(s) {
        var v = s || "0"
        return v.charAt(0) === "-" ? "−" + v.slice(1) : (v === "0" ? v : "+" + v)
    }
    function txStatus(r) {
        if (r.expired) return "expired"
        if (r.pending) {
            var left = root.zatOf(r.expiryHeight) - root.chainTip
            return "pending" + (r.expiryHeight && root.chainTip ? " · expires in " + Math.max(0, left) + " blocks" : "")
        }
        if (!r.height || !root.chainTip) return "mined"
        var n = root.chainTip - r.height + 1
        return n >= 10 ? "confirmed" : (n > 0 ? n + " conf" : "mined")
    }

    // Built on the Wallets screen and in Settings: servers are needed before a wallet can open.
    // While one is open the settings show but do not change; they apply when a wallet opens.
    Component {
        id: networkPane
        ColumnLayout {
            id: pane
            spacing: Theme.spacing.small

            // The fields clear at once, so a reply arriving later never wipes the next server typed in.
            function addServer() {
                var address = addServerAddress.text.trim(), name = addServerName.text.trim()
                addServerAddress.text = ""
                addServerName.text = ""
                root.networkCall(backend.addServer(address, name), "servers", function () {
                    if (addServerAddress.text === "" && addServerName.text === "") {
                        addServerAddress.text = address
                        addServerName.text = name
                    }
                })
            }

            LogosNotice {
                objectName: "networkLockedNotice"
                Layout.fillWidth: true
                shown: root.networkLocked
                message: "These settings apply when a wallet opens. Close the wallet to change them."
            }

            LogosText { text: "Network privacy"; font.pixelSize: 15 }
            LogosText { Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.palette.textSecondary
                        text: "Servers go through this Tor proxy, unless you set one to skip Tor. Servers on your own network "
                              + "are reached directly, since Tor cannot reach them." }
            RowLayout {
                Layout.fillWidth: true
                LogosTextField { id: proxyField; objectName: "proxyField"; Layout.fillWidth: true; readOnly: root.networkLocked
                                 placeholderText: root.defaultProxy; text: root.serversInfo.proxy || "" }
                LogosButton {
                    objectName: "saveProxyButton"; text: "Save proxy"
                    visible: !root.networkLocked
                    enabled: root.ready && proxyField.text.trim() !== "" && proxyField.text.trim() !== (root.serversInfo.proxy || "")
                    onClicked: root.networkCall(backend.setProxy(proxyField.text.trim()), "proxy")
                }
            }
            LogosNotice {
                Layout.fillWidth: true
                severity: LogosNotice.Error
                shown: root.networkNote !== "" && root.networkNoteAt === "proxy"
                message: shown ? root.networkNote : ""
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Theme.spacing.small
                LogosText { text: "Servers"; font.pixelSize: 15 }
                LogosInfoButton {
                    objectName: "operatorsInfo"
                    title: "More than one operator"
                    text: "Blocks come from each operator in turn and must fit together, so a server that serves a false chain "
                          + "is caught. A transaction one server accepts must reach another operator within two minutes, or the "
                          + "wallet sends it there too, so a server that drops it is caught. If one operator goes down, another "
                          + "keeps the wallet working, and no one operator sees every transaction you look up. Servers of the "
                          + "same operator only stand in for each other."
                }
                LogosBadge { visible: root.overall !== ""; text: root.overallLabel(root.overall); color: root.overallColor(root.overall) }
                Item { Layout.fillWidth: true }
            }
            LogosText { Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.palette.textTertiary
                        text: (root.localNodeOn ? "Your node answers every read; these servers only receive the transactions you send. "
                                                : "")
                              + "Turn on the servers you want, from more than one operator if you can: they check each other. "
                              + "A change applies the next time a wallet opens." }
            // Above the list, so it stays in place however long the list grows.
            ColumnLayout {
                objectName: "addServerPane"
                Layout.fillWidth: true
                Layout.topMargin: Theme.spacing.small
                visible: !root.networkLocked
                spacing: Theme.spacing.tiny
                LogosText { text: "Add a server"; font.weight: Theme.typography.weightMedium }
                LogosText { Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.palette.textSecondary
                            text: "A lightwalletd server you trust, such as your own node: an address like 192.168.1.20 or "
                                  + "zebra.lan:9067, or https://host:port. Servers on your own network are reached directly, "
                                  + "without Tor. Plain http to them is not encrypted, so use it only on a network you trust." }
                RowLayout {
                    Layout.fillWidth: true
                    LogosTextField { id: addServerAddress; objectName: "addServerAddress"; Layout.fillWidth: true
                                     placeholderText: "192.168.1.20:9067" }
                    LogosTextField { id: addServerName; objectName: "addServerName"; Layout.preferredWidth: 180
                                     placeholderText: "Name (optional)" }
                    LogosButton { objectName: "addServerButton"; text: "Add"
                                  enabled: root.ready && addServerAddress.text.trim() !== ""; onClicked: pane.addServer() }
                }
            }
            LogosNotice {
                objectName: "serversNote"
                Layout.fillWidth: true
                severity: LogosNotice.Error
                shown: root.networkNote !== "" && root.networkNoteAt === "servers"
                message: shown ? root.networkNote : ""
            }
            LogosText { visible: root.serverList.length === 0; color: Theme.palette.textSecondary
                        text: "No server list yet." }
            Repeater {
                model: root.serverList
                LogosFrame {
                    id: serverRow
                    readonly property bool lan: root.isLanUrl(modelData.url)
                    readonly property bool onion: root.isOnionUrl(modelData.url)
                    readonly property bool direct: modelData.direct === true && !lan
                    Layout.fillWidth: true
                    contentItem: ColumnLayout {
                        spacing: Theme.spacing.tiny
                        RowLayout {
                            Layout.fillWidth: true
                            LogosText { textFormat: Text.PlainText; text: modelData.label || modelData.id || "" }
                            LogosText { visible: text !== "" && text !== (modelData.label || ""); textFormat: Text.PlainText
                                        color: Theme.palette.textTertiary; text: modelData.operator || "" }
                            LogosBadge { text: modelData.enabled ? (root.localNodeOn ? "Broadcasts" : "In use") : "Standby"
                                         color: modelData.enabled ? Theme.palette.success : Theme.palette.textTertiary }
                            LogosBadge { objectName: "lanBadge_" + modelData.id; visible: serverRow.lan
                                         text: "Your network"; color: Theme.palette.textSecondary }
                            LogosBadge { objectName: "withoutTorBadge_" + modelData.id; visible: serverRow.direct
                                         text: "Without Tor"; color: Theme.palette.warning }
                            // Takes the free space but asks for none, so a long error elides (keeping its cause)
                            // instead of widening the row and pushing its controls out.
                            LogosText { Layout.fillWidth: true; Layout.preferredWidth: 1; horizontalAlignment: Text.AlignRight; elide: Text.ElideMiddle
                                        textFormat: Text.PlainText; font.pixelSize: 12; color: Theme.palette.textSecondary
                                        text: modelData.enabled ? root.healthLine(modelData.id) : "" }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            LogosText { Layout.fillWidth: true; Layout.preferredWidth: 1; elide: Text.ElideRight; textFormat: Text.PlainText
                                        font.pixelSize: 11; color: Theme.palette.textTertiary
                                        text: (modelData.url || "") + (serverRow.lan ? " · reached directly, without Tor"
                                              : serverRow.onion ? " · an onion service, always through Tor"
                                              : serverRow.direct ? " · without Tor" : " · through Tor") }
                            // Off asks first, below; on needs no asking.
                            LogosSwitch {
                                objectName: "torSwitch_" + modelData.id
                                visible: !root.networkLocked && !serverRow.lan && !serverRow.onion
                                text: "Tor"
                                checkable: false
                                checked: !serverRow.direct
                                enabled: root.ready
                                onClicked: {
                                    if (serverRow.direct) root.networkCall(backend.setServerTor(modelData.id, true), "servers")
                                    else root.torOffAskedFor = modelData.id
                                }
                            }
                            LogosSwitch {
                                objectName: "serverSwitch_" + modelData.id
                                visible: !root.networkLocked
                                text: "Use"
                                checkable: false
                                checked: modelData.enabled === true
                                enabled: root.ready
                                onClicked: root.networkCall(backend.setServerEnabled(modelData.id, !modelData.enabled), "servers")
                            }
                            LogosButton {
                                objectName: "removeServer_" + modelData.id
                                visible: !root.networkLocked && modelData.source === "user"
                                text: "Remove"
                                enabled: root.ready
                                onClicked: root.networkCall(backend.removeServer(modelData.id), "servers")
                            }
                        }
                        LogosNotice {
                            objectName: "torOffConfirm_" + modelData.id
                            Layout.fillWidth: true
                            severity: LogosNotice.Warning
                            shown: root.torOffAskedFor === modelData.id && !serverRow.direct && !root.networkLocked
                            title: "Reach " + (modelData.label || modelData.id) + " without Tor?"
                            message: "It will see this computer's IP address, and can link it to the transactions this wallet "
                                     + "sends and looks up, and to its transparent addresses. Your internet provider sees that "
                                     + "you use Zcash."
                            actions: [
                                LogosButton { objectName: "skipTorButton_" + modelData.id; text: "Reach it without Tor"
                                              onClicked: { root.torOffAskedFor = ""; root.networkCall(backend.setServerTor(modelData.id, false), "servers") } },
                                LogosButton { objectName: "keepTorButton_" + modelData.id; text: "Keep Tor"
                                              onClicked: root.torOffAskedFor = "" }
                            ]
                        }
                    }
                }
            }
            LogosNotice {
                objectName: "oneOperatorNotice"
                Layout.fillWidth: true
                shown: root.serversRead && !root.localNodeOn && root.operatorsInUse.length === 1
                message: shown ? "Only " + root.operatorsInUse[0] + " is in use, so nothing checks its answers. "
                                 + "Turn on a server from another operator." : ""
            }
            // Below the list, so the rows do not move when it appears; each row has its own badge.
            LogosNotice {
                objectName: "directNotice"
                Layout.fillWidth: true
                severity: LogosNotice.Warning
                shown: root.directServers.length > 0
                title: "Reached without Tor"
                message: shown ? root.directServers.map(function (d) { return d.label || d.id }).join(", ")
                                 + (root.directServers.length === 1 ? " sees" : " see")
                                 + " this computer's IP address, and can link it to this wallet's transactions." : ""
            }
            ColumnLayout {
                id: localNodePane
                objectName: "localNodePane"
                Layout.fillWidth: true
                Layout.topMargin: Theme.spacing.small
                spacing: Theme.spacing.small
                // Read while on screen only: an absent zebrad_module costs the node module 1.5 s a read.
                onVisibleChanged: if (visible && root.ready) backend.refreshLocalNode()
                Component.onCompleted: if (visible && root.ready) backend.refreshLocalNode()
                Timer {
                    interval: root.localStatus ? 3000 : 15000
                    repeat: true
                    running: localNodePane.visible && root.ready
                    onTriggered: backend.refreshLocalNode()
                }

                RowLayout {
                    Layout.fillWidth: true
                    LogosText { text: "Your node"; font.pixelSize: 15 }
                    Item { Layout.fillWidth: true }
                    LogosSwitch {
                        objectName: "localNodeSwitch"
                        text: "Use my local node"
                        checkable: false
                        checked: root.localNodeOn
                        enabled: root.ready && !root.networkLocked && (root.localNodeOn || root.localNodeAvailable)
                        onClicked: root.setLocalNode(!root.localNodeOn)
                    }
                }
                LogosText {
                    Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.palette.textSecondary
                    text: "Reads come from your own Zcash node over Logos IPC, so no server sees them. Transactions you send "
                          + "still go to the servers below. With no server enabled, your node broadcasts them itself, "
                          + "over its own peer connections and without Tor. A change applies the next time a wallet opens."
                }
                LogosText {
                    objectName: "localNodeState"
                    Layout.fillWidth: true; Layout.topMargin: Theme.spacing.tiny; textFormat: Text.PlainText; wrapMode: Text.Wrap
                    font.weight: Theme.typography.weightMedium
                    color: root.localNodeAvailable ? Theme.palette.success : Theme.palette.text
                    text: root.localNodeLine()
                }
                LogosText {
                    objectName: "localNodeDetail"
                    Layout.fillWidth: true; visible: text !== ""; textFormat: Text.PlainText; wrapMode: Text.Wrap
                    color: Theme.palette.textSecondary
                    text: root.localNodeDetail()
                }
                LogosText {
                    objectName: "localNodeCrossCheck"
                    Layout.fillWidth: true; visible: text !== ""; textFormat: Text.PlainText; wrapMode: Text.Wrap
                    color: Theme.palette.textSecondary
                    text: root.crossCheckLine()
                }
                LogosNotice {
                    readonly property var check: root.sync.crossCheck
                    objectName: "localNodeDiffersNotice"
                    Layout.fillWidth: true
                    severity: LogosNotice.Error
                    shown: !!check && check.verdict === "differs"
                    message: shown ? "Your node and " + root.serverName(check.server) + " have different blocks at "
                                     + root.fmtHeight(Math.min(check.nodeTip, check.serverTip)) + ", so one of them is on a "
                                     + "false chain. Until they agree, do not count on new payments shown here." : ""
                }
                LogosNotice {
                    objectName: "localNodeDownNotice"
                    Layout.fillWidth: true
                    severity: LogosNotice.Warning
                    shown: root.localNodeOn && root.localNode.network !== undefined && !root.localNodeAvailable
                    message: "Reads go to your node, which is not running for " + root.activeNetwork + ". The wallet cannot sync until it is."
                }
                LogosNotice {
                    objectName: "localNodeBroadcastNotice"
                    Layout.fillWidth: true
                    severity: LogosNotice.Warning
                    shown: root.localNodeOn && root.serversRead && !root.broadcastServer
                    message: "No server is enabled, so your node sends your transactions itself, without Tor: "
                             + "its peers see them come from this computer's IP address."
                }
                RowLayout {
                    Layout.fillWidth: true
                    LogosButton { objectName: "manageLocalNodeButton"; text: "Manage local node…"; enabled: root.ready; onClicked: root.manageLocalNode() }
                    LogosText { objectName: "localNodeNote"; visible: text !== ""; Layout.fillWidth: true; textFormat: Text.PlainText
                                wrapMode: Text.Wrap; color: Theme.palette.error; text: root.localNodeNote }
                }
            }


        }
    }

    ColumnLayout {
        anchors.fill: parent; anchors.margins: 16; spacing: 10

        RowLayout {
            Layout.fillWidth: true
            LogosText { text: "Zcash"; font.pixelSize: 22 }
            Item { Layout.fillWidth: true }
            LogosText { objectName: "syncChip"; textFormat: Text.PlainText; font.pixelSize: 12
                        color: Theme.palette.textSecondary; text: root.syncChip() }
            // Orange marks the network where the money is not real.
            LogosBadge {
                objectName: "networkChip"
                text: root.displayedNetwork || "—"
                color: root.displayedNetwork === "mainnet" ? Theme.palette.success : Theme.palette.accentOrange
            }
            LogosButton {
                objectName: "closeWalletButton"
                visible: root.walletOpen
                enabled: root.ready && !root.busy
                text: "Close wallet"
                onClicked: { root.hideSecret(); backend.closeWallet() }
            }
        }

        LogosText {
            objectName: "statusLine"
            textFormat: Text.PlainText
            color: Theme.palette.textSecondary
            text: !root.ready ? "" : (root.busy ? root.jobLine()
                  : (root.walletOpen ? ("Open: " + (status.name || "") + " · " + (status.network || "")) : "No wallet open"))
        }

        LogosNotice {
            objectName: "errorNotice"
            Layout.fillWidth: true
            severity: LogosNotice.Error
            closable: true
            shown: false
            message: root.ready ? backend.lastError : ""
            onMessageChanged: shown = message.length > 0
            Component.onCompleted: shown = message.length > 0
        }

        // Above the tabs, not in the review: the engine dying is what makes an outcome unknown,
        // and it also closes the wallet.
        LogosNotice {
            objectName: "sendUnknownBanner"
            Layout.fillWidth: true
            severity: LogosNotice.Warning
            shown: root.sendOpen && root.send.state === "unknown"
            title: "A transaction's outcome is unknown"
            message: (root.send.error ? root.send.error + "\n" : "") + "Check Activity once the wallet re-syncs, before sending again."
            actions: [ LogosButton { objectName: "dismissUnknownButton"; text: "Dismiss"; onClicked: backend.dismissSend() } ]
        }
        LogosNotice {
            objectName: "sendWaitingBanner"
            Layout.fillWidth: true
            severity: LogosNotice.Info
            shown: root.walletOpen && root.sendOpen && root.send.state !== "unknown" && !reviewSheet.visible
            title: root.sendLive ? "A send is waiting for review" : "A send has settled"
            message: root.sendLive ? "Its preview expires two minutes after it is built." : ("State: " + (root.send.state || ""))
            actions: [ LogosButton { objectName: "showReviewButton"; text: "Show"; onClicked: reviewSheet.open() } ]
        }

        // ================= NO WALLET OPEN: the Wallets screen =================
        ColumnLayout {
            objectName: "walletsPage"
            visible: root.ready && !root.walletOpen
            Layout.fillWidth: true; Layout.fillHeight: true
            spacing: Theme.spacing.small

            RowLayout {
                Layout.fillWidth: true
                LogosText { text: "Wallets"; font.pixelSize: 22 }
                Item { Layout.fillWidth: true }
                LogosText { text: "Network"; color: Theme.palette.textSecondary }
                LogosComboBox {
                    objectName: "networkBox"
                    enabled: root.ready && !root.busy
                    model: networks.networks || []
                    currentIndex: Math.max(0, (networks.networks || []).indexOf(networks.active || ""))
                    onActivated: root.selectNetwork(currentText)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.small
                LogosButton { objectName: "createWalletButton"; text: "Create"; enabled: root.ready && !root.busy; onClicked: createSheet.open() }
                LogosButton { objectName: "restoreWalletButton"; text: "Restore"; enabled: root.ready && !root.busy; onClicked: restoreSheet.open() }
                LogosButton { objectName: "networkSettingsButton"; text: "Servers and privacy"; enabled: root.ready; onClicked: networkSheet.open() }
                Item { Layout.fillWidth: true }
                LogosButton { objectName: "refreshWalletsButton"; text: "Refresh"; enabled: root.ready; onClicked: backend.clearAndRefresh() }
            }

            Item {
                Layout.fillWidth: true; Layout.fillHeight: true

                LogosText {
                    objectName: "walletsEmpty"
                    anchors.centerIn: parent
                    visible: root.walletsOnNetwork.length === 0
                    color: Theme.palette.textSecondary
                    text: "No wallets on " + (root.activeNetwork || "this network") + " yet"
                }

                ListView {
                    objectName: "walletList"
                    anchors.fill: parent
                    clip: true
                    spacing: Theme.spacing.tiny
                    model: root.walletsOnNetwork
                    delegate: LogosFrame {
                        width: ListView.view.width
                        contentItem: RowLayout {
                            spacing: Theme.spacing.small
                            LogosText { text: modelData.name; textFormat: Text.PlainText }
                            LogosText { textFormat: Text.PlainText; color: Theme.palette.textTertiary
                                        text: "from block " + root.fmtHeight(modelData.birthdayHeight) }
                            Item { Layout.fillWidth: true }
                            LogosButton {
                                text: "Open"
                                enabled: root.ready && !root.busy
                                onClicked: { openNameField.text = modelData.name; openWalletSheet.open() }
                            }
                        }
                    }
                }
            }
        }

        // ================= A WALLET IS OPEN =================
        LogosTabBar {
            id: tabs
            objectName: "walletTabs"
            visible: root.walletOpen
            Layout.fillWidth: true
            // Not bound to root.page: a click assigns currentIndex and would break the binding.
            onCurrentIndexChanged: root.selectTab(currentIndex)
            LogosTabButton { text: "Home" }
            LogosTabButton { text: "Send" }
            LogosTabButton { text: "Receive" }
            LogosTabButton { text: "Activity" }
            LogosTabButton { text: "Settings" }
        }

        StackLayout {
            visible: root.walletOpen
            Layout.fillWidth: true; Layout.fillHeight: true
            currentIndex: root.page

            // Home
            ScrollView {
                id: homeScroll
                clip: true
                contentWidth: availableWidth
                ColumnLayout {
                    width: homeScroll.availableWidth
                    spacing: Theme.spacing.medium

                    LogosStatCard {
                        objectName: "shieldedBalanceCard"
                        Layout.fillWidth: true
                        label: "Shielded balance"
                        value: root.balancesReady ? (root.spendPool.spendableZec + " ZEC") : "— ZEC"
                        caption: root.shieldedCaption()
                        valueFontSizeMode: Text.HorizontalFit
                        labelTrailing: [
                            LogosBadge { text: "Shielded"; color: Theme.palette.success },
                            LogosInfoButton {
                                title: "Shielded"
                                text: "Sender, receiver and amount are encrypted on-chain. This is the balance Send spends, "
                                      + "held in the Ironwood and Sapling pools. Pending funds become spendable after 3 "
                                      + "confirmations for your own change and 10 for payments from others."
                            }
                        ]
                    }

                    LogosNotice {
                        objectName: "transparentRow"
                        Layout.fillWidth: true
                        shown: root.balancesReady && (root.zatOf(root.transparentPool.total) > 0
                                                      || root.zatOf(root.transparentPool.uneconomic) > 0)
                        severity: LogosNotice.Info
                        title: "Transparent funds"
                        message: root.balancesReady ? root.transparentMessage() : ""
                        actions: [
                            ColumnLayout {
                                spacing: Theme.spacing.tiny
                                RowLayout {
                                    LogosBadge { text: "Transparent"; color: Theme.palette.warning }
                                    LogosInfoButton {
                                        title: "Transparent"
                                        text: "Sender, receiver and amount are public, as in Bitcoin. Shielding moves one "
                                              + "address at a time, so your addresses are never linked in one transaction."
                                    }
                                }
                                // One Shield per address: shielding several in one transaction links them (ZIP 315).
                                Repeater {
                                    model: root.transparentAddresses
                                    RowLayout {
                                        spacing: Theme.spacing.small
                                        LogosText { textFormat: Text.PlainText; font.pixelSize: 12; text: modelData.address }
                                        LogosText { objectName: "transparentAmount_" + modelData.address
                                                    textFormat: Text.PlainText; font.pixelSize: 12; color: Theme.palette.textSecondary
                                                    text: modelData.totalZec + " ZEC" + (root.zatOf(modelData.uneconomic) > 0
                                                          ? " + " + modelData.uneconomicZec + " ZEC too small to spend" : "") }
                                        LogosButton {
                                            objectName: "shieldButton"
                                            visible: root.zatOf(modelData.spendable) >= root.shieldThreshold
                                            text: "Shield"
                                            enabled: root.ready && !root.sendLive
                                            onClicked: root.shield(modelData.address)
                                        }
                                        LogosText {
                                            visible: root.zatOf(modelData.spendable) < root.shieldThreshold
                                            font.pixelSize: 12
                                            color: Theme.palette.textSecondary
                                            text: root.zatOf(modelData.total) >= root.shieldThreshold ? "Waiting for confirmations"
                                                  : root.zatOf(modelData.total) > 0 ? "Too small to shield" : "Too small to spend"
                                        }
                                    }
                                }
                            }
                        ]
                    }

                    // Migration required: Orchard funds that no live run is moving.
                    LogosNotice {
                        objectName: "orchardRow"
                        Layout.fillWidth: true
                        shown: root.balancesReady && root.zatOf(root.orchard.total) > 0 && !root.migrationLive
                        severity: root.zatOf(root.orchard.total) >= root.minMigratable ? LogosNotice.Warning : LogosNotice.Info
                        title: root.zatOf(root.orchard.total) >= root.minMigratable ? "Migration required" : "Orchard dust"
                        message: root.balancesReady
                                 ? ((root.orchard.totalZec || "0") + " ZEC is in Orchard, which has been spend-only since NU6.3. "
                                    + (root.zatOf(root.orchard.total) >= root.minMigratable
                                       ? "Move privately sends it into your shielded balance on the ZIP 318 schedule, over hours or days. "
                                         + "Move now sends all of it in one transaction, which makes the whole amount public."
                                       : "ZIP 318 does not move less than 0.01 ZEC."))
                                 : ""
                        actions: [
                            LogosBadge { text: "Orchard"; color: Theme.palette.info },
                            LogosButton {
                                objectName: "migrateButton"
                                visible: root.zatOf(root.orchard.total) >= root.minMigratable
                                text: root.migrationJob === "plan" ? "Planning…" : "Move privately"
                                enabled: root.ready && root.migrationJob === "" && root.zatOf(root.orchard.spendable) >= root.minMigratable
                                onClicked: root.startMigration()
                            },
                            LogosButton {
                                objectName: "migrateNowButton"
                                visible: root.zatOf(root.orchard.total) >= root.minMigratable
                                text: "Move now"
                                enabled: root.ready && root.migrationJob === "" && !root.sendLive
                                         && root.zatOf(root.orchard.spendable) >= root.minMigratable
                                onClicked: root.migrateNow()
                            },
                            LogosText {
                                visible: root.zatOf(root.orchard.total) >= root.minMigratable
                                         && root.zatOf(root.orchard.spendable) < root.minMigratable
                                font.pixelSize: 12
                                color: Theme.palette.textSecondary
                                text: "Waiting for confirmations"
                            }
                        ]
                    }

                    // The run: its phase, how far it got, and the controls ZIP 318 leaves to the user.
                    LogosFrame {
                        objectName: "migrationPanel"
                        visible: root.migrationShown
                        Layout.fillWidth: true
                        contentItem: ColumnLayout {
                            spacing: Theme.spacing.small
                            RowLayout {
                                Layout.fillWidth: true
                                LogosText { objectName: "migrationTitle"; font.pixelSize: 15; text: root.migrationTitle() }
                                LogosBadge { text: "Orchard to Ironwood"; color: Theme.palette.info }
                                Item { Layout.fillWidth: true }
                                LogosInfoButton {
                                    title: "Moving Orchard funds"
                                    text: "ZIP 318 moves Orchard funds into Ironwood in fixed amounts, at random times, so that "
                                          + "they blend with other wallets' migrations. Each amount is public as it moves; who owns it "
                                          + "is not. The wallet broadcasts only while it is open and synced, so a run can slip by "
                                          + "a few hours; that is normal."
                                }
                            }
                            LogosStageLane {
                                objectName: "migrationStageLane"
                                visible: !root.migrationEnded || root.migrationStatus === "complete"
                                Layout.fillWidth: true
                                currentIndex: root.migrationStage()
                                busy: root.migrationLive && root.migration.paused !== true
                                stages: [
                                    LogosStage { label: "Preparing"; busyLabel: "Preparing…" },
                                    LogosStage { label: "Waiting"; busyLabel: "Waiting for its window…" },
                                    LogosStage { label: "Migrating"; busyLabel: "Migrating…" },
                                    LogosStage { label: "Done" }
                                ]
                            }
                            LogosProgressBar {
                                objectName: "migrationProgress"
                                visible: root.migrationLive
                                Layout.fillWidth: true
                                value: root.zatOf(root.migration.migratable) > 0
                                       ? root.zatOf(root.migration.migrated) / root.zatOf(root.migration.migratable) : 0
                            }
                            LogosText {
                                objectName: "migrationCounts"
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                textFormat: Text.PlainText
                                color: Theme.palette.textSecondary
                                text: root.migrationStatus === "complete"
                                      ? ((root.migration.migratedZec || "0") + " ZEC moved into your shielded balance in "
                                         + root.zatOf(root.migration.transactions) + " transactions.")
                                      : root.migrationCounts()
                            }
                            LogosText {
                                visible: root.zatOf(root.migration.unsatisfiable) > 0
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                color: Theme.palette.warning
                                text: root.zatOf(root.migration.unsatisfiable) + " transactions can no longer be mined."
                            }
                            LogosText {
                                visible: root.migrationLive && root.migration.paused === true
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                color: Theme.palette.textSecondary
                                text: "Paused: nothing more is broadcast until you resume. Transfers already sent may still confirm."
                            }
                            LogosNotice {
                                objectName: "migrationNeedsApproval"
                                Layout.fillWidth: true
                                severity: LogosNotice.Warning
                                shown: !!root.migration.needsApproval
                                title: "The migration needs your approval"
                                message: String(root.migration.needsApproval || "")
                                actions: [
                                    LogosButton { objectName: "replanMigrationButton"; text: "Plan again"
                                                  enabled: root.ready && root.migrationJob === ""
                                                  onClicked: root.startMigration() }
                                ]
                            }
                            LogosNotice {
                                Layout.fillWidth: true
                                severity: LogosNotice.Error
                                shown: message.length > 0 && !migrationReview.visible
                                message: root.migrationError
                            }
                            RowLayout {
                                spacing: Theme.spacing.small
                                LogosButton { objectName: "pauseMigrationButton"; text: root.migrationJob === "pause" ? "Pausing…" : "Pause"
                                              visible: root.migrationLive && root.migration.paused !== true
                                              enabled: root.ready && root.migrationJob === ""
                                              onClicked: backend.pauseMigration() }
                                LogosButton { objectName: "resumeMigrationButton"; text: root.migrationJob === "resume" ? "Resuming…" : "Resume"
                                              visible: root.migrationLive && root.migration.paused === true
                                              enabled: root.ready && root.migrationJob === ""
                                              onClicked: backend.resumeMigration() }
                                LogosButton { objectName: "cancelMigrationButton"; text: root.migrationJob === "cancel" ? "Cancelling…" : "Cancel"
                                              visible: root.migrationLive
                                              enabled: root.ready && root.migrationJob === ""
                                              onClicked: cancelMigrationSheet.open() }
                                LogosButton { objectName: "dismissMigrationButton"; text: "Dismiss"
                                              visible: root.migrationEnded
                                              onClicked: root.dismissedRun = root.migration.id || "" }
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacing.tiny
                        RowLayout {
                            Layout.fillWidth: true
                            LogosText { objectName: "syncLine"; textFormat: Text.PlainText; text: root.syncLine() }
                            Item { Layout.fillWidth: true }
                            LogosBadge {
                                objectName: "serverHealthBadge"
                                visible: root.overall !== ""
                                text: root.overallLabel(root.overall)
                                color: root.overallColor(root.overall)
                            }
                        }
                        LogosProgressBar {
                            objectName: "syncProgress"
                            Layout.fillWidth: true
                            visible: root.syncRead && root.sync.state !== "synced"
                            indeterminate: !root.sync.tip
                            value: root.syncFraction()
                        }
                        LogosText {
                            visible: root.syncRead && !!root.sync.lastError
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            textFormat: Text.PlainText
                            color: Theme.palette.warning
                            font.pixelSize: 12
                            text: "Last sync error: " + (root.sync.lastError || "")
                        }
                    }
                }
            }

            // Send
            ScrollView {
                id: sendScroll
                clip: true
                contentWidth: availableWidth
                ColumnLayout {
                    width: sendScroll.availableWidth
                    spacing: Theme.spacing.small

                    LogosText {
                        objectName: "sendAvailable"
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        color: Theme.palette.textSecondary
                        textFormat: Text.PlainText
                        text: "Send spends your shielded balance only"
                              + (root.balancesReady ? (": " + root.spendPool.spendableZec + " ZEC is available.") : ".")
                    }
                    LogosText { text: "Recipient"; color: Theme.palette.textSecondary }
                    RowLayout {
                        Layout.fillWidth: true
                        LogosTextField {
                            id: sendTo
                            objectName: "sendRecipientField"
                            Layout.fillWidth: true
                            enabled: !root.sendLive
                            placeholderText: "Shielded, transparent or TEX address, or a zcash: payment request"
                            onTextChanged: recipientCheckTimer.restart()
                        }
                        // Checked once typing pauses, not on every keystroke.
                        Timer { id: recipientCheckTimer; interval: 300; onTriggered: root.checkRecipient() }
                        LogosBadge {
                            objectName: "recipientKindBadge"
                            visible: root.recipientKind !== ""
                            text: root.recipientKind
                            color: root.recipientKind === "shielded" ? Theme.palette.success
                                   : (root.recipientKind === "other network" || root.recipientKind === "not an address"
                                      ? Theme.palette.error : Theme.palette.warning)
                        }
                    }
                    LogosText {
                        visible: root.recipientKind === "transparent" || root.recipientKind === "tex"
                        Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.palette.warning
                        text: root.recipientKind === "tex"
                              ? "A TEX address takes two transactions, and the amount is public."
                              : "The amount sent to a transparent address is public."
                    }
                    LogosText {
                        visible: root.recipientKind === "other network" || root.recipientKind === "not an address"
                        color: Theme.palette.error
                        text: root.recipientKind === "other network" ? "This address is for another network."
                                                                     : "This is not a Zcash address."
                    }
                    LogosText { visible: !root.sendIsUri; text: "Amount (ZEC)"; color: Theme.palette.textSecondary }
                    LogosTextField {
                        id: sendAmount
                        objectName: "sendAmountField"
                        visible: !root.sendIsUri
                        Layout.fillWidth: true
                        enabled: !root.sendLive
                        placeholderText: "0.0"
                        validator: RegularExpressionValidator { regularExpression: /^[0-9]{0,8}\.?[0-9]{0,8}$/ }
                    }
                    LogosText { visible: root.memoAllowed && !root.sendIsUri; text: "Memo"; color: Theme.palette.textSecondary }
                    LogosTextArea {
                        id: sendMemo
                        objectName: "sendMemoField"
                        visible: root.memoAllowed && !root.sendIsUri
                        Layout.fillWidth: true
                        Layout.preferredHeight: 80
                        enabled: !root.sendLive
                        placeholderText: "Private note to a shielded recipient (optional)"
                    }
                    LogosText {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        color: root.memoAllowed && root.memoBytes > 512 ? Theme.palette.error : Theme.palette.textTertiary
                        text: root.sendIsUri ? "The payment request sets the amount and any memo."
                              : (!root.memoAllowed ? "No memo: memos go to shielded recipients only."
                                 : (root.memoBytes > 512 ? "A memo holds at most 512 bytes; this one has " + root.memoBytes + "."
                                    : "Memos go to shielded recipients only."))
                    }
                    LogosNotice {
                        objectName: "sendErrorNotice"
                        Layout.fillWidth: true
                        severity: LogosNotice.Error
                        shown: message.length > 0 && !root.sendOpen
                        message: root.ready ? backend.sendError : ""
                    }
                    LogosButton {
                        objectName: "reviewButton"
                        text: "Review"
                        variant: LogosButton.Variant.Primary
                        enabled: root.canReview
                        onClicked: root.review()
                    }
                }
            }

            // Receive
            ColumnLayout {
                spacing: Theme.spacing.small

                LogosTabBar {
                    id: receiveTabs
                    objectName: "receiveTabs"
                    Layout.fillWidth: true
                    LogosTabButton { text: "Shielded" }
                    LogosTabButton { text: "Transparent" }
                }

                StackLayout {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    currentIndex: receiveTabs.currentIndex

                    ColumnLayout {
                        objectName: "receiveShieldedPage"
                        spacing: Theme.spacing.small
                        RowLayout {
                            LogosBadge { text: "Shielded"; color: Theme.palette.success }
                            LogosInfoButton {
                                title: "Shielded address"
                                text: "A Unified Address with Orchard and Sapling receivers; funds land in your shielded "
                                      + "balance. Sender, receiver and amount are encrypted on-chain. New address makes "
                                      + "another one: all pay into the same balance, and none can be linked to the others on-chain."
                            }
                        }
                        LogosText { Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.palette.textSecondary
                                    text: "Give this address to be paid privately." }
                        QrMatrix { objectName: "shieldedQr"; qr: root.ready ? root.parseQr(backend.shieldedQrJson) : null }
                        LogosCopyableText {
                            objectName: "shieldedAddress"
                            Layout.fillWidth: true
                            text: root.receiveRead && receive.unified ? root.shortAddress(receive.unified) : "—"
                            copyText: receive.unified || ""
                            showCopyButton: !!receive.unified
                            onCopied: root.notify("Shielded address copied", "")
                        }
                        LogosButton {
                            objectName: "newAddressButton"
                            text: "New address"
                            enabled: root.ready && root.receiveRead
                            onClicked: backend.newAddress()
                        }
                        Item { Layout.fillHeight: true }
                    }

                    ColumnLayout {
                        objectName: "receiveTransparentPage"
                        spacing: Theme.spacing.small
                        RowLayout {
                            LogosBadge { text: "Transparent"; color: Theme.palette.warning }
                            LogosInfoButton {
                                title: "Transparent address"
                                text: "Sender, receiver and amount are all public, as in Bitcoin. Use it only for payers "
                                      + "that cannot pay a shielded address. Once it has been paid, a new address replaces it."
                            }
                        }
                        LogosText { objectName: "transparentExplainer"; Layout.fillWidth: true; wrapMode: Text.Wrap
                                    color: Theme.palette.textSecondary
                                    text: "Payments here are public, and must be shielded before they can be spent." }
                        QrMatrix { objectName: "transparentQr"; qr: root.ready ? root.parseQr(backend.transparentQrJson) : null }
                        LogosCopyableText {
                            objectName: "transparentAddress"
                            Layout.fillWidth: true
                            text: root.receiveRead && receive.transparent ? receive.transparent : "—"
                            copyText: receive.transparent || ""
                            showCopyButton: !!receive.transparent
                            onCopied: root.notify("Transparent address copied", "")
                        }
                        Item { Layout.fillHeight: true }
                    }
                }
            }

            // Activity: one page of history, newest first; a row expands into its detail.
            ColumnLayout {
                spacing: Theme.spacing.small
                RowLayout {
                    Layout.fillWidth: true
                    LogosText { textFormat: Text.PlainText; color: Theme.palette.textSecondary
                                text: root.historyRead ? "Page " + (root.historyPage + 1) : "" }
                    Item { Layout.fillWidth: true }
                    LogosButton { objectName: "historyNewerButton"; text: "Newer"; enabled: root.historyPage > 0
                                  onClicked: backend.showHistoryPage(root.historyPage - 1) }
                    LogosButton { objectName: "historyOlderButton"; text: "Older"
                                  enabled: root.historyRows.length > 0 && root.historyRows.length >= (root.historyData.pageSize || 25)
                                  onClicked: backend.showHistoryPage(root.historyPage + 1) }
                    LogosButton { text: "Refresh"; enabled: root.ready; onClicked: backend.refreshHistory() }
                }
                LogosText { objectName: "historyEmpty"; visible: root.historyRead && root.historyRows.length === 0
                            color: Theme.palette.textSecondary
                            text: root.historyPage === 0 ? "No transactions yet." : "No older transactions." }
                LogosText { visible: !root.historyRead; text: "—" }
                ListView {
                    objectName: "historyList"
                    Layout.fillWidth: true; Layout.fillHeight: true
                    clip: true
                    spacing: 2
                    model: root.historyView
                    delegate: Rectangle {
                        id: txRow
                        width: ListView.view.width
                        implicitHeight: txCol.implicitHeight + 12
                        radius: 4
                        readonly property bool open: root.openTx === modelData.txid
                        readonly property bool header: modelData.kind === "migrationGroup"
                        color: open ? Theme.palette.surface : "transparent"
                        ColumnLayout {
                            id: txCol
                            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                            anchors.margins: 6
                            // A migration row sits under its heading.
                            anchors.leftMargin: modelData.kind === "migration" ? 30 : 6
                            spacing: 4
                            RowLayout {
                                objectName: "migrationGroupHeader"
                                visible: txRow.header
                                Layout.fillWidth: true
                                spacing: Theme.spacing.small
                                LogosText { Layout.preferredWidth: 80; text: "Migration" }
                                LogosBadge { text: "Orchard to Ironwood"; color: Theme.palette.info }
                                LogosText { textFormat: Text.PlainText
                                            text: (modelData.count || 0) + " transactions"
                                                  + (modelData.pending ? " · " + modelData.pending + " pending" : "")
                                                  + (modelData.moved ? " · " + root.zecOf(modelData.moved) + " ZEC moved" : "") }
                                Item { Layout.fillWidth: true }
                                LogosButton { objectName: "migrationGroupToggle"; text: root.migrationGroupOpen ? "Hide" : "Show"
                                              onClicked: root.migrationGroupOpen = !root.migrationGroupOpen }
                            }
                            RowLayout {
                                visible: !txRow.header
                                Layout.fillWidth: true
                                spacing: Theme.spacing.small
                                LogosText { Layout.preferredWidth: 80; text: root.kindLabel(modelData.kind) }
                                LogosBadge { text: root.txIsTransparent(modelData) ? "Transparent" : "Shielded"
                                             color: root.txIsTransparent(modelData) ? Theme.palette.warning : Theme.palette.success }
                                LogosBadge { visible: root.zatOf(modelData.amountMadePublic) > 0; text: "Public amount"
                                             color: Theme.palette.warning }
                                LogosText { objectName: "historyIntent"; textFormat: Text.PlainText; text: root.intentLine(modelData) }
                                LogosText { textFormat: Text.PlainText; color: Theme.palette.textTertiary; text: root.txStatus(modelData) }
                                LogosText { textFormat: Text.PlainText; color: Theme.palette.textTertiary; font.pixelSize: 11
                                            text: root.whenOf(modelData.time) }
                                Item { Layout.fillWidth: true }
                                LogosText { textFormat: Text.PlainText; color: Theme.palette.textTertiary; font.pixelSize: 10
                                            text: root.shortId(modelData.txid) }
                                LogosButton { text: txRow.open ? "Hide" : "Details"
                                              onClicked: root.openTx = (root.openTx === modelData.txid ? "" : modelData.txid) }
                            }
                            GridLayout {
                                visible: txRow.open && !txRow.header
                                columns: 2; columnSpacing: 14; rowSpacing: 3
                                Layout.fillWidth: true
                                LogosText { text: "Status"; color: Theme.palette.textTertiary; font.pixelSize: 11 }
                                LogosText { textFormat: Text.PlainText; font.pixelSize: 11
                                            text: modelData.expired ? "Expired unmined"
                                                  : (modelData.pending ? ("Pending" + (modelData.expiryHeight ? ", expires at block " + root.fmtHeight(modelData.expiryHeight) : ""))
                                                     : ("Mined at block " + root.fmtHeight(modelData.height) + " · " + root.txStatus(modelData))) }
                                LogosText { text: "Fee"; color: Theme.palette.textTertiary; font.pixelSize: 11 }
                                LogosText { textFormat: Text.PlainText; font.pixelSize: 11
                                            text: modelData.fee !== null && modelData.fee !== undefined ? modelData.feeZec + " ZEC" : "—" }
                                LogosText { text: "Pools"; color: Theme.palette.textTertiary; font.pixelSize: 11 }
                                LogosText { textFormat: Text.PlainText; font.pixelSize: 11
                                            text: (modelData.pools || []).map(root.poolLabel).join(", ") || "—" }
                                LogosText { visible: root.zatOf(modelData.amountMadePublic) > 0; text: "Made public"
                                            color: Theme.palette.textTertiary; font.pixelSize: 11 }
                                LogosText { visible: root.zatOf(modelData.amountMadePublic) > 0; textFormat: Text.PlainText; font.pixelSize: 11
                                            color: Theme.palette.warning; text: modelData.amountMadePublicZec + " ZEC crossed pools" }
                                LogosText { visible: (modelData.to || []).length > 0; text: "To"; color: Theme.palette.textTertiary; font.pixelSize: 11 }
                                LogosText { visible: (modelData.to || []).length > 0; textFormat: Text.PlainText; font.pixelSize: 11
                                            wrapMode: Text.WrapAnywhere; Layout.fillWidth: true
                                            text: (modelData.to || []).map(function (t) {
                                                      return root.shortAddress(t.address || "") + " · " + root.poolLabel(t.pool) + " · " + t.amountZec + " ZEC"
                                                  }).join("\n") }
                                LogosText { visible: (modelData.toSelf || []).length > 0; text: "To yourself"; color: Theme.palette.textTertiary; font.pixelSize: 11 }
                                LogosText { visible: (modelData.toSelf || []).length > 0; textFormat: Text.PlainText; font.pixelSize: 11
                                            wrapMode: Text.WrapAnywhere; Layout.fillWidth: true
                                            text: (modelData.toSelf || []).map(function (t) {
                                                      return root.shortAddress(t.address || "") + " · " + root.poolLabel(t.pool) + " · " + t.amountZec + " ZEC"
                                                  }).join("\n") }
                                LogosText { visible: (modelData.from || []).length > 0; text: "From"; color: Theme.palette.textTertiary; font.pixelSize: 11 }
                                LogosText { visible: (modelData.from || []).length > 0; textFormat: Text.PlainText; font.pixelSize: 11
                                            wrapMode: Text.WrapAnywhere; Layout.fillWidth: true
                                            text: (modelData.from || []).map(function (f) {
                                                      return root.shortAddress(f.address || "") + " · " + f.amountZec + " ZEC"
                                                             + (f.coins > 1 ? " in " + f.coins + " coins" : "")
                                                  }).join("\n") }
                                LogosText { visible: (modelData.memos || []).length > 0; text: "Memo"; color: Theme.palette.textTertiary; font.pixelSize: 11 }
                                LogosText { visible: (modelData.memos || []).length > 0; textFormat: Text.PlainText; font.pixelSize: 11
                                            wrapMode: Text.Wrap; Layout.fillWidth: true; text: (modelData.memos || []).join("\n") }
                                LogosText { text: "Transaction ID"; color: Theme.palette.textTertiary; font.pixelSize: 11 }
                                LogosCopyableText { Layout.fillWidth: true; text: root.shortId(modelData.txid); copyText: modelData.txid
                                                    onCopied: root.notify("Transaction ID copied", "") }
                            }
                        }
                    }
                }
            }

            // Settings
            ScrollView {
                id: settingsScroll
                clip: true
                contentWidth: availableWidth
                ColumnLayout {
                    width: settingsScroll.availableWidth
                    spacing: Theme.spacing.small

                    LogosText { text: "Wallet"; font.pixelSize: 16 }
                    LogosText { textFormat: Text.PlainText; color: Theme.palette.textSecondary
                                text: (status.name || "") + " · " + (status.network || "") + " · from block " + root.fmtHeight(status.birthdayHeight) }
                    RowLayout {
                        LogosText { text: "Password"; Layout.preferredWidth: 160; color: Theme.palette.textSecondary }
                        LogosButton { objectName: "changePasswordButton"; text: "Change password…"
                                      enabled: root.ready && !root.busy; onClicked: changePasswordSheet.open() }
                    }
                    RowLayout {
                        LogosText { text: "Recovery phrase"; Layout.preferredWidth: 160; color: Theme.palette.textSecondary }
                        LogosButton { objectName: "revealSeedButton"; text: "Show recovery phrase…"
                                      enabled: root.ready; onClicked: revealSheet.open() }
                    }
                    RowLayout {
                        LogosText { text: "Viewing key"; Layout.preferredWidth: 160; color: Theme.palette.textSecondary }
                        LogosButton { objectName: "exportViewingKeyButton"; text: "Export viewing key…"
                                      enabled: root.ready; onClicked: exportKeySheet.open() }
                    }

                    LogosFrame {
                        objectName: "secretPanel"
                        visible: root.shownSecret !== ""
                        Layout.fillWidth: true
                        contentItem: ColumnLayout {
                            spacing: Theme.spacing.small
                            LogosText {
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                color: Theme.palette.warning
                                text: root.secretKind === "phrase"
                                      ? "Your recovery phrase. Anyone who has it can spend this wallet's funds. Write it down and keep it offline."
                                      : "Your viewing key. Whoever holds it sees every past and future transaction of this wallet, and sharing it cannot be undone."
                            }
                            LogosSelectableText {
                                objectName: "secretText"
                                Layout.fillWidth: true
                                wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
                                text: root.shownSecret
                            }
                            RowLayout {
                                LogosCopyButton { value: root.shownSecret }
                                LogosButton { objectName: "hideSecretButton"; text: "Hide"; onClicked: root.hideSecret() }
                            }
                        }
                    }

                    LogosText { text: "Network"; font.pixelSize: 16; Layout.topMargin: Theme.spacing.medium }
                    Loader {
                        Layout.fillWidth: true
                        active: root.walletOpen
                        sourceComponent: networkPane
                    }
                    Item { Layout.fillHeight: true }
                }
            }
        }
    }

    // ── QR codes: rectangles from a qrcodegen matrix (the sandbox refuses data: URIs and Canvas) ──
    function parseQr(s) { try { return s ? JSON.parse(s) : null } catch (e) { return null } }
    // A contrast target, not a themed surface: the two literal colours stay literal.
    component QrMatrix: Rectangle {
        id: qrBox
        property var qr: null
        readonly property int quiet: 4
        readonly property int cell: qr ? Math.max(1, Math.floor(264 / (qr.size + quiet * 2))) : 0
        function runs(q) {
            const out = []
            for (let y = 0; y < q.size; y++) {
                let x = 0
                while (x < q.size) {
                    if (q.bits.charAt(y * q.size + x) !== "1") { x++; continue }
                    const start = x
                    while (x < q.size && q.bits.charAt(y * q.size + x) === "1") x++
                    out.push([start, y, x - start])
                }
            }
            return out
        }
        visible: !!qr
        color: "#ffffff"
        Layout.preferredWidth: qr ? cell * (qr.size + quiet * 2) : 0
        Layout.preferredHeight: Layout.preferredWidth
        Repeater {
            model: qrBox.qr ? qrBox.runs(qrBox.qr) : []
            Rectangle {
                required property var modelData
                x: (modelData[0] + qrBox.quiet) * qrBox.cell
                y: (modelData[1] + qrBox.quiet) * qrBox.cell
                width: modelData[2] * qrBox.cell
                height: qrBox.cell
                color: "#000000"
            }
        }
    }

    LogosToast {
        id: toast
        objectName: "toast"
        z: 10
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.spacing.large
        width: Math.min(parent.width - 40, 480)
        severity: LogosNotice.Success
    }

    // ── sheets: outside the layout, so a closed one reserves no space. Titles stay literal. ──

    // The review of a send or a shielding: what goes where, what becomes public, the fee and
    // the expiry. Approving opens the password dialog. Only an explicit choice closes it.
    LogosDialog {
        id: reviewSheet
        objectName: "reviewSheet"
        title: root.preview && root.preview.migrateNow ? "Review moving Orchard funds now"
               : root.preview && root.preview.shielding ? "Review shielding" : "Review send"
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 680)
        closePolicy: Popup.NoAutoClose
        contentItem: ScrollView {
            id: reviewScroll
            clip: true
            contentWidth: availableWidth
            implicitHeight: Math.min(reviewCol.implicitHeight, Math.max(200, root.height - 240))
            ColumnLayout {
                id: reviewCol
                width: reviewScroll.availableWidth
                spacing: Theme.spacing.small

                LogosStageLane {
                    objectName: "sendStageLane"
                    Layout.fillWidth: true
                    currentIndex: root.sendStage()
                    busy: root.send.state === "preparing" || root.send.state === "signing"
                    failed: ["failed", "expired", "cancelled", "unknown"].indexOf(root.send.state) >= 0
                    stages: [
                        LogosStage { label: "Prepare"; busyLabel: "Preparing…" },
                        LogosStage { label: "Review" },
                        LogosStage { label: "Sign and send"; busyLabel: "Signing…" },
                        LogosStage { label: "Sent" }
                    ]
                }
                LogosText {
                    visible: !!root.send.requester && !root.ownSend
                    textFormat: Text.PlainText
                    color: Theme.palette.warning
                    text: "Requested by " + (root.send.requester || "")
                }
                LogosText { visible: root.send.state === "preparing"; color: Theme.palette.textSecondary
                            text: "Building the transaction…" }

                ColumnLayout {
                    visible: !!root.preview
                    Layout.fillWidth: true
                    spacing: Theme.spacing.small

                    LogosText {
                        visible: !!root.preview && !!root.preview.shielding
                        Layout.fillWidth: true; wrapMode: Text.WrapAnywhere; textFormat: Text.PlainText
                        text: "From " + (root.shieldingFrom || "a transparent address") + " into your shielded balance: "
                              + (root.preview ? root.preview.changeTotalZec : "") + " ZEC"
                    }
                    LogosText {
                        objectName: "reviewMigrateNow"
                        visible: !!root.preview && !!root.preview.migrateNow
                        Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText
                        text: "From Orchard into your shielded balance, in one transaction: "
                              + (root.preview ? root.preview.amountMadePublicZec : "") + " ZEC"
                    }
                    Repeater {
                        // Moving now pays the wallet's own address, said above instead.
                        model: root.preview && !root.preview.migrateNow ? (root.preview.recipients || []) : []
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            RowLayout {
                                Layout.fillWidth: true
                                LogosBadge { text: root.poolLabel(modelData.pool)
                                             color: modelData.pool === "transparent" ? Theme.palette.warning : Theme.palette.success }
                                LogosText { Layout.fillWidth: true; wrapMode: Text.WrapAnywhere; textFormat: Text.PlainText
                                            font.pixelSize: 12; text: modelData.address }
                                LogosText { textFormat: Text.PlainText; font.weight: Font.Bold; text: modelData.amountZec + " ZEC" }
                            }
                            LogosText { visible: !!modelData.memo; Layout.fillWidth: true; wrapMode: Text.Wrap
                                        textFormat: Text.PlainText; color: Theme.palette.textSecondary
                                        text: "Memo: " + (modelData.memo || "") }
                        }
                    }
                    GridLayout {
                        columns: 2; columnSpacing: 14; rowSpacing: 3
                        Layout.fillWidth: true
                        LogosText { text: "Fee"; color: Theme.palette.textTertiary }
                        LogosText { objectName: "reviewFee"; textFormat: Text.PlainText
                                    text: root.preview ? root.preview.feeZec + " ZEC" : "" }
                        LogosText { visible: !root.preview || !root.preview.shielding; text: "Spent from"; color: Theme.palette.textTertiary }
                        LogosText { visible: !root.preview || !root.preview.shielding; textFormat: Text.PlainText; text: root.spentFromLine() }
                        LogosText { text: "Change"; color: Theme.palette.textTertiary }
                        LogosText { textFormat: Text.PlainText; text: root.changeLine() }
                        LogosText { text: "Expires"; color: Theme.palette.textTertiary }
                        LogosText { objectName: "reviewExpiry"; textFormat: Text.PlainText
                                    text: root.preview ? "at block " + root.fmtHeight(root.preview.expiryHeight) + " if not mined by then" : "" }
                    }
                    LogosNotice {
                        objectName: "reviewUneconomicNotice"
                        Layout.fillWidth: true
                        severity: LogosNotice.Warning
                        title: "Too small to spend"
                        shown: !!root.preview && (root.preview.recipients || []).some(function (r) { return r.uneconomic === true })
                        message: "A transparent payment of 0.00005 ZEC or less costs more in fees to spend than it is worth, so "
                                 + "wallets, this one included, leave it out of their balance. Its recipient cannot use it."
                    }
                    LogosNotice {
                        objectName: "reviewPublicNotice"
                        Layout.fillWidth: true
                        severity: LogosNotice.Warning
                        title: "Becomes public"
                        shown: root.publicLines().length > 0
                        message: root.publicLines().join("\n")
                    }
                    LogosText {
                        objectName: "reviewCountdown"
                        visible: root.send.state === "previewed"
                        color: root.ttl > 0 && root.ttl <= 20 ? Theme.palette.warning : Theme.palette.textSecondary
                        text: root.ttl > 0 ? "Approve within " + root.ttl + " s, or review it again." : "This preview has expired."
                    }
                }

                LogosText { visible: root.send.state === "signing"; Layout.fillWidth: true; wrapMode: Text.Wrap
                            color: Theme.palette.textSecondary
                            text: "Proving and signing, then broadcasting over Tor. This takes a few seconds." }
                Repeater {
                    model: root.send.result && Array.isArray(root.send.result.transactions) ? root.send.result.transactions : []
                    RowLayout {
                        Layout.fillWidth: true
                        LogosBadge { text: modelData.accepted ? "Accepted" : "Refused"
                                     color: modelData.accepted ? Theme.palette.success : Theme.palette.error }
                        LogosCopyableText { Layout.fillWidth: true; text: root.shortId(modelData.txid); copyText: modelData.txid || ""
                                            onCopied: root.notify("Transaction ID copied", "") }
                        LogosText { textFormat: Text.PlainText; color: Theme.palette.textTertiary; font.pixelSize: 11
                                    text: (modelData.server || "") + (modelData.error ? " · " + modelData.error : "") }
                    }
                }
                LogosNotice {
                    objectName: "reviewMixedPools"
                    Layout.fillWidth: true
                    severity: LogosNotice.Warning
                    shown: root.needsMixedPools && !root.ownSend
                    message: "No single pool can pay this. The app that asked must allow paying from several pools, which makes amounts public."
                }
                LogosNotice {
                    objectName: "reviewError"
                    Layout.fillWidth: true
                    severity: LogosNotice.Error
                    shown: message.length > 0
                    message: root.ready ? backend.sendError : ""
                }
            }
        }
        leftActions: [
            LogosButton { objectName: "cancelSendButton"; text: "Cancel"
                          visible: root.send.state === "preparing" || root.send.state === "previewed"
                          onClicked: backend.cancelSend() },
            LogosButton { objectName: "hideReviewButton"; text: "Hide"; visible: root.send.state === "signing"
                          onClicked: reviewSheet.close() }
        ]
        rightActions: [
            LogosButton { objectName: "approveSendButton"; text: "Approve…"; variant: LogosButton.Variant.Primary
                          visible: root.send.state === "previewed"; enabled: root.ttl > 0
                          onClicked: { root.approveMode = "send"; approveSheet.open() } },
            LogosButton { objectName: "doneSendButton"; text: "Done"; visible: root.sendSettled && !(root.needsMixedPools && root.ownSend)
                          onClicked: root.finishSend() }
        ]
    }

    LogosDialog {
        id: approveSheet
        objectName: "approveSheet"
        title: "Approve with your password"
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 520)
        onClosed: approvePw.text = ""
        contentItem: ColumnLayout {
            spacing: Theme.spacing.small
            LogosText { Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText
                        text: root.approveMode === "migration" ? root.migrationApproveSummary() : root.approveSummary() }
            LogosTextField {
                id: approvePw; objectName: "approvePasswordField"; placeholderText: "Wallet password"
                echoMode: TextInput.Password; Layout.fillWidth: true
                Component.onCompleted: textInput.passwordMaskDelay = 0
                Connections {
                    target: approvePw.textInput
                    function onAccepted() { if (approveConfirm.enabled) approveConfirm.clicked() }
                }
            }
            LogosText { visible: root.approveMode === "send" && root.ttl === 0; color: Theme.palette.error
                        text: "The preview expired. Cancel and review again." }
            LogosButton {
                id: approveConfirm
                objectName: "approveConfirm"
                text: root.approveMode === "migration" ? "Approve and sign the run"
                      : (root.preview && root.preview.migrateNow ? "Approve and move"
                         : root.preview && root.preview.shielding ? "Approve and shield" : "Approve and send")
                variant: LogosButton.Variant.Primary
                enabled: root.ready && approvePw.text !== ""
                         && (root.approveMode === "migration"
                             ? (!!root.plan && root.plan.crossesNu7 !== true && root.migrationJob === "")
                             : (root.send.state === "previewed" && root.ttl > 0))
                onClicked: {
                    if (root.approveMode === "migration") backend.approveMigration(approvePw.text)
                    else backend.approveSend(approvePw.text)
                    approvePw.text = ""
                    approveSheet.close()
                }
            }
        }
    }

    // The review of a migration plan: what moves, what becomes public, how many transactions and
    // when. Approving signs every transaction of the run at once (ZIP 318).
    LogosDialog {
        id: migrationReview
        objectName: "migrationReviewSheet"
        title: "Move Orchard funds privately"
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 720)
        closePolicy: Popup.NoAutoClose
        contentItem: ScrollView {
            id: migrationScroll
            clip: true
            contentWidth: availableWidth
            implicitHeight: Math.min(migrationCol.implicitHeight, Math.max(240, root.height - 240))
            ColumnLayout {
                id: migrationCol
                width: migrationScroll.availableWidth
                spacing: Theme.spacing.small

                LogosText { visible: !root.plan && root.migrationJob === "plan"; color: Theme.palette.textSecondary
                            text: "Planning the migration…" }
                ColumnLayout {
                    visible: !!root.plan
                    Layout.fillWidth: true
                    spacing: Theme.spacing.small

                    LogosNotice {
                        objectName: "migrationPublicNotice"
                        Layout.fillWidth: true
                        severity: LogosNotice.Warning
                        title: "These amounts become public"
                        message: "ZIP 318 moves Orchard funds as fixed denominations, the same ones every migrating wallet uses: "
                                 + (root.plan ? (root.plan.amountsMadePublicZec || []).join(", ") : "") + " ZEC. "
                                 + "Each amount is visible on-chain as it moves; who owns it is not."
                    }
                    GridLayout {
                        columns: 2; columnSpacing: 14; rowSpacing: 3
                        Layout.fillWidth: true
                        LogosText { text: "Moves"; color: Theme.palette.textTertiary }
                        LogosText { objectName: "migrationMoves"; textFormat: Text.PlainText
                                    text: root.plan ? root.plan.migratingZec + " ZEC into your shielded balance" : "" }
                        LogosText { visible: root.remainderLine() !== ""; text: "Stays in Orchard"; color: Theme.palette.textTertiary }
                        LogosText { visible: root.remainderLine() !== ""; Layout.fillWidth: true; wrapMode: Text.Wrap
                                    textFormat: Text.PlainText; text: root.remainderLine() }
                        LogosText { text: "Transactions"; color: Theme.palette.textTertiary }
                        LogosText { objectName: "migrationTransactions"; Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText
                                    text: root.plan ? (root.zatOf(root.plan.preparationTransactions) + " to prepare, then "
                                                       + root.zatOf(root.plan.transfers) + " transfers: "
                                                       + (root.zatOf(root.plan.preparationTransactions) + root.zatOf(root.plan.transfers))
                                                       + " in all") : "" }
                        LogosText { text: "Fees"; color: Theme.palette.textTertiary }
                        LogosText { objectName: "migrationFees"; textFormat: Text.PlainText
                                    text: root.plan ? root.plan.feeTotalZec + " ZEC in all, paid from the Orchard funds" : "" }
                        LogosText { text: "First transfer"; color: Theme.palette.textTertiary }
                        LogosText { objectName: "migrationFirst"; textFormat: Text.PlainText
                                    text: root.plan ? root.whenText(root.plan.firstBroadcast) : "" }
                        LogosText { text: "Last transfer"; color: Theme.palette.textTertiary }
                        LogosText { objectName: "migrationLast"; textFormat: Text.PlainText
                                    text: root.plan ? root.whenText(root.plan.lastBroadcast) : "" }
                        LogosText { text: "Signed until"; color: Theme.palette.textTertiary }
                        LogosText { objectName: "migrationExpires"; Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText
                                    text: root.plan ? root.whenText(root.plan.expiresAt)
                                                      + ". A transfer not sent by then needs your approval again." : "" }
                        LogosText { text: "Plan"; color: Theme.palette.textTertiary }
                        LogosText { textFormat: Text.PlainText; color: Theme.palette.textSecondary
                                    text: root.plan ? root.shortId(root.plan.digest) + " · valid for about an hour" : "" }
                    }
                    LogosNotice {
                        objectName: "migrationNu7Notice"
                        Layout.fillWidth: true
                        severity: LogosNotice.Error
                        shown: !!root.plan && root.plan.crossesNu7 === true
                        title: "NU7 activates during this run"
                        message: "It would still be broadcasting at block " + root.fmtHeight(root.plan ? root.plan.nu7Height : null)
                                 + ", when NU7 activates, and transactions signed now would not be valid after it. "
                                 + "Start the migration after the upgrade."
                    }
                    LogosText {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        color: Theme.palette.textSecondary
                        text: "Approving signs every transaction of this run now. The wallet then broadcasts them on schedule, "
                              + "over Tor, only while it is open and synced. Pause and Cancel stay available."
                    }
                    LogosText { text: "Schedule"; font.pixelSize: 15; Layout.topMargin: Theme.spacing.small }
                    Repeater {
                        model: root.plan ? (root.plan.schedule || []) : []
                        LogosText {
                            textFormat: Text.PlainText
                            font.pixelSize: 12
                            color: Theme.palette.textSecondary
                            text: "#" + (index + 1) + " · " + root.whenText(modelData.broadcastHeight)
                                  + " · expires at block " + root.fmtHeight(modelData.expiryHeight)
                        }
                    }
                }
                LogosNotice {
                    objectName: "migrationReviewError"
                    Layout.fillWidth: true
                    severity: LogosNotice.Error
                    shown: message.length > 0
                    message: root.migrationError
                }
            }
        }
        leftActions: [
            LogosButton { objectName: "dismissMigrationPlanButton"; text: "Cancel"
                          onClicked: { backend.dismissMigrationPlan(); migrationReview.close() } }
        ]
        rightActions: [
            LogosButton { objectName: "planMigrationAgainButton"; text: "Plan again"
                          visible: !root.plan && root.migrationJob === ""
                          enabled: root.ready
                          onClicked: root.startMigration() },
            LogosButton { objectName: "approveMigrationButton"; text: root.migrationJob === "approve" ? "Signing…" : "Approve…"
                          variant: LogosButton.Variant.Primary
                          visible: !!root.plan
                          enabled: root.ready && root.migrationJob === "" && !!root.plan && root.plan.crossesNu7 !== true
                          onClicked: { root.approveMode = "migration"; approveSheet.open() } }
        ]
    }

    LogosWarningDialog {
        id: cancelMigrationSheet
        objectName: "cancelMigrationSheet"
        title: "Cancel the migration?"
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 560)
        message: "Cancelling stops the run, releases the Orchard notes it reserved and deletes its unbroadcast "
                 + "transactions. Transfers already sent may still confirm. What stays in Orchard can move in a new run."
        leftActions: [ LogosButton { text: "Keep migrating"; onClicked: cancelMigrationSheet.close() } ]
        rightActions: [
            LogosButton { objectName: "confirmCancelMigrationButton"; text: "Cancel migration"
                          onClicked: { cancelMigrationSheet.close(); backend.cancelMigration() } }
        ]
    }

    // ZIP 315: spending from several pools at once reveals amounts, so it needs consent.
    LogosWarningDialog {
        id: mixedPoolsSheet
        objectName: "mixedPoolsSheet"
        title: "Pay from more than one pool?"
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 560)
        closePolicy: Popup.NoAutoClose
        message: "No single pool holds enough to pay this. Paying from Ironwood and Sapling together moves an amount "
                 + "across pools, and that amount becomes public on-chain. The review shows exactly how much before you approve."
        leftActions: [ LogosButton { text: "Cancel"; onClicked: { mixedPoolsSheet.close(); backend.dismissSend() } } ]
        rightActions: [
            LogosButton { objectName: "allowMixedPoolsButton"; text: "Continue"
                          onClicked: { mixedPoolsSheet.close(); root.retryMixedPools() } }
        ]
    }

    LogosDialog {
        id: openWalletSheet
        objectName: "openWalletSheet"
        title: "Open a wallet"
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 560)
        onClosed: {
            openPw.text = ""
            // The user walked away from an unlock another app asked for.
            if (root.unlockRequestId !== "" && !root.unlockOpenSent) {
                logos.respond(root.unlockRequestId, false, ({}), "cancelled")
                root.unlockRequestId = ""
                root.unlockWallet = ""
            }
        }
        contentItem: ColumnLayout {
            spacing: Theme.spacing.small
            LogosText { visible: root.unlockRequestId !== ""; wrapMode: Text.Wrap; Layout.fillWidth: true
                        text: "Another app asked to unlock this wallet." }
            LogosTextField { id: openNameField; objectName: "openNameField"; placeholderText: "Wallet name"; Layout.fillWidth: true }
            LogosTextField {
                id: openPw; objectName: "openPasswordField"; placeholderText: "Wallet password"
                echoMode: TextInput.Password; Layout.fillWidth: true
                // `accepted` and passwordMaskDelay belong to the inner TextInput.
                Component.onCompleted: textInput.passwordMaskDelay = 0
                Connections {
                    target: openPw.textInput
                    function onAccepted() { if (openButton.enabled) openButton.clicked() }
                }
            }
            LogosButton {
                id: openButton
                objectName: "openButton"; text: "Open"
                variant: LogosButton.Variant.Primary
                enabled: root.ready && !root.busy && openNameField.text !== "" && openPw.text !== ""
                onClicked: {
                    root.unlockOpenSent = root.unlockRequestId !== "" && openNameField.text === root.unlockWallet
                    backend.openWallet(openNameField.text, openPw.text)
                    openPw.text = ""
                    openWalletSheet.close()
                }
            }
        }
    }

    LogosDialog {
        id: createSheet
        objectName: "createWalletSheet"
        title: "Create a wallet"
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 560)
        onOpened: { cName.text = ""; cPw.text = ""; cPw2.text = "" }
        onClosed: { cPw.text = ""; cPw2.text = "" }
        contentItem: ColumnLayout {
            spacing: Theme.spacing.small
            LogosTextField { id: cName; objectName: "createNameField"; Layout.fillWidth: true
                             placeholderText: "Wallet name: letters, digits, - and _"
                             validator: RegularExpressionValidator { regularExpression: /^[A-Za-z0-9_-]{0,64}$/ } }
            LogosTextField { id: cPw; objectName: "createPasswordField"; placeholderText: "Password"; echoMode: TextInput.Password
                             Layout.fillWidth: true; Component.onCompleted: textInput.passwordMaskDelay = 0 }
            LogosTextField { id: cPw2; objectName: "createPasswordRepeatField"; placeholderText: "Repeat password"; echoMode: TextInput.Password
                             Layout.fillWidth: true; Component.onCompleted: textInput.passwordMaskDelay = 0 }
            LogosText { visible: cPw2.text !== "" && cPw.text !== cPw2.text; text: "Passwords do not match"; color: Theme.palette.error }
            LogosText { Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.palette.textSecondary
                        text: "On " + (root.activeNetwork || "this network") + ". The wallet starts at the current block. "
                              + "Once it is open, write down its recovery phrase: Settings, Show recovery phrase." }
            LogosButton {
                objectName: "createButton"; text: "Create wallet"
                variant: LogosButton.Variant.Primary
                enabled: root.ready && !root.busy && cName.text !== "" && cPw.text !== "" && cPw.text === cPw2.text
                onClicked: { backend.createWallet(cName.text, cPw.text); cPw.text = ""; cPw2.text = ""; createSheet.close() }
            }
        }
    }

    LogosDialog {
        id: restoreSheet
        objectName: "restoreWalletSheet"
        title: "Restore from a recovery phrase"
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 620)
        onOpened: { rName.text = ""; rPhrase.text = ""; rWhen.text = ""; rPw.text = ""; rPw2.text = "" }
        onClosed: { rPhrase.text = ""; rPw.text = ""; rPw2.text = "" }
        contentItem: ColumnLayout {
            spacing: Theme.spacing.small
            LogosTextField { id: rName; objectName: "restoreNameField"; Layout.fillWidth: true
                             placeholderText: "Wallet name: letters, digits, - and _"
                             validator: RegularExpressionValidator { regularExpression: /^[A-Za-z0-9_-]{0,64}$/ } }
            LogosTextArea { id: rPhrase; objectName: "restorePhraseField"; placeholderText: "24-word recovery phrase"
                            Layout.fillWidth: true; Layout.preferredHeight: 90 }
            LogosText { visible: rPhrase.text.trim() !== "" && root.wordCount(rPhrase.text) !== 24
                        color: Theme.palette.textSecondary
                        text: "A recovery phrase has 24 words; this has " + root.wordCount(rPhrase.text) + "." }
            LogosTextField { id: rWhen; objectName: "restoreBirthdayField"; Layout.fillWidth: true
                             placeholderText: root.activeNetwork === "testnet" ? "Block height first used at (optional)"
                                                                               : "Month first used, such as 2024-05, or a block height (optional)" }
            LogosText { objectName: "restoreStartLine"; Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText
                        color: Theme.palette.textTertiary; text: root.restoreStartLine(rWhen.text) }
            LogosTextField { id: rPw; objectName: "restorePasswordField"; placeholderText: "New password"; echoMode: TextInput.Password
                             Layout.fillWidth: true; Component.onCompleted: textInput.passwordMaskDelay = 0 }
            LogosTextField { id: rPw2; objectName: "restorePasswordRepeatField"; placeholderText: "Repeat password"; echoMode: TextInput.Password
                             Layout.fillWidth: true; Component.onCompleted: textInput.passwordMaskDelay = 0 }
            LogosText { visible: rPw2.text !== "" && rPw.text !== rPw2.text; text: "Passwords do not match"; color: Theme.palette.error }
            LogosButton {
                objectName: "restoreButton"; text: "Restore"
                variant: LogosButton.Variant.Primary
                enabled: root.ready && !root.busy && rName.text !== "" && root.wordCount(rPhrase.text) === 24
                         && root.birthdayFor(rWhen.text) > 0 && rPw.text !== "" && rPw.text === rPw2.text
                onClicked: {
                    backend.restoreWallet(rName.text, rPw.text, root.normalisePhrase(rPhrase.text), root.birthdayFor(rWhen.text))
                    rPhrase.text = ""; rPw.text = ""; rPw2.text = ""
                    restoreSheet.close()
                }
            }
        }
    }

    LogosDialog {
        id: networkSheet
        objectName: "networkSheet"
        title: "Servers and privacy"
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 720)
        contentItem: ScrollView {
            id: networkSheetScroll
            clip: true
            contentWidth: availableWidth
            implicitHeight: Math.min(networkSheetLoader.implicitHeight, Math.max(200, root.height - 200))
            Loader {
                id: networkSheetLoader
                width: networkSheetScroll.availableWidth
                active: networkSheet.visible
                sourceComponent: networkPane
            }
        }
        rightActions: [ LogosButton { text: "Done"; onClicked: networkSheet.close() } ]
    }

    LogosDialog {
        id: changePasswordSheet
        objectName: "changePasswordSheet"
        title: "Change password"
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 560)
        onOpened: { oldPw.text = ""; newPw.text = ""; newPw2.text = "" }
        onClosed: { oldPw.text = ""; newPw.text = ""; newPw2.text = "" }
        contentItem: ColumnLayout {
            spacing: Theme.spacing.small
            LogosTextField { id: oldPw; objectName: "oldPasswordField"; placeholderText: "Current password"; echoMode: TextInput.Password
                             Layout.fillWidth: true; Component.onCompleted: textInput.passwordMaskDelay = 0 }
            LogosTextField { id: newPw; objectName: "newPasswordField"; placeholderText: "New password"; echoMode: TextInput.Password
                             Layout.fillWidth: true; Component.onCompleted: textInput.passwordMaskDelay = 0 }
            LogosTextField { id: newPw2; objectName: "newPasswordRepeatField"; placeholderText: "Repeat new password"; echoMode: TextInput.Password
                             Layout.fillWidth: true; Component.onCompleted: textInput.passwordMaskDelay = 0 }
            LogosText { visible: newPw2.text !== "" && newPw.text !== newPw2.text; text: "Passwords do not match"; color: Theme.palette.error }
            LogosButton {
                objectName: "changePasswordConfirm"; text: "Change password"
                variant: LogosButton.Variant.Primary
                enabled: root.ready && !root.busy && oldPw.text !== "" && newPw.text !== "" && newPw.text === newPw2.text
                onClicked: {
                    backend.changePassword(oldPw.text, newPw.text)
                    oldPw.text = ""; newPw.text = ""; newPw2.text = ""
                    changePasswordSheet.close()
                }
            }
        }
    }

    LogosDialog {
        id: revealSheet
        objectName: "revealSeedSheet"
        title: "Show recovery phrase"
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 560)
        onClosed: revealPw.text = ""
        contentItem: ColumnLayout {
            spacing: Theme.spacing.small
            LogosText { Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.palette.textSecondary
                        text: "Anyone who sees the recovery phrase can spend this wallet's funds. Check that nobody can see your screen." }
            LogosTextField {
                id: revealPw; objectName: "revealPasswordField"; placeholderText: "Wallet password"
                echoMode: TextInput.Password; Layout.fillWidth: true
                Component.onCompleted: textInput.passwordMaskDelay = 0
            }
            LogosButton {
                objectName: "revealSeedConfirm"; text: "Show"
                variant: LogosButton.Variant.Primary
                enabled: root.ready && revealPw.text !== ""
                onClicked: { root.reveal("phrase", revealPw.text); revealPw.text = ""; revealSheet.close() }
            }
        }
    }

    // ZIP 315: the export warns that the key sees everything, and that sharing it cannot be undone.
    LogosWarningDialog {
        id: exportKeySheet
        objectName: "exportViewingKeySheet"
        title: "Export viewing key"
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 560)
        onClosed: exportPw.text = ""
        contentItem: ColumnLayout {
            spacing: Theme.spacing.small
            LogosText { Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.palette.textSecondary
                        text: "Whoever holds this key sees every past and future transaction of this wallet, with amounts and memos. "
                              + "It cannot spend. Sharing it cannot be undone." }
            LogosTextField {
                id: exportPw; objectName: "exportPasswordField"; placeholderText: "Wallet password"
                echoMode: TextInput.Password; Layout.fillWidth: true
                Component.onCompleted: textInput.passwordMaskDelay = 0
            }
        }
        leftActions: [ LogosButton { text: "Cancel"; onClicked: exportKeySheet.close() } ]
        rightActions: [
            LogosButton {
                objectName: "exportViewingKeyConfirm"; text: "Export"
                enabled: root.ready && exportPw.text !== ""
                onClicked: { root.reveal("ufvk", exportPw.text); exportPw.text = ""; exportKeySheet.close() }
            }
        ]
    }
}
