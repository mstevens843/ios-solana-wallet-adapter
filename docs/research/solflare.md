# Solflare - research notes (2026-05-03)

Source: <https://docs.solflare.com/solflare/technical/deeplinks>

## Transport

- Universal link: `https://solflare.com/ul/<version>/<method>`
- Same shape as Phantom.

## Methods (from doc index)

- `Connect`
- `Disconnect`
- `SignMessage`
- `SignTransaction`
- `SignAllTransactions`
- `SignAndSendTransaction` (Solflare's docs flag this as the recommended path; the wallet broadcasts directly, which is safer than handing the signed tx back for the dApp to send.)

## Session

`connect` returns a session parameter that must be echoed on every subsequent method call.

## Crypto

- Index page calls out universal-link transport but doesn't name the cipher. Sub-pages (`/connect`, `/signtransaction`) describe `nonce` + `payload` patterns consistent with NaCl box.
- TODO: verify against a per-method sub-page.

## References

- Sample app (React Native): <https://github.com/solflare-wallet/deep-link-sample-app>
- JS SDK (different surface, useful for envelope shape): <https://github.com/solflare-wallet/solflare-sdk>
