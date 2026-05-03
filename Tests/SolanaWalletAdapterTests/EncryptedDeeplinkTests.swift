import XCTest
import SolanaWalletAdapter
import SolanaWalletAdapterCore
import SolanaWalletAdapterPhantom
import SolanaWalletAdapterSolflare
import SolanaWalletAdapterBackpack

final class EncryptedDeeplinkTests: XCTestCase {
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

    func testConnectResponseDecodingSupportsWalletPublicKeyAliases() throws {
        for alias in [
            "phantom_encryption_public_key",
            "solflare_encryption_public_key",
            "wallet_encryption_public_key",
        ] {
            let url = try responseURL(
                publicKeyAlias: alias,
                payload: ["public_key": "User1111111111111111111111111111111111", "session": "token-123"]
            )
            let session = try WalletResponseDecoder.connectSession(from: url, keypair: dapp)
            XCTAssertEqual(session.walletEncryptionPublicKey, wallet.publicKey)
            XCTAssertEqual(session.token, "token-123")
            XCTAssertEqual(session.userPublicKey, "User1111111111111111111111111111111111")
        }
    }

    func testSigningPayloadBuildersEmitMethodPathsAndRequiredParams() throws {
        let session = Session(walletEncryptionPublicKey: wallet.publicKey, token: "token-123", userPublicKey: "user")
        let cases: [(String, URL, String)] = [
            ("signMessage", try PhantomAdapter().signMessageURL(message: Data([1, 2, 3]), session: session, keypair: dapp, redirectLink: redirect, nonce: nonce), "message"),
            ("signTransaction", try SolflareAdapter().signTransactionURL(transaction: Data([4, 5, 6]), session: session, keypair: dapp, redirectLink: redirect, nonce: nonce), "transaction"),
            ("signAllTransactions", try BackpackAdapter().signAllTransactionsURL(transactions: [Data([7]), Data([8])], session: session, keypair: dapp, redirectLink: redirect, nonce: nonce), "transactions"),
            ("signAndSendTransaction", try PhantomAdapter().signAndSendTransactionURL(transaction: Data([9]), session: session, keypair: dapp, redirectLink: redirect, sendOptions: .init(skipPreflight: true, preflightCommitment: "confirmed", maxRetries: 3), nonce: nonce), "sendOptions"),
            ("disconnect", try SolflareAdapter().disconnectURL(session: session, keypair: dapp, redirectLink: redirect, nonce: nonce), "session"),
        ]

        for (method, url, payloadKey) in cases {
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            XCTAssertEqual(components.path, "/ul/v1/\(method)")
            let params = queryParams(url)
            XCTAssertEqual(params["dapp_encryption_public_key"], Base58.encode(dapp.publicKey))
            XCTAssertEqual(params["nonce"], Base58.encode(nonce))
            XCTAssertEqual(params["redirect_link"], redirect.absoluteString)
            XCTAssertNotNil(params["payload"])
            let payload = try decryptRequestPayload(url)
            XCTAssertNotNil(payload[payloadKey], "\(method) payload is missing \(payloadKey)")
            XCTAssertEqual(payload["session"] as? String, session.token)
        }
    }

    func testEncryptedResponseDecodingForSigningResults() throws {
        let session = Session(walletEncryptionPublicKey: wallet.publicKey, token: "token-123", userPublicKey: "user")
        let signature = Data(Array(0..<64).map(UInt8.init))
        let signedTransaction = Data([1, 3, 5, 7])
        let firstTransaction = Data([2, 4])
        let secondTransaction = Data([6, 8])

        let signMessageURL = try responseURL(payload: ["signature": Base58.encode(signature)])
        XCTAssertEqual(try WalletResponseDecoder.signMessageResult(from: signMessageURL, session: session, keypair: dapp).signature, signature)

        let signTransactionURL = try responseURL(payload: ["transaction": Base58.encode(signedTransaction)])
        XCTAssertEqual(try WalletResponseDecoder.signTransactionResult(from: signTransactionURL, session: session, keypair: dapp).transaction, signedTransaction)

        let allTransactionsURL = try responseURL(payload: ["transactions": [Base58.encode(firstTransaction), Base58.encode(secondTransaction)]])
        XCTAssertEqual(try WalletResponseDecoder.signAllTransactionsResult(from: allTransactionsURL, session: session, keypair: dapp).transactions, [firstTransaction, secondTransaction])

        let signAndSendURL = try responseURL(payload: ["signature": "Txid111111111111111111111111111111111111"])
        XCTAssertEqual(try WalletResponseDecoder.signAndSendTransactionResult(from: signAndSendURL, session: session, keypair: dapp).signature, "Txid111111111111111111111111111111111111")
    }

    func testDocumentedErrorCodesMapToWalletAdapterErrors() {
        XCTAssertEqual(WalletResponseDecoder.mapError(code: "USER_REJECTED", message: "no"), .userRejected)
        XCTAssertEqual(WalletResponseDecoder.mapError(code: "INVALID_SESSION", message: "bad"), .invalidSession)
        XCTAssertEqual(WalletResponseDecoder.mapError(code: "UNSUPPORTED_METHOD", message: "old"), .unsupportedMethod("old"))
        XCTAssertEqual(WalletResponseDecoder.mapError(code: "MALFORMED_PAYLOAD", message: "json"), .malformedPayload("json"))
        XCTAssertEqual(WalletResponseDecoder.mapError(code: "WALLET_UNREACHABLE", message: "missing"), .walletUnreachable)
        XCTAssertEqual(WalletResponseDecoder.mapError(code: "DECRYPTION_FAILED", message: "auth"), .decryptionFailed)
        XCTAssertEqual(WalletResponseDecoder.mapError(code: "CLUSTER_MISMATCH", message: "devnet"), .clusterMismatch(expected: .mainnetBeta, got: "devnet"))
        XCTAssertEqual(WalletResponseDecoder.mapError(code: "SOMETHING_ELSE", message: "raw"), .other(code: "SOMETHING_ELSE", message: "raw"))
    }

    private func responseURL(publicKeyAlias: String = "phantom_encryption_public_key", payload: [String: Any]) throws -> URL {
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
