# Phantom - research notes (2026-05-03)

Source: <https://docs.phantom.com/phantom-deeplinks/deeplinks-ios-and-android>

## Transport

- Universal link: `https://phantom.app/ul/<version>/<method>`
- Custom scheme fallback: `phantom://<version>/<method>`
- `<version>` confirmed as `v1` in current docs.

## Methods enumerated

`Connect`, `Disconnect`, `SignAndSendTransaction`, `SignAllTransactions`, `SignTransaction`, `SignMessage`.

## Required parameters (every request after connect)

- `dapp_encryption_public_key`
- `redirect_link`
- (and method-specific params)

## Crypto

- Phantom's encryption page documents `dapp_encryption_public_key`, a fresh x25519 keypair for each connect session, and a wallet-returned `phantom_encryption_public_key`.
- The same page points implementers to TweetNaCl resources for encryption/decryption.
- The Swift implementation uses CryptoKit X25519 key agreement and a TweetNaCl-compatible NaCl box layer.

## References

- Brian Friel's "Complete Guide to Phantom Deeplinks": <https://www.brianfriel.xyz/the-complete-guide-to-phantom-deeplinks/>
- Encryption: <https://docs.phantom.com/phantom-deeplinks/encryption>
- Tokr-Labs Swift reference: <https://github.com/Tokr-Labs/phantom-connect>
