# Changelog

## 0.2.0-rc.1 - Public RC

- Added `SolanaWalletAdapterUI`, an app-facing lifecycle layer for SwiftUI/UIKit URL opening and async callback handling.
- Added `WalletAdapterClient` for async connect, signing, disconnect, and `.onOpenURL` bridging.
- Added codable adapter state, provider capability metadata, and a Keychain-backed state store.
- Added deterministic logging for URL builds, callback decoding, and smoke-test troubleshooting.
- Added a SwiftUI demo app source under `Examples/iWADemo`.
- Added pending-request cancellation and redirect matching in `WalletAdapterClient`.
- Added Backpack `wallet_*` connect response key alias support.
- Updated the demo to restore per-wallet Keychain state and cancel stuck wallet bounces.
- Added Jupiter Mobile compatibility research notes and classified it as WalletConnect/Reown rather than native iWA.
- Added `SolanaWalletAdapterWalletConnect`, a dependency-free WalletConnect/Reown Solana request layer for Jupiter Mobile and other non-iWA wallets.
- Added env-backed Solana RPC and Jupiter endpoint configuration helpers.
- Added simulator-only mock wallet testing support.
- Added local release verification and secret-scan scripts.

Stable `0.2.0` remains blocked on physical-iPhone smoke logs for Phantom, Solflare, and Backpack.

## 0.1.0-alpha

- Initial pure Swift Package with wallet-specific deeplink URL builders.
- Added X25519 key agreement, NaCl-box encryption/decryption, Base58 encoding, and callback decoders.
- Added Phantom, Solflare, and Backpack providers.
