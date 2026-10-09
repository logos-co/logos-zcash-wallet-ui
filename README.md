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
- **History**, with a run's migration transactions under one heading, and **settings**: wallets, password, recovery phrase, viewing key, servers
  and proxy.
- **Use my local node** (Servers and privacy): reads come from `zebrad_module`'s node over
  Logos IPC; sends still go to the servers over Tor, and with no server enabled the node
  broadcasts them itself, without Tor. The pane shows the node's state, height and peers, or
  that it is not installed or not running for this network, and opens the Zcash Node app
  (`zcash.node.configure`). It applies the next time a wallet opens. The servers take turns
  checking the node; the pane shows the last check, and a warning if they hold different blocks.

Passwords, phrases and keys cross the `.rep` only as SLOT arguments and return values, never
as PROPs. CI checks that.

`src/qrcodegen.*` is Project Nayuki's QR Code generator (MIT License; notice in the files).

```bash
nix build .#lgx
```
