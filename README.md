# ios-solana-wallet-adapter

**iOS Wallet Adapter (iWA).** A Swift Package that abstracts the iOS deeplink / universal-link signing protocols of Phantom, Solflare, and Backpack behind one SwiftUI-friendly API, plus a draft community spec — `iWA v0.1` — that wallets can adopt.

1. **Public umbrella module** — `SolanaWalletAdapter` exposes the protocol surface (request types, error codes, session shape).
2. **Per-wallet adapters** — `SolanaWalletAdapterPhantom`, `SolanaWalletAdapterSolflare`, `SolanaWalletAdapterBackpack` each conform to one `WalletProvider` protocol so consumers can target one or all from one API.
3. **Internal core** — `SolanaWalletAdapterCore` carries Base58, deeplink URL building, and the X25519 + XSalsa20-Poly1305 (NaCl box) layer the wallets share.

Status: **early scaffolding**. Connect-URL building works for all three wallets; the encryption layer ships in Phase 2. See `spec/protocol.md` for the in-progress protocol design and `docs/research/` for per-wallet findings.

> This is **not** Mobile Wallet Adapter (MWA). MWA is Android-only by protocol (Android Intents + localhost WebSocket). iWA is a different protocol class — universal-link based, request/response, no persistent session.

## Why

Every Solana iOS app today either hand-rolls Phantom-only deeplink crypto, leans on Web3Auth's embedded-only path, or skips iOS entirely. Solana Mobile's own blog admits no native MWA exists for iOS and recommends scattered per-wallet deeplinks with no unified spec. The community Swift reference (`Tokr-Labs/phantom-connect`) is Phantom-only; Solflare's sample is React Native; Backpack ships docs but no Swift package.

iWA v0.1 unifies the three published deeplink protocols behind one Swift Package and one written spec. Wallet teams can adopt the spec; dApps target one API; the iOS-wallet-fragmentation tax goes away.

## Repo layout

```
Package.swift
spec/
  protocol.md                # iWA v0.1 draft
docs/
  README.md
  research/                  # per-wallet findings (Phantom, Solflare, Backpack, Glow)
Sources/
  SolanaWalletAdapter/        # public umbrella: types, errors, session
  SolanaWalletAdapterCore/    # base58, NaCl box layer, deeplink URL builder
  SolanaWalletAdapterPhantom/ # Phantom adapter
  SolanaWalletAdapterSolflare/# Solflare adapter
  SolanaWalletAdapterBackpack/# Backpack adapter
Tests/
  SolanaWalletAdapterTests/   # URL-shape and Base58 unit tests
```

## Quick build

```sh
swift build
swift test
```

Both should pass on Phase 1's scaffold. Phase 2 wires the live encryption layer against a real device.

## License

Apache-2.0.
