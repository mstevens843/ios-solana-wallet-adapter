import XCTest
import SolanaWalletAdapter
import SolanaWalletAdapterCore

final class SimulatorMockWalletTests: XCTestCase {
    private let appURL = URL(string: "https://example.com")!
    private let redirect = URL(string: "iwademo://wallet/callback")!

    func testMockWalletExercisesConnectSignAndDisconnectPath() throws {
        let mockWallet = SimulatorMockWalletResponder()
        let adapter = WalletAdapter(
            provider: SimulatorMockWalletProvider(),
            keypair: .generate(),
            cluster: .devnet
        )

        let connectURL = try adapter.connectURL(appURL: appURL, redirectLink: redirect)
        let connectCallback = try XCTUnwrap(mockWallet.callback(for: connectURL, redirectLink: redirect))
        let session = try adapter.handleConnectCallback(connectCallback)

        XCTAssertEqual(session.userPublicKey, mockWallet.userPublicKey)
        XCTAssertEqual(session.token, mockWallet.sessionToken)

        let signURL = try adapter.signMessageURL(Data("simulator smoke".utf8), redirectLink: redirect)
        let signCallback = try XCTUnwrap(mockWallet.callback(for: signURL, redirectLink: redirect))
        let result = try adapter.handleSignMessageCallback(signCallback)

        XCTAssertEqual(result.signature, mockWallet.messageSignature)

        let disconnectURL = try adapter.disconnectURL(redirectLink: redirect)
        XCTAssertNil(try mockWallet.callback(for: disconnectURL, redirectLink: redirect))
    }

    func testMockWalletReturnsWalletErrorForSessionMismatch() throws {
        let mockWallet = SimulatorMockWalletResponder()
        let adapter = WalletAdapter(
            provider: SimulatorMockWalletProvider(),
            keypair: .generate(),
            cluster: .devnet
        )

        let connectURL = try adapter.connectURL(appURL: appURL, redirectLink: redirect)
        let connectCallback = try XCTUnwrap(mockWallet.callback(for: connectURL, redirectLink: redirect))
        _ = try adapter.handleConnectCallback(connectCallback)
        adapter.restoreSession(Session(
            walletEncryptionPublicKey: mockWallet.keypair.publicKey,
            token: "wrong-session",
            userPublicKey: mockWallet.userPublicKey
        ))

        let signURL = try adapter.signMessageURL(Data("simulator smoke".utf8), redirectLink: redirect)
        let signCallback = try XCTUnwrap(mockWallet.callback(for: signURL, redirectLink: redirect))

        XCTAssertThrowsError(try adapter.handleSignMessageCallback(signCallback)) { error in
            XCTAssertEqual(error as? WalletAdapterError, .invalidSession)
        }
    }
}
