import QtQuick

// Drives the view through the first-run "Use Tor for" choice and the Settings choice against a fake
// backend. Prints STATES-OK, or STATES-FAIL with the cases that disagree.
Item {
    id: scene
    width: 1280; height: 900

    // The host injects `logos`; the view finds this one by name up its context chain.
    property QtObject logos: QtObject {
        signal viewModuleReadyChanged(string moduleName, bool isReady)
        signal intentRequested(string requestId, string intent, var params, string requesterName)
        property var responses: []
        property var requests: []
        property var lastCallback: null
        function module(name) { return fake }
        function isViewModuleReady(name) { return true }
        function request(intent, params, cb) { requests = requests.concat([{ intent: intent, params: params }]); lastCallback = cb }
        function respond(id, ok, result, error) { responses = responses.concat([[id, ok, error]]) }
        function watch(reply, ok, err) { ok(reply) }
    }

    QtObject {
        id: fake
        property string lastError: ""
        property bool busy: false
        property string pendingJobId: ""
        property string pendingJobKind: ""
        property string lastJobJson: ""
        property string statusJson: "{}"
        property string syncJson: ""
        property string networksJson: JSON.stringify({ networks: ["mainnet", "testnet", "regtest"], active: "mainnet" })
        property string walletsJson: "[]"
        property string balancesJson: ""
        property string receiveJson: ""
        property string shieldedQrJson: ""
        property string transparentQrJson: ""
        property string serversJson: ""
        property string serverHealthJson: ""
        property string localNodeJson: ""
        property string historyJson: ""
        property int historyPage: 0
        property string sendRequestId: ""
        property string sendStatusJson: "{}"
        property string sendError: ""
        property string migrationJson: ""
        property string migrationPlanJson: ""
        property string migrationJobKind: ""
        property string migrationError: ""
        property string torUseJson: ""
        // What setTorUse answers: "" or the refusal.
        property string torUseRefusal: ""
        property var calls: []
        function note(name, args) { calls = calls.concat([[name].concat(args)]) }
        function last(name) {
            for (var i = calls.length - 1; i >= 0; i--) if (calls[i][0] === name) return calls[i]
            return null
        }
        function count(name) { return calls.filter(function (c) { return c[0] === name }).length }
        function refresh() {}
        function clearAndRefresh() {}
        function setActiveNetwork(n) { note("setActiveNetwork", [n]) }
        function openWallet(name, password) { note("openWallet", [name]) }
        function createWallet(name, password) { note("createWallet", [name]) }
        function restoreWallet(name, password, phrase, birthday) { note("restoreWallet", [name]) }
        function changePassword(oldPassword, newPassword) {}
        function revealSeed(password) { return "" }
        function exportViewingKey(password) { return "" }
        function closeWallet() { note("closeWallet", []) }
        function prepareSend(recipient, amount, memo, mixed) {}
        function shieldAddress(address) {}
        function approveSend(password) {}
        function cancelSend() {}
        function dismissSend() {}
        function planMigration() {}
        function migrateNow() {}
        function approveMigration(password) {}
        function pauseMigration() {}
        function resumeMigration() {}
        function cancelMigration() {}
        function dismissMigrationPlan() {}
        function newAddress() {}
        function addressValid(t) { return JSON.stringify({ ok: true, valid: false, reason: "not an address" }) }
        function refreshHistory() {}
        function showHistoryPage(p) {}
        function setTorUse(mode) { note("setTorUse", [mode]); return torUseRefusal }
        function setProxy(p) { note("setProxy", [p]); return "" }
        function addServer(address, name) { note("addServer", [address, name]); return "" }
        function removeServer(id) { return "" }
        function setServerEnabled(id, enabled) { return "" }
        function setServerTor(id, tor) { note("setServerTor", [id, tor]); return "" }
        function setLocalNode(enabled) { return "" }
        function watchServers(on) {}
        function refreshLocalNode() {}
    }

    function torUse(mode, chosen, migrated) {
        return JSON.stringify({ torUse: mode, torUseChosen: chosen, torUseMigrated: migrated })
    }
    // One operator's server in use, and an onion service on standby.
    readonly property string servers: JSON.stringify({ proxy: "tor", localNode: false, servers: [
        { id: "zec.rocks", url: "https://zec.rocks:443", operator: "zec.rocks", label: "zec.rocks", enabled: true, source: "preset" },
        { id: "onion", url: "http://" + "a".repeat(56) + ".onion:9067", operator: "Onion", label: "Onion", enabled: false, source: "preset" }
    ] })

    property var bad: []
    function expect(name, got, want) {
        if (JSON.stringify(got) !== JSON.stringify(want)) bad.push(name + ": got " + JSON.stringify(got) + ", want " + JSON.stringify(want))
    }
    // Every object named `name`, through items, popups and loaders.
    function findAll(obj, name, depth, out) {
        if (!obj || (depth || 0) > 80) return out
        if (obj.objectName === name) out.push(obj)
        var kids = []
        if (obj.data) for (var i = 0; i < obj.data.length; i++) kids.push(obj.data[i])
        var lists = [obj.leftActions, obj.rightActions]
        for (var l = 0; l < lists.length; l++)
            if (lists[l]) for (var a = 0; a < lists[l].length; a++) kids.push(lists[l][a])
        if (obj.contentItem && kids.indexOf(obj.contentItem) < 0) kids.push(obj.contentItem)
        if (obj.item && kids.indexOf(obj.item) < 0) kids.push(obj.item)
        for (var k = 0; k < kids.length; k++) findAll(kids[k], name, (depth || 0) + 1, out)
        return out
    }
    function find(name) { var all = findAll(view.item, name, 0, []); return all.length ? all[0] : null }
    function prop(name, p) { var o = find(name); return o ? o[p] : "<no " + name + ">" }
    function shown(name) { return prop(name, "visible") }
    // The servers pane is in Settings and in a sheet: true when any copy of `name` is visible.
    function shownAny(name) { return findAll(view.item, name, 0, []).some(function (o) { return o.visible === true }) }
    function click(name) { var o = find(name); if (o) o.clicked(); else bad.push("no " + name + " to click") }
    function checks(prefix) {
        return ["identifying", "all", "none"].map(function (k) { return prop(prefix + "_" + k, "checked") })
    }
    function tags(prefix, tag) {
        return ["identifying", "all", "none"].map(function (k) { return shown(prefix + tag + "_" + k) })
    }

    property var steps: [
        function (v) {
            expect("a backend without tor_use: no first-run screen", shown("torUsePage"), false)
            expect("...the Wallets screen instead", shown("walletsPage"), true)
            // An existing install: today's all-Tor routing, migrated, not chosen yet.
            fake.torUseJson = scene.torUse("all", false, true)
        },
        function (v) {
            expect("not chosen yet: the screen shows", shown("torUsePage"), true)
            expect("...in place of the Wallets screen", shown("walletsPage"), false)
            expect("existing install: its routing preselected", checks("torUseFirst"), [false, true, false])
            expect("...tagged Current", tags("torUseFirst", "Current"), [false, true, false])
            expect("...and identifying still Recommended", tags("torUseFirst", "Recommended"), [true, false, false])
            click("torUseContinue")
            expect("Continue keeps it", fake.last("setTorUse"), ["setTorUse", "all"])
            // A fresh install.
            fake.torUseJson = scene.torUse("identifying", false, false)
        },
        function (v) {
            expect("fresh install: identifying preselected", checks("torUseFirst"), [true, false, false])
            expect("...nothing tagged Current", tags("torUseFirst", "Current"), [false, false, false])
            expect("...identifying Recommended", tags("torUseFirst", "Recommended"), [true, false, false])
            click("torUseContinue")
            expect("Continue sends identifying", fake.last("setTorUse"), ["setTorUse", "identifying"])
            click("torUseFirst_none")
        },
        function (v) {
            expect("a click moves the selection", checks("torUseFirst"), [false, false, true])
            fake.torUseRefusal = "close the wallet to change this"
            click("torUseContinue")
            expect("Continue sends the changed selection", fake.last("setTorUse"), ["setTorUse", "none"])
            expect("...and shows a refusal", prop("torUseNotice", "message"), "close the wallet to change this")
            expect("...on screen", shown("torUseNotice"), true)
            expect("...without losing the selection", checks("torUseFirst"), [false, false, true])
            fake.torUseRefusal = ""
            click("torUseFirst_all")
            click("torUseContinue")
            expect("...then the next pick", fake.last("setTorUse"), ["setTorUse", "all"])
            fake.torUseJson = scene.torUse("all", true, false)
        },
        function (v) {
            expect("chosen: the screen is gone", shown("torUsePage"), false)
            expect("...for the Wallets screen", shown("walletsPage"), true)
            var n = fake.count("setTorUse")
            v.chooseTorUse("none")
            expect("...and chooseTorUse does nothing", fake.count("setTorUse"), n)
            // Not chosen, but a wallet is open.
            fake.torUseJson = scene.torUse("identifying", false, false)
            fake.serversJson = scene.servers
            fake.statusJson = JSON.stringify({ open: true, name: "w", network: "mainnet" })
        },
        function (v) {
            expect("never over an open wallet", shown("torUsePage"), false)
            expect("...whose tabs show", shown("walletTabs"), true)
            v.selectTab(4)
        },
        function (v) {
            var opts = ["identifying", "all", "none"].map(function (k) { return findAll(view.item, "torUseSetting_" + k, 0, []) })
            expect("Settings has the three options", opts.map(function (o) { return o.length > 0 }), [true, true, true])
            expect("...disabled while a wallet is open",
                   opts.map(function (o) { return o.some(function (r) { return r.enabled === true }) }), [false, false, false])
            expect("...saying why", shownAny("torUseLockedLine"), true)
            expect("...the current mode checked", opts.map(function (o) { return o.length > 0 && o[0].checked }), [true, false, false])
            fake.statusJson = "{}"
            fake.torUseJson = scene.torUse("identifying", true, false)
        },
        function (v) {
            click("networkSettingsButton")
        },
        function (v) {
            expect("the sheet opens", shown("networkSheet"), true)
            expect("with no wallet open, Settings is enabled", prop("torUseSetting_identifying", "enabled"), true)
            expect("...with no lock line", shownAny("torUseLockedLine"), false)
            expect("identifying: no per-server Tor switch", shownAny("torSwitch_zec.rocks"), false)
            expect("...but Which Tor", shownAny("ownTorSwitch"), true)
            expect("...and one operator sees both sides",
                   String(prop("oneOperatorNotice", "message")).indexOf("sees both sides") >= 0, true)
            var vis = function (n) { return findAll(view.item, n, 0, []).filter(function (o) { return o.visible })[0] || null }
            var ys = ["localNodePane", "torUseSetting_all", "torUseSetting_identifying", "torUseSetting_none"].map(function (n) {
                var o = vis(n); return o ? Math.round(o.mapToItem(null, 0, 0).y) : -1 })
            expect("most private first: your own node, then Everything to Nothing",
                   ys.every(function (y, i) { return y >= 0 && (i === 0 || y > ys[i - 1]) }) ? "in order" : JSON.stringify(ys), "in order")
            expect("...with its benefits and costs", [vis("ownNodeBenefits"), vis("ownNodeCosts")].every(function (o) { return o !== null }), true)
            expect("...and Servers below", vis("localNodePane").mapToItem(null, 0, 0).y < vis("addServerPane").mapToItem(null, 0, 0).y, true)
            vis("manageLocalNodeButton").clicked()
            var asked = logos.requests[logos.requests.length - 1]
            expect("Open Zcash Zebra Node raises zcash.node.configure", asked ? asked.intent : "<none>", "zcash.node.configure")
            logos.lastCallback({ ok: false, error: "unavailable" })
            expect("...and says when the app is missing", vis("localNodeNote") ? vis("localNodeNote").text : "", "The Zcash Zebra Node app is not installed.")
            v.localNodeNote = ""
            click("torUseSetting_all")
            expect("a pick in Settings sends it", fake.last("setTorUse"), ["setTorUse", "all"])
            fake.torUseJson = scene.torUse("all", true, false)
        },
        function (v) {
            expect("everything: the per-server Tor switch", shownAny("torSwitch_zec.rocks"), true)
            expect("...and Which Tor", shownAny("ownTorSwitch"), true)
            expect("...one operator, no timing line",
                   String(prop("oneOperatorNotice", "message")).indexOf("sees both sides") >= 0, false)
            fake.torUseJson = scene.torUse("none", true, false)
        },
        function (v) {
            expect("nothing: no per-server Tor switch", shownAny("torSwitch_zec.rocks"), false)
            expect("...no Which Tor", shownAny("ownTorSwitch"), false)
            expect("...nor its pane", shownAny("ownTorPane"), false)
            expect("...nor Manage Tor", shownAny("manageTorLink"), false)
            find("torUseExplainLink").activate()
            expect("What this means opens the text", v.torUseExplained, true)
            // A backend that predates the setting: as before, every switch through Tor.
            fake.torUseJson = ""
        },
        function (v) {
            expect("no setting from an old backend", shownAny("torUsePane"), false)
            expect("...the per-server Tor switch as before", shownAny("torSwitch_zec.rocks"), true)
            v.closeSheets()
            // Another app asks to unlock a wallet before the choice is made.
            fake.torUseJson = scene.torUse("identifying", false, false)
            logos.intentRequested("r1", "zcash.wallet.unlock", { wallet: "w" }, "other_app")
        },
        function (v) {
            expect("an unlock waits for the choice", shown("openWalletSheet"), false)
            expect("...behind the screen", shown("torUsePage"), true)
            fake.torUseJson = scene.torUse("identifying", true, false)
        },
        function (v) {
            expect("...then its sheet opens", shown("openWalletSheet"), true)
            expect("...for that wallet", prop("openNameField", "text"), "w")
        }
    ]
    property int step: 0
    Timer {
        id: driver
        interval: 30
        repeat: true
        onTriggered: {
            var v = view.item
            try { scene.steps[scene.step](v) } catch (e) { bad.push("step " + scene.step + " threw " + e) }
            scene.step += 1
            if (scene.step >= scene.steps.length) {
                driver.stop()
                console.log(bad.length ? "STATES-FAIL " + bad.join("; ") : "STATES-OK " + scene.steps.length + " steps")
                Qt.quit()
            }
        }
    }

    Loader {
        id: view
        anchors.fill: parent
        source: "../qml/ZcashWalletView.qml"
        onStatusChanged: {
            if (status === Loader.Error) { console.log("STATES-FAIL load"); Qt.quit(); return }
            if (status === Loader.Ready) driver.start()
        }
    }
}
