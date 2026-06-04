# SwiftUI Demo Flow

This repo ships both a pure Swift URL/callback adapter and an optional app lifecycle layer in `SolanaWalletAdapterUI`.

## 1. Pick a Wallet

```swift
import SwiftUI
import SolanaWalletAdapter
import SolanaWalletAdapterPhantom

@State private var adapter = WalletAdapter(provider: PhantomAdapter(), cluster: .devnet)
```

Swap `PhantomAdapter()` for `SolflareAdapter()` or `BackpackAdapter()` when the user chooses a different wallet.

Use `SimulatorMockWalletProvider()` only for simulator smoke tests. It exercises the same encrypted URL/callback path but is not a real wallet.

For real-device testing, enable deterministic logs:

```swift
@State private var adapter = WalletAdapter(
    provider: PhantomAdapter(),
    cluster: .devnet,
    logger: WalletAdapterLoggers.print(),
    logLevel: .debug
)
```

See [`logging.md`](./logging.md) for the expected log flow and privacy rules.

## 2. Connect

```swift
let redirect = URL(string: "myapp://wallet/callback")!
let appURL = URL(string: "https://example.com")!

let connectURL = try adapter.connectURL(
    appURL: appURL,
    redirectLink: redirect,
    cluster: .devnet
)
openURL(connectURL)
```

Handle the wallet callback:

```swift
.onOpenURL { url in
    do {
        let session = try adapter.handleConnectCallback(url)
        print("connected wallet:", session.userPublicKey)
    } catch {
        print("connect callback failed:", error)
    }
}
```

If you prefer async app code, use the UI client:

```swift
import SolanaWalletAdapterUI

let client = WalletAdapterClient(
    provider: PhantomAdapter(),
    appURL: URL(string: "https://example.com")!,
    redirectLink: URL(string: "myapp://wallet/callback")!,
    cluster: .devnet,
    opener: SwiftUIWalletURLOpener(openURL: openURL),
    stateStore: KeychainWalletAdapterStateStore()
)

let session = try await client.connect(cluster: .devnet)
```

Bridge callbacks once:

```swift
.onOpenURL { url in
    _ = client.handleOpenURL(url)
}
```

## 3. Sign a Message

```swift
let messageURL = try adapter.signMessageURL(
    Data("Sign in to Example".utf8),
    redirectLink: redirect,
    display: .utf8
)
openURL(messageURL)
```

Decode the callback:

```swift
let result = try adapter.handleSignMessageCallback(url)
print("signature:", result.signature)
```

## 4. Sign Transactions

```swift
let signURL = try adapter.signTransactionURL(transactionBytes, redirectLink: redirect)
openURL(signURL)

let signed = try adapter.handleSignTransactionCallback(url)
print("signed tx:", signed.transaction)
```

For batch signing:

```swift
let batchURL = try adapter.signAllTransactionsURL([txA, txB], redirectLink: redirect)
let batch = try adapter.handleSignAllTransactionsCallback(url)
```

For wallet-side broadcast:

```swift
let sendURL = try adapter.signAndSendTransactionURL(
    transactionBytes,
    redirectLink: redirect,
    sendOptions: SendOptions(skipPreflight: false, preflightCommitment: "confirmed", maxRetries: 3)
)
let sent = try adapter.handleSignAndSendTransactionCallback(url)
print("txid:", sent.signature)
```

## 5. Disconnect

```swift
let disconnectURL = try adapter.disconnectURL(redirectLink: redirect)
openURL(disconnectURL)
adapter.clearSession()
```

## Demo Checklist

- Add the callback scheme to the app's URL types.
- Prefer universal links for wallet requests.
- Test one wallet at a time with an explicit wallet picker.
- Enable deterministic iWA logs during smoke testing.
- Do not log full callback URLs or decrypted payloads in public reports.
- Use `Mock Wallet (Simulator)` when you do not have a physical iPhone available.
- Use `Examples/iWADemo` as the reference real-device smoke flow.
