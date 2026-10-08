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
    readonly property var orchardPool: balancesReady ? ((balances.pools || {}).orchard || {}) : ({})
    // ZIP 315's un-economic balance: below this, shielding costs more than it moves.
    readonly property real shieldThreshold: balancesReady && balances.shieldingThreshold !== undefined ? zatOf(balances.shieldingThreshold) : 100000
    readonly property bool receiveRead: ready && backend.receiveJson !== ""
    readonly property var receive: receiveRead ? j(backend.receiveJson, "{}") : ({})
    readonly property var serversInfo: ready ? j(backend.serversJson, "{}") : ({})
    readonly property var serverList: Array.isArray(serversInfo.servers) ? serversInfo.servers : []
    readonly property var health: ready ? j(backend.serverHealthJson, "{}") : ({})
    readonly property string overall: health.overall || ""
    readonly property string activeNetwork: ready ? (networks.active || "") : ""
    readonly property string displayedNetwork: walletOpen ? (status.network || activeNetwork) : activeNetwork
    readonly property var walletsOnNetwork: wallets.filter(function (w) { return !w.network || w.network === root.activeNetwork })
    readonly property real chainTip: zatOf(sync.tip) || zatOf(balances.chainTip)
    readonly property bool historyRead: ready && backend.historyJson !== ""
    readonly property var historyData: historyRead ? j(backend.historyJson, "{}") : ({})
    readonly property var historyRows: Array.isArray(historyData.rows) ? historyData.rows : []
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
            root.notify(root.preview && root.preview.shielding ? "Shielded" : "Sent", "It shows in Activity once mined.")
        root.lastSendState = s
    }
    onNeedsMixedPoolsChanged: if (root.needsMixedPools && root.ownSend && root.lastRequest) mixedPoolsSheet.open()

    // ---- the Send form ----
    readonly property bool sendIsUri: sendTo.text.trim().toLowerCase().indexOf("zcash:") === 0
    readonly property string recipientKind: sendIsUri ? "payment request" : root.addressKind(sendTo.text)
    // ZIP 302: memos go to shielded recipients only.
    readonly property bool memoAllowed: recipientKind === "" || recipientKind === "shielded"
    readonly property int memoBytes: utf8Bytes(sendMemo.text)
    readonly property bool canReview: ready && walletOpen && !sendLive && send.state !== "unknown" && sendTo.text.trim() !== ""
                                      && recipientKind !== "other network"
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
            root.notify(lastJob.kind === "create" ? "Wallet created" : "Wallet restored", "Enter its password to open it.")
            openNameField.text = lastJob.name || ""
            openWalletSheet.open()
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
    }
    function hideSecret() { root.shownSecret = ""; root.secretKind = "" }
    onWalletOpenChanged: {
        root.hideSecret()
        root.closeSheets()
        root.openTx = ""
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
    // Done on a settled send. A send that went out clears the form behind it.
    function finishSend() {
        var s = root.send.state
        backend.dismissSend()
        if (s === "sent" && !(root.preview && root.preview.shielding)) {
            sendTo.text = ""; sendAmount.text = ""; sendMemo.text = ""
        }
    }

    function zatOf(v) { var n = Number(v); return isFinite(n) ? n : 0 }
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

    // The address kind as typed. Prefixes only: the backend has no address validator yet.
    function addressKind(a) {
        var t = (a || "").trim().toLowerCase()
        if (t === "") return ""
        var test = root.displayedNetwork === "testnet"
        function starts(list) { return list.some(function (p) { return t.indexOf(p) === 0 }) }
        if (starts(test ? ["utest1", "ztestsapling1"] : ["u1", "zs1"])) return "shielded"
        if (starts(test ? ["textest1"] : ["tex1"])) return "tex"
        if (starts(test ? ["tm", "t2"] : ["t1", "t3"])) return "transparent"
        if (starts(test ? ["u1", "zs1", "tex1", "t1", "t3"] : ["utest1", "ztestsapling1", "textest1", "tm", "t2"]))
            return "other network"
        return "unknown"
    }

    // Restore starts from a height: a block number, or a month (mainnet) less two weeks' margin.
    // Below the first bundled checkpoint the core starts at Sapling activation.
    function birthdayFor(input) {
        var t = (input || "").trim()
        var floor = root.activeNetwork === "testnet" ? 280000 : 419200
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

    function syncFraction() {
        var tip = root.sync.tip, done = root.sync.fullyScanned, from = root.sync.birthday || 0
        if (!tip || done === undefined || done === null || tip <= from) return 0
        return Math.max(0, Math.min(1, (done - from) / (tip - from)))
    }
    function syncLine() {
        if (!root.syncRead) return "Sync: —"
        var s = root.sync.state || ""
        if (s === "synced") return "Synced to block " + root.fmtHeight(root.sync.tip)
        if (s === "scanning" || s === "downloading")
            return "Scanning · block " + root.fmtHeight(root.sync.fullyScanned) + " of " + root.fmtHeight(root.sync.tip)
                   + " (" + Math.floor(root.syncFraction() * 100) + "%)"
        if (s === "starting" || s === "connecting") return "Connecting to servers…"
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
    function shieldedCaption() {
        if (!root.balancesRead) return ""
        if (!root.balancesReady) return "Waiting for the first scan"
        return root.zatOf(root.spendPool.pending) > 0 ? ("+ " + root.spendPool.pendingZec + " ZEC pending") : "Spendable now"
    }
    function transparentMessage() {
        var t = root.transparentPool
        var s = (t.totalZec || "0") + " ZEC"
        if (root.zatOf(t.total) > root.zatOf(t.spendable)) s += " (" + t.pendingZec + " ZEC pending)"
        return s + ". Payments to your transparent addresses are public. Shield each one to spend it privately."
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
        if (root.zatOf(p.amountMadePublic) > 0)
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

    // ---- activity ----
    function kindLabel(k) {
        if (k === "received") return "Received"
        if (k === "sent") return "Sent"
        if (k === "shielded") return "Shielded"
        if (k === "migration") return "Migration"
        return k || ""
    }
    function txIsTransparent(r) {
        if (r.kind === "sent") return (r.to || []).some(function (t) { return t.pool === "transparent" })
        var pools = r.pools || []
        return pools.length > 0 && pools.every(function (p) { return p === "transparent" })
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
    Component {
        id: networkPane
        ColumnLayout {
            spacing: Theme.spacing.small

            LogosText { text: "Network privacy"; font.pixelSize: 15 }
            LogosText { Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.palette.textSecondary
                        text: "Every connection goes through this Tor proxy. The wallet never connects without it." }
            RowLayout {
                Layout.fillWidth: true
                LogosTextField { id: proxyField; objectName: "proxyField"; Layout.fillWidth: true
                                 placeholderText: "socks5h://127.0.0.1:9050"; text: root.serversInfo.proxy || "" }
                LogosButton {
                    objectName: "saveProxyButton"; text: "Save proxy"
                    enabled: root.ready && proxyField.text.trim() !== "" && proxyField.text.trim() !== (root.serversInfo.proxy || "")
                    onClicked: backend.setProxy(proxyField.text.trim())
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Theme.spacing.small
                LogosText { text: "Servers"; font.pixelSize: 15 }
                LogosBadge { visible: root.overall !== ""; text: root.overallLabel(root.overall); color: root.overallColor(root.overall) }
                Item { Layout.fillWidth: true }
                LogosText { text: "Preset"; color: Theme.palette.textSecondary }
                Repeater {
                    model: [{ id: "two-operators", label: "Two operators" }, { id: "single", label: "Single server" }]
                    LogosButton {
                        objectName: "preset_" + modelData.id
                        text: modelData.label
                        enabled: root.ready
                        variant: root.serversInfo.preset === modelData.id ? LogosButton.Variant.Primary : LogosButton.Variant.Secondary
                        onClicked: backend.applyPreset(modelData.id)
                    }
                }
            }
            LogosText { Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.palette.textTertiary
                        text: "Two operators check each other's answers. A change applies the next time a wallet opens." }
            LogosText { visible: root.serverList.length === 0; color: Theme.palette.textSecondary
                        text: "No server list yet." }
            Repeater {
                model: root.serverList
                LogosFrame {
                    Layout.fillWidth: true
                    contentItem: ColumnLayout {
                        spacing: Theme.spacing.tiny
                        RowLayout {
                            Layout.fillWidth: true
                            LogosText { textFormat: Text.PlainText; text: modelData.label || modelData.id || "" }
                            LogosText { textFormat: Text.PlainText; color: Theme.palette.textTertiary; text: modelData.operator || "" }
                            LogosBadge { text: modelData.enabled ? "In use" : "Standby"
                                         color: modelData.enabled ? Theme.palette.success : Theme.palette.textTertiary }
                            Item { Layout.fillWidth: true }
                            LogosText { textFormat: Text.PlainText; font.pixelSize: 12; color: Theme.palette.textSecondary
                                        text: modelData.enabled ? root.healthLine(modelData.id) : "" }
                        }
                        LogosText { textFormat: Text.PlainText; font.pixelSize: 11; color: Theme.palette.textTertiary
                                    text: modelData.url || "" }
                    }
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
                        shown: root.balancesReady && root.zatOf(root.transparentPool.total) > 0
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
                                        LogosText { textFormat: Text.PlainText; font.pixelSize: 12; color: Theme.palette.textSecondary
                                                    text: modelData.totalZec + " ZEC" }
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
                                                                                                      : "Too small to shield"
                                        }
                                    }
                                }
                            }
                        ]
                    }

                    LogosNotice {
                        objectName: "orchardRow"
                        Layout.fillWidth: true
                        shown: root.balancesReady && root.zatOf(root.orchardPool.total) > 0
                        severity: LogosNotice.Warning
                        title: "Orchard funds need moving"
                        message: root.balancesReady
                                 ? ((root.orchardPool.totalZec || "0") + " ZEC is in Orchard, which has been spend-only since NU6.3. "
                                    + "Moving it privately follows the ZIP 318 schedule into your shielded balance.")
                                 : ""
                        actions: [
                            LogosBadge { text: "Orchard"; color: Theme.palette.info },
                            LogosButton { objectName: "migrateButton"; text: "Move privately · coming soon"; enabled: false }
                        ]
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
                        }
                        LogosBadge {
                            objectName: "recipientKindBadge"
                            visible: root.recipientKind !== ""
                            text: root.recipientKind
                            color: root.recipientKind === "shielded" ? Theme.palette.success
                                   : (root.recipientKind === "other network" ? Theme.palette.error : Theme.palette.warning)
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
                        visible: root.recipientKind === "other network"
                        color: Theme.palette.error
                        text: "This address is for another network."
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
                                      + "that cannot pay a shielded address."
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
                    model: root.historyRows
                    delegate: Rectangle {
                        id: txRow
                        width: ListView.view.width
                        implicitHeight: txCol.implicitHeight + 12
                        radius: 4
                        readonly property bool open: root.openTx === modelData.txid
                        color: open ? Theme.palette.surface : "transparent"
                        ColumnLayout {
                            id: txCol
                            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                            anchors.margins: 6
                            spacing: 4
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.spacing.small
                                LogosText { Layout.preferredWidth: 80; text: root.kindLabel(modelData.kind) }
                                LogosBadge { text: root.txIsTransparent(modelData) ? "Transparent" : "Shielded"
                                             color: root.txIsTransparent(modelData) ? Theme.palette.warning : Theme.palette.success }
                                LogosBadge { visible: root.zatOf(modelData.amountMadePublic) > 0; text: "Public amount"
                                             color: Theme.palette.warning }
                                LogosText { textFormat: Text.PlainText; text: root.signedZec(modelData.deltaZec) + " ZEC" }
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
                                visible: txRow.open
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
        title: root.preview && root.preview.shielding ? "Review shielding" : "Review send"
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
                    Repeater {
                        model: root.preview ? (root.preview.recipients || []) : []
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
                          onClicked: approveSheet.open() },
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
            LogosText { Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText; text: root.approveSummary() }
            LogosTextField {
                id: approvePw; objectName: "approvePasswordField"; placeholderText: "Wallet password"
                echoMode: TextInput.Password; Layout.fillWidth: true
                Component.onCompleted: textInput.passwordMaskDelay = 0
                Connections {
                    target: approvePw.textInput
                    function onAccepted() { if (approveConfirm.enabled) approveConfirm.clicked() }
                }
            }
            LogosText { visible: root.ttl === 0; color: Theme.palette.error; text: "The preview expired. Cancel and review again." }
            LogosButton {
                id: approveConfirm
                objectName: "approveConfirm"
                text: root.preview && root.preview.shielding ? "Approve and shield" : "Approve and send"
                variant: LogosButton.Variant.Primary
                enabled: root.ready && approvePw.text !== "" && root.send.state === "previewed" && root.ttl > 0
                onClicked: { backend.approveSend(approvePw.text); approvePw.text = ""; approveSheet.close() }
            }
        }
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
