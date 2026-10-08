# logos-zcash-wallet-ui

`zcash_wallet_ui`: the Zcash wallet app for Logos Basecamp, built on the Logos Design System.
It talks only to `zcash_wallet_backend`.

- **Home:** the shielded balance (Ironwood and Sapling), transparent funds per address with a
  Shield action each, and Orchard funds that need moving to Ironwood.
- **Send:** the recipient is checked as you type. The review shows the fee, the pools spent
  and any amount that becomes public. The password approves it.
- **Receive:** a shielded Unified Address, and a transparent address that is replaced once
  it is paid, each with a QR code.
- **History**, and **settings**: wallets, password, recovery phrase, viewing key, servers
  and proxy.

Passwords, phrases and keys cross the `.rep` only as SLOT arguments and return values, never
as PROPs. CI checks that.

`src/qrcodegen.*` is Project Nayuki's QR Code generator (MIT License; notice in the files).

```bash
nix build .#lgx
```
