# ``SolanaWalletAdapterPicker``

A SwiftUI wallet-picker sheet for iOS Solana apps.

## Overview

`SolanaWalletAdapterPicker` ships an in-app picker that mirrors the
Android Intent disambiguator UX. The picker lists installed wallets, lets
the user pin one with "Always", and hands the selection back to the
caller — which then drives `WalletAdapterClient.connect()`.

iOS has no OS-level wallet picker (custom schemes resolve to exactly one
app, universal links open the first match), so the picker is rendered by
the SDK instead. Detection is based on
`UIApplication.canOpenURL(_:)` against each wallet's custom URL scheme,
which only works when the host app's `Info.plist` declares
``WalletPicker/requiredQuerySchemes``.

## Quick start

```swift
import SwiftUI
import SolanaWalletAdapterPicker

struct ConnectScreen: View {
    @State private var showingPicker = false
    let client: WalletAdapterClient

    var body: some View {
        Button("Connect Wallet") { showingPicker = true }
            .walletPickerSheet(
                isPresented: $showingPicker,
                preferredWalletId: client.preferredWalletId
            ) { selection in
                switch selection {
                case .cancelled: break
                case .picked(let walletId, let remember):
                    Task {
                        if remember {
                            try await client.rememberPreferredWallet(walletId)
                        }
                        _ = try await client.connect()
                    }
                }
            }
    }
}
```

## Topics

### Presenting the picker

- ``WalletPickerView``
- ``WalletPickerSelection``

### Bundled wallet brands

- ``WalletBrand``
- ``WalletBrandRegistry``

### Filtering and testing

- ``WalletPickerModel``
- ``WalletPickerEntry``

### Required setup

- ``WalletPicker/requiredQuerySchemes``
