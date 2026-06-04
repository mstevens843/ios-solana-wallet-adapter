import XCTest
import SolanaWalletAdapter
import SolanaWalletAdapterCore
import SolanaWalletAdapterPhantom
import SolanaWalletAdapterUI

@MainActor
final class WalletAdapterClientSessionLifecycleTests: XCTestCase {
    private let appURL = URL(string: "https://example.com")!
    private let redirect = URL(string: "iwademo://wallet/callback")!

    /// Soft logout drops the in-memory session but must leave the persisted
    /// session intact so the user can reconnect-cached without a wallet round-trip.
    func testSignOutLocallyClearsInMemorySessionButKeepsCache() async throws {
        let store = LifecycleMemoryStore()
        store.state = seededState()
        let opener = SpyOpener()
        let client = makeClient(stateStore: store, opener: opener)
        client.adapter.restoreSession(seededSession())

        try await client.signOutLocally()

        XCTAssertNil(client.adapter.session, "in-memory session should be cleared")
        XCTAssertNotNil(store.state?.session, "cached session must be retained for offline reconnect")
        XCTAssertEqual(opener.openCount, 0, "soft logout must not open the wallet")
    }

    /// Resuming a cached session restores it from the store with zero wallet
    /// round-trips (the opener is never invoked).
    func testResumeCachedSessionRestoresWithoutWalletRoundTrip() async throws {
        let store = LifecycleMemoryStore()
        store.state = seededState()
        let opener = SpyOpener()
        let client = makeClient(stateStore: store, opener: opener)
        XCTAssertNil(client.adapter.session)

        let resumed = await client.resumeCachedSession()

        XCTAssertTrue(resumed)
        XCTAssertEqual(client.adapter.session?.userPublicKey, seededSession().userPublicKey)
        XCTAssertEqual(opener.openCount, 0, "cached resume must not open the wallet")
    }

    func testResumeCachedSessionReturnsFalseWhenNothingCached() async throws {
        let store = LifecycleMemoryStore()
        let client = makeClient(stateStore: store, opener: SpyOpener())

        let resumed = await client.resumeCachedSession()

        XCTAssertFalse(resumed)
        XCTAssertNil(client.adapter.session)
    }

    /// End-to-end of the soft-disconnect → reconnect-cached loop on one client.
    func testSignOutThenResumeRoundTrips() async throws {
        let store = LifecycleMemoryStore()
        store.state = seededState()
        let client = makeClient(stateStore: store, opener: SpyOpener())
        client.adapter.restoreSession(seededSession())

        try await client.signOutLocally()
        XCTAssertNil(client.adapter.session)

        let resumed = await client.resumeCachedSession()
        XCTAssertTrue(resumed)
        XCTAssertNotNil(client.adapter.session)
    }

    // MARK: - helpers

    private func makeClient(stateStore: LifecycleMemoryStore, opener: SpyOpener) -> WalletAdapterClient {
        WalletAdapterClient(
            provider: PhantomAdapter(),
            appURL: appURL,
            redirectLink: redirect,
            cluster: .mainnetBeta,
            opener: opener,
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

    private func seededState() -> WalletAdapterState {
        WalletAdapterState(
            providerId: "phantom",
            cluster: .mainnetBeta,
            keypair: .generate(),
            session: seededSession()
        )
    }
}

@MainActor
private final class SpyOpener: WalletURLOpening {
    private(set) var openCount = 0
    func openWalletURL(_ url: URL) async -> Bool {
        openCount += 1
        return true
    }
}

private final class LifecycleMemoryStore: WalletAdapterStateStore, @unchecked Sendable {
    var state: WalletAdapterState?
    func loadState() throws -> WalletAdapterState? { state }
    func saveState(_ state: WalletAdapterState?) throws { self.state = state }
}
