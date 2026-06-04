import XCTest
import SolanaWalletAdapter
import SolanaWalletAdapterCore
import SolanaWalletAdapterPhantom
import SolanaWalletAdapterUI

@MainActor
final class WalletAdapterClientClearStateTests: XCTestCase {
    private let appURL = URL(string: "https://example.com")!
    private let redirect = URL(string: "iwademo://wallet/callback")!

    func testClearStateRotatesKeypairAndWipesPersistedState() async throws {
        let stateStore = ClearStateMemoryStore()
        let client = WalletAdapterClient(
            provider: PhantomAdapter(),
            appURL: appURL,
            redirectLink: redirect,
            cluster: .mainnetBeta,
            opener: NoopOpener(),
            stateStore: stateStore
        )
        // Seed a session so we can verify it's gone after clearState.
        client.adapter.restoreSession(Session(
            walletEncryptionPublicKey: Data(repeating: 1, count: 32),
            token: "session-pre-clear",
            userPublicKey: "User1111111111111111111111111111111111"
        ))
        let preClearPublicKey = client.adapter.keypair.publicKey

        try await client.clearState()

        XCTAssertNil(client.adapter.session, "session should be cleared")
        XCTAssertNotEqual(client.adapter.keypair.publicKey, preClearPublicKey, "ephemeral keypair should be rotated")
        XCTAssertNil(stateStore.state, "Keychain blob should be deleted")
        XCTAssertNil(client.preferredWalletId, "preferredProviderId should be wiped")
    }

    func testClearStateCancelsPendingRequestWithRequestCancelled() async throws {
        let opener = AwaitingOpener()
        let client = WalletAdapterClient(
            provider: PhantomAdapter(),
            appURL: appURL,
            redirectLink: redirect,
            cluster: .mainnetBeta,
            opener: opener
        )
        let connectTask = Task { try await client.connect() }
        try await opener.waitUntilOpened()

        try await client.clearState()

        do {
            _ = try await connectTask.value
            XCTFail("pending connect should fail with requestCancelled after clearState")
        } catch {
            XCTAssertEqual(error as? WalletAdapterError, .requestCancelled)
        }
    }

    func testForgetPreferredWalletKeepsSession() async throws {
        let stateStore = ClearStateMemoryStore()
        let client = WalletAdapterClient(
            provider: PhantomAdapter(),
            appURL: appURL,
            redirectLink: redirect,
            cluster: .mainnetBeta,
            opener: NoopOpener(),
            stateStore: stateStore
        )
        client.adapter.restoreSession(Session(
            walletEncryptionPublicKey: Data(repeating: 1, count: 32),
            token: "keep-me",
            userPublicKey: "User1111111111111111111111111111111111"
        ))
        try await client.rememberPreferredWallet("phantom")
        XCTAssertEqual(client.preferredWalletId, "phantom")

        try await client.forgetPreferredWallet()

        XCTAssertNil(client.preferredWalletId)
        XCTAssertEqual(client.adapter.session?.token, "keep-me", "session should survive")
        XCTAssertNil(stateStore.state?.preferredProviderId)
    }
}

@MainActor
private final class NoopOpener: WalletURLOpening {
    func openWalletURL(_ url: URL) async -> Bool { true }
}

@MainActor
private final class AwaitingOpener: WalletURLOpening {
    private(set) var opened = false
    func openWalletURL(_ url: URL) async -> Bool {
        opened = true
        return true
    }
    func waitUntilOpened() async throws {
        for _ in 0..<50 {
            if opened { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("wallet URL was not opened in time")
    }
}

private final class ClearStateMemoryStore: WalletAdapterStateStore, @unchecked Sendable {
    var state: WalletAdapterState?
    func loadState() throws -> WalletAdapterState? { state }
    func saveState(_ state: WalletAdapterState?) throws { self.state = state }
}
