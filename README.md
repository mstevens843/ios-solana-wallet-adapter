# ios-solana-wallet-adapter

**iOS Wallet Adapter (iWA): one Swift Package for Phantom, Solflare, and Backpack deeplink signing.**

`ios-solana-wallet-adapter` gives native iOS Solana apps a single URL/callback API for external wallet signing. The app keeps no user private keys. The wallet shows the approval screen. The adapter builds the wallet URL, encrypts request payloads, and decodes the callback.

This is not Mobile Wallet Adapter. MWA is Android-only by protocol. iWA is the iOS-native request/response shape built on universal links and wallet-specific deeplinks.

## Status

Version `0.1.0-alpha`, Phase 2A.

Shipped in this repo:

- `WalletAdapter`, the high-level coordinator for connect, sign, sign and send, and disconnect URLs.
- Per-wallet providers for Phantom, Solflare, and Backpack.
- Real X25519 ephemeral key generation through CryptoKit.
- TweetNaCl-compatible NaCl box encryption and decryption (XSalsa20-Poly1305), vendored with license notice.
- Base58 wire encoding for public keys, nonces, ciphertexts, messages, transactions, and signatures.
- Callback decoding for connect, sign message, sign transaction, sign all transactions, and sign and send.
- Focused XCTest coverage for Base58, crypto vectors, encrypted payloads, wallet aliases, error mapping, and the high-level adapter.

Not shipped yet:

- UIKit or SwiftUI URL-opening helpers.
- Async continuation plumbing for app lifecycle callbacks.
- A bundled iOS sample app target.
- Real-device smoke logs against installed wallet apps.

The package is intentionally pure Swift and URL/callback based. Your app chooses when to call `openURL` and where to handle `.onOpenURL`.

## Install

Add the package in Xcode:

```text
File > Add Package Dependencies > https://github.com/mstevens843/ios-solana-wallet-adapter
```

Or in `Package.swift`:

```swift
.package(url: "https://github.com/mstevens843/ios-solana-wallet-adapter", from: "0.1.0")
```

Products:

- `SolanaWalletAdapter`
- `SolanaWalletAdapterPhantom`
- `SolanaWalletAdapterSolflare`
- `SolanaWalletAdapterBackpack`

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

## Supported Wallets

| Wallet | Universal-link host | Custom scheme | Status |
| --- | --- | --- | --- |
| Phantom | `phantom.app` | `phantom` | connect, encrypted signing URLs, callback decoding |
| Solflare | `solflare.com` | `solflare` | connect, encrypted signing URLs, callback decoding |
| Backpack | `backpack.app` | `backpack` | connect, encrypted signing URLs, callback decoding |
| Glow | TBD | TBD | research only |

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
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

The explicit `DEVELOPER_DIR` is useful on local macOS setups where Command Line Tools are selected but XCTest requires full Xcode.

## Project Layout

```text
Sources/SolanaWalletAdapter/          public API, WalletAdapter, Session, errors
Sources/SolanaWalletAdapterCore/      Base58, X25519 keypairs, NaCl box, URL helpers
Sources/SolanaWalletAdapterPhantom/   Phantom provider
Sources/SolanaWalletAdapterSolflare/  Solflare provider
Sources/SolanaWalletAdapterBackpack/  Backpack provider
Tests/SolanaWalletAdapterTests/       XCTest coverage
spec/protocol.md                      iWA v0.1 wire protocol
docs/                                 demo docs and wallet research notes
```

## References

- Phantom deeplinks: <https://docs.phantom.com/phantom-deeplinks/deeplinks-ios-and-android>
- Solflare deeplinks: <https://docs.solflare.com/solflare/technical/deeplinks>
- Backpack deeplinks: <https://docs.backpack.app/deeplinks/provider-methods/connect>
- Solana Mobile iOS wallet signing: <https://docs.solanamobile.com/blog/ios-wallet-signing>

## License

Apache-2.0. See [`LICENSE`](LICENSE).
