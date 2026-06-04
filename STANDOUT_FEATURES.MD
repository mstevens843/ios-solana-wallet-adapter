# Standout Features

`ios-solana-wallet-adapter` is an iOS-native Solana wallet adapter for external wallet signing through universal links and wallet-specific deeplinks. It gives native Swift apps one API for Phantom, Solflare, and Backpack instead of forcing every app to hand-roll wallet-specific URL construction, encryption, callback parsing, and app lifecycle routing.

This is not Mobile Wallet Adapter for iOS. Mobile Wallet Adapter is Android-only by protocol because it depends on Android intents and a persistent local communication channel that iOS background execution does not support. This package fills the adjacent iOS gap with a request/response URL-bounce model that matches what major Solana iOS wallets already document.

## The Gap

Native iOS Solana apps do not have an official equivalent to Android Mobile Wallet Adapter.

Existing public options split across different integration classes:

| Surface | What exists | Why it is not this |
| --- | --- | --- |
| Android MWA | Official Solana Mobile SDK over Android intents/local session transport | Not available on iOS by protocol and OS constraints |
| Web Wallet Adapter / Wallet Standard | Standard browser-injected wallet interface for web apps | Does not solve native Swift app-to-wallet signing |
| WalletConnect / Reown | Remote pairing through relay, QR/deeplink, project IDs | Different protocol and UX model than local wallet-specific iOS deeplinks |
| Embedded wallet providers | Privy, Web3Auth, Magic, Turnkey, etc. | Different custody model; the dApp/provider manages or provisions wallets |
| Wallet-specific deeplinks | Phantom, Solflare, Backpack each document their own endpoints | Useful but fragmented; each app must implement each wallet directly |
| Phantom-only Swift wrappers | Community packages such as `phantom-connect` | Single-wallet scope, not a multi-wallet iOS adapter/spec layer |

The durable opportunity is that iOS cannot simply receive Android MWA later. Native iOS apps need a separate, honest integration class.

## What This Implements

The package turns the common shape across major Solana iOS wallet deeplink docs into one Swift Package.

- `WalletAdapter`: high-level coordinator for connect, sign message, sign transaction, sign all transactions, sign and send transaction, and disconnect.
- Per-wallet providers: `SolanaWalletAdapterPhantom`, `SolanaWalletAdapterSolflare`, and `SolanaWalletAdapterBackpack`.
- Core crypto and wire layer: X25519 ephemeral key agreement, TweetNaCl-compatible NaCl box encryption/decryption, Base58 wire encoding, nonce handling, and encrypted response decoding.
- `SolanaWalletAdapterUI`: async SwiftUI/UIKit-friendly lifecycle wrapper for URL opening, pending request tracking, `.onOpenURL` routing, cancellation, and persisted adapter state.
- MWA-style app semantics without MWA transport claims: `getCapabilities`, `signInWithSolana`, `authorize`, `deauthorize`, `signMessages`, `signTransactions`, and `signAndSendTransactions` map onto native iOS deeplink behavior where supported.
- SIWS v1 message construction with nonce, statement, and chain validation that signs through the existing native `signMessage` deeplink path.
- A WalletConnect/Reown companion client with Solana account methods, capability reporting, and typed request/response helpers for Jupiter-style integrations.
- Env-backed Solana RPC and Jupiter endpoint configuration with deterministic precedence and redacted log metadata.
- A simulator-only mock wallet that exercises the same URL, encryption, callback, and async routing path without requiring App Store wallet apps.
- Deterministic logging for real-device smoke testing, with redacted default logs and explicit unsafe raw-payload mode for local debugging only.
- A draft `iWA v0.1` protocol document that defines the shared iOS request/response shape without pretending it is MWA.

## How It Stands Out

### 1. It Standardizes a Real Wallet Pattern Already in the Market

Phantom, Solflare, and Backpack all expose native deeplink/provider-method flows with the same basic shape:

