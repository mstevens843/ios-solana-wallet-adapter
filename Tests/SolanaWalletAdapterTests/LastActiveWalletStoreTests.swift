import XCTest
import SolanaWalletAdapter
import SolanaWalletAdapterCore
import SolanaWalletAdapterPhantom
import SolanaWalletAdapterUI

@MainActor
final class LastActiveWalletStoreTests: XCTestCase {
    private let appURL = URL(string: "https://example.com")!
    private let redirect = URL(string: "iwademo://wallet/callback")!

    /// A hard `clearState()` must also wipe the last-active pointer so the next
    /// launch doesn't try to restore a deleted wallet.
    func testClearStateClearsLastActivePointer() async throws {
        let lastActive = MemoryLastActiveStore()
        try lastActive.saveLastActiveWalletId("phantom")
        let client = WalletAdapterClient(
            provider: PhantomAdapter(),
            appURL: appURL,
            redirectLink: redirect,
            cluster: .mainnetBeta,
            opener: NoopOpener(),
            stateStore: MemoryStore(),
            lastActiveStore: lastActive
        )

        try await client.clearState()

        XCTAssertNil(try lastActive.loadLastActiveWalletId())
    }

    func testMemoryStoreRoundTrips() throws {
        let store = MemoryLastActiveStore()
        XCTAssertNil(try store.loadLastActiveWalletId())
        try store.saveLastActiveWalletId("backpack")
        XCTAssertEqual(try store.loadLastActiveWalletId(), "backpack")
        try store.saveLastActiveWalletId(nil)
        XCTAssertNil(try store.loadLastActiveWalletId())
    }
}

@MainActor
private final class NoopOpener: WalletURLOpening {
    func openWalletURL(_ url: URL) async -> Bool { true }
}

private final class MemoryStore: WalletAdapterStateStore, @unchecked Sendable {
    var state: WalletAdapterState?
    func loadState() throws -> WalletAdapterState? { state }
    func saveState(_ state: WalletAdapterState?) throws { self.state = state }
}

private final class MemoryLastActiveStore: LastActiveWalletStoring, @unchecked Sendable {
    private var id: String?
    func loadLastActiveWalletId() throws -> String? { id }
    func saveLastActiveWalletId(_ walletId: String?) throws { id = walletId }
}
