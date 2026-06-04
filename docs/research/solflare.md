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

- Solflare's encryption page documents `dapp_encryption_public_key`, a fresh x25519 keypair for each connect session, and a wallet-returned `solflare_encryption_public_key`.
- The same page points implementers to TweetNaCl resources for encryption/decryption.
- The Swift implementation uses CryptoKit X25519 key agreement and a TweetNaCl-compatible NaCl box layer.

## References

- Sample app (React Native): <https://github.com/solflare-wallet/deep-link-sample-app>
- JS SDK (different surface, useful for envelope shape): <https://github.com/solflare-wallet/solflare-sdk>
- Encryption: <https://docs.solflare.com/solflare/technical/deeplinks/encryption>
