# Wallet Picker

`SolanaWalletAdapterPicker` provides an in-app sheet that mirrors the
Android Intent disambiguator on iOS. iOS has no OS-level wallet picker
(custom schemes resolve to one app and universal links open the first
match), so the SDK draws the sheet itself.

Out of the box the picker lists four wallets: Phantom, Solflare, Backpack,
and Jupiter Mobile. Phantom/Solflare/Backpack are real native-deeplink
providers; Jupiter Mobile is shown for parity but routes through
WalletConnect, which is a separate transport.

## Setup

1. Add the `SolanaWalletAdapterPicker` product to your app target.
2. Declare the three custom URL schemes in your app's Info.plist:

   ```xml
   <key>LSApplicationQueriesSchemes</key>
   <array>
       <string>phantom</string>
       <string>solflare</string>
       <string>backpack</string>
   </array>
   ```

   Apple's `UIApplication.canOpenURL` silently returns `false` for any
   scheme not in this list. Without these keys the picker will render
   every wallet as "Not installed".

3. Optionally drop branded PNGs into
   `Sources/SolanaWalletAdapterPicker/Resources/Wallets.xcassets/`. The
   picker falls back to a colored tile with a monogram if assets are
   missing.

## Presenting the picker

```swift
.walletPickerSheet(
    isPresented: $showingPicker,
    preferredWalletId: client.preferredWalletId,
    onSelect: { selection in
        switch selection {
        case .cancelled: break
        case .picked(let walletId, let remember):
            if remember {
                Task { try await client.rememberPreferredWallet(walletId) }
            }
            // hand off to your connect flow
        }
    }
)
```

The selection callback returns synchronously; the caller drives any async
`client.connect()` / `signInWithSolana(_:)` flow.

## "Just Once" vs "Always"

The preferred row exposes two buttons. **Just Once** picks the wallet
without persistence; **Always** also calls
`WalletAdapterClient.rememberPreferredWallet(_:)`, which writes
`preferredProviderId` into the persisted Keychain envelope. Future
launches read it back and can skip the picker:

```swift
let client = try WalletAdapterClient.restore(...)
if await client.reconnectIfPossible() {
    // resume cached session without re-opening the picker
}
```

Clear the preference with `forgetPreferredWallet()` (keeps the session)
or `clearState()` (rotates the keypair, wipes everything).

## Customization

### Brand overrides

`WalletBrand` is the visual identity object. Default brands live in
`WalletBrandRegistry.defaults`. Custom providers can ship their own
brand by passing a merged list:

```swift
WalletPickerView(
    detector: InstalledWalletDetector.default,
    preferredWalletId: client.preferredWalletId,
    brands: WalletBrandRegistry.defaults + [myCustomBrand]
) { ... }
```

### Filtering

Pass a `filter` closure to hide wallets:

```swift
WalletPickerView(
    brands: WalletBrandRegistry.defaults,
    filter: { walletId in walletId != "jupiter" }
) { ... }
```

## Testing

`InstalledWalletDetecting` is the seam the picker uses to probe
`canOpenURL`. Inject `StubInstalledWalletDetector(installed: [...])`
in unit tests to control which wallets appear installed:

```swift
let model = WalletPickerModel(
    detector: StubInstalledWalletDetector(installed: ["phantom"]),
    preferredWalletId: "phantom"
)
XCTAssertEqual(model.preferredEntry?.brand.id, "phantom")
```

The default detector (`UIApplicationInstalledWalletDetector`) wraps
`UIApplication.shared.canOpenURL(_:)` and is annotated `@MainActor`.