- `https://<wallet-host>/ul/v1/<method>`
- `dapp_encryption_public_key`
- encrypted `payload`
- `nonce`
- `redirect_link`
- encrypted callback data
- session token carried after connect

The adapter does not ask wallets to adopt a brand-new architecture before it is useful. It packages the overlapping wallet behavior developers already need to integrate.

### 2. It Solves the Native Swift App Problem

Solana web apps have Wallet Adapter and Wallet Standard. Android apps have MWA. Native iOS apps currently have wallet-specific deeplinks, WalletConnect/Reown, embedded wallets, or Safari extension flows.

This project is specifically for native iOS apps that want the user's existing self-custody wallet app to show approval UI and keep private keys out of the dApp.

### 3. It Is Multi-Wallet From the Start

The first-class provider set is not Phantom-only:

- Phantom: implemented; `signAndSendTransaction` is marked deprecated upstream, so apps should prefer signing and broadcasting themselves for Phantom.
- Solflare: implemented.
- Backpack: implemented, including documented response-key alias handling such as `wallet_encryption_public_key` and `wallet_*`.

That makes the project closer to "Solana Wallet Adapter for native iOS" than to a wallet-specific helper.

### 4. It Handles the Hard Parts Developers Usually Get Wrong

The package owns the brittle protocol details:

- X25519 ephemeral key generation.
- Shared-secret based encrypted request/response handling.
- NaCl box / XSalsa20-Poly1305 payload sealing and opening.
- Base58 encoding for keys, nonces, payloads, transactions, messages, and signatures.
- Wallet callback decoding for connect and all signing responses.
- Wallet error mapping into Swift errors.
- Session storage/export/restore.
- Redirect matching and pending async request cancellation.

The app code stays focused on "connect" and "sign" instead of URL query construction and callback plumbing.

### 5. It Directly Addresses the iOS Deeplink Lifecycle Problem

One of the known pain points with iOS deeplinks is that the callback enters through app lifecycle hooks, far away from the button or async operation that opened the wallet.

`WalletAdapterClient` bridges that gap:

- starts an async operation,
- opens the wallet URL through SwiftUI or UIKit,
- stores the pending request,
- routes the next matching callback,
- resumes the correct continuation,
- allows cancellation if the wallet opens but never redirects back.

This is the app-facing layer that turns a fragile URL-bounce into something Swift developers can use cleanly.

### 6. It Is Honest About Boundaries

The repo avoids overclaiming:

- It does not call itself MWA for iOS.
- It does not list Glow as supported until a compatible native deeplink spec is verified.
- It does not list Jupiter Mobile as supported while public docs point to WalletConnect/Reown rather than native iWA-style deeplinks.
- It keeps real-device smoke logs as the release gate before claiming wallet flows are production-validated.

That matters because wallet infrastructure loses credibility quickly when compatibility is guessed.

## Positioning

Use this phrasing:

> iOS Wallet Adapter (iWA) is a Swift Package that gives native iOS Solana apps one URL/callback API for external wallet signing with Phantom, Solflare, and Backpack.

Use this shorter phrasing:

> Solana Wallet Adapter for native iOS deeplinks.

Avoid this phrasing:

> Mobile Wallet Adapter for iOS.

That is technically incorrect. MWA is Android-only; this project is a separate iOS-native request/response adapter over universal links and wallet-specific deeplinks.

## Comparison To Current Public Research

### Solana Mobile MWA

Solana Mobile's docs position MWA as the standard mobile wallet protocol, but its platform support excludes iOS. Their iOS signing research explains why the persistent transport used by Android MWA is incompatible with iOS app backgrounding.

This package accepts that constraint and implements a different iOS-native model.

References:

- https://docs.solanamobile.com/developers/mobile-wallet-adapter
- https://docs.solanamobile.com/blog/ios-wallet-signing

### Phantom

Phantom documents native mobile deeplinks for connect, sign message, sign transaction, sign all transactions, disconnect, and a deprecated sign-and-send flow. Phantom also documents X25519-style shared-secret encrypted deeplinks and a wallet-specific connect response key.

