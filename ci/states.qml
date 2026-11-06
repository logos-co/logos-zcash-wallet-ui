import QtQuick

// Drives the view through the first-run choice, where the chain comes from and Use Tor for, against
// a fake backend. Prints STATES-OK, or STATES-FAIL with the cases that disagree.
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
        // The node module's answers, kept in serversJson as it reports them.
        function patchServers(change) {
            var s = JSON.parse(serversJson || "{}")
            for (var k in change) s[k] = change[k]
            serversJson = JSON.stringify(s)
        }
        function setLocalNode(enabled) {
            note("setLocalNode", [enabled]); patchServers({ localNode: enabled, chainSource: enabled ? "local" : "public" }); return ""
        }
        function setChainSource(source) {
            note("setChainSource", [source]); patchServers({ chainSource: source, localNode: source === "local" }); return ""
        }
        function setOwnServer(address, tor) {
            note("setOwnServer", [address, tor])
            patchServers({ chainSource: "own", localNode: false, own: { id: "own", url: "https://" + address, direct: !tor } })
            return ""
        }
        function setLocalSends(via) { note("setLocalSends", [via]); patchServers({ localSends: via }); return "" }
        function applyPreset(name) { note("applyPreset", [name]); patchServers({ preset: name }); return "" }
        function watchServers(on) {}
        function refreshLocalNode() {}
    }

    function torUse(mode, chosen, migrated) {
        return JSON.stringify({ torUse: mode, torUseChosen: chosen, torUseMigrated: migrated })
    }
    // One operator's server in use, and an onion service on standby, on a list the user keeps.
    readonly property string servers: JSON.stringify({ proxy: "tor", localNode: false, chainSource: "public", localSends: "servers",
                                                       preset: "custom", servers: [
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
    // The visible copy of `name`, or null.
    function vis(name) { return findAll(view.item, name, 0, []).filter(function (o) { return o.visible })[0] || null }
    function visCount(name) { return findAll(view.item, name, 0, []).filter(function (o) { return o.visible }).length }
    function setText(name, text) { var o = vis(name); if (o) o.text = text; else bad.push("no " + name + " to type into") }
    function yOf(name) { var o = vis(name); return o ? Math.round(o.mapToItem(null, 0, 0).y) : -1 }

    property var steps: [
        function (v) {
            expect("a backend without tor_use: no notice", shown("nodeSetupNotice"), false)
            expect("...the Wallets screen", shown("walletsPage"), true)
            // An existing install: today's all-Tor routing, migrated, not chosen yet.
            fake.torUseJson = scene.torUse("all", false, true)
        },
        function (v) {
            expect("not chosen yet: the Wallets screen, with a notice", shown("walletsPage") + " " + shown("nodeSetupNotice"), "true true")
            expect("...naming the network", prop("nodeSetupNotice", "title"), "Set up Node for mainnet")
            expect("...no first-run screen", findAll(view.item, "torUsePage", 0, []).length, 0)
            expect("create and restore wait for it", [prop("createWalletButton", "enabled"), prop("restoreWalletButton", "enabled")], [false, false])
            expect("the network, picked in the header", prop("networkPicker", "displayText") + " " + prop("networkPicker", "enabled"), "mainnet true")
            expect("...not on the Wallets screen", shown("networkBox"), "<no networkBox>")
            click("nodeSetupButton")
        },
        function (v) {
            expect("Open Node opens the sheet", shown("networkSheet"), true)
            expect("...saying it isn't saved", vis("nodeSetupSheetNotice") ? vis("nodeSetupSheetNotice").title : "", "Not saved for mainnet yet")
            expect("...for this network", vis("chainNetworkLine") ? vis("chainNetworkLine").text : "", "For mainnet. Each network has its own setting.")
            expect("...in the shared words", vis("torUseIntro") ? vis("torUseIntro").text : "", v.torUseIntro)
            expect("existing install: its routing checked", ["identifying", "all", "none"].map(function (k) { return vis("torUseSetting_" + k).checked }),
                   [false, true, false])
            expect("...identifying still Recommended", vis("torUseSettingRecommended_identifying") !== null, true)
            expect("...no Current tag any more", findAll(view.item, "torUseSettingCurrent_all", 0, []).length, 0)
            expect("...each option with an i, nothing spelled out under it", ["identifying", "all", "none"].map(function (m) {
                return vis("torUseSettingInfo_" + m) !== null && ["Happens_", "Pros_", "Cons_"].every(function (k) {
                    return findAll(view.item, "torUseSetting" + k + m, 0, []).length > 0 && vis("torUseSetting" + k + m) === null }) }), [true, true, true])
            var idInfo = vis("torUseSettingInfo_identifying")
            idInfo.clicked()
            expect("...its i opens what happens, pros and cons", [idInfo.opened, idInfo.title, ["Happens_", "Pros_", "Cons_"].map(function (k) {
                return vis("torUseSetting" + k + "identifying") !== null })], [true, "Only what identifies you", [true, true, true]])
            idInfo.close()
            expect("...and what every mode shares", shownAny("torUseEveryMode"), true)
            expect("the button saves", prop("networkSheetDone", "text"), "Save")
            click("networkSheetDone")
            expect("Save keeps the existing routing", fake.last("setTorUse"), ["setTorUse", "all"])
        },
        function (v) {
            expect("saved: the sheet closes, the notice goes", shown("networkSheet") + " " + shown("nodeSetupNotice"), "false false")
            expect("create is offered", prop("createWalletButton", "enabled"), true)
            // A fresh install, in a new session.
            v.torUseAnswered = false
            fake.torUseJson = scene.torUse("identifying", false, false)
        },
        function (v) {
            expect("fresh install: the notice again", shown("nodeSetupNotice"), true)
            click("networkSettingsButton")
        },
        function (v) {
            expect("fresh: identifying checked", ["identifying", "all", "none"].map(function (k) { return vis("torUseSetting_" + k).checked }),
                   [true, false, false])
            fake.torUseRefusal = "close the wallet to change this"
            click("networkSheetDone")
            expect("Save sends identifying", fake.last("setTorUse"), ["setTorUse", "identifying"])
        },
        function (v) {
            expect("a refusal shows in the sheet", vis("nodeSetupNote") ? vis("nodeSetupNote").message : "", "close the wallet to change this")
            expect("...which stays open", shown("networkSheet"), true)
            fake.torUseRefusal = ""
            vis("torUseSetting_none").clicked()
            expect("picking an option saves it", fake.last("setTorUse"), ["setTorUse", "none"])
        },
        function (v) {
            expect("...so the button is Done", [prop("networkSheetDone", "text"), v.nodeSetupNeeded], ["Done", false])
            v.closeSheets()
            v.torUseAnswered = false
        },
        function (v) {
            click("nodeSetupButton")
        },
        function (v) {
            vis("sourceOwn").clicked()
        },
        function (v) {
            expect("your own node: picked, Use Tor for gone", [vis("sourceOwn").checked, vis("torUsePane")], [true, null])
            expect("...on your own node", shownAny("ownNodeBranch"), true)
            expect("...saying the wallet stays on public sources until then", shownAny("ownNodePickLine"), true)
            click("networkSheetDone")
            expect("...Save still stores the mode", fake.last("setTorUse"), ["setTorUse", "identifying"])
        },
        function (v) {
            expect("saved: the sheet closes", shown("networkSheet"), false)
            fake.torUseJson = scene.torUse("all", true, false)
            v.torUseAnswered = false
            fake.networksJson = JSON.stringify({ networks: ["mainnet", "testnet", "regtest"], active: "testnet" })
            fake.torUseJson = JSON.stringify({ torUse: "identifying", torUseChosen: false, torUseMigrated: false, network: "testnet" })
        },
        function (v) {
            expect("another network asks for itself", shown("nodeSetupNotice") + " " + prop("nodeSetupNotice", "title"), "true Set up Node for testnet")
            expect("...the header shows it", prop("networkPicker", "displayText"), "testnet")
            fake.networksJson = JSON.stringify({ networks: ["mainnet", "testnet", "regtest"], active: "mainnet" })
            fake.torUseJson = scene.torUse("all", true, false)
        },
        function (v) {
            expect("back on mainnet: chosen there", shown("nodeSetupNotice") + " " + prop("networkPicker", "displayText"), "false mainnet")
            // Not chosen, but a wallet is open.
            fake.torUseJson = scene.torUse("identifying", false, false)
            fake.serversJson = scene.servers
            fake.statusJson = JSON.stringify({ open: true, name: "w", network: "mainnet" })
        },
        function (v) {
            expect("never over an open wallet", v.nodeSetupNeeded, false)
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
            expect("the sheet closed: a pick that saved nothing is dropped", v.ownNodeOpen, false)
            expect("public sources: picked", [prop("sourcePublic", "checked"), prop("sourceOwn", "checked")], [true, false])
            expect("...your own node marked most private", shownAny("sourceOwnBadge"), true)
            expect("...its branch closed", shownAny("ownNodeBranch"), false)
            var ys = ["sourceOwn", "sourcePublic", "torUseSetting_all", "torUseSetting_identifying", "torUseSetting_none",
                      "publicTorBuiltIn", "addServerPane"].map(scene.yOf)
            expect("one tree: own node, public sources, Use Tor for, Which Tor, then servers",
                   ys.every(function (y, i) { return y >= 0 && (i === 0 || y > ys[i - 1]) }) ? "in order" : JSON.stringify(ys), "in order")
            expect("...for this network", prop("chainNetworkLine", "text"), "For mainnet. Each network has its own setting.")
            expect("...and what every mode shares", shownAny("torUseEveryMode"), true)
            expect("...options with what happens, pros and cons behind an i", shownAny("torUseSettingInfo_identifying") && !shownAny("torUseSettingCons_identifying"), true)
            expect("...the servers' choices too", ["serversPickedInfo", "serversChosenInfo"].map(shownAny).concat([shownAny("serversPickedNote")]), [true, true, false])
            expect("identifying: no per-server Tor switch", shownAny("torSwitch_zec.rocks"), false)
            expect("...Which Tor: the one with Logos, with its chip and Manage Tor",
                   [prop("publicTorBuiltIn", "checked"), shownAny("publicManageTor"), shownAny("proxyField")], [true, true, false])
            expect("...and one operator sees both sides",
                   String(prop("oneOperatorNotice", "message")).indexOf("sees both sides") >= 0, true)
            click("publicTorOwn")
        },
        function (v) {
            expect("your own Tor: its field", vis("proxyField") !== null, true)
            expect("...no Manage Tor", shownAny("publicManageTor"), false)
            setText("proxyField", "socks5h://127.0.0.1:9050")
            click("saveProxyButton")
            expect("...Use it sets the proxy", fake.last("setProxy"), ["setProxy", "socks5h://127.0.0.1:9050"])
            click("publicTorBuiltIn")
        },
        function (v) {
            expect("back to the Tor with Logos", [prop("publicTorBuiltIn", "checked"), shownAny("proxyField")], [true, false])
            click("serversPicked")
            expect("servers picked for you: the two operators' preset", fake.last("applyPreset"), ["applyPreset", "two-operators"])
            expect("...in every mode one operator checks the blocks from the other",
                   [String(prop("serversPickedNote", "text")).indexOf("each checking the blocks") >= 0,
                    String(prop("operatorsInfo", "text")).indexOf("checks the first one's chain") >= 0,
                    String(prop("operatorsInfo", "text")).indexOf("only a server of the operator you sync from") >= 0], [true, true, true])
        },
        function (v) {
            expect("...shown read-only", [shownAny("addServerPane"), visCount("removeServer_zec.rocks"), shownAny("pickedHealth_zec.rocks")],
                   [false, 0, true])
            click("serversChosen")
            expect("servers you choose: the list as it is", fake.last("applyPreset"), ["applyPreset", "custom"])
            click("sourceOwn")
        },
        function (v) {
            expect("your own node: picked before anything is saved", [prop("sourceOwn", "checked"), prop("sourcePublic", "checked")], [true, false])
            expect("...nothing sent yet", fake.count("setChainSource") + fake.count("setLocalNode"), 0)
            expect("...one note of benefits and costs, behind its i", [findAll(view.item, "ownNodeNote", 0, []).length, visCount("ownNodeNote"),
                   shownAny("sourceOwnInfo")], [1, 0, true])
            expect("...no Use Tor for, no Which Tor, no servers",
                   [shownAny("torUseSetting_identifying"), shownAny("publicTorBuiltIn"), shownAny("localSendsTorBuiltIn"),
                    shownAny("addServerPane"), shownAny("serverRows")], [false, false, false, false, false])
            expect("...In Logos off while Zebra is not running", prop("ownNodeInLogos", "enabled"), false)
            vis("manageLocalNodeButton").clicked()
            var asked = logos.requests[logos.requests.length - 1]
            expect("Open Zcash Zebra Node raises zcash.node.configure", asked ? asked.intent : "<none>", "zcash.node.configure")
            logos.lastCallback({ ok: false, error: "unavailable" })
            expect("...and says when the app is missing", vis("localNodeNote") ? vis("localNodeNote").text : "", "The Zcash Zebra Node app is not installed.")
            v.localNodeNote = ""
            fake.localNodeJson = JSON.stringify({ available: true, network: "mainnet",
                                                  status: { state: "running", network: "mainnet", height: 100, estimatedHeight: 100, peers: 8 } })
        },
        function (v) {
            expect("In Logos on once Zebra runs this network", prop("ownNodeInLogos", "enabled"), true)
            click("ownNodeInLogos")
            expect("...picking it turns the local node on", fake.last("setLocalNode"), ["setLocalNode", true])
        },
        function (v) {
            expect("In Logos: picked", [prop("ownNodeInLogos", "checked"), prop("ownNodeAtAddress", "checked")], [true, false])
            expect("...the node's state and peer line", [shownAny("localNodeState"), shownAny("localNodePeersLine")], [true, true])
            expect("...sending through public servers, over Tor, recommended",
                   [prop("localSends_servers", "checked"), shownAny("localSends_serversBadge")], [true, true])
            expect("...and the node is never told who sent it",
                   [String(prop("localSends_serversNote", "text")).indexOf("isn't told who sent it") >= 0, String(prop("localSends_serversNote", "text")).indexOf("through your node")],
                   [true, -1])
            expect("...with Which Tor under it", shownAny("localSendsTorBuiltIn"), true)
            expect("...and still no Use Tor for", shownAny("torUseSetting_identifying"), false)
            expect("...a server is contacted", v.serversInUse, true)
            click("localSends_node")
            expect("through your node", fake.last("setLocalSends"), ["setLocalSends", "node"])
        },
        function (v) {
            expect("through your node: picked", [prop("localSends_node", "checked"), prop("localSends_servers", "checked")], [true, false])
            expect("...no Which Tor", shownAny("localSendsTorBuiltIn"), false)
            expect("...no server contacted, so no server badge on Home", v.serversInUse, false)
            click("ownNodeAtAddress")
        },
        function (v) {
            expect("at an address: the field, nothing saved yet", [shownAny("ownServerField"), fake.count("setOwnServer")], [true, 0])
            expect("...In Logos no longer shows as picked", prop("ownNodeInLogos", "checked"), false)
            expect("...nor its sending choice", shownAny("localSendsPane"), false)
            setText("ownServerField", "192.168.1.20")
        },
        function (v) {
            expect("a LAN address is reached directly", vis("ownServerReach") ? vis("ownServerReach").text : "",
                   "Reached directly. Tor can't reach your network.")
            expect("...with no Tor switch and no Which Tor", [shownAny("ownServerTorSwitch"), shownAny("ownServerTorBuiltIn")], [false, false])
            setText("ownServerField", "a".repeat(56) + ".onion:9067")
        },
        function (v) {
            expect("an onion address always goes through Tor", vis("ownServerReach") ? vis("ownServerReach").text : "",
                   "Always reached through Tor.")
            expect("...then Which Tor, no switch", [shownAny("ownServerTorBuiltIn"), shownAny("ownServerTorSwitch")], [true, false])
            setText("ownServerField", "node.example.com:9067")
        },
        function (v) {
            expect("an internet address: Reach it through Tor, on by default",
                   [shownAny("ownServerReach"), shownAny("ownServerTorSwitch"), prop("ownServerTorSwitch", "checked")], [false, true, true])
            expect("...saying what going without it shows", shownAny("ownServerTorLine"), true)
            expect("...with Which Tor", shownAny("ownServerTorBuiltIn"), true)
            click("ownServerTorSwitch")
        },
        function (v) {
            expect("switched off before Save: no Which Tor", [prop("ownServerTorSwitch", "checked"), shownAny("ownServerTorBuiltIn")], [false, false])
            expect("...and nothing sent", fake.count("setOwnServer"), 0)
            click("saveOwnServerButton")
            expect("Save sends the address and its Tor switch", fake.last("setOwnServer"), ["setOwnServer", "node.example.com:9067", false])
        },
        function (v) {
            expect("saved: at an address is the source", [prop("ownNodeAtAddress", "checked"), prop("ownNodeInLogos", "checked")], [true, false])
            expect("...the field shows it as saved", prop("ownServerField", "text"), "https://node.example.com:9067")
            expect("...its switch as saved", prop("ownServerTorSwitch", "checked"), false)
            expect("...and its health", shownAny("ownServerHealth"), true)
            click("ownServerTorSwitch")
            expect("a saved address's switch applies at once", fake.last("setOwnServer"), ["setOwnServer", "https://node.example.com:9067", true])
            click("sourcePublic")
            expect("public sources again", fake.last("setChainSource"), ["setChainSource", "public"])
        },
        function (v) {
            expect("public: its branch is back", [shownAny("publicBranch"), shownAny("ownNodeBranch")], [true, false])
            fake.torUseJson = scene.torUse("all", true, false)
        },
        function (v) {
            expect("everything: the per-server Tor switch", shownAny("torSwitch_zec.rocks"), true)
            expect("...and Which Tor", shownAny("publicTorBuiltIn"), true)
            expect("...one operator, no timing line",
                   String(prop("oneOperatorNotice", "message")).indexOf("sees both sides") >= 0, false)
            fake.torUseJson = scene.torUse("none", true, false)
        },
        function (v) {
            expect("nothing: no per-server Tor switch", shownAny("torSwitch_zec.rocks"), false)
            expect("...no Which Tor", [shownAny("publicTorBuiltIn"), shownAny("publicTorOwn")], [false, false])
            expect("...nor Manage Tor", shownAny("publicManageTor"), false)
            // A backend that predates the setting: as before, every switch through Tor.
            fake.torUseJson = ""
        },
        function (v) {
            expect("no setting from an old backend", shownAny("torUsePane"), false)
            expect("...the per-server Tor switch as before", shownAny("torSwitch_zec.rocks"), true)
            // A backend that predates chainSource: the local node switch is all it has.
            fake.serversJson = JSON.stringify({ proxy: "tor", localNode: true, servers: JSON.parse(scene.servers).servers })
        },
        function (v) {
            expect("old backend: its local node reads as In Logos", [prop("sourceOwn", "checked"), prop("ownNodeInLogos", "checked")], [true, true])
            expect("...with no address or sending choice it can't keep", [shownAny("ownNodeAtAddress"), shownAny("localSendsPane")], [false, false])
            click("sourcePublic")
            expect("...public turns the local node off", fake.last("setLocalNode"), ["setLocalNode", false])
            fake.serversJson = scene.servers
            v.closeSheets()
            // Another app asks to unlock a wallet before the choice is made.
            fake.torUseJson = scene.torUse("identifying", false, false)
            logos.intentRequested("r1", "zcash.wallet.unlock", { wallet: "w" }, "other_app")
        },
        function (v) {
            expect("an unlock waits for the choice", shown("openWalletSheet"), false)
            expect("...behind the notice", shown("nodeSetupNotice"), true)
            fake.torUseJson = scene.torUse("identifying", true, false)
        },
        function (v) {
            expect("...then its sheet opens", shown("openWalletSheet"), true)
            expect("...for that wallet", prop("openNameField", "text"), "w")
        },
        function (v) {
            // A short window: the Node sheet scrolls, and its bar must leave the pane's right edge clear.
            v.closeSheets()
            scene.height = 560
            find("networkSheet").open()
        },
        function (v) {
            var sv = find("networkSheet").contentItem, line = vis("chainNetworkLine")
            expect("a short window: the Node sheet scrolls", sv.effectiveScrollBarWidth > 0, true)
            expect("...and its bar leaves the pane's right edge clear",
                   line ? Math.round(line.mapToItem(sv, line.width, 0).x) <= sv.width - sv.effectiveScrollBarWidth : "<no chainNetworkLine>", true)
            v.closeSheets()
            scene.height = 900
        }
    ]
    property int step: 0
    Timer {
        id: driver
        interval: 30
        repeat: true
        onTriggered: {
            var v = view.item
            try { scene.steps[scene.step](v) } catch (e) { bad.push("step " + scene.step + " threw " + e + " at line " + e.lineNumber) }
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
