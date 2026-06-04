# ios-solana-wallet-adapter

**iOS Wallet Adapter (iWA): one Swift Package for Phantom, Solflare, and Backpack deeplink signing.**

`ios-solana-wallet-adapter` gives native iOS Solana apps a single URL/callback API for external wallet signing. The app keeps no user private keys. The wallet shows the approval screen. The adapter builds the wallet URL, encrypts request payloads, and decodes the callback.

This is not Mobile Wallet Adapter. MWA is Android-only by protocol. iWA is the iOS-native request/response shape built on universal links and wallet-specific deeplinks.

## Status

Version `0.2.0-rc.1` public release candidate. Local build/test coverage is green; physical-iPhone wallet smoke logs are still required before a stable production claim.

Shipped in this repo:

- `WalletAdapter`, the high-level coordinator for connect, sign, sign and send, and disconnect URLs.
- Per-wallet providers for Phantom, Solflare, and Backpack.
- Real X25519 ephemeral key generation through CryptoKit.
- TweetNaCl-compatible NaCl box encryption and decryption (XSalsa20-Poly1305), vendored with license notice.
- Base58 wire encoding for public keys, nonces, ciphertexts, messages, transactions, and signatures.
- Callback decoding for connect, sign message, sign transaction, sign all transactions, and sign and send.
- Opt-in deterministic logging for real-device smoke testing.
- `SolanaWalletAdapterUI`, an async SwiftUI/UIKit-friendly lifecycle layer.
- MWA-style app method semantics over the native iOS deeplink transport: `getCapabilities`, `signInWithSolana`, and strict compatibility aliases such as `authorize`, `deauthorize`, `signMessages`, `signTransactions`, and `signAndSendTransactions`.
- SIWS v1 message construction with nonce, statement, and chain validation, signed through the existing native `signMessage` deeplink flow.
- Codable adapter state and a Keychain-backed state store.
- `SolanaWalletAdapterWalletConnect`, a dependency-free Solana WalletConnect/Reown request layer.
- `WalletAdapterServiceConfiguration` for redacted Solana RPC and Jupiter endpoint configuration.
- `SimulatorMockWalletProvider` and `SimulatorMockWalletResponder` for simulator-only URL/encryption/callback smoke testing.
- Focused XCTest coverage for Base58, crypto vectors, encrypted payloads, wallet aliases, error mapping, and the high-level adapter.

Not stable-certified yet:

- Physical-iPhone smoke logs against installed wallet apps.
- A concrete Reown/WalletConnect Swift transport and Jupiter Mobile smoke result.

The core package remains pure Swift and URL/callback based. Apps that want lifecycle plumbing can use `SolanaWalletAdapterUI`.

## Install

Add the package in Xcode:

```text
File > Add Package Dependencies > https://github.com/mstevens843/ios-solana-wallet-adapter
```

Or in `Package.swift` while testing the public RC:

```swift
.package(url: "https://github.com/mstevens843/ios-solana-wallet-adapter", exact: "0.2.0-rc.1")
```

While iterating locally, use the branch:

```swift
.package(url: "https://github.com/mstevens843/ios-solana-wallet-adapter", branch: "master")
```

Products:

- `SolanaWalletAdapter`
- `SolanaWalletAdapterPhantom`
- `SolanaWalletAdapterSolflare`
- `SolanaWalletAdapterBackpack`
- `SolanaWalletAdapterWalletConnect`
- `SolanaWalletAdapterUI`
- `SolanaWalletAdapterPicker`

## Quick Start

```swift
import SwiftUI
import SolanaWalletAdapter
import SolanaWalletAdapterPhantom

struct WalletDemoView: View {
    @Environment(\.openURL) private var openURL
    @State private var adapter = WalletAdapter(provider: PhantomAdapter(), cluster: .devnet)

    var body: some View {
        Button("Connect Phantom") {
            do {
                let url = try adapter.connectURL(
                    appURL: URL(string: "https://example.com")!,
                    redirectLink: URL(string: "myapp://wallet/callback")!,
                    cluster: .devnet
                )
                openURL(url)
            } catch {
                print("connect failed:", error)
            }
        }
        .onOpenURL { callback in
            do {
                let session = try adapter.handleConnectCallback(callback)
                print("connected:", session.userPublicKey)
            } catch {
                print("callback failed:", error)
            }
        }
    }
}
```

