# logos-zcash-wallet-ui

`zcash_wallet_ui`: the Zcash wallet app for Logos Basecamp, built on the Logos Design System.
It talks only to `zcash_wallet_backend`.

- **Home:** the shielded balance (Ironwood and Sapling), transparent funds per address with a
  Shield action each, and Orchard funds that need moving to Ironwood. A transparent coin worth
  no more than the 0.00005 ZEC it costs to spend shows as too small to spend; the wallet
  library leaves it out of every balance, and Send's review warns before paying one.
- **Migration (ZIP 318):** Move privately plans the run; the review shows the amounts that
  become public, the fees, the transactions, the schedule and when the signed transfers expire.
  The password signs the whole run, and Home follows it with Pause, Resume and Cancel. Move now
  sends all of it in one transaction instead, which makes the whole amount public; it is
  reviewed and approved like a send.
- **Send:** the recipient is checked as you type. The review shows the fee, the pools spent
  and any amount that becomes public. The password approves it.
- **Receive:** a shielded Unified Address, and a transparent address that is replaced once
  it is paid, each with a QR code.
- **History**, with a run's migration transactions under one heading. Each row says what the
  transaction was for: an amount sent, sent to yourself, or shielded, with its fee, rather than
  only the balance change.
- **Settings:** wallets, password, recovery phrase, viewing key, and where the chain comes from.
- **Restore** takes the 24-word phrase one word to a numbered field, shown as typed so it can be
  checked against the paper; a phrase pasted into any field spreads over the rest. **Show
  recovery phrase** in Settings shows it in the same numbered fields, to be written down as it
  will be typed back. Both are the account kit's `PhraseGrid`, vendored in `qml/accountkit/` by
  `logos-account-kit/scripts/vendor.sh` at the commit in its `VERSION`; CI checks the copy
  against that commit.
- **Where the wallet gets Zcash's chain**, asked once, before the first wallet is created,
  restored or opened: the screen takes the place of the Wallets screen while the node module's
  `torUseChosen` is false.
  - **Your own node** (tagged Most private) or **Public sources**, which is preselected.
  - Under Public sources, **Use Tor for**, most private first, each with what happens, its pros
    and its cons: **Everything**, **Only what identifies you** (tagged Recommended) and
    **Nothing**. A fresh install has Only what identifies you selected. An existing one has its
    routing so far, tagged Current, so Continue keeps it.
  - Continue stores the choice for every network (`set_tor_use`), and the screen does not come
    back. With your own node it keeps the node module's mode (Only what identifies you on a
    fresh install) and opens Servers and privacy to pick where the node runs.
  - An unlock another app asks for waits for it. It never shows over an open wallet, nor with a
    backend too old to have the setting.
- **Servers and privacy** reads top to bottom as one choice, **Where the wallet gets Zcash's
  chain**. Each setting shows only while it can change something. While a wallet is open the
  sheet keeps its shape but is read-only: changes apply when a wallet opens.
  - **Your own node**, with one note of its benefits and costs, then where it runs:
    - **In Logos**: the Zebra node of the Zcash Zebra Node app, read over Logos IPC
      (`set_local_node`). It can be picked only while Zebra runs this network. Its state,
      height and peers show here, with **Open Zcash Zebra Node…** (`zcash.node.configure`) and
      the last check of its chain against a server. Zebra reaches its peers without Tor.
      **Sending payments**: **Through public servers, over Tor** (Recommended), where every
      request to those servers goes through Tor whatever Use Tor for says, or **Through your
      node**, where no server is contacted and Zebra's peers can tell this computer sent it
      (`set_local_sends`).
    - **At an address**: a lightwalletd you run elsewhere (`set_own_server`). Its address
      decides Tor: one on your network is reached directly, an onion address always through
      Tor, and any other has a **Reach it through Tor** switch, on by default. Use Tor for
      doesn't apply to it. The address is kept when you switch away.
  - **Public sources**: **Servers picked for you** (the two operators' preset) or **Servers
    you choose** (the list, with **Use** switches, servers you add by address, such as
    `192.168.1.20` or `zebra.lan:9067`, and Remove). Then **Use Tor for**, with the same three
    options behind **What this means**, for every network that uses public sources.
    - With Only what identifies you, blocks come straight from the servers, and lookups and
      sends go through Tor. With one operator in use, its notice says that operator sees both
      sides and could match them by timing.
    - With Everything, every https server you choose has its own **Tor** switch. Turning it off
      first says what that server would see, and a notice names every server reached without
      Tor.
    - Servers from more than one operator check each other, as the info button explains. A
      notice asks for a second operator when only one is in use. Servers on your own network
      are reached directly; an onion service always goes through Tor, so Nothing leaves it off.
  - **Which Tor** shows in whichever branch uses Tor: **The Tor that comes with Logos**
    (`tor_module`), with its state and **Manage Tor…** (`tor.manage`), or **Your own Tor**, a
    `socks5h://` address such as `socks5h://127.0.0.1:9050`. If Tor is blocked or cannot start,
    a notice says why and what to do.
  - Servers are checked once a minute: an open wallet's network's, and with no wallet open,
    the network on show while this sheet is open. A server switched on reads "checking…" until
    its first check answers or fails.

Passwords, phrases and keys cross the `.rep` only as SLOT arguments and return values, never
as PROPs. CI checks that.

`src/qrcodegen.*` is Project Nayuki's QR Code generator (MIT License; notice in the files).

```bash
nix build .#lgx
```
