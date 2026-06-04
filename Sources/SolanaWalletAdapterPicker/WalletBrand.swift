import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif

/// Visual + identity metadata for a row in the wallet picker. Brand colors and
/// logos are kept in the picker module (not the protocol) so adapter targets
/// stay focused on URL/callback work and don't ship images.
public struct WalletBrand: Sendable, Equatable, Identifiable {
    /// Stable identifier matching `WalletProvider.walletId`. Picker rows are
    /// keyed by this value so consumer overrides line up.
    public let id: String
    public let displayName: String
    /// Logical wallet URL scheme used for `canOpenURL` probing. `nil` for
    /// wallets that don't expose a native deeplink (e.g. WalletConnect-only).
    public let urlScheme: String?
    /// Asset name inside the picker module's `Wallets.xcassets`. Looked up via
    /// `Bundle.module`; falls back to a monogram placeholder when absent.
    public let logoAssetName: String?
    public let brandColorHex: String

    public init(
        id: String,
        displayName: String,
        urlScheme: String?,
        logoAssetName: String?,
        brandColorHex: String
    ) {
        self.id = id
        self.displayName = displayName
        self.urlScheme = urlScheme
        self.logoAssetName = logoAssetName
        self.brandColorHex = brandColorHex
    }
}

/// The four wallets shipped out of the box. Consumers can extend or override
/// this set via `WalletPickerView.brandOverrides(_:)`.
public enum WalletBrandRegistry {
    public static let phantom = WalletBrand(
        id: "phantom",
        displayName: "Phantom",
        urlScheme: "phantom",
        logoAssetName: "wallet-phantom",
        brandColorHex: "#AB9FF2"
    )
    public static let solflare = WalletBrand(
        id: "solflare",
        displayName: "Solflare",
        urlScheme: "solflare",
        logoAssetName: "wallet-solflare",
        brandColorHex: "#FFC10B"
    )
    public static let backpack = WalletBrand(
        id: "backpack",
        displayName: "Backpack",
        urlScheme: "backpack",
        logoAssetName: "wallet-backpack",
        brandColorHex: "#E33E3F"
    )
    public static let jupiter = WalletBrand(
        id: "jupiter",
        displayName: "Jupiter Mobile",
        urlScheme: nil,
        logoAssetName: "wallet-jupiter",
        brandColorHex: "#22B388"
    )

    public static let defaults: [WalletBrand] = [phantom, solflare, backpack, jupiter]
}
