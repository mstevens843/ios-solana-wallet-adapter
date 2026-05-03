# ios-solana-wallet-adapter

**iOS Wallet Adapter (iWA): one Swift Package, one wire format, every Solana iOS wallet.**

A unified Swift Package that abstracts the iOS deeplink and universal-link signing protocols of Phantom, Solflare, and Backpack behind a single SwiftUI-friendly API, plus a draft community spec (iWA v0.1) that wallets can adopt the way Android wallets adopted MWA.

```
+---------------------------------------+
|   Your iOS dApp (SwiftUI / UIKit)     |
+------------------+--------------------+
                   |
                   v
+---------------------------------------+
|   SolanaWalletAdapter (one API)       |
|   connect, signMessage, signTx, ...   |
+--+----------+----------+--------------+
   |          |          |
   v          v          v
+--------+ +--------+ +--------+
|Phantom | |Solflare| |Backpack|
|adapter | |adapter | |adapter |
+--------+ +--------+ +--------+
   \\         |         /
    \\        v        /
     +-----------+
     |   Core    |
     |  (Base58, |
     |  NaCl box,|
     |  URLs)    |
     +-----------+
```

---

## Status

Version `0.1.0-alpha`. Phase 1 of 5 shipped on 2026-05-03 (commit `10c1153`).

What works today:

- Construction of `connect` deeplink URLs that match each wallet's published format.
- Per-wallet adapter pattern (`PhantomAdapter`, `SolflareAdapter`, `BackpackAdapter`) all conforming to one `WalletProvider` protocol.
- Vendored Base58 (encode and decode, round-trip tested).
- Apache-2.0 licensed, zero external dependencies, builds clean on Swift 5.9, iOS 16+, macOS 13+.
- 7 unit tests pass: Base58 known vectors, round-trip, invalid input rejection, plus URL-shape assertions for all three wallets.

What is not yet shipped:

- Real X25519 + XSalsa20-Poly1305 (NaCl box) layer. The `NaClBox` and `EphemeralKeypair` types in `Sources/SolanaWalletAdapterCore/` are stubs that trap if called. They land in Phase 2.
- The non-`connect` methods (`signMessage`, `signTransaction`, `signAndSendTransaction`, etc.) are spec'd but not implemented.
- No SwiftUI demo app yet (Phase 3).
- No GitHub Actions CI yet.

The spec is the artifact this repo cares about most in Phase 1. Read it: [`spec/protocol.md`](spec/protocol.md).

---

## Why this exists

Every Solana iOS dApp today picks one of three bad options. It either rolls its own Phantom-only deeplink crypto (and ignores the other two thirds of the wallet market). It falls back to Web3Auth or Privy and gives up on letting users bring their own external wallet. Or it skips iOS entirely.

Solana Mobile published a blog post in 2024 titled "Wallet Signing on iOS" that admits this directly. They acknowledge that the WebSocket-based MWA protocol is incompatible with iOS, that deeplinks cause excessive context switching, that iOS provides no app-chooser when multiple wallets register the same scheme. They propose no unified protocol; they recommend Safari Web Extensions or wallet-as-a-service.

