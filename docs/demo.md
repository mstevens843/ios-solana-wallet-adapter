# SwiftUI Demo Flow

This repo ships a pure Swift URL/callback adapter. Your app is responsible for opening URLs and receiving callbacks.

## 1. Pick a Wallet

```swift
import SwiftUI
import SolanaWalletAdapter
import SolanaWalletAdapterPhantom

@State private var adapter = WalletAdapter(provider: PhantomAdapter(), cluster: .devnet)
```

Swap `PhantomAdapter()` for `SolflareAdapter()` or `BackpackAdapter()` when the user chooses a different wallet.

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
- Log callback URLs during development, but never log decrypted payloads in production.
