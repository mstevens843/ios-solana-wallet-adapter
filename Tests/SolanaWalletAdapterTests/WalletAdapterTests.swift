import XCTest
import SolanaWalletAdapter
import SolanaWalletAdapterCore
import SolanaWalletAdapterPhantom

final class WalletAdapterTests: XCTestCase {
    private let dapp = EphemeralKeypair(
        publicKey: Base58.decode("WpSggvhoqoVW4XJvfjsB52dvVunYSQWrz6XiuMQVsCf")!,
        secretKey: Base58.decode("4wBqpZM9xaSheZzJSMawUKKwhdpChKbZ5eu5ky4Vigw")!
    )
    private let wallet = EphemeralKeypair(
        publicKey: Base58.decode("6rvZvM15TRkYozYPXwXPiAMFpXPmiVoTPtCT6uqSLd1X")!,
        secretKey: Base58.decode("7ppk9w8NHnH6ehajvJyU31VcMafwZ3ybRtJWumSyD2wd")!
    )
    private let nonce = Base58.decode("KPym5Vq98pYDgiKHQQu8Ty122PDwRNgJ3")!
    private let redirect = URL(string: "myapp://wallet/callback")!
    private let appURL = URL(string: "https://example.com")!

    func testInitializerGeneratesRealKeypairByDefault() {
        let adapter = WalletAdapter(provider: PhantomAdapter())
        XCTAssertEqual(adapter.keypair.publicKey.count, 32)
        XCTAssertEqual(adapter.keypair.secretKey.count, 32)
        XCTAssertNil(adapter.session)
    }

    func testConnectURLUsesAdapterKeypairAndCluster() throws {
        let adapter = WalletAdapter(provider: PhantomAdapter(), keypair: dapp)
        let url = try adapter.connectURL(appURL: appURL, redirectLink: redirect, cluster: .devnet)
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let params = queryParams(url)

        XCTAssertEqual(components.host, "phantom.app")
        XCTAssertEqual(components.path, "/ul/v1/connect")
        XCTAssertEqual(params["dapp_encryption_public_key"], Base58.encode(dapp.publicKey))
        XCTAssertEqual(params["redirect_link"], redirect.absoluteString)
        XCTAssertEqual(params["app_url"], appURL.absoluteString)
        XCTAssertEqual(params["cluster"], "devnet")
        XCTAssertEqual(adapter.cluster, .devnet)
    }

    func testHandleConnectCallbackStoresSession() throws {
        let adapter = WalletAdapter(provider: PhantomAdapter(), keypair: dapp, cluster: .devnet)
        let callback = try responseURL(
            publicKeyAlias: "phantom_encryption_public_key",
            payload: ["public_key": "User1111111111111111111111111111111111", "session": "session-123"]
        )

        let session = try adapter.handleConnectCallback(callback)
        XCTAssertEqual(session.token, "session-123")
        XCTAssertEqual(adapter.session, session)
    }

    func testSigningURLsRequireSession() {
        let adapter = WalletAdapter(provider: PhantomAdapter(), keypair: dapp)
        XCTAssertThrowsError(try adapter.signMessageURL(Data("hello".utf8), redirectLink: redirect)) { error in
            XCTAssertEqual(error as? WalletAdapterError, .invalidSession)
        }
    }

    func testSigningURLUsesStoredSessionAndEncryptedPayload() throws {
        let adapter = try connectedAdapter()
        let url = try adapter.signMessageURL(Data("hello".utf8), redirectLink: redirect)
        let params = queryParams(url)

        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.path, "/ul/v1/signMessage")
        XCTAssertEqual(params["dapp_encryption_public_key"], Base58.encode(dapp.publicKey))
        XCTAssertEqual(params["redirect_link"], redirect.absoluteString)
        XCTAssertNotNil(params["nonce"])
        XCTAssertNotNil(params["payload"])

        let payload = try decryptRequestPayload(url)
        XCTAssertEqual(payload["session"] as? String, "session-123")
        XCTAssertEqual(payload["message"] as? String, Base58.encode(Data("hello".utf8)))
        XCTAssertEqual(payload["display"] as? String, "utf8")
    }

    func testSigningCallbackDecodersUseStoredSession() throws {
        let adapter = try connectedAdapter()
        let signature = Data(Array(0..<64).map(UInt8.init))
        let signedTransaction = Data([1, 2, 3, 4])
        let txid = "Txid111111111111111111111111111111111111"

        let signMessage = try responseURL(payload: ["signature": Base58.encode(signature)])
        XCTAssertEqual(try adapter.handleSignMessageCallback(signMessage).signature, signature)

        let signTransaction = try responseURL(payload: ["transaction": Base58.encode(signedTransaction)])
        XCTAssertEqual(try adapter.handleSignTransactionCallback(signTransaction).transaction, signedTransaction)

        let signAndSend = try responseURL(payload: ["signature": txid])
        XCTAssertEqual(try adapter.handleSignAndSendTransactionCallback(signAndSend).signature, txid)
    }

    func testDisconnectURLIncludesEncryptedSessionProof() throws {
        let adapter = try connectedAdapter()
        let url = try adapter.disconnectURL(redirectLink: redirect)
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.path, "/ul/v1/disconnect")
        let payload = try decryptRequestPayload(url)
        XCTAssertEqual(payload["session"] as? String, "session-123")
    }

    func testClearSessionResetsSigningState() throws {
        let adapter = try connectedAdapter()
        adapter.clearSession()
        XCTAssertNil(adapter.session)
        XCTAssertThrowsError(try adapter.signTransactionURL(Data([1, 2, 3]), redirectLink: redirect)) { error in
            XCTAssertEqual(error as? WalletAdapterError, .invalidSession)
        }
    }

    private func connectedAdapter() throws -> WalletAdapter {
        let adapter = WalletAdapter(provider: PhantomAdapter(), keypair: dapp, cluster: .devnet)
        let callback = try responseURL(payload: ["public_key": "User1111111111111111111111111111111111", "session": "session-123"])
        _ = try adapter.handleConnectCallback(callback)
        return adapter
    }

    private func responseURL(
        publicKeyAlias: String = "phantom_encryption_public_key",
        payload: [String: Any]
    ) throws -> URL {
        let plaintext = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let box = NaClBox.seal(message: plaintext, nonce: nonce, theirPublicKey: dapp.publicKey, mySecretKey: wallet.secretKey)
        var components = URLComponents(string: redirect.absoluteString)!
        components.queryItems = [
            URLQueryItem(name: publicKeyAlias, value: Base58.encode(wallet.publicKey)),
            URLQueryItem(name: "nonce", value: Base58.encode(nonce)),
            URLQueryItem(name: "data", value: Base58.encode(box)),
        ]
        return components.url!
    }

    private func decryptRequestPayload(_ url: URL) throws -> [String: Any] {
        let params = queryParams(url)
        let requestNonce = Base58.decode(params["nonce"]!)!
        let box = Base58.decode(params["payload"]!)!
        let plaintext = NaClBox.open(box: box, nonce: requestNonce, theirPublicKey: dapp.publicKey, mySecretKey: wallet.secretKey)!
        return try JSONSerialization.jsonObject(with: plaintext) as! [String: Any]
    }

    private func queryParams(_ url: URL) -> [String: String] {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }
}