The community has filled exactly half of the gap. [`Tokr-Labs/phantom-connect`](https://github.com/Tokr-Labs/phantom-connect) is a Swift package, but it only speaks to Phantom. [`solflare-wallet/deep-link-sample-app`](https://github.com/solflare-wallet/deep-link-sample-app) is a React Native sample, not a Swift library. [`StrawHatXYZ/phantom_connect`](https://github.com/StrawHatXYZ/phantom_connect) is Flutter. No package, in any language, abstracts the three published wallet protocols behind one API.

That is what this package is. The protocols themselves are nearly identical across the three wallets (universal links of shape `https://<host>/ul/v1/<method>`, X25519 ECDH, base58 wire encoding, the same `nonce` plus `payload` shape). The fragmentation is mostly accidental, the result of three teams independently building the same primitive without coordinating. iWA proposes the spec they would have written together.

---

## What it is, and what it isn't

**iWA is** a Swift Package, plus a written spec at [`spec/protocol.md`](spec/protocol.md), targeting iOS 16+ and macOS 13+. It uses universal links and custom URL schemes for transport. It uses NaCl box (X25519 + XSalsa20-Poly1305) for end-to-end encryption between the dApp and the wallet. Sessions are ephemeral (one X25519 keypair per dApp instance) and cluster-bound.

**iWA is not** Mobile Wallet Adapter (MWA). MWA is Android-only by design: it relies on Android Intents and a localhost WebSocket, neither of which iOS exposes the same way. Anyone calling iWA "MWA on iOS" is technically wrong, and the public framing of this repo will never use that phrase. Use "iOS Wallet Adapter" or "iWA."

**iWA is not** a wallet-as-a-service or embedded-wallet SDK. Web3Auth, Privy, Magic, and Dynamic all serve a different model where the dApp creates and holds the user's wallet. iWA is the opposite shape: the user already has Phantom or Solflare or Backpack installed, and the dApp routes signing through that wallet without ever seeing the private key.

**iWA is not** a Solana RPC client. The package signs payloads and returns the signed bytes (or, for `signAndSendTransaction`, the transaction id). Constructing transactions, broadcasting them, and confirming them are the dApp's job. Use the Solana JSON-RPC client of your choice.

---

## Features

- One Swift API for three wallets (Phantom, Solflare, Backpack), with a fourth (Glow) under research.
- Zero external Swift dependencies. Apple's CryptoKit covers Curve25519, Base58 is vendored.
- NaCl box wire format (X25519 ECDH + XSalsa20-Poly1305), the same primitive every published wallet protocol uses.
- Per-wallet products (`SolanaWalletAdapterPhantom`, `SolanaWalletAdapterSolflare`, `SolanaWalletAdapterBackpack`) so consumers pull only the wallet they need.
- Strict typing on the public surface (`WalletProvider`, `ConnectRequest`, `Session`, `Cluster`, `SigningRequest`, `WalletAdapterError`).
- Apache-2.0 licensed.

---

## Supported wallets

| Wallet | Universal-link host | Custom scheme | Status |
|--------|---------------------|---------------|--------|
| Phantom | `phantom.app` | `phantom` | shipped (connect URL only in v0.1) |
| Solflare | `solflare.com` | `solflare` | shipped (connect URL only in v0.1) |
| Backpack | `backpack.app` | `backpack` | shipped (connect URL only in v0.1) |
| Glow | TBD | TBD | candidate, pending verification (see [`docs/research/glow.md`](docs/research/glow.md)) |

Glow is held out of v0.1 because Solana Mobile's iOS blog characterizes Glow's signing model as a Safari Web Extension rather than a deeplink wallet. Until we confirm a published deeplink path, Glow is not in `Package.swift` and not in marketing copy.

---

## Install

Swift Package Manager. In Xcode:

```
File > Add Package Dependencies > paste:
https://github.com/mstevens843/ios-solana-wallet-adapter
```

Or in `Package.swift`:

```swift
.package(url: "https://github.com/mstevens843/ios-solana-wallet-adapter", from: "0.1.0"),
```

Then list the products you want as target dependencies. The four products are:

- `SolanaWalletAdapter` (the umbrella module, types and protocol)
- `SolanaWalletAdapterPhantom`
- `SolanaWalletAdapterSolflare`
- `SolanaWalletAdapterBackpack`

Pick one wallet adapter, or all three, depending on which wallets your app supports.

---

## Quickstart (Phase 1 surface)

The v0.1 alpha can build connect deeplinks for any of the three wallets. The actual signing methods land in v0.2 once the NaCl box layer is wired.

```swift
import SwiftUI
import SolanaWalletAdapter
import SolanaWalletAdapterPhantom

struct ContentView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button("Connect Phantom") {
            connectPhantom()
        }
        .onOpenURL { incoming in
            // The wallet bounces the user back here with the connect response
            // as query parameters. Phase 2 wires the response decoding.
            print("got callback:", incoming)
        }
    }

    private func connectPhantom() {
        let phantom = PhantomAdapter()

        // In Phase 1 the dapp encryption pubkey is a placeholder. Phase 2
        // generates a real X25519 ephemeral keypair via CryptoKit.
        let request = ConnectRequest(
            dappEncryptionPublicKey: "YourBase58X25519PublicKeyHere",
            redirectLink: URL(string: "myapp://wallet/callback")!,
            appURL: URL(string: "https://example.com")!,
            cluster: .devnet
        )

        do {
            let url = try phantom.connectURL(request: request)
            openURL(url)
        } catch {
            print("failed to build connect URL:", error)
        }
    }
}
```

The exact same call shape works for Solflare and Backpack, swap the adapter:

```swift
import SolanaWalletAdapterSolflare
import SolanaWalletAdapterBackpack

let solflare = SolflareAdapter()
let backpack = BackpackAdapter()

let solflareURL = try solflare.connectURL(request: request)
let backpackURL = try backpack.connectURL(request: request)
```

The user picks which wallet via your UI. Open the resulting URL with `UIApplication.shared.open(_:)` (UIKit) or the `@Environment(\.openURL)` action (SwiftUI).

---

## Quickstart (target v1.0 API, preview only)

This is what the full API will look like once Phase 2 lands. **Not yet shipped.** Subject to change. Included so you can see where this is going.

```swift
import SolanaWalletAdapter
import SolanaWalletAdapterPhantom

let adapter = WalletAdapter(provider: PhantomAdapter())

// 1. Connect. Generates an ephemeral X25519 keypair under the hood.
let session = try await adapter.connect(
    appURL: URL(string: "https://example.com")!,
    redirectLink: URL(string: "myapp://wallet/callback")!,
    cluster: .mainnetBeta
)
print("connected:", session.userPublicKey)

// 2. Sign a message.
let signature = try await adapter.signMessage(
    Data("Sign in to Example".utf8),
    session: session
)

// 3. Sign a transaction (without broadcasting).
let signedTxBytes = try await adapter.signTransaction(
    transactionBytes,
    session: session
)

// 4. Sign and broadcast.
let txid = try await adapter.signAndSendTransaction(
    transactionBytes,
    session: session,
    sendOptions: SendOptions(skipPreflight: false)
)
```

Errors surface through `WalletAdapterError`:

```swift
do {
    let session = try await adapter.connect(...)
} catch WalletAdapterError.userRejected {
    // user dismissed the approval sheet inside the wallet
} catch WalletAdapterError.invalidSession {
    // wallet forgot the session, reconnect
} catch WalletAdapterError.walletUnreachable {
    // the OS could not open any handler for the universal link
} catch {
    // other, log it
}
```

---

## Protocol summary

| Method | Purpose |
|--------|---------|
| `connect` | Establish a session: derive shared X25519 secret, get user's public key, get session token. |
| `disconnect` | Best-effort: tell the wallet to forget the session. |
| `signMessage` | Produce a 64-byte ed25519 signature over an arbitrary message. |
| `signTransaction` | Sign a serialized Solana transaction without broadcasting. |
| `signAllTransactions` | Sign a batch of transactions in one approval. |
| `signAndSendTransaction` | Sign and broadcast in one approval, return the txid. |

Read [`spec/protocol.md`](spec/protocol.md) for the wire format, encrypted payload shapes, query parameters, and error code table.

---

## Security model

**Ephemeral keys.** The dApp generates a fresh X25519 keypair on every session. The private half never leaves the device. The public half goes on the wire as `dapp_encryption_public_key`. After `disconnect` (or app termination), the keypair is discarded.

**End-to-end encryption.** Once `connect` exchanges public keys, every subsequent payload is encrypted with NaCl box (XSalsa20-Poly1305 authenticated encryption) using the shared secret. Anyone who intercepts a deeplink URL learns nothing useful: the ciphertext is opaque, the nonce is a one-time value, the only plaintext fields are routing metadata.

**No key custody.** The user's Solana private key lives in their wallet app (Phantom, Solflare, Backpack) and is never exposed. The dApp gets signatures, never seeds.

**Cluster binding.** Sessions are bound to a Solana cluster (`mainnet-beta`, `devnet`, `testnet`). An adapter MUST reject a sign request whose cluster does not match the session. This prevents a devnet-debug session from accidentally signing a mainnet transaction.

**Wallet authentication.** Each wallet's `apple-app-site-association` file scopes the universal link to that wallet's host (`phantom.app`, `solflare.com`, `backpack.app`). A malicious app cannot intercept the redirect for another wallet's domain. Custom URL schemes are weaker (any app can register them); consumers SHOULD prefer the universal link path.

---

## The app-chooser problem

iOS does not surface a system-level chooser when multiple wallets register the same custom URL scheme. If two wallets both register `solana-wallet://`, the OS silently routes to whichever was installed first. This is not a bug iWA can fix; it is an iOS platform behavior.

iWA's response: do not use a shared scheme. Each wallet adapter targets that wallet's specific universal-link host. The dApp picks which wallet at the UI level (a wallet picker screen, or a "connect with Phantom" button), and the adapter for that wallet is what builds the URL.

A consumer who wants a generic `connect-any-wallet` flow should iterate the installed adapters, present the user with a chooser, and dispatch to the chosen adapter. iWA does not ship a chooser UI in v0.1; build your own.

---

## Roadmap

| Phase | Scope | Status |
|-------|-------|--------|
| 1 | Scaffold: SwiftPM project, `WalletProvider` protocol, three adapters with `connect` URL building, vendored Base58, draft `spec/protocol.md`, captured research notes. | shipped 2026-05-03 |
| 2 | Real NaCl box layer (X25519 via CryptoKit, vendored XSalsa20-Poly1305 or TweetNaCl-Swift port), `signMessage` / `signTransaction` / `signAndSendTransaction` wired, async/await surface, first end-to-end smoke against Phantom on a real device. | next |
| 3 | SwiftUI demo app showing the full flow, full docs site, GitHub Actions CI, version 1.0 API freeze. | after Phase 2 |
| 4 | Wallet-team outreach to standardize the spec, with the goal of getting at least one wallet team to formally bless iWA v1.0. Confirm or reject Glow as a v1.x wallet. | after Phase 3 |
| 5 | Cross-platform bridges: React Native package, Flutter plugin, Cocos Creator binding, all wrapping the same iWA wire format so cross-platform dApps target one API on both Android (MWA) and iOS (iWA). | after Phase 4 |

The target ship for the iWA spec freeze is one of the goals of the Solana SDK Top-3 commitment for May 2026.

---

## Building

The package builds clean on a stock Swift 5.9 toolchain. The CommandLineTools-only setup that ships with macOS does not include XCTest, so running tests requires either a full Xcode install or a `DEVELOPER_DIR` override:

```sh
# Build (works without Xcode):
swift build

# Test (needs Xcode for XCTest):
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

To make the override permanent:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
swift test
```

To build for iOS specifically (not the default macOS target):

```sh
xcodebuild -scheme SolanaWalletAdapter -destination 'platform=iOS Simulator,name=iPhone 15' build
```

---

## Project layout

```
ios-solana-wallet-adapter/
├── Package.swift                              SwiftPM manifest, four library products
├── README.md                                  this file
├── LICENSE                                    Apache-2.0
├── spec/
│   └── protocol.md                            iWA v0.1 draft spec
├── docs/
│   ├── README.md                              docs index
│   └── research/                              captured per-wallet findings
│       ├── phantom.md
│       ├── solflare.md
│       ├── backpack.md
│       └── glow.md
├── Sources/
│   ├── SolanaWalletAdapter/                   public umbrella module
│   │   ├── WalletProvider.swift               the protocol every adapter conforms to
│   │   ├── WalletAdapter.swift                entry-point class
│   │   ├── ConnectRequest                     (defined inside WalletProvider.swift)
│   │   ├── Session.swift                      session state after connect
│   │   ├── Cluster.swift                      mainnet-beta / devnet / testnet
│   │   ├── SigningRequest.swift               request variants
│   │   └── Errors.swift                       WalletAdapterError enum
│   ├── SolanaWalletAdapterCore/               internal building blocks
│   │   ├── Base58.swift                       vendored, round-trip tested
│   │   ├── DeeplinkURL.swift                  URL builder for the shared deeplink shape
│   │   ├── NaClBox.swift                      X25519 + XSalsa20-Poly1305 (Phase 2)
│   │   └── Keypair.swift                      X25519 ephemeral keypair (Phase 2)
│   ├── SolanaWalletAdapterPhantom/
│   │   └── PhantomAdapter.swift
│   ├── SolanaWalletAdapterSolflare/
│   │   └── SolflareAdapter.swift
│   └── SolanaWalletAdapterBackpack/
│       └── BackpackAdapter.swift
└── Tests/
    └── SolanaWalletAdapterTests/
        ├── Base58Tests.swift
        └── DeeplinkURLTests.swift
```

---

## Prior art and references

The wallets, in alphabetical order:

- **Backpack** deeplinks: <https://docs.backpack.app/deeplinks/provider-methods/connect>
- **Phantom** deeplinks: <https://docs.phantom.com/phantom-deeplinks/deeplinks-ios-and-android>
- **Solflare** deeplinks: <https://docs.solflare.com/solflare/technical/deeplinks>

Solana Mobile's own writeup of the iOS situation:

- "Wallet Signing on iOS" (2024): <https://docs.solanamobile.com/blog/ios-wallet-signing>

Existing community implementations (none unify the three wallets):

- `Tokr-Labs/phantom-connect` (Swift, Phantom-only): <https://github.com/Tokr-Labs/phantom-connect>
- `solflare-wallet/deep-link-sample-app` (React Native): <https://github.com/solflare-wallet/deep-link-sample-app>
- `solflare-wallet/solflare-sdk` (TypeScript): <https://github.com/solflare-wallet/solflare-sdk>
- `StrawHatXYZ/phantom_connect` (Flutter): <https://github.com/StrawHatXYZ/phantom_connect>

Brian Friel's writeup, useful background reading:

- "The Complete Guide to Phantom Deeplinks": <https://www.brianfriel.xyz/the-complete-guide-to-phantom-deeplinks/>

---

## Contributing

The spec is the contract. PRs that change behavior should also update [`spec/protocol.md`](spec/protocol.md), and changes that affect the wire format require a version bump (currently `v1`, would become `v2`).

Adding a fourth wallet:

1. Open an issue with a link to the wallet's published deeplink documentation.
2. Add a research note at `docs/research/<wallet>.md` capturing the wallet's universal-link host, its `connect` query parameters, its response shape, and any deviations from iWA v0.1.
3. Add a target at `Sources/SolanaWalletAdapter<Wallet>/<Wallet>Adapter.swift` conforming to `WalletProvider`.
4. Add a library product in `Package.swift`.
5. Add a URL-shape test in `Tests/SolanaWalletAdapterTests/DeeplinkURLTests.swift`.

Issues for spec changes are encouraged. The whole point of iWA is to be a community spec wallets can adopt, not a one-author standard. Wallet teams reading this: please open issues, or reach out directly.

---

## FAQ

**Is this MWA on iOS?**
No. MWA (Mobile Wallet Adapter) is Android-only by protocol: it uses Android Intents to launch a wallet app and a localhost WebSocket for the encrypted JSON-RPC session. iOS exposes neither in a way that lets MWA work. iWA is a different protocol class, request-response over universal links, no persistent socket.

**Why is Glow not supported?**
Solana Mobile's iOS blog characterizes Glow's signing model as a Safari Web Extension. We have not yet confirmed whether Glow also publishes a deeplink protocol that conforms to the iWA shape. Until that is verified (see [`docs/research/glow.md`](docs/research/glow.md)), Glow is held out of v0.1.

**Why not WalletConnect?**
WalletConnect's Solana support is patchy. Several wallets implement it incompletely or not at all, and the Solana namespace in the WalletConnect spec has historically lagged the EVM namespace. iWA targets the wallets that publish their own Solana-native deeplink specs, where the protocol is already settled and the implementations work in production.

**Why not React Native?**
React Native is on the roadmap (Phase 5), as part of a broader cross-platform bridge layer. The Phase 1 + Phase 2 work has to land first so that the Swift package is the authoritative reference implementation. A React Native wrapper around an unfinished Swift package is not useful.

**Can I use this on macOS?**
Yes, but iOS is the primary target. The package builds on macOS 13+ and the protocol works in principle (universal links exist on macOS too), but no macOS wallet app implements iWA today. Most users on macOS will use the Wallet Standard browser path instead.

**Can my agent or background process use this?**
Not in iOS. iOS suspends backgrounded apps and disables their network communication. A signing flow that takes more than a few seconds (for example, a user reading a transaction summary in the wallet) requires the user to come back to the dApp through the redirect URL. Headless flows are not supported by the platform itself; iWA cannot work around this.

**Is this an Anchor or Solana-program SDK?**
No. iWA signs payloads. It does not construct transactions, broadcast them, or read on-chain state. Use any Solana JSON-RPC client (for example, `solana-swift`) to construct transactions, then hand them to iWA for signing.

---

## License

Apache-2.0. See [`LICENSE`](LICENSE).
