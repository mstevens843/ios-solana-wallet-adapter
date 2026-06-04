#if canImport(SwiftUI)
import SwiftUI
import SolanaWalletAdapterUI

/// SwiftUI picker that mirrors the Android Intent disambiguator UX: a sheet
/// listing installed Solana wallets, with inline "Just Once" / "Always"
/// buttons on the preferred row so users can pin a wallet.
@available(iOS 16.0, macOS 13.0, *)
public struct WalletPickerView: View {
    private let model: WalletPickerModel
    private let onSelect: (WalletPickerSelection) -> Void
    private let brandOverrides: [String: WalletBrand]

    public init(
        detector: any InstalledWalletDetecting = InstalledWalletDetector.default,
        preferredWalletId: String? = nil,
        brands: [WalletBrand] = WalletBrandRegistry.defaults,
        filter: @Sendable (String) -> Bool = { _ in true },
        onSelect: @escaping (WalletPickerSelection) -> Void
    ) {
        let merged = WalletPickerView.mergeBrands(defaults: brands, overrides: [])
        self.model = WalletPickerModel(
            brands: merged,
            detector: detector,
            preferredWalletId: preferredWalletId,
            filter: filter
        )
        self.brandOverrides = [:]
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(spacing: 0) {
            handle
            content
        }
        .background(WalletPickerView.backgroundColor)
    }

    private static var backgroundColor: Color {
        #if canImport(UIKit)
        return Color(uiColor: .systemBackground)
        #else
        return Color(nsColor: .windowBackgroundColor)
        #endif
    }

    private var handle: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.4))
            .frame(width: 36, height: 5)
            .padding(.top, 8)
            .padding(.bottom, 12)
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let preferred = model.preferredEntry {
                    preferredSection(preferred)
                    Divider()
                }
                if !model.otherEntries.isEmpty {
                    Text(model.preferredEntry == nil ? "Choose a wallet" : "Use a different app")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 8)
                    ForEach(model.otherEntries) { entry in
                        WalletPickerRow(entry: entry) {
                            onSelect(.picked(walletId: entry.brand.id, remember: false))
                        }
                    }
                }
                Button("Cancel") {
                    onSelect(.cancelled)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 16)
                .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func preferredSection(_ entry: WalletPickerEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                WalletLogoView(brand: entry.brand)
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Open with \(entry.brand.displayName)")
                        .font(.headline)
                    if !entry.isInstalled {
                        Text("Not installed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            HStack(spacing: 12) {
                Spacer()
                Button("Just Once") {
                    onSelect(.picked(walletId: entry.brand.id, remember: false))
                }
                .buttonStyle(.bordered)
                Button("Always") {
                    onSelect(.picked(walletId: entry.brand.id, remember: true))
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private static func mergeBrands(defaults: [WalletBrand], overrides: [WalletBrand]) -> [WalletBrand] {
        var lookup = Dictionary(uniqueKeysWithValues: defaults.map { ($0.id, $0) })
        for brand in overrides {
            lookup[brand.id] = brand
        }
        return defaults.map { lookup[$0.id] ?? $0 } + overrides.filter { override in
            !defaults.contains(where: { $0.id == override.id })
        }
    }
}

@available(iOS 16.0, macOS 13.0, *)
private struct WalletPickerRow: View {
    let entry: WalletPickerEntry
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                WalletLogoView(brand: entry.brand)
                    .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.brand.displayName)
                        .foregroundStyle(.primary)
                    if !entry.isInstalled {
                        Text("Not installed")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(entry.isInstalled ? 1.0 : 0.55)
    }
}

@available(iOS 16.0, macOS 13.0, *)
struct WalletLogoView: View {
    let brand: WalletBrand

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(hex: brand.brandColorHex) ?? .gray)
            if let assetName = brand.logoAssetName,
               let image = WalletLogoView.loadImage(named: assetName) {
                image
                    .resizable()
                    .scaledToFit()
                    .padding(4)
            } else {
                Text(monogram(for: brand.displayName))
                    .font(.headline)
                    .foregroundStyle(.white)
            }
        }
    }

    private func monogram(for name: String) -> String {
        String(name.prefix(1)).uppercased()
    }

    private static func loadImage(named: String) -> Image? {
        #if canImport(UIKit)
        if let uiImage = UIImage(named: named, in: .module, with: nil) {
            return Image(uiImage: uiImage)
        }
        #endif
        return nil
    }
}

extension Color {
    init?(hex: String) {
        var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hexString.hasPrefix("#") { hexString.removeFirst() }
        guard hexString.count == 6, let value = UInt32(hexString, radix: 16) else {
            return nil
        }
        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        self = Color(red: red, green: green, blue: blue)
    }
}
#endif
