# Phantom — research notes (2026-05-03)

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

- Phantom docs describe encryption as "Diffie-Hellman key exchange" without naming the cipher on the index page.
- The community Swift reference [`Tokr-Labs/phantom-connect`](https://github.com/Tokr-Labs/phantom-connect) implements **TweetNaCl `box`** (X25519 + XSalsa20-Poly1305) and `nacl.boxKeyPair`. The Flutter port [`StrawHatXYZ/phantom_connect`](https://github.com/StrawHatXYZ/phantom_connect) does the same.
- TODO: verify by fetching the encryption sub-page directly.

## References

- Brian Friel's "Complete Guide to Phantom Deeplinks": <https://www.brianfriel.xyz/the-complete-guide-to-phantom-deeplinks/>
- Tokr-Labs Swift reference: <https://github.com/Tokr-Labs/phantom-connect>