After connect, build signing URLs from the same adapter:

```swift
let signURL = try adapter.signMessageURL(
    Data("Sign in to Example".utf8),
    redirectLink: URL(string: "myapp://wallet/callback")!
)
openURL(signURL)
```

Decode the signing callback:

```swift
let result = try adapter.handleSignMessageCallback(callbackURL)
print("signature bytes:", result.signature)
```

The same high-level adapter also exposes:

- `signTransactionURL(_:redirectLink:)`
- `signAllTransactionsURL(_:redirectLink:)`
- `signAndSendTransactionURL(_:redirectLink:sendOptions:)`
- `disconnectURL(redirectLink:)`

See [`docs/demo.md`](docs/demo.md) for a full SwiftUI flow.

## Wallet Picker

`SolanaWalletAdapterPicker` ships a SwiftUI sheet that mirrors the Android
Intent disambiguator UX: a list of installed wallets (Phantom, Solflare,
Backpack, Jupiter Mobile) with inline **Just Once** / **Always** buttons on
the preferred row. Pin a wallet with **Always** and the next launch can call
`reconnectIfPossible()` to skip the picker entirely.

```swift
import SolanaWalletAdapterPicker

struct ConnectScreen: View {
    @State private var showingPicker = false
    let preferredWalletId: String?
    let onPick: (WalletPickerSelection) -> Void

    var body: some View {
        Button("Connect Wallet") { showingPicker = true }
            .walletPickerSheet(
                isPresented: $showingPicker,
                preferredWalletId: preferredWalletId,
                onSelect: onPick
            )
    }
}
```

### Required Info.plist setup

Apple only lets `UIApplication.canOpenURL` succeed for schemes the host app
has declared. Add these three keys to your `Info.plist` (or
`INFOPLIST_KEY_LSApplicationQueriesSchemes` in build settings):

```xml
<key>LSApplicationQueriesSchemes</key>
<array>
    <string>phantom</string>
    <string>solflare</string>
    <string>backpack</string>
</array>
```

`WalletPicker.requiredQuerySchemes` exposes the same list for programmatic
use. Jupiter Mobile is reachable via WalletConnect, not a native scheme, so
it intentionally is not in this list.

See [`docs/picker.md`](docs/picker.md) for brand overrides, filtering, and
the `InstalledWalletDetecting` test seam.

## Async App Client

`SolanaWalletAdapterUI` wraps URL opening and callbacks in async methods:

```swift
import SwiftUI
import SolanaWalletAdapter
import SolanaWalletAdapterPhantom
import SolanaWalletAdapterUI

@Environment(\.openURL) private var openURL

let client = WalletAdapterClient(
    provider: PhantomAdapter(),
    appURL: URL(string: "https://example.com")!,
    redirectLink: URL(string: "myapp://wallet/callback")!,
    cluster: .devnet,
    opener: SwiftUIWalletURLOpener(openURL: openURL),
    stateStore: KeychainWalletAdapterStateStore(),
    logger: WalletAdapterLoggers.print(),
    logLevel: .debug
)

let session = try await client.connect(cluster: .devnet)
let capabilities = try await client.getCapabilities()
let signed = try await client.signMessage(Data("Sign in to Example".utf8))

let siws = try await client.signInWithSolana(
    SignInWithSolanaInput(nonce: "bZQJ0SL6gJ")
)
```

Bridge wallet callbacks from SwiftUI:

```swift
.onOpenURL { url in
    _ = client.handleOpenURL(url)
}
```

If a wallet opens but never redirects back, call `client.cancelPendingRequest()` to resume the pending async call with `.requestCancelled`.

UIKit apps can use `UIKitWalletURLOpener`.

