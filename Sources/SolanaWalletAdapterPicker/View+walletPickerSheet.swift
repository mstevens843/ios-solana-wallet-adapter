#if canImport(SwiftUI)
import SwiftUI
import SolanaWalletAdapterUI

@available(iOS 16.0, macOS 13.0, *)
public extension View {
    /// Present the bundled wallet picker as a sheet. The picker renders the
    /// installed wallets among the four bundled brands (Phantom, Solflare,
    /// Backpack, Jupiter Mobile), with inline "Just Once" / "Always" buttons
    /// on the preferred row.
    ///
    /// The caller drives the connect/sign flow on `WalletAdapterClient` after
    /// the selection lands — the picker only hands back the chosen wallet.
    func walletPickerSheet(
        isPresented: Binding<Bool>,
        detector: any InstalledWalletDetecting = InstalledWalletDetector.default,
        preferredWalletId: String? = nil,
        brands: [WalletBrand] = WalletBrandRegistry.defaults,
        filter: @escaping @Sendable (String) -> Bool = { _ in true },
        onSelect: @escaping (WalletPickerSelection) -> Void
    ) -> some View {
        self.sheet(isPresented: isPresented) {
            WalletPickerView(
                detector: detector,
                preferredWalletId: preferredWalletId,
                brands: brands,
                filter: filter
            ) { selection in
                isPresented.wrappedValue = false
                onSelect(selection)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.hidden)
        }
    }
}
#endif