This package implements Phantom as one provider behind the same Swift API used for other wallets.

References:

- https://docs.phantom.com/phantom-deeplinks/deeplinks-ios-and-android
- https://docs.phantom.com/phantom-deeplinks/encryption
- https://docs.phantom.com/phantom-deeplinks/provider-methods/connect
- https://docs.phantom.com/phantom-deeplinks/provider-methods/signandsendtransaction

### Solflare

Solflare documents native iOS/Android deeplinks with the same provider-method URL shape, encrypted payload pattern, session token, and sign/sign-and-send methods.

This package treats Solflare as a first-class provider rather than a separate integration project.

References:

- https://docs.solflare.com/solflare/technical/deeplinks
- https://docs.solflare.com/solflare/technical/deeplinks/encryption
- https://docs.solflare.com/solflare/technical/deeplinks/provider-methods/connect
- https://docs.solflare.com/solflare/technical/deeplinks/provider-methods/signandsendtransaction

### Backpack

Backpack documents the same native deeplink method family and encrypted request/response model, with wallet-specific naming around the wallet encryption public key.

This package supports Backpack as a first-class provider and intentionally handles documented response-key alias variation.

References:

- https://docs.backpack.app/
- https://docs.backpack.app/deeplinks/provider-methods/connect
- https://docs.backpack.app/deeplinks/encryption
- https://docs.backpack.app/deeplinks/provider-methods/signtransaction

### Jupiter Mobile

Jupiter Mobile is strategically interesting, but its current public developer docs point to a WalletConnect/Reown QR-code adapter path through `@jup-ag/jup-mobile-adapter`, not a native `/ul/v1/connect` URL-bounce provider spec.

Until Jupiter confirms native iOS deeplink signing endpoints compatible with this shape, Jupiter belongs in research, not in `WalletProviderRegistry`.

References:

- https://docs.jup.ag/user-docs/manage/mobile
- https://developers.jup.ag/docs/tool-kits/wallet-kit/jupiter-mobile-adapter

### Glow

Glow is relevant to iOS wallet signing, but public docs emphasize a JavaScript/Safari extension integration model. Safari Web Extensions are useful, but they are not the same as native app-to-wallet URL-bounce signing.

Until Glow publishes or confirms compatible native deeplink provider methods, Glow should remain research-only.

References:

- https://docs.glow.app/docs/getting-started
- https://docs.solanamobile.com/blog/ios-wallet-signing

## Credible Claims

Strong claims:

- First-class Swift package for native iOS Solana wallet deeplink signing across Phantom, Solflare, and Backpack.
- Unifies wallet-specific deeplink signing behind one Swift API.
- Implements real encrypted request/response handling instead of just URL string builders.
- Separates pure protocol code from optional SwiftUI/UIKit lifecycle plumbing.
- Honest iOS counterpart to the Android MWA problem, without misusing the MWA name.

Claims to avoid until smoke testing is complete:

- Production-validated against every supported wallet.
- Fully standardized by wallet teams.
- Drop-in replacement for Android MWA.
- Support for Glow or Jupiter Mobile.
- Automatic installed-wallet discovery.

## Current Release Gates

The public RC can ship as `0.2.0-rc.1` after local verification, secret scanning, docs, and simulator mock validation pass.

Before a stable `0.2.0` release, capture physical-iPhone smoke logs and screenshots for:

- Phantom connect, sign message, disconnect.
- Solflare connect, sign message, disconnect.
- Backpack connect, sign message, disconnect.

The code and tests are locally complete for the adapter layer, but installed-wallet behavior must be verified on physical devices before making stable production compatibility claims.

## Important Wording Correction

Do not describe the implemented crypto as AES-GCM.

The current code and wallet docs align around:

- X25519 / Curve25519 key agreement.
- NaCl box compatible encryption.
- XSalsa20-Poly1305 authenticated encryption.
- Base58 wire encoding.

Using precise crypto language is part of the credibility of the project.
