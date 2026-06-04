import XCTest
import SolanaWalletAdapter
import SolanaWalletAdapterCore
import SolanaWalletAdapterPhantom
import SolanaWalletAdapterUI

@MainActor
final class WalletAdapterClientConnectKeypairTests: XCTestCase {
    private let appURL = URL(string: "https://example.com")!
    private let redirect = URL(string: "iwademo://wallet/callback")!

    /// `rotateEphemeralKeypair()` must change the dapp encryption keypair used by
    /// the next connect, so a soft logout + reconnect produces a clean handshake
    /// (recovers from a desynced session the wallet would reject).
    func testRotateEphemeralKeypairChangesDappKey() async {
        let opener = CapturingConnectOpener()
        let client = WalletAdapterClient(
            provider: PhantomAdapter(),
            appURL: appURL,
            redirectLink: redirect,
            cluster: .mainnetBeta,
            opener: opener
        )

        // The opener returns false, so connect() fails fast (no callback to
        // await) but still captures the dapp key from the connect URL it built.
        _ = try? await client.connect()
        let firstKey = opener.lastDappKey

        client.rotateEphemeralKeypair()
        _ = try? await client.connect()
        let secondKey = opener.lastDappKey

        XCTAssertNotNil(firstKey)
        XCTAssertNotNil(secondKey)
        XCTAssertNotEqual(firstKey, secondKey, "rotateEphemeralKeypair() should change the dapp encryption keypair")
    }

    /// Rotation is a no-op while a session is active (it would orphan the live
    /// session), so the dapp key is unchanged.
    func testRotateIsNoOpWhenSessionActive() async {
        let opener = CapturingConnectOpener()
        let client = WalletAdapterClient(
            provider: PhantomAdapter(),
            appURL: appURL,
            redirectLink: redirect,
            cluster: .mainnetBeta,
            opener: opener
        )
        client.adapter.restoreSession(
            Session(
                walletEncryptionPublicKey: Data(repeating: 1, count: 32),
                token: "session-token",
                userPublicKey: "User1111111111111111111111111111111111"
            )
        )

        _ = try? await client.connect()
        let firstKey = opener.lastDappKey
        client.rotateEphemeralKeypair()   // no-op: session is active
        _ = try? await client.connect()
        let secondKey = opener.lastDappKey

        XCTAssertNotNil(firstKey)
        XCTAssertEqual(firstKey, secondKey, "rotate must be a no-op while a session is active")
    }
}

@MainActor
private final class CapturingConnectOpener: WalletURLOpening {
    var lastDappKey: String?
    func openWalletURL(_ url: URL) async -> Bool {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        lastDappKey = items.first(where: { $0.name == "dapp_encryption_public_key" })?.value
        return false
    }
}
