# Marketing Video Storyboard

Target: 30-45 seconds, clean technical launch clip for a public RC.

## Frame 1

Show title card:

`iOS Wallet Adapter`

Subtitle:

`Native Solana deeplink signing for Swift apps`

## Frame 2

Show the problem:

`Android has MWA. Native iOS apps need a different wallet-signing path.`

Small note:

`No MWA transport claims on iOS.`

## Frame 3

Show the API:

```swift
try await client.connect()
try await client.getCapabilities()
try await client.signMessage(...)
try await client.signTransaction(...)
try await client.signInWithSolana(...)
try await client.disconnect()
```

## Frame 4

Show the implementation layers:

- universal links
- encrypted payloads
- callback routing
- Keychain state
- deterministic logs

## Frame 5

Show supported native iWA providers:

`Phantom · Solflare · Backpack`

Add small text:

`Physical-device smoke pending for stable 0.2.0.`

## Frame 6

Show Jupiter note:

`Jupiter Mobile: WalletConnect/Reown track`

Small text:

`Not listed as a native deeplink provider without public native endpoints.`

## Frame 7

Show final card:

`0.2.0-rc.1 is public`

`github.com/mstevens843/ios-solana-wallet-adapter`

## Capture Rules

- Do not show raw payload logs.
- Do not show real API keys or keyed RPC URLs.
- Do not say "production-validated" until physical-iPhone smoke files are committed.
- Use the generated PNGs from `assets/` as title/end cards.
