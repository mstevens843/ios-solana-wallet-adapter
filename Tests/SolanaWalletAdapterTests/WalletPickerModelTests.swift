import XCTest
import SolanaWalletAdapterUI
@testable import SolanaWalletAdapterPicker

final class WalletPickerModelTests: XCTestCase {
    func testPreferredEntrySurfacesFirst() {
        let detector = StubInstalledWalletDetector(installed: ["phantom", "solflare"])
        let model = WalletPickerModel(
            detector: detector,
            preferredWalletId: "solflare"
        )

        XCTAssertEqual(model.preferredEntry?.brand.id, "solflare")
        XCTAssertEqual(model.entries.first?.brand.id, "solflare")
    }

    func testInstalledWalletsSortAheadOfMissingOnes() {
        let detector = StubInstalledWalletDetector(installed: ["backpack"])
        let model = WalletPickerModel(detector: detector)

        // Backpack is installed; Phantom and Solflare are not. Jupiter has no
        // scheme so it surfaces as installed.
        let installedIds = Set(model.entries.filter { $0.isInstalled }.map { $0.brand.id })
        let missingIds = Set(model.entries.filter { !$0.isInstalled }.map { $0.brand.id })

        XCTAssertEqual(installedIds, ["backpack", "jupiter"])
        XCTAssertEqual(missingIds, ["phantom", "solflare"])
    }

    func testFilterRemovesWalletsFromList() {
        let detector = StubInstalledWalletDetector(installed: ["phantom", "solflare", "backpack"])
        let model = WalletPickerModel(detector: detector, filter: { $0 != "jupiter" })

        XCTAssertFalse(model.entries.contains(where: { $0.brand.id == "jupiter" }))
    }

    func testJupiterAlwaysSurfacesEvenWithoutScheme() {
        let detector = StubInstalledWalletDetector(installed: [])
        let model = WalletPickerModel(detector: detector)
        let jupiter = model.entries.first { $0.brand.id == "jupiter" }

        XCTAssertNotNil(jupiter)
        XCTAssertTrue(jupiter?.isInstalled ?? false, "Jupiter has no scheme so it's treated as available")
    }
}
