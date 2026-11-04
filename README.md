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
- **Settings:** wallets, password, recovery phrase, viewing key, Use Tor for, servers and proxy.
- **Restore** takes the 24-word phrase one word to a numbered field, shown as typed so it can be
  checked against the paper; a phrase pasted into any field spreads over the rest. **Show
  recovery phrase** in Settings shows it in the same numbered fields, to be written down as it
  will be typed back. Both are the account kit's `PhraseGrid`, vendored in `qml/accountkit/` by
  `logos-account-kit/scripts/vendor.sh` at the commit in its `VERSION`; CI checks the copy
  against that commit.
- **Use Tor for**, asked once, before the first wallet is created, restored or opened: the
  screen takes the place of the Wallets screen while the node module's `torUseChosen` is false.
  - Three options, most private first, each with what happens, its pros and its cons:
    **Everything**, **Only what identifies you** (tagged Recommended) and **Nothing**.
  - A fresh install has Only what identifies you selected. An existing one has its routing so far, tagged
    Current, so Continue keeps it.
  - Continue stores the choice for every network (`set_tor_use`), and the screen does not come
    back. An unlock another app asks for waits for it.
  - It never shows over an open wallet, nor with a backend too old to have the setting.
- **Servers and privacy:** Network privacy lists the most private first: **Run your own node**
  (below), then **Use Tor for**, with the same three options, with their text behind
  **What this means**. While a wallet is open it shows but is disabled: "Close the wallet to
  change this." Servers that use Tor reach it through the Tor that comes with Logos
  (`tor_module`), with nothing to install or run.
  - A badge and a progress bar show Tor joining. If it is blocked or cannot start, a notice
    says why and what to do. While Tor joins, the server badges read "Connecting to Tor"
    rather than "Servers offline".
  - **Manage Tor…** opens the Tor app (`tor.manage`): Tor's state, its log, Reconnect.
  - **Use my own Tor instead** takes a `socks5h://` address, such as a system Tor at
    `socks5h://127.0.0.1:9050` or Tor Browser at `socks5h://127.0.0.1:9150`. This choice of
    Tor, and Manage Tor…, show for Everything and Only what identifies you; Nothing uses no Tor.
  - With Only what identifies you, blocks come straight from the servers, and looking up
    transactions and transparent addresses, and sending, go through Tor. With one operator in
    use, its notice says that operator sees both sides and could match them by timing.
  - The info button says what each choice reveals: through Tor, without Tor for a server, or
    a server on your own network.
  - Every server has a **Use** switch, and you can add servers of your own by address, such
    as `192.168.1.20` or `zebra.lan:9067`, and remove them.
  - Servers from more than one operator check each other, as the info button explains. Blocks
    come from each operator in turn and must fit together. A transaction one server accepts
    must reach another operator. If one operator goes down, another keeps the wallet working.
    A notice asks for a second operator when only one is in use.
  - Servers on your own network are reached directly, since Tor cannot reach them.
  - With Everything, every other https server has its own **Tor** switch, on by default.
    Turning it off first says what that server would see, and a notice names every server
    reached without Tor.
  - An onion service always goes through Tor, so Nothing leaves it off.
  - While a wallet is open these settings show but do not change; they apply when a wallet
    opens.
  - Servers are checked once a minute: an open wallet's network's, and with no wallet open,
    the network on show while this sheet is open. Nothing is checked otherwise. A server
    switched on reads "checking…" until its first check answers or fails; through Tor that
    can take a while, as the check's circuit is built.
- **Run your own node**, at the top of Network privacy, with its benefits and costs. **Use my
  local node**: reads come from `zebrad_module`'s node over
  Logos IPC; sends still go to the servers, and with no server enabled the node
  broadcasts them itself, without Tor. The pane shows the node's state, height and peers, or
  that it is not installed or not running for this network, and opens the Zcash Zebra Node app
  (`zcash.node.configure`). It applies the next time a wallet opens. The servers take turns
  checking the node; the pane shows the last check, and a warning if they hold different blocks.

Passwords, phrases and keys cross the `.rep` only as SLOT arguments and return values, never
as PROPs. CI checks that.

`src/qrcodegen.*` is Project Nayuki's QR Code generator (MIT License; notice in the files).

```bash
nix build .#lgx
```