Compatibility aliases are intentionally strict. `authorize()` maps to `connect()`, `deauthorize()` maps to `disconnect()`, `signTransactions(_:)` maps to `signAllTransactions(_:)`, and the current native iOS deeplink layer supports one-message `signMessages(_:)` and one-transaction `signAndSendTransactions(_:)` calls. Real wallet batch aliases should only expand after the underlying wallet protocols expose that request shape.

Enable deterministic logs while smoke testing:

```swift
let logConfiguration = WalletAdapterLogConfiguration.fromEnvironment()

let client = WalletAdapterClient(
    provider: PhantomAdapter(),
    appURL: URL(string: "https://example.com")!,
    redirectLink: URL(string: "myapp://wallet/callback")!,
    cluster: .devnet,
    opener: SwiftUIWalletURLOpener(openURL: openURL),
    logger: logConfiguration.printLogger,
    logLevel: logConfiguration.logLevel,
    payloadPolicy: logConfiguration.payloadPolicy
)
```

Local environment flags:

```sh
SOLANA_WALLET_ADAPTER_LOG_LEVEL=debug
SOLANA_WALLET_ADAPTER_UNSAFE_LOGS=1
```

See [`docs/logging.md`](docs/logging.md) for expected log sequences, `flow_id` correlation, failure hints, and privacy rules.

For exact smoke-test payload dumps, pass `payloadPolicy: .unsafeRawPayloads` or set `SOLANA_WALLET_ADAPTER_UNSAFE_LOGS=1`. This logs full URLs, query values, encrypted payloads, decrypted wallet JSON, session tokens, messages, transactions, signatures, and WalletConnect request/result fields. It still does not log private keys, shared secrets, raw Keychain blobs, or Reown Project IDs. Do not enable it in production.

## RPC And Jupiter Configuration

The package exposes `WalletAdapterServiceConfiguration` for apps that need the same wallet signing flow alongside Solana RPC and Jupiter HTTP calls. It reads local environment values, validates them, and keeps log metadata redacted.

```swift
let services = try WalletAdapterServiceConfiguration.fromEnvironment(defaultCluster: .devnet)

let rpcURL = services.solanaRPCURL
let quoteURL = try services.jupiter.quoteURL(
    inputMint: inputMint,
    outputMint: outputMint,
    amount: amount,
    slippageBps: 50
)
let swapURL = try services.jupiter.swapURL()
let headers = services.jupiter.requestHeaders
```

Supported environment values:

```sh
SOLANA_CLUSTER=devnet
SOLANA_RPC_URL=https://your-rpc.example
HELIUS_RPC_URL=https://your-helius-rpc.example
JUP_API_URL=https://api.jup.ag
JUP_API_KEY=your-local-jupiter-key
JUPITER_API_KEY=your-local-jupiter-key
JUP_FETCH_TIMEOUT_MS=8000
```

RPC resolution is deterministic: `SOLANA_RPC_URL`, then `HELIUS_RPC_URL`, then the public mainnet RPC default. Jupiter defaults to `https://api.jup.ag` and builds the Solpulse-compatible `/swap/v1/quote`, `/swap/v1/swap`, and `/tokens/v2/search` endpoints. Do not commit real API keys or keyed RPC URLs.

## Simulator Smoke Testing

iOS Simulator cannot install App Store wallet apps, so the demo includes a clearly marked `Mock Wallet (Simulator)` option. It uses the same URL construction, NaCl-box encryption, callback URL, and `WalletAdapterClient.handleOpenURL` route as a real wallet, but signs with deterministic mock data.

Use it only to validate app wiring, logging, env configuration, and callback lifecycle. It does not prove Phantom, Solflare, or Backpack behavior on device.

## Supported Wallets

| Wallet | Universal-link host | Custom scheme | Status |
| --- | --- | --- | --- |
| Phantom | `phantom.app` | `phantom` | local implementation complete; real-device smoke pending; `signAndSendTransaction` deprecated upstream |
| Solflare | `solflare.com` | `solflare` | local implementation complete; real-device smoke pending |
| Backpack | `backpack.app` | `backpack` | local implementation complete; real-device smoke pending |
| Glow | TBD | TBD | research only |
| Jupiter Mobile | N/A | N/A | WalletConnect/Reown track; not a native iWA provider |

