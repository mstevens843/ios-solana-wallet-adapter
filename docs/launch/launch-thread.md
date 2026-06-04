# Launch Thread Draft

## Post 1

I built `ios-solana-wallet-adapter`: a Swift Package for native iOS Solana apps that need external wallet signing through Phantom, Solflare, and Backpack deeplinks.

Public RC: `0.2.0-rc.1`.

## Post 2

This is not "Mobile Wallet Adapter for iOS."

MWA is Android-only by protocol. iOS needs a different request/response model because apps cannot keep the same persistent background channel alive.

## Post 3

iWA gives native Swift apps one API for:

- connect
- get capabilities
- sign message
- sign transaction
- sign and send transaction
- SIWS
- disconnect

Under the hood it maps to wallet-specific iOS universal links and encrypted callbacks.

## Post 4

The hard part is not opening a URL.

The hard parts are X25519 key agreement, NaCl-box payload encryption, nonce handling, Base58 wire values, callback decoding, session restore, lifecycle routing, and failure logging.

That is what the package owns.

## Post 5

The RC includes:

- Phantom, Solflare, Backpack provider targets
- SwiftUI/UIKit async client
- Keychain-backed session state
- deterministic redacted logging
- SIWS message construction
- WalletConnect/Reown Solana request helpers
- simulator mock wallet for local testing

## Post 6

Jupiter Mobile is tracked separately through WalletConnect/Reown because public Jupiter docs point there, not to Phantom-style native deeplink signing.

The package does not guess unsupported wallet protocols.

## Post 7

Current status: local package tests and demo builds are green. The stable `0.2.0` tag waits for physical-iPhone smoke logs against installed wallet apps.

RC is public for review, integration feedback, and wallet-team validation.

## Post 8

Repo:

`https://github.com/mstevens843/ios-solana-wallet-adapter`

Install:

```swift
.package(url: "https://github.com/mstevens843/ios-solana-wallet-adapter", exact: "0.2.0-rc.1")
```
