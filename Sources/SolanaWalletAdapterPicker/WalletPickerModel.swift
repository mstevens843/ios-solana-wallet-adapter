import Foundation
import SolanaWalletAdapterUI

/// One row in the picker, after installed-status probing and filtering.
public struct WalletPickerEntry: Sendable, Equatable, Identifiable {
    public let brand: WalletBrand
    /// True if the wallet's URL scheme is installed, or if no scheme is
    /// declared (e.g. Jupiter / WalletConnect-only wallets, which always
    /// surface so the user can still pick them).
    public let isInstalled: Bool
    /// True if this wallet matches the user's last "Always" choice. The view
    /// renders these at the top with `Just Once` / `Always` buttons inline.
    public let isPreferred: Bool

    public var id: String { brand.id }

    public init(brand: WalletBrand, isInstalled: Bool, isPreferred: Bool) {
        self.brand = brand
        self.isInstalled = isInstalled
        self.isPreferred = isPreferred
    }
}

/// Pure data layer for the picker. Resolves the displayable list once and
/// exposes selection helpers so `WalletPickerView` stays trivially testable.
public struct WalletPickerModel: Sendable, Equatable {
    public let entries: [WalletPickerEntry]

    public init(
        brands: [WalletBrand] = WalletBrandRegistry.defaults,
        detector: any InstalledWalletDetecting,
        preferredWalletId: String? = nil,
        filter: @Sendable (String) -> Bool = { _ in true }
    ) {
        let resolved = brands
            .filter { filter($0.id) }
            .map { brand -> WalletPickerEntry in
                let installed: Bool
                if let scheme = brand.urlScheme {
                    installed = detector.isInstalled(scheme: scheme)
                } else {
                    // WalletConnect-only wallets surface unconditionally — we
                    // cannot probe their installed state via canOpenURL.
                    installed = true
                }
                return WalletPickerEntry(
                    brand: brand,
                    isInstalled: installed,
                    isPreferred: brand.id == preferredWalletId
                )
            }
        // Sort: preferred row first, then installed, then alphabetical.
        self.entries = resolved.sorted { lhs, rhs in
            if lhs.isPreferred != rhs.isPreferred { return lhs.isPreferred }
            if lhs.isInstalled != rhs.isInstalled { return lhs.isInstalled }
            return lhs.brand.displayName.localizedCaseInsensitiveCompare(rhs.brand.displayName) == .orderedAscending
        }
    }

    public var preferredEntry: WalletPickerEntry? {
        entries.first { $0.isPreferred }
    }

    public var otherEntries: [WalletPickerEntry] {
        entries.filter { !$0.isPreferred }
    }
}