## Jupiter Mobile / Reown

Jupiter Mobile is not implemented as a `WalletProvider` because Jupiter's public adapter uses Reown AppKit / WalletConnect rather than Phantom-style `/ul/v1` native deeplinks.

Use `SolanaWalletAdapterWalletConnect` for this track. It provides typed Solana WalletConnect request builders, Reown project metadata types, Jupiter Mobile constants, response helpers, capability reporting, account methods, and an async `WalletConnectSolanaClient` that apps can back with a concrete Reown/WalletConnect Swift transport.

Do not hardcode a Reown Project ID in package source. Read it from local app config, build settings, or environment-specific configuration.

See [`docs/walletconnect-reown.md`](docs/walletconnect-reown.md).

## API Shape

Use `WalletAdapter` for app code. It owns:

- the selected `WalletProvider`
- the dApp ephemeral X25519 keypair
- the active `Session`
- the target `Cluster`

Use provider methods directly only if you need lower-level control:

```swift
let provider = PhantomAdapter()
let keypair = EphemeralKeypair.generate()
let connect = try provider.connectURL(
    request: ConnectRequest(
        dappEncryptionPublicKey: Base58.encode(keypair.publicKey),
        redirectLink: redirect,
        appURL: appURL,
        cluster: .devnet
    )
)
```

## Security Model

- The dApp generates an ephemeral X25519 keypair per adapter instance.
- Connect establishes the wallet encryption public key, session token, and user public key.
- Every post-connect request is encrypted with NaCl box using a fresh 24-byte nonce.
- Wire values are Base58 encoded to match Phantom, Solflare, and Backpack deeplink docs.
- The user's Solana private key never leaves the wallet app.

## Build and Test

```sh
swift build
swift build -c release
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
scripts/secret-scan.sh
scripts/verify-local.sh
```

The explicit `DEVELOPER_DIR` is useful on local macOS setups where Command Line Tools are selected but XCTest requires full Xcode.

## Project Layout

```text
Sources/SolanaWalletAdapter/          public API, WalletAdapter, Session, errors
Sources/SolanaWalletAdapterCore/      Base58, X25519 keypairs, NaCl box, URL helpers
Sources/SolanaWalletAdapterPhantom/   Phantom provider
Sources/SolanaWalletAdapterSolflare/  Solflare provider
Sources/SolanaWalletAdapterBackpack/  Backpack provider
Sources/SolanaWalletAdapterWalletConnect/ WalletConnect/Reown Solana request layer
Sources/SolanaWalletAdapterUI/        SwiftUI/UIKit async lifecycle helpers
Tests/SolanaWalletAdapterTests/       XCTest coverage
Examples/iWADemo/                     SwiftUI real-device smoke app source
spec/protocol.md                      iWA v0.1 wire protocol
docs/                                 demo docs and wallet research notes
```

## References

- Phantom deeplinks: <https://docs.phantom.com/phantom-deeplinks/deeplinks-ios-and-android>
- Solflare deeplinks: <https://docs.solflare.com/solflare/technical/deeplinks>
- Backpack deeplinks: <https://docs.backpack.app/deeplinks/provider-methods/connect>
- Jupiter Mobile: <https://docs.jup.ag/user-docs/manage/mobile>
- Jupiter Mobile Adapter: <https://developers.jup.ag/docs/tool-kits/wallet-kit/jupiter-mobile-adapter>
- Reown supported chains: <https://docs.reown.com/appkit/networks/supported-chains>
- WalletConnect Solana methods: <https://docs.walletconnect.network/wallet-sdk/chain-support/solana>
- Sign In With Solana: <https://github.com/phantom/sign-in-with-solana>
- Solana Mobile iOS wallet signing: <https://docs.solanamobile.com/blog/ios-wallet-signing>
- Real-device smoke testing: [`docs/smoke-testing.md`](docs/smoke-testing.md)

## License

Apache-2.0. See [`LICENSE`](LICENSE).
