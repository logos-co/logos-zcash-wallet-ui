import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Logos.Controls
import Logos.Theme
import "accountkit" as Accounts

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
            if (!root.nodeSetupNeeded) openWalletSheet.open()
        }
    }
    // Home and the header follow your node while the wallet reads from it.
    Timer {
        interval: root.localStatus ? 10000 : 30000
        repeat: true
        triggeredOnStart: true
        running: root.ready && root.walletOpen && root.localNodeOn && root.activeNetwork !== "regtest"
        onTriggered: backend.refreshLocalNode()
    }
    // With no wallet open, servers are checked only while the servers sheet is open. The
    // backend holds that for 3 minutes, so it is renewed each minute.
    Timer {
        interval: 60000
        repeat: true
        running: root.ready && networkSheet.visible
        onTriggered: backend.watchServers(true)
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
    // Home's rows key on the address alone: a new block changes amounts, not rows, so a Shield
    // button is not destroyed and rebuilt under a click.
    property var transparentAddressList: []
    onTransparentAddressesChanged: {
        var next = transparentAddresses.map(function (a) { return a.address })
        if (next.join(",") !== transparentAddressList.join(",")) transparentAddressList = next
    }
    readonly property var transparentByAddress: {
        var m = {}
        transparentAddresses.forEach(function (a) { m[a.address] = a })
        return m
    }
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
    // Some enabled server has not had its first check yet.
    readonly property bool healthPending: health.pending === true
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
    property string torNote: ""
    // Network settings apply when a wallet opens; while one is open they show but do not change.
    readonly property bool networkLocked: walletOpen
    // The proxy setting: "tor" for the Tor that comes with Logos, a socks5h URL for the user's
    // own, "direct" for none (regtest).
    readonly property string proxySetting: serversInfo.proxy || ""
    readonly property bool ownTor: proxySetting.indexOf("socks5h://") === 0
    // tor_use() for the active network: { torUse, torUseChosen, torUseMigrated, network }; null from a
    // backend that predates it, which routes as Everything does.
    readonly property var torUseInfo: {
        var t = ready ? j(backend.torUseJson, "{}") : ({})
        return ["all", "identifying", "none"].indexOf(t.torUse) >= 0 ? t : null
    }
    readonly property string torUse: torUseInfo ? torUseInfo.torUse : "all"
    // Saved in Node: wallets open before the reads catch up. Each network asks anew.
    property bool torUseAnswered: false
    // Create, restore and open wait for Node to be saved, never over a wallet.
    readonly property bool nodeSetupNeeded: torUseInfo !== null && torUseInfo.torUseChosen === false && !torUseAnswered && !walletOpen
    property bool torUseSending: false
    property string nodeSetupNote: ""
    // The network the shown setting belongs to.
    readonly property string torUseNetwork: (torUseInfo && torUseInfo.network) || activeNetwork
    onNodeSetupNeededChanged: {
        // An unlock another app asked for waits for Node.
        if (!root.nodeSetupNeeded && root.unlockRequestId !== "" && !root.walletOpen) openWalletSheet.open()
    }
    // The Node sheet's words, shared with the Bitcoin and Monero wallets.
    readonly property string torUseIntro: "Your own node is the most private. Public sources are run by other people."
    function torUseNetworkLine() { return "For " + (root.torUseNetwork || "this network") + ". Each network has its own setting." }
    readonly property string ownNodeSummary: "A Zebra node, in Logos or at an address."
    readonly property string publicSummary: "Zcash servers run by other people."
    readonly property string torUseTorIntro: "Tor hides your IP address, which can reveal where you are, from public sources, but "
                                             + "it is slower than a direct connection."
    // Most private first; identifying stays the default.
    readonly property var torUseModes: [
        { key: "all", label: "Everything",
          happens: "Every request to the servers goes through Tor, unless you set a server to skip it.",
          pros: "No server learns your IP address, and your internet provider can't see that you use Zcash, unless you "
                + "set a server to skip Tor.",
          cons: "Slower syncing, which stops while Tor is down." },
        { key: "identifying", label: "Only what identifies you",
          happens: "Blocks, which are the same for everyone, come straight from the server. Looking up your transactions "
                   + "and transparent addresses, and sending, go over Tor. With servers from two operators on, blocks come "
                   + "from one, lookups go to the other, and sends try the other first.",
          pros: "Syncs faster than Everything. The servers can't tie your transactions, transparent addresses or sends "
                + "to your IP address.",
          cons: "The server you sync from and your internet provider can see that your IP address uses a Zcash wallet, "
                + "and when it is open. The server can also tell roughly when the wallet was created: within about a day "
                + "for a new wallet, about nine days for a restored one. With only one operator's servers on, that "
                + "operator sees both sides and could try to match them by timing." },
        { key: "none", label: "Nothing",
          happens: "Every request goes directly to the servers. Tor isn't used, so onion services are off.",
          pros: "The fastest choice, and it works where Tor is blocked.",
          cons: "The servers see your IP address together with your transactions, transparent addresses and sends. "
                + "Your internet provider can see that you use Zcash." }
    ]
    readonly property string torUseEveryMode: "In every mode, anything on your own network is reached directly, and an onion "
                                              + "address only through Tor. Use Tor for doesn't apply to your own node."
    // The built-in Tor's { state, progress, detail } while the network uses it, else null.
    readonly property var tor: health.tor || null
    readonly property bool torWaiting: tor !== null && tor.state !== "ready"
    // "Your own Tor" picked, before an address is saved.
    property bool ownTorOpen: false
    readonly property bool hasTor: proxySetting === "tor" || ownTor
    // Where the chain comes from: "public", "local" (Zebra in Logos) or "own" (an address).
    // A backend that predates it reports only localNode.
    readonly property bool sourcesKnown: typeof serversInfo.chainSource === "string"
    readonly property string chainSource: sourcesKnown ? serversInfo.chainSource : (localNodeOn ? "local" : "public")
    // Your own server at an address: { url, direct, ... }, kept while another source is in use.
    readonly property var ownServer: serversInfo.own || null
    // With the node in Logos, payments go "servers" (over Tor) or "node"; with your server at an
    // address too, when the node module lists "own" in localSendsFor.
    readonly property string localSends: serversInfo.localSends || "servers"
    readonly property bool ownSendsKnown: Array.isArray(serversInfo.localSendsFor) && serversInfo.localSendsFor.indexOf("own") >= 0
    readonly property bool ownSendsViaServers: chainSource === "own" && ownSendsKnown && localSends === "servers" && broadcastServer
    // "Your own node" or "At an address" picked before anything is saved.
    property bool ownNodeOpen: false
    property bool ownAddressOpen: false
    readonly property bool ownNodeChosen: chainSource !== "public" || ownNodeOpen
    readonly property bool inLogosChosen: chainSource === "local" && !ownAddressOpen
    // In Logos is the default place: picked when "Your own node" opens, applied once Zebra runs.
    readonly property bool inLogosPreselected: chainSource === "public" && ownNodeOpen && !ownAddressOpen
    // The "Reach it through Tor" switch before Save; null follows the saved server.
    property var ownTorPick: null
    readonly property bool ownServerTor: ownTorPick !== null ? ownTorPick : !(ownServer && ownServer.direct === true)
    // Servers you choose, or the default operators' (regtest has no presets).
    readonly property bool choosingServers: activeNetwork === "regtest" || (serversInfo.preset || "custom") === "custom"
    // Some server is contacted: public sources, your own server, or sends through servers.
    readonly property bool serversInUse: chainSource !== "local" || (localSends === "servers" && broadcastServer)
    onChainSourceChanged: { ownNodeOpen = false; ownAddressOpen = false; ownTorPick = null }
    // Each network asks anew.
    onActiveNetworkChanged: {
        ownNodeOpen = false; ownAddressOpen = false; ownTorPick = null
        torUseAnswered = false; nodeSetupNote = ""
    }
    // The header's network picker: only while no wallet is open.
    readonly property bool canPickNetwork: ready && !busy && !walletOpen
    // Public servers the user set to skip Tor, in Everything; the user's own network never goes through it.
    readonly property var directServers: serverList.filter(function (s) {
        return root.torUse === "all" && s.enabled === true && s.direct === true && !root.isLanUrl(s.url)
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
    // What a settings change refused, shown next to it: "proxy", "servers", "torUse", "source", "own" or "sends".
    property string networkNote: ""
    property string networkNoteAt: ""
    onNetworkLockedChanged: { torOffAskedFor = ""; networkNote = ""; ownTorOpen = false; ownNodeOpen = false; ownAddressOpen = false; ownTorPick = null }
    readonly property bool localNodeAvailable: localNode.available === true
    onLocalNodeAvailableChanged: if (localNodeAvailable) { localNodeNote = ""; root.takeInLogos() }
    // While the wallet reads from your node: the blocks it is behind, by its own estimate or the
    // last server check. 0 within 10 blocks, and on regtest, whose estimate runs far ahead.
    readonly property int nodeBehind: {
        if (!walletOpen || !localNodeOn || activeNetwork === "regtest") return 0
        var gap = 0, s = localStatus, c = sync.crossCheck
        if (localNodeAvailable && s && Number(s.estimatedHeight) > 0) gap = Number(s.estimatedHeight) - Number(s.height)
        if (c && c.verdict === "node_behind" && sync.tip) gap = Math.max(gap, c.serverTip - sync.tip)
        return gap > 10 ? gap : 0
    }
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
        for (let i = 0; i < historyRows.length; i++) {
            const r = historyRows[i]
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
            const opened = lastJob.state === "done"
            const mine = opened && lastJob.name === root.unlockWallet
            const err = !opened ? (lastJob.error || "open failed") : (mine ? "" : "a different wallet was opened")
            logos.respond(root.unlockRequestId, mine, ({}), err)
            root.unlockRequestId = ""
            root.unlockWallet = ""
            root.unlockOpenSent = false
        }
        if (lastJob.state !== "done") return
        if (lastJob.kind === "create" || lastJob.kind === "restore") {
            const created = lastJob.kind === "create"
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
        for (let i = 0; i < s.length; i++) {
            const c = s.charCodeAt(i)
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
    // Your node's progress as the Zcash Node app shows it, else the blocks it is behind.
    function nodeFraction() {
        var s = root.localStatus
        return root.localNodeAvailable && s && Number(s.estimatedHeight) > 0
               ? Math.max(0, Math.min(1, Number(s.height) / Number(s.estimatedHeight))) : 0
    }
    function nodeProgress() {
        var f = root.nodeFraction()
        return f > 0 ? (Math.floor(f * 1000) / 10).toFixed(1) + "%" : root.fmtHeight(root.nodeBehind) + " blocks behind"
    }
    function nodeLine() {
        return "Your node is still syncing, " + root.fmtHeight(root.nodeBehind) + " blocks behind. Until it catches up, "
               + "the wallet can't see newer blocks, so transactions in them don't show yet."
    }
    function syncLine() {
        if (!root.syncRead) return "Sync: —"
        var s = root.sync.state || ""
        if (s === "synced") return (root.nodeBehind > 0 ? "Synced to your node, at block " : "Synced to block ") + root.fmtHeight(root.sync.tip)
        if (s === "scanning" || s === "downloading") {
            const eta = root.etaText(root.sync.etaSecs)
            return "Scanning · block " + root.fmtHeight(root.sync.fullyScanned) + " of " + root.fmtHeight(root.sync.tip)
                   + " (" + Math.floor(root.syncFraction() * 100) + "%)" + (eta ? " · " + eta : "")
        }
        if (s === "starting" || s === "connecting") return root.chainSource !== "public" ? "Connecting to your node…" : "Connecting to servers…"
        return "Sync: " + s
    }
    function syncChip() {
        if (!root.ready) return "Connecting…"
        if (!root.walletOpen) return ""
        if (!root.syncRead) return "Sync —"
        var s = root.sync.state
        if (s === "synced") return root.nodeBehind > 0 ? "Node syncing · " + root.nodeProgress() : "Synced · " + root.fmtHeight(root.sync.tip)
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
        // Every server reads offline while the built-in Tor joins: say what is happening instead.
        if (o === "offline" && root.torWaiting) return root.torLine()
        // None has answered yet, and one is still on its first check.
        if (o === "offline" && root.healthPending) return "Checking servers…"
        if (o === "ok") return "Servers OK"
        if (o === "degraded") return "Servers degraded"
        if (o === "disagreement") return "Servers disagree"
        if (o === "offline") return "Servers offline"
        if (o === "update_required") return "Update required"
        return o
    }
    function overallColor(o) {
        if (o === "offline" && root.torWaiting) return root.torColor()
        if (o === "offline" && root.healthPending) return Theme.palette.textSecondary
        if (o === "ok") return Theme.palette.success
        if (o === "degraded") return Theme.palette.warning
        return Theme.palette.error
    }
    function torLine() {
        var t = root.tor
        if (!t) return ""
        if (t.state === "ready") return "Connected to Tor"
        if (t.state === "connecting") return "Connecting to Tor… " + (t.progress || 0) + "%"
        return t.state === "blocked" ? "Tor can't connect" : "Tor could not start"
    }
    function torColor() {
        if (!root.torWaiting) return Theme.palette.success
        return root.tor.state === "connecting" ? Theme.palette.warning : Theme.palette.error
    }
    // server_health() per server, as a list of { id, ... } or a map keyed by id.
    function healthOf(id) {
        var s = root.health.servers
        if (Array.isArray(s)) {
            for (let i = 0; i < s.length; i++) if (s[i] && s[i].id === id) return s[i]
            return null
        }
        return s && s[id] ? s[id] : null
    }
    // The node lists a server it has not checked yet with no checkedAt, and reachable false.
    function healthState(id) {
        var h = root.healthOf(id)
        if (!h || h.checkedAt === undefined || h.checkedAt === null) return "checking"
        return h.reachable === true ? "reachable" : "unreachable"
    }
    function healthLine(id) {
        var h = root.healthOf(id), state = root.healthState(id)
        if (state === "checking") return "checking…"
        if (state === "unreachable") return "unreachable" + (h.lastError ? ": " + h.lastError : "")
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
        if (!s) return (l.error ? l.error + ". " : "") + "The Zcash Zebra Node app installs and runs it."
        var st = s.state || "unknown"
        if (l.available !== true) {
            if (st === "running") return "It is running " + (s.network || "another network") + "; this wallet is on " + root.activeNetwork + "."
            if (st === "failed") return "It failed" + (s.lastError ? ": " + s.lastError : ".")
            return "It is " + st + ". Start it for " + root.activeNetwork + " in the Zcash Zebra Node app."
        }
        return root.activeNetwork !== "regtest" && Number(s.estimatedHeight) - Number(s.height) > 10
               ? "Still syncing: the wallet sees the chain only as far as your node has it." : ""
    }
    // The label the user knows a server by, or its host.
    function serverName(url) {
        for (let i = 0; i < root.serverList.length; i++)
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
            const a = +v4[1], b = +v4[2]
            return a === 127 || a === 10 || (a === 172 && b >= 16 && b < 32) || (a === 192 && b === 168)
                   || (a === 100 && b >= 64 && b < 128) || (a === 169 && b === 254)
        }
        if (h.indexOf(":") >= 0) return h === "::1" || /^f[cd]/.test(h) || /^fe[89ab]/.test(h)
        return h === "localhost" || /\.(local|lan|home\.arpa|internal)$/.test(h)
    }
    function isOnionUrl(url) { return /^http:\/\/[a-z2-7]{56}\.onion(:\d+)?\/?$/i.test(url || "") }
    // A settings SLOT's reply: "" or the refusal, shown at `at`; `refused` runs on a refusal, `done` on success.
    function networkCall(reply, at, refused, done) {
        root.networkNote = ""
        logos.watch(reply,
                    function (e) {
                        root.networkNoteAt = at
                        root.networkNote = e || ""
                        if (e && refused) refused()
                        if (!e && done) done()
                    },
                    function () {
                        root.networkNoteAt = at
                        root.networkNote = "The wallet backend did not answer."
                        if (refused) refused()
                    })
    }
    // A network's first Save keeps the checked mode, so an existing routing is never weakened.
    function saveNodeSetup() {
        root.nodeSetupNote = ""
        root.torUseSending = true
        logos.watch(backend.setTorUse(root.torUse),
                    function (e) {
                        root.torUseSending = false
                        if (e) { root.nodeSetupNote = e; return }
                        root.torUseAnswered = true
                        networkSheet.close()
                    },
                    function () {
                        root.torUseSending = false
                        root.nodeSetupNote = "The wallet backend did not answer."
                    })
    }
    readonly property string ownNodeNote:
        "<b>Benefits:</b> the wallet asks only your node for blocks, transactions and transparent addresses, so no one "
        + "else sees what it looks up.<br><br><b>Costs:</b> about 300 GB of disk on mainnet and a first sync of hours to days. "
        + "It must be running while you use the wallet.<br><br>" + ownSendsNote
    // An older node module sends through a server at an address always.
    readonly property string ownSendsNote: ownSendsKnown
        ? "<b>Sending:</b> payments go as Sending payments says: through public servers over Tor, the default, or through "
          + "your node. Zebra in Logos then passes them to its peers from this computer's IP address; a server at an "
          + "address hands them to its node, which passes them to its peers."
        : "<b>Sending:</b> with Zebra in Logos, payments go as Sending payments says: through public servers over Tor, the "
          + "default, or through Zebra, which passes them to its peers from this computer's IP address. A server at an "
          + "address always hands them to its node, which passes them to its peers."
    // How your own server's address is reached: "lan", "onion" or "internet"; "" with none typed.
    function ownAddressKind(text) {
        var t = (text || "").trim()
        if (t === "") return ""
        var u = t.indexOf("://") >= 0 ? t : "http://" + t
        if (/^[a-z]+:\/\/[^\/:]+\.onion(:\d+)?\/?$/i.test(u)) return "onion"
        return root.isLanUrl(u) ? "lan" : "internet"
    }
    function pickInLogos() {
        root.ownAddressOpen = false
        root.ownTorPick = null
        if (root.chainSource !== "local") root.setLocalNode(true)
    }
    function takeInLogos() {
        if (root.inLogosPreselected && root.localNodeAvailable && root.ready && !root.networkLocked) root.pickInLogos()
    }
    // With an address saved before, it is used again at once; otherwise the field waits for one.
    function pickAtAddress() {
        root.ownAddressOpen = true
        if (root.chainSource !== "own" && root.ownServer) root.networkCall(backend.setChainSource("own"), "own")
    }
    function pickPublic() {
        root.ownNodeOpen = false
        root.ownAddressOpen = false
        root.ownTorPick = null
        if (root.chainSource === "public") return
        if (root.sourcesKnown) root.networkCall(backend.setChainSource("public"), "source")
        else root.setLocalNode(false)
    }
    function useBuiltInTor() {
        root.ownTorOpen = false
        if (root.ownTor) root.networkCall(backend.setProxy("tor"), "proxy")
    }
    function setLocalNode(on) {
        root.localNodeNote = ""
        logos.watch(backend.setLocalNode(on),
                    function (e) { root.localNodeNote = e || "" },
                    function () { root.localNodeNote = "The wallet backend did not answer." })
    }
    // The built-in Tor has its own app.
    function manageTor() {
        root.torNote = ""
        logos.request("tor.manage", ({}), function (res) {
            if (res.ok || res.error === "cancelled") return
            root.torNote = res.error === "unavailable" ? "The Tor app is not installed."
                                                        : "That request did not go through (" + res.error + ")."
        })
    }
    // The node has its own app.
    function manageLocalNode() {
        root.localNodeNote = ""
        logos.request("zcash.node.configure", ({ network: root.activeNetwork }), function (res) {
            if (res.ok || res.error === "cancelled") return
            root.localNodeNote = res.error === "unavailable" ? "The Zcash Zebra Node app is not installed."
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
            const h = Math.floor(hours), m = Math.round((secs - h * 3600) / 60)
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
            const others = root.zatOf(r.sentToOthers), self = root.zatOf(r.sentToSelf)
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
            const left = root.zatOf(r.expiryHeight) - root.chainTip
            return "pending" + (r.expiryHeight && root.chainTip ? " · expires in " + Math.max(0, left) + " blocks" : "")
        }
        if (!r.height || !root.chainTip) return "mined"
        var n = root.chainTip - r.height + 1
        return n >= 10 ? "confirmed" : (n > 0 ? n + " conf" : "mined")
    }

    // Built on the Wallets screen and in Settings: servers are needed before a wallet can open.
    // One decision tree; while a wallet is open it keeps its shape, read-only.
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
            // The address as saved, normalized by the node module, replaces what was typed.
            function saveOwnServer() {
                root.networkNote = ""
                logos.watch(backend.setOwnServer(ownServerField.text.trim(), root.ownServerTor),
                            function (e) {
                                root.networkNoteAt = "own"
                                root.networkNote = e || ""
                                if (e) return
                                root.ownTorPick = null
                                root.ownAddressOpen = false
                                if (root.ownServer) ownServerField.text = root.ownServer.url
                            },
                            function () { root.networkNoteAt = "own"; root.networkNote = "The wallet backend did not answer." })
            }
            readonly property string ownTyped: ownServerField.text.trim()
            readonly property bool ownEdited: ownTyped !== (root.ownServer ? root.ownServer.url : "")
            readonly property string ownKind: root.ownAddressKind(ownTyped)
            // The address this branch describes: what is typed, or the saved one.
            readonly property bool ownNeedsTor: ownKind === "onion" || (ownKind === "internet" && root.ownServerTor)

            LogosNotice {
                objectName: "networkLockedNotice"
                Layout.fillWidth: true
                shown: root.networkLocked
                message: "These settings apply when a wallet opens. Close the wallet to change them."
            }

            LogosText { text: "Where the wallet gets Zcash's chain"; font.pixelSize: 15 }
            LogosText { objectName: "chainNetworkLine"; Layout.fillWidth: true; Layout.preferredWidth: 1; wrapMode: Text.Wrap
                        textFormat: Text.PlainText; color: Theme.palette.textSecondary; text: root.torUseNetworkLine() }
            LogosText { objectName: "torUseIntro"; Layout.fillWidth: true; Layout.preferredWidth: 1; wrapMode: Text.Wrap
                        color: Theme.palette.textSecondary; text: root.torUseIntro }
            LogosNotice {
                objectName: "nodeSetupSheetNotice"
                Layout.fillWidth: true
                shown: root.nodeSetupNeeded
                title: "Not saved for " + (root.torUseNetwork || "this network") + " yet"
                message: "Wallets open on " + (root.torUseNetwork || "this network") + " once you save. Check where the "
                         + "wallet gets the chain and what to use Tor for, then press Save."
            }
            LogosNotice {
                objectName: "nodeSetupNote"
                Layout.fillWidth: true
                severity: LogosNotice.Error
                shown: root.nodeSetupNote !== ""
                message: root.nodeSetupNote
            }

            // ---- 1. Your own node ----
            Choice {
                Layout.fillWidth: true
                name: "sourceOwn"
                label: "Your own node"
                badge: "Most private"
                note: root.ownNodeSummary
                info: root.ownNodeNote
                infoName: "ownNodeNote"
                selected: root.ownNodeChosen
                choosable: root.ready && !root.networkLocked
                onPicked: { root.ownNodeOpen = true; root.takeInLogos() }
            }
            ColumnLayout {
                id: localNodePane
                objectName: "ownNodeBranch"
                Layout.fillWidth: true
                Layout.leftMargin: 30
                visible: root.ownNodeChosen
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
                LogosText {
                    objectName: "ownNodePickLine"
                    visible: root.chainSource === "public" && !root.ownAddressOpen
                    Layout.fillWidth: true; Layout.preferredWidth: 1; wrapMode: Text.Wrap; color: Theme.palette.textTertiary
                    text: "In Logos takes over once Zebra is running for " + (root.activeNetwork || "this network")
                          + ". Until then the wallet keeps using public sources."
                }

                // In Logos: the Zebra node this computer runs, read over Logos IPC.
                Choice {
                    Layout.fillWidth: true
                    name: "ownNodeInLogos"
                    label: "In Logos"
                    info: "The Zcash Zebra Node app on this computer."
                    selected: root.inLogosChosen || root.inLogosPreselected
                    // Only while Zebra runs this network, or to keep it.
                    choosable: root.ready && !root.networkLocked && (root.localNodeOn || root.localNodeAvailable)
                    onPicked: root.pickInLogos()
                }
                ColumnLayout {
                    objectName: "inLogosPane"
                    Layout.fillWidth: true
                    Layout.leftMargin: 30
                    spacing: Theme.spacing.tiny
                    LogosText {
                        objectName: "localNodeState"
                        Layout.fillWidth: true; textFormat: Text.PlainText; wrapMode: Text.Wrap
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
                    RowLayout {
                        Layout.fillWidth: true
                        LogosButton { objectName: "manageLocalNodeButton"; text: "Open Zcash Zebra Node…"; enabled: root.ready; onClicked: root.manageLocalNode() }
                        LogosText { objectName: "localNodeNote"; visible: text !== ""; Layout.fillWidth: true; textFormat: Text.PlainText
                                    wrapMode: Text.Wrap; color: Theme.palette.error; text: root.localNodeNote }
                    }
                    LogosText {
                        objectName: "localNodePeersLine"
                        visible: root.inLogosChosen
                        Layout.fillWidth: true; Layout.preferredWidth: 1; wrapMode: Text.Wrap; color: Theme.palette.textTertiary
                        text: "Zebra reaches its peers directly: it has no Tor setting, here or in the Zcash Zebra Node app. "
                              + "Its peers see that this computer runs a Zcash node."
                    }
                    LogosText {
                        objectName: "localNodeCrossCheck"
                        Layout.fillWidth: true; visible: text !== "" && root.inLogosChosen; textFormat: Text.PlainText
                        wrapMode: Text.Wrap; color: Theme.palette.textSecondary
                        text: root.crossCheckLine()
                    }
                    LogosNotice {
                        readonly property var check: root.sync.crossCheck
                        objectName: "localNodeDiffersNotice"
                        Layout.fillWidth: true
                        severity: LogosNotice.Error
                        shown: root.inLogosChosen && !!check && check.verdict === "differs"
                        message: shown ? "Your node and " + root.serverName(check.server) + " have different blocks at "
                                         + root.fmtHeight(Math.min(check.nodeTip, check.serverTip)) + ", so one of them is on a "
                                         + "false chain. Until they agree, do not count on new payments shown here." : ""
                    }
                    LogosNotice {
                        objectName: "localNodeDownNotice"
                        Layout.fillWidth: true
                        severity: LogosNotice.Warning
                        shown: root.localNodeOn && root.localNode.network !== undefined && !root.localNodeAvailable
                        message: "The wallet reads from your node, which is not running for " + root.activeNetwork + ". It cannot sync until it is."
                    }

                    // Where payments go out, with the node in Logos.
                    ColumnLayout {
                        objectName: "localSendsPane"
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.spacing.tiny
                        visible: root.inLogosChosen && root.sourcesKnown
                        spacing: Theme.spacing.tiny
                        LogosText { text: "Sending payments"; font.weight: Theme.typography.weightMedium }
                        Choice {
                            Layout.fillWidth: true
                            name: "localSends_servers"
                            label: "Through public servers, over Tor"
                            badge: "Recommended"
                            info: "Your node isn't told who sent it, unless only one server is on and your node hasn't seen the "
                                  + "payment within two minutes; then the wallet sends it through your node too. The same servers "
                                  + "cross-check your node's chain."
                            selected: root.localSends === "servers"
                            choosable: root.ready && !root.networkLocked
                            onPicked: if (!selected) root.networkCall(backend.setLocalSends("servers"), "sends")
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.leftMargin: 30
                            visible: root.localSends === "servers"
                            spacing: Theme.spacing.tiny
                            LogosText {
                                objectName: "localSendsServersLine"
                                Layout.fillWidth: true; Layout.preferredWidth: 1; wrapMode: Text.Wrap; textFormat: Text.PlainText
                                color: Theme.palette.textTertiary
                                text: root.operatorsInUse.length
                                      ? "Through " + root.operatorsInUse.join(" or ") + ", the servers under Public sources."
                                      : "No server under Public sources is on, so your node sends them itself."
                            }
                            WhichTor {
                                Layout.fillWidth: true
                                prefix: "localSends"
                                visible: root.hasTor || root.ownTorOpen
                                proxy: root.proxySetting
                                ownOpen: root.ownTorOpen
                                locked: root.networkLocked
                                ready: root.ready
                                tor: root.tor
                                torText: root.torLine()
                                torTint: root.torColor()
                                waiting: "Payments can't go out until it can."
                                note: root.networkNoteAt === "proxy" ? root.networkNote : ""
                                manageNote: root.torNote
                                onPickBuiltIn: root.useBuiltInTor()
                                onPickOwn: root.ownTorOpen = true
                                onUseOwn: function (address) { root.networkCall(backend.setProxy(address), "proxy") }
                                onManage: root.manageTor()
                            }
                        }
                        Choice {
                            Layout.fillWidth: true
                            name: "localSends_node"
                            label: "Through your node"
                            info: "No server is contacted, but Zebra's peers can tell this computer sent it."
                            selected: root.localSends === "node"
                            choosable: root.ready && !root.networkLocked
                            onPicked: if (!selected) root.networkCall(backend.setLocalSends("node"), "sends")
                        }
                        LogosNotice {
                            Layout.fillWidth: true
                            severity: LogosNotice.Error
                            shown: root.networkNote !== "" && root.networkNoteAt === "sends"
                            message: shown ? root.networkNote : ""
                        }
                    }
                }

                // At an address: a lightwalletd the user runs elsewhere. The address decides Tor.
                Choice {
                    Layout.fillWidth: true
                    name: "ownNodeAtAddress"
                    visible: root.sourcesKnown
                    label: "At an address"
                    info: "A node you run elsewhere, with lightwalletd in front of it."
                    selected: root.chainSource === "own" || root.ownAddressOpen
                    choosable: root.ready && !root.networkLocked
                    onPicked: root.pickAtAddress()
                }
                ColumnLayout {
                    objectName: "ownServerPane"
                    Layout.fillWidth: true
                    Layout.leftMargin: 30
                    visible: root.sourcesKnown && (root.chainSource === "own" || root.ownAddressOpen)
                    spacing: Theme.spacing.tiny
                    RowLayout {
                        Layout.fillWidth: true
                        LogosTextField { id: ownServerField; objectName: "ownServerField"; Layout.fillWidth: true
                                         readOnly: root.networkLocked
                                         placeholderText: "192.168.1.20 or node.example.com:9067"
                                         text: root.ownServer ? root.ownServer.url : "" }
                        LogosButton {
                            objectName: "saveOwnServerButton"; text: "Save"
                            visible: !root.networkLocked
                            enabled: root.ready && pane.ownTyped !== "" && (pane.ownEdited || root.chainSource !== "own")
                            onClicked: pane.saveOwnServer()
                        }
                    }
                    LogosText {
                        objectName: "ownServerReach"
                        visible: pane.ownKind === "lan" || pane.ownKind === "onion"
                        Layout.fillWidth: true; Layout.preferredWidth: 1; wrapMode: Text.Wrap; color: Theme.palette.textSecondary
                        text: pane.ownKind === "lan" ? "Reached directly. Tor can't reach your network." : "Always reached through Tor."
                    }
                    LogosSwitch {
                        objectName: "ownServerTorSwitch"
                        visible: pane.ownKind === "internet"
                        text: "Reach it through Tor"
                        checkable: false
                        checked: root.ownServerTor
                        enabled: root.ready && !root.networkLocked
                        onClicked: {
                            // A saved address changes at once; one being typed waits for Save.
                            if (root.ownServer && !pane.ownEdited && root.chainSource === "own")
                                root.networkCall(backend.setOwnServer(root.ownServer.url, !root.ownServerTor), "own")
                            else
                                root.ownTorPick = !root.ownServerTor
                        }
                    }
                    LogosText {
                        objectName: "ownServerTorLine"
                        visible: pane.ownKind === "internet"
                        Layout.fillWidth: true; Layout.preferredWidth: 1; wrapMode: Text.Wrap; color: Theme.palette.textTertiary
                        text: "Otherwise its network sees this computer reaching your node."
                    }
                    WhichTor {
                        Layout.fillWidth: true
                        prefix: "ownServer"
                        visible: pane.ownNeedsTor && (root.hasTor || root.ownTorOpen)
                        proxy: root.proxySetting
                        ownOpen: root.ownTorOpen
                        locked: root.networkLocked
                        ready: root.ready
                        tor: root.tor
                        torText: root.torLine()
                        torTint: root.torColor()
                        waiting: root.ownSendsViaServers ? "The wallet can't reach your node or send payments until it can."
                                                         : "The wallet can't reach your node until it can."
                        note: root.networkNoteAt === "proxy" ? root.networkNote : ""
                        manageNote: root.torNote
                        onPickBuiltIn: root.useBuiltInTor()
                        onPickOwn: root.ownTorOpen = true
                        onUseOwn: function (address) { root.networkCall(backend.setProxy(address), "proxy") }
                        onManage: root.manageTor()
                    }
                    LogosText {
                        objectName: "ownServerHealth"
                        readonly property string healthState: root.healthState("own")
                        visible: root.chainSource === "own" && !pane.ownEdited
                        Layout.fillWidth: true; textFormat: Text.PlainText; elide: Text.ElideMiddle; font.pixelSize: 12
                        color: Theme.palette.textSecondary
                        text: root.healthLine("own")
                    }
                    LogosNotice {
                        objectName: "ownServerNote"
                        Layout.fillWidth: true
                        severity: LogosNotice.Error
                        shown: root.networkNote !== "" && root.networkNoteAt === "own"
                        message: shown ? root.networkNote : ""
                    }

                    // Where payments go out, with your server at an address: the same setting as In Logos.
                    ColumnLayout {
                        objectName: "ownSendsPane"
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.spacing.tiny
                        visible: root.chainSource === "own" && root.ownSendsKnown
                        spacing: Theme.spacing.tiny
                        LogosText { text: "Sending payments"; font.weight: Theme.typography.weightMedium }
                        Choice {
                            Layout.fillWidth: true
                            name: "ownSends_servers"
                            label: "Through public servers, over Tor"
                            badge: "Recommended"
                            info: "The payment reaches the network through the servers, not through your server's node. If only one "
                                  + "server is on and your server hasn't seen the payment within two minutes, the wallet sends it "
                                  + "through your server too."
                            selected: root.localSends === "servers"
                            choosable: root.ready && !root.networkLocked
                            onPicked: if (!selected) root.networkCall(backend.setLocalSends("servers"), "sends")
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.leftMargin: 30
                            visible: root.localSends === "servers"
                            spacing: Theme.spacing.tiny
                            LogosText {
                                objectName: "ownSendsServersLine"
                                Layout.fillWidth: true; Layout.preferredWidth: 1; wrapMode: Text.Wrap; textFormat: Text.PlainText
                                color: Theme.palette.textTertiary
                                text: root.broadcastServer
                                      ? "Through " + root.operatorsInUse.join(" or ") + ", the servers under Public sources."
                                      : "No server under Public sources is on, so your server sends them itself."
                            }
                            // Your server's Which Tor, when it goes through Tor, covers sends too.
                            WhichTor {
                                Layout.fillWidth: true
                                prefix: "ownSends"
                                visible: root.broadcastServer && !pane.ownNeedsTor && (root.hasTor || root.ownTorOpen)
                                proxy: root.proxySetting
                                ownOpen: root.ownTorOpen
                                locked: root.networkLocked
                                ready: root.ready
                                tor: root.tor
                                torText: root.torLine()
                                torTint: root.torColor()
                                waiting: "Payments can't go out until it can."
                                note: root.networkNoteAt === "proxy" ? root.networkNote : ""
                                manageNote: root.torNote
                                onPickBuiltIn: root.useBuiltInTor()
                                onPickOwn: root.ownTorOpen = true
                                onUseOwn: function (address) { root.networkCall(backend.setProxy(address), "proxy") }
                                onManage: root.manageTor()
                            }
                        }
                        Choice {
                            Layout.fillWidth: true
                            name: "ownSends_node"
                            label: "Through your server"
                            info: "No public server is contacted. Your server's node passes the payment to its peers, which can "
                                  + "tell that node sent it."
                            selected: root.localSends === "node"
                            choosable: root.ready && !root.networkLocked
                            onPicked: if (!selected) root.networkCall(backend.setLocalSends("node"), "sends")
                        }
                        LogosNotice {
                            Layout.fillWidth: true
                            severity: LogosNotice.Error
                            shown: root.networkNote !== "" && root.networkNoteAt === "sends"
                            message: shown ? root.networkNote : ""
                        }
                    }
                }
            }

            // ---- 2. Public sources ----
            Choice {
                Layout.fillWidth: true
                name: "sourcePublic"
                label: "Public sources"
                note: root.publicSummary
                selected: !root.ownNodeChosen
                choosable: root.ready && !root.networkLocked
                onPicked: root.pickPublic()
            }
            LogosNotice {
                Layout.fillWidth: true
                severity: LogosNotice.Error
                shown: root.networkNote !== "" && root.networkNoteAt === "source"
                message: shown ? root.networkNote : ""
            }
            ColumnLayout {
                objectName: "publicBranch"
                Layout.fillWidth: true
                Layout.leftMargin: 30
                visible: !root.ownNodeChosen
                spacing: Theme.spacing.small

                // Which servers: the default operators, or a list the user keeps. Regtest has no presets.
                ColumnLayout {
                    objectName: "serverChoicePane"
                    Layout.fillWidth: true
                    visible: root.activeNetwork !== "regtest"
                    spacing: Theme.spacing.tiny
                    Choice {
                        Layout.fillWidth: true
                        name: "serversPicked"
                        label: "Servers picked for you"
                        info: "Servers from two operators. Only what identifies you splits blocks and lookups between them; "
                              + "the other modes check each one's blocks against the other's."
                        selected: !root.choosingServers
                        choosable: root.ready && !root.networkLocked
                        onPicked: if (!selected) root.networkCall(backend.applyPreset("two-operators"), "servers")
                    }
                    Choice {
                        Layout.fillWidth: true
                        name: "serversChosen"
                        label: "Servers you choose"
                        info: "Turn servers on and off, and add your own."
                        selected: root.choosingServers
                        choosable: root.ready && !root.networkLocked
                        onPicked: if (!selected) root.networkCall(backend.applyPreset("custom"), "servers")
                    }
                }

                // Kept per network by the node module; a backend that predates it has none.
                ColumnLayout {
                    objectName: "torUsePane"
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.spacing.tiny
                    visible: root.torUseInfo !== null
                    spacing: Theme.spacing.small
                    LogosText { text: "Use Tor for"; font.weight: Theme.typography.weightMedium }
                    LogosText { Layout.fillWidth: true; Layout.preferredWidth: 1; wrapMode: Text.Wrap; color: Theme.palette.textSecondary
                                text: root.torUseTorIntro }
                    Repeater {
                        model: root.torUseModes
                        TorUseOption {
                            required property var modelData
                            Layout.fillWidth: true
                            mode: modelData
                            prefix: "torUseSetting"
                            // An open wallet's Settings shows the same pane, read-only and short.
                            detailed: !root.networkLocked
                            selected: root.torUse === modelData.key
                            choosable: root.ready && !root.networkLocked
                            onPicked: if (!selected) root.networkCall(backend.setTorUse(modelData.key), "torUse", null,
                                                                      function () { root.torUseAnswered = true })
                        }
                    }
                    LogosText { objectName: "torUseEveryMode"; Layout.fillWidth: true; Layout.preferredWidth: 1; wrapMode: Text.Wrap
                                font.pixelSize: 12; color: Theme.palette.textTertiary; text: root.torUseEveryMode }
                    LogosText { objectName: "torUseLockedLine"; visible: root.networkLocked; color: Theme.palette.textSecondary
                                text: "Close the wallet to change this." }
                    LogosNotice {
                        Layout.fillWidth: true
                        severity: LogosNotice.Error
                        shown: root.networkNote !== "" && root.networkNoteAt === "torUse"
                        message: shown ? root.networkNote : ""
                    }
                }
                WhichTor {
                    Layout.fillWidth: true
                    prefix: "public"
                    visible: root.torUse !== "none" && (root.hasTor || root.ownTorOpen)
                    proxy: root.proxySetting
                    ownOpen: root.ownTorOpen
                    locked: root.networkLocked
                    ready: root.ready
                    tor: root.tor
                    torText: root.torLine()
                    torTint: root.torColor()
                    waiting: "Servers that need Tor are not reached until it can."
                    hint: root.torUse !== "all" ? "Or set Use Tor for to Nothing."
                          : root.choosingServers ? "Or set a server below to skip Tor." : "Or choose servers yourself and set one to skip Tor."
                    note: root.networkNoteAt === "proxy" ? root.networkNote : ""
                    manageNote: root.torNote
                    onPickBuiltIn: root.useBuiltInTor()
                    onPickOwn: root.ownTorOpen = true
                    onUseOwn: function (address) { root.networkCall(backend.setProxy(address), "proxy") }
                    onManage: root.manageTor()
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.spacing.small
                    LogosText { text: "Servers"; font.weight: Theme.typography.weightMedium }
                    LogosInfoButton {
                        objectName: "operatorsInfo"
                        title: "More than one operator"
                        text: "With Everything or Nothing, blocks come from each operator in turn and must fit together, so a "
                              + "false chain stops the sync, and no one operator sees every transaction you look up. With Only what "
                              + "identifies you, blocks come from one operator and lookups go to the other. A transaction one server "
                              + "accepts must reach another server within two minutes, or the wallet sends it there too. Servers of "
                              + "the same operator only stand in for each other."
                    }
                    LogosBadge { visible: root.overall !== ""; text: root.overallLabel(root.overall); color: root.overallColor(root.overall) }
                    Item { Layout.fillWidth: true }
                }

                // Servers picked for you: what is in use, read-only.
                Repeater {
                    objectName: "pickedRows"
                    model: root.choosingServers ? [] : root.serverList.filter(function (s) { return s.enabled === true })
                    RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        LogosText { textFormat: Text.PlainText; text: modelData.label || modelData.id || "" }
                        LogosText { visible: text !== "" && text !== (modelData.label || ""); textFormat: Text.PlainText
                                    color: Theme.palette.textTertiary; text: modelData.operator || "" }
                        LogosBadge { visible: root.torUse === "all" && modelData.direct === true && !root.isLanUrl(modelData.url)
                                     text: "Without Tor"; color: Theme.palette.warning }
                        LogosText { objectName: "pickedHealth_" + modelData.id
                                    Layout.fillWidth: true; Layout.preferredWidth: 1; horizontalAlignment: Text.AlignRight; elide: Text.ElideMiddle
                                    textFormat: Text.PlainText; font.pixelSize: 12; color: Theme.palette.textSecondary
                                    text: root.healthLine(modelData.id) }
                    }
                }

                // Servers you choose. The form sits above the list, so it stays in place however long the list grows.
                ColumnLayout {
                    objectName: "addServerPane"
                    Layout.fillWidth: true
                    visible: root.choosingServers && !root.networkLocked
                    spacing: Theme.spacing.tiny
                    LogosText { Layout.fillWidth: true; Layout.preferredWidth: 1; wrapMode: Text.Wrap; color: Theme.palette.textSecondary
                                text: "Add a lightwalletd server you trust: an address like zebra.lan:9067, or https://host:port. "
                                      + "Servers on your own network are reached directly, without Tor." }
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
                LogosText { visible: root.choosingServers && root.serverList.length === 0; color: Theme.palette.textSecondary
                            text: "No server yet." }
                Repeater {
                    objectName: "serverRows"
                    model: root.choosingServers ? root.serverList : []
                    LogosFrame {
                        id: serverRow
                        readonly property bool lan: root.isLanUrl(modelData.url)
                        readonly property bool onion: root.isOnionUrl(modelData.url)
                        // A server's own Tor switch applies in Everything only.
                        readonly property bool direct: root.torUse === "all" && modelData.direct === true && !lan
                        Layout.fillWidth: true
                        contentItem: ColumnLayout {
                            spacing: Theme.spacing.tiny
                            RowLayout {
                                Layout.fillWidth: true
                                LogosText { textFormat: Text.PlainText; text: modelData.label || modelData.id || "" }
                                LogosText { visible: text !== "" && text !== (modelData.label || ""); textFormat: Text.PlainText
                                            color: Theme.palette.textTertiary; text: modelData.operator || "" }
                                LogosBadge { objectName: "lanBadge_" + modelData.id; visible: serverRow.lan
                                             text: "Your network"; color: Theme.palette.textSecondary }
                                LogosBadge { objectName: "withoutTorBadge_" + modelData.id; visible: serverRow.direct
                                             text: "Without Tor"; color: Theme.palette.warning }
                                // Takes the free space but asks for none, so a long error elides (keeping its cause)
                                // instead of widening the row and pushing its controls out.
                                LogosText { objectName: "serverHealth_" + modelData.id
                                            readonly property string healthState: modelData.enabled ? root.healthState(modelData.id) : ""
                                            Layout.fillWidth: true; Layout.preferredWidth: 1; horizontalAlignment: Text.AlignRight; elide: Text.ElideMiddle
                                            textFormat: Text.PlainText; font.pixelSize: 12; color: Theme.palette.textSecondary
                                            text: modelData.enabled ? root.healthLine(modelData.id) : "" }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                LogosText { Layout.fillWidth: true; Layout.preferredWidth: 1; elide: Text.ElideRight; textFormat: Text.PlainText
                                            font.pixelSize: 11; color: Theme.palette.textTertiary
                                            text: (modelData.url || "") + (serverRow.lan ? " · reached directly, without Tor"
                                                  : serverRow.onion ? (root.torUse === "none" ? " · an onion service, off without Tor"
                                                                                              : " · an onion service, always through Tor")
                                                  : root.torUse === "none" ? " · directly, without Tor"
                                                  : root.torUse === "identifying" ? " · blocks directly, lookups and sends through Tor"
                                                  : serverRow.direct ? " · without Tor" : " · through Tor") }
                                // Off asks first, below; on needs no asking.
                                LogosSwitch {
                                    objectName: "torSwitch_" + modelData.id
                                    visible: !root.networkLocked && root.torUse === "all" && !serverRow.lan && !serverRow.onion
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
                                message: "It will see this computer's IP address. It can tie it to this wallet's transparent "
                                         + "addresses, to the transactions it sends and looks up, and to when you are online. Your "
                                         + "internet provider sees that you use Zcash. Shielded balances, addresses and memos stay "
                                         + "private either way."
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
                    shown: root.serversRead && root.operatorsInUse.length === 1
                    message: shown ? "Only " + root.operatorsInUse[0] + " is in use, so nothing checks its answers"
                                     + (root.torUse === "identifying" ? ". It also serves both your blocks and your lookups, so it sees "
                                                                        + "both sides and could try to match them by timing" : "")
                                     + (root.choosingServers ? ". Turn on a server from another operator." : ".") : ""
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
                        color: root.nodeBehind > 0 && root.sync.state === "synced" ? Theme.palette.warning : Theme.palette.textSecondary
                        text: root.syncChip() }
            // Orange marks the networks where the money is not real.
            LogosComboBox {
                id: networkPicker
                objectName: "networkPicker"
                readonly property int shownIndex: Math.max(0, (root.networks.networks || []).indexOf(root.displayedNetwork))
                enabled: root.canPickNetwork
                model: root.networks.networks || []
                placeholderText: root.displayedNetwork || "—"
                textColor: root.displayedNetwork === "mainnet" ? Theme.palette.success : Theme.palette.accentOrange
                // Set, not bound: a new model and a pick both reset currentIndex. A refused switch shows the network in use.
                function showNetwork() { currentIndex = shownIndex }
                onModelChanged: Qt.callLater(showNetwork)
                onShownIndexChanged: Qt.callLater(showNetwork)
                Component.onCompleted: showNetwork()
                onActivated: function (index) {
                    root.selectNetwork(textAt(index))
                    Qt.callLater(showNetwork)
                }
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
            }
            // A network's first visit: Node is the one place this is set, and wallets wait for it.
            LogosNotice {
                objectName: "nodeSetupNotice"
                Layout.fillWidth: true
                shown: root.nodeSetupNeeded
                title: "Set up Node for " + (root.torUseNetwork || "this network")
                message: "Before a wallet opens on " + (root.torUseNetwork || "this network") + ", choose where the wallet "
                         + "gets Zcash's chain and what to use Tor for. Each network has its own setting."
                actions: [ LogosButton { objectName: "nodeSetupButton"; text: "Open Node"; variant: LogosButton.Variant.Primary
                                         enabled: root.ready; onClicked: networkSheet.open() } ]
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacing.small
                LogosButton { objectName: "createWalletButton"; text: "Create"; enabled: root.ready && !root.busy && !root.nodeSetupNeeded; onClicked: createSheet.open() }
                LogosButton { objectName: "restoreWalletButton"; text: "Restore"; enabled: root.ready && !root.busy && !root.nodeSetupNeeded; onClicked: restoreSheet.open() }
                LogosButton { objectName: "networkSettingsButton"; text: "Node"; enabled: root.ready; onClicked: networkSheet.open() }
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
                                enabled: root.ready && !root.busy && !root.nodeSetupNeeded
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
                    width: homeScroll.availableWidth - homeScroll.effectiveScrollBarWidth
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
                                    model: root.transparentAddressList
                                    RowLayout {
                                        id: addressRow
                                        readonly property var row: root.transparentByAddress[modelData] || ({})
                                        spacing: Theme.spacing.small
                                        LogosText { textFormat: Text.PlainText; font.pixelSize: 12; text: modelData }
                                        LogosText { objectName: "transparentAmount_" + modelData
                                                    textFormat: Text.PlainText; font.pixelSize: 12; color: Theme.palette.textSecondary
                                                    text: addressRow.row.totalZec + " ZEC" + (root.zatOf(addressRow.row.uneconomic) > 0
                                                          ? " + " + addressRow.row.uneconomicZec + " ZEC too small to spend" : "") }
                                        LogosButton {
                                            objectName: "shieldButton"
                                            visible: root.zatOf(addressRow.row.spendable) >= root.shieldThreshold
                                            text: "Shield"
                                            enabled: root.ready && !root.sendLive
                                            onClicked: root.shield(modelData)
                                        }
                                        LogosText {
                                            visible: root.zatOf(addressRow.row.spendable) < root.shieldThreshold
                                            font.pixelSize: 12
                                            color: Theme.palette.textSecondary
                                            text: root.zatOf(addressRow.row.total) >= root.shieldThreshold ? "Waiting for confirmations"
                                                  : root.zatOf(addressRow.row.total) > 0 ? "Too small to shield" : "Too small to spend"
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
                                visible: root.overall !== "" && root.serversInUse
                                text: root.overallLabel(root.overall)
                                color: root.overallColor(root.overall)
                            }
                        }
                        LogosProgressBar {
                            objectName: "syncProgress"
                            Layout.fillWidth: true
                            // Synced as far as a node that is still syncing: the node's progress.
                            readonly property bool forNode: root.sync.state === "synced" && root.nodeBehind > 0
                            visible: root.syncRead && (root.sync.state !== "synced" || forNode)
                            indeterminate: forNode ? root.nodeFraction() === 0 : !root.sync.tip
                            value: forNode ? root.nodeFraction() : root.syncFraction()
                        }
                        LogosText {
                            objectName: "nodeSyncingNote"
                            visible: root.nodeBehind > 0
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            textFormat: Text.PlainText
                            color: Theme.palette.warning
                            font.pixelSize: 12
                            text: root.nodeLine()
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
                    width: sendScroll.availableWidth - sendScroll.effectiveScrollBarWidth
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
                    width: settingsScroll.availableWidth - settingsScroll.effectiveScrollBarWidth
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
                            // The phrase in the numbered fields it is typed back into; the key as text.
                            Accounts.PhraseGrid {
                                id: secretWords
                                objectName: "secretWords"
                                visible: root.secretKind === "phrase"
                                Layout.fillWidth: true
                                counts: [24]
                                readOnly: true
                            }
                            LogosSelectableText {
                                objectName: "secretText"
                                visible: root.secretKind !== "phrase"
                                Layout.fillWidth: true
                                wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
                                text: root.shownSecret
                            }
                            // Set, not bound: the grid writes its own text back as it fills.
                            Connections {
                                target: root
                                function onShownSecretChanged() { secretWords.text = root.secretKind === "phrase" ? root.shownSecret : "" }
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

    // An "i" beside a choice; its dialog holds the explanation, one paragraph per line.
    component ChoiceInfo: LogosInfoButton {
        id: choiceInfo
        property var lines: []   // [{ name: objectName, text: StyledText }]
        dialogContentItem: ColumnLayout {
            spacing: Theme.spacing.medium
            Repeater {
                model: choiceInfo.lines
                LogosText {
                    required property var modelData
                    objectName: modelData.name || ""
                    Layout.fillWidth: true; Layout.preferredWidth: 1; wrapMode: Text.Wrap; textFormat: Text.StyledText
                    color: Theme.palette.textSecondary; text: modelData.text || ""
                }
            }
        }
    }

    // One "Use Tor for" option: label and tags; what happens, pros and cons behind its "i" when `detailed`.
    component TorUseOption: RowLayout {
        id: opt
        property var mode: ({})
        property bool selected: false
        property bool choosable: true
        property bool detailed: true
        // objectNames: <prefix>_<key>, <prefix>Recommended_<key>, <prefix>Info_<key>, <prefix>Happens_<key>…
        property string prefix: ""
        signal picked()
        spacing: Theme.spacing.small
        LogosRadioButton { objectName: opt.prefix + "_" + opt.mode.key; text: opt.mode.label; enabled: opt.choosable
                           checkable: false; autoExclusive: false; checked: opt.selected; onClicked: opt.picked() }
        LogosBadge { objectName: opt.prefix + "Recommended_" + opt.mode.key; visible: opt.mode.key === "identifying"
                     text: "Recommended"; color: Theme.palette.success }
        ChoiceInfo {
            objectName: opt.prefix + "Info_" + opt.mode.key
            visible: opt.detailed
            title: opt.mode.label || ""
            lines: [["What happens", "Happens_", opt.mode.happens], ["Pros", "Pros_", opt.mode.pros], ["Cons", "Cons_", opt.mode.cons]]
                   .map(function (l) { return { name: opt.prefix + l[1] + opt.mode.key, text: "<b>" + l[0] + ":</b> " + (l[2] || "") } })
        }
        Item { Layout.fillWidth: true }
    }

    // One option of a radio group: the radio is the state; `note` under it, `info` behind its "i".
    // objectNames: <name>, <name>Badge, <name>Info, and infoName (<name>Note) for the info's text.
    component Choice: ColumnLayout {
        id: choice
        property string name: ""
        property string label: ""
        property string badge: ""
        property string note: ""
        property string info: ""
        property string infoName: name + "Note"
        property bool choosable: true
        property bool selected: false
        signal picked()
        spacing: 2
        RowLayout {
            spacing: Theme.spacing.small
            LogosRadioButton { objectName: choice.name; text: choice.label; enabled: choice.choosable
                               checkable: false; autoExclusive: false; checked: choice.selected; onClicked: choice.picked() }
            LogosBadge { objectName: choice.name + "Badge"; visible: choice.badge !== ""; text: choice.badge; color: Theme.palette.success }
            ChoiceInfo { objectName: choice.name + "Info"; visible: choice.info !== ""; title: choice.label
                         lines: [{ name: choice.infoName, text: choice.info }] }
        }
        LogosText { visible: choice.note !== ""; Layout.fillWidth: true; Layout.preferredWidth: 1; Layout.leftMargin: 30
                    wrapMode: Text.Wrap; color: Theme.palette.textSecondary; text: choice.note }
    }

    // Which Tor, shown in whichever branch uses it. objectNames: <prefix>TorBuiltIn, <prefix>TorOwn,
    // <prefix>TorChip, <prefix>ManageTor; the public branch's field and button are proxyField, saveProxyButton.
    component WhichTor: ColumnLayout {
        id: which
        property string prefix: ""
        property string proxy: ""
        property bool ownOpen: false
        property bool locked: false
        property bool ready: false
        property var tor: null
        property string torText: ""
        property color torTint: Theme.palette.success
        // What waits while Tor can't connect, and what else the user can do.
        property string waiting: ""
        property string hint: ""
        property string note: ""
        property string manageNote: ""
        readonly property bool ownChosen: proxy.indexOf("socks5h://") === 0 || ownOpen
        signal pickBuiltIn()
        signal pickOwn()
        signal useOwn(string address)
        signal manage()
        spacing: Theme.spacing.tiny
        LogosText { text: "Which Tor"; font.weight: Theme.typography.weightMedium }
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.small
            LogosRadioButton { objectName: which.prefix + "TorBuiltIn"; text: "The Tor that comes with Logos"
                               enabled: which.ready && !which.locked; checkable: false; autoExclusive: false
                               checked: !which.ownChosen; onClicked: if (which.ownChosen) which.pickBuiltIn() }
            LogosBadge { objectName: which.prefix + "TorChip"; visible: !which.ownChosen && which.tor !== null
                         text: which.torText; color: which.torTint }
            Item { Layout.fillWidth: true }
            LogosLink { objectName: which.prefix + "ManageTor"; visible: !which.ownChosen; text: "Manage Tor…"; underline: false
                        onActivated: which.manage() }
        }
        LogosText { visible: !which.ownChosen && which.manageNote !== ""; Layout.fillWidth: true; textFormat: Text.PlainText
                    wrapMode: Text.Wrap; color: Theme.palette.error; text: which.manageNote }
        LogosProgressBar {
            Layout.fillWidth: true
            visible: !which.ownChosen && which.tor !== null && which.tor.state === "connecting"
            value: which.tor ? (which.tor.progress || 0) / 100 : 0
        }
        LogosNotice {
            objectName: which.prefix + "TorTrouble"
            Layout.fillWidth: true
            severity: LogosNotice.Warning
            shown: !which.ownChosen && which.tor !== null && which.tor.state !== "ready" && which.tor.state !== "connecting"
            title: shown ? which.torText : ""
            message: shown ? (which.tor.detail ? which.tor.detail + ". " : "") + which.waiting + " The app keeps trying. "
                             + "If Tor is blocked on this network, use your own Tor with a bridge." + (which.hint ? " " + which.hint : "") : ""
        }
        LogosRadioButton { objectName: which.prefix + "TorOwn"; text: "Your own Tor"
                           enabled: which.ready && !which.locked; checkable: false; autoExclusive: false
                           checked: which.ownChosen; onClicked: if (!which.ownChosen) which.pickOwn() }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 30
            visible: which.ownChosen
            spacing: Theme.spacing.tiny
            LogosText { Layout.fillWidth: true; Layout.preferredWidth: 1; wrapMode: Text.Wrap; color: Theme.palette.textSecondary
                        text: "For a Tor you already run: a system Tor listens at socks5h://127.0.0.1:9050, Tor Browser at "
                              + "socks5h://127.0.0.1:9150. Your Tor's own settings, such as bridges, apply." }
            RowLayout {
                Layout.fillWidth: true
                LogosTextField { id: ownTorField; objectName: which.prefix === "public" ? "proxyField" : which.prefix + "ProxyField"
                                 Layout.fillWidth: true; readOnly: which.locked; placeholderText: "socks5h://127.0.0.1:9050"
                                 text: which.proxy.indexOf("socks5h://") === 0 ? which.proxy : "" }
                LogosButton {
                    objectName: which.prefix === "public" ? "saveProxyButton" : which.prefix + "SaveProxyButton"
                    text: "Use it"
                    visible: !which.locked
                    // A Tor only: going without one is Use Tor for, Nothing.
                    enabled: which.ready && ownTorField.text.trim().toLowerCase().indexOf("socks5h://") === 0
                             && ownTorField.text.trim() !== which.proxy
                    onClicked: which.useOwn(ownTorField.text.trim())
                }
            }
        }
        LogosNotice {
            Layout.fillWidth: true
            severity: LogosNotice.Error
            shown: which.note !== ""
            message: which.note
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
                width: reviewScroll.availableWidth - reviewScroll.effectiveScrollBarWidth
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
                width: migrationScroll.availableWidth - migrationScroll.effectiveScrollBarWidth
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
            // One word to a numbered field, shown as typed, so it can be checked against the paper.
            Accounts.PhraseGrid { id: rPhrase; objectName: "restorePhraseField"; counts: [24]; Layout.fillWidth: true }
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
                enabled: root.ready && !root.busy && rName.text !== "" && rPhrase.complete
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
        title: "Node"
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 720)
        onOpened: if (root.ready) backend.watchServers(true)
        // A pick that saved nothing is dropped with the sheet.
        onClosed: {
            if (root.ready) backend.watchServers(false)
            root.ownNodeOpen = false; root.ownAddressOpen = false; root.ownTorPick = null
        }
        contentItem: ScrollView {
            id: networkSheetScroll
            objectName: "networkSheetScroll"
            clip: true
            contentWidth: availableWidth
            implicitHeight: Math.min(networkSheetLoader.implicitHeight, Math.max(200, root.height - 200))
            // Scrolls the item named `name` into view, at the bottom. Doc-tests call it before a screenshot:
            // their actions never scroll the sheet.
            function reveal(name) {
                const find = it => {
                    if (it.objectName === name) return it
                    for (let i = 0; i < it.children.length; ++i) { const f = find(it.children[i]); if (f) return f }
                    return null
                }
                const pane = networkSheetLoader.item, it = pane ? find(pane) : null
                if (!it) return false
                const f = networkSheetScroll.contentItem
                const y = it.mapToItem(pane, 0, 0).y + it.height + 16 - f.height
                f.contentY = Math.max(0, Math.min(y, f.contentHeight - f.height))
                return true
            }
            Loader {
                // Less the bar: it is drawn over the content and would take clicks meant for the right edge.
                id: networkSheetLoader
                width: networkSheetScroll.availableWidth - networkSheetScroll.effectiveScrollBarWidth
                active: networkSheet.visible
                sourceComponent: networkPane
            }
        }
        // On a network's first visit, Save stores the checked choice; wallets open after it.
        rightActions: [ LogosButton {
            objectName: "networkSheetDone"
            text: !root.nodeSetupNeeded ? "Done" : root.torUseSending ? "Saving…" : "Save"
            variant: root.nodeSetupNeeded ? LogosButton.Variant.Primary : LogosButton.Variant.Secondary
            enabled: !root.nodeSetupNeeded || (root.ready && !root.torUseSending)
            onClicked: root.nodeSetupNeeded ? root.saveNodeSetup() : networkSheet.close()
        } ]
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
