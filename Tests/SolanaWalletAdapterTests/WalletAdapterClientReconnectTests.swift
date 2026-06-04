import XCTest
import SolanaWalletAdapter
import SolanaWalletAdapterCore
import SolanaWalletAdapterPhantom
import SolanaWalletAdapterUI

@MainActor
final class WalletAdapterClientReconnectTests: XCTestCase {
    private let appURL = URL(string: "https://example.com")!
    private let redirect = URL(string: "iwademo://wallet/callback")!

    func testReconnectReturnsTrueWhenSessionRestoredAndWalletInstalled() async throws {
        let client = makeClient()
        client.adapter.restoreSession(seededSession())

        let detector = StubInstalledWalletDetector(installed: ["phantom"])
        let canReconnect = await client.reconnectIfPossible(detector: detector)

        XCTAssertTrue(canReconnect)
    }

    func testReconnectReturnsFalseWhenSessionMissing() async throws {
        let client = makeClient()

        let detector = StubInstalledWalletDetector(installed: ["phantom"])
        let canReconnect = await client.reconnectIfPossible(detector: detector)

        XCTAssertFalse(canReconnect)
    }

    func testReconnectReturnsFalseWhenWalletNotInstalled() async throws {
        let client = makeClient()
        client.adapter.restoreSession(seededSession())

        let detector = StubInstalledWalletDetector(installed: [])
        let canReconnect = await client.reconnectIfPossible(detector: detector)

        XCTAssertFalse(canReconnect)
    }

    func testRememberPreferredWalletPersistsThroughKeychainEnvelope() async throws {
        let store = ReconnectMemoryStore()
        let client = makeClient(stateStore: store)
        try await client.rememberPreferredWallet("phantom")

        XCTAssertEqual(store.state?.preferredProviderId, "phantom")
        XCTAssertEqual(client.preferredWalletId, "phantom")
    }

    // MARK: - helpers

    private func makeClient(stateStore: ReconnectMemoryStore? = nil) -> WalletAdapterClient {
        WalletAdapterClient(
            provider: PhantomAdapter(),
            appURL: appURL,
            redirectLink: redirect,
            cluster: .mainnetBeta,
            opener: ReconnectNoopOpener(),
            stateStore: stateStore
        )
    }

    private func seededSession() -> Session {
        Session(
            walletEncryptionPublicKey: Data(repeating: 1, count: 32),
            token: "session-token",
            userPublicKey: "User1111111111111111111111111111111111"
        )
    }
}

@MainActor
private final class ReconnectNoopOpener: WalletURLOpening {
    func openWalletURL(_ url: URL) async -> Bool { true }
}

private final class ReconnectMemoryStore: WalletAdapterStateStore, @unchecked Sendable {
    var state: WalletAdapterState?
    func loadState() throws -> WalletAdapterState? { state }
    func saveState(_ state: WalletAdapterState?) throws { self.state = state }
}
