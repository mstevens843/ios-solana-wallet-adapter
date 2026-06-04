import Foundation
import SolanaWalletAdapterCore

/// Simulator-only wallet responder for exercising the full iWA URL, encryption,
/// callback, and decoding path without installing a real wallet app.
///
/// Do not use this as a production wallet and do not add it to
/// `WalletProviderRegistry`.
public struct SimulatorMockWalletProvider: WalletProvider {
    public let walletId = "simulator-mock"
    public let universalLinkHost = "mock.iwa.local"
    public let customScheme = "iwa-mock"

    public init() {}

    public var capabilities: WalletProviderCapabilities {
        WalletProviderCapabilities(
            walletId: walletId,
            displayName: "Mock Wallet (Simulator)",
            universalLinkHost: universalLinkHost,
            customScheme: customScheme,
            methods: WalletMethod.nativeDeeplinkProtocolMethods.map { WalletMethodSupport(method: $0) },
            featureIdentifiers: ["simulator-only", "test-harness"]
        )
    }

    public func connectURL(request: ConnectRequest) throws -> URL {
        try DeeplinkURL.make(
            host: DeeplinkURL.WalletHost(
                universalLinkHost: universalLinkHost,
                customScheme: customScheme
            ),
            method: "connect",
            params: [
                ("app_url", request.appURL.absoluteString),
                ("dapp_encryption_public_key", request.dappEncryptionPublicKey),
                ("redirect_link", request.redirectLink.absoluteString),
                ("cluster", request.cluster.rawValue),
            ]
        )
    }
}

/// Local wallet-side simulator for `SimulatorMockWalletProvider`.
public final class SimulatorMockWalletResponder: @unchecked Sendable {
    public let keypair: EphemeralKeypair
    public let userPublicKey: String
    public let sessionToken: String
    public let messageSignature: Data
    public let transactionSignature: String

    public init(
        keypair: EphemeralKeypair = .generate(),
        userPublicKey: String = "Mock111111111111111111111111111111111111111",
        sessionToken: String = "mock-session-token",
        messageSignature: Data = Data((0..<64).map(UInt8.init)),
        transactionSignature: String = Base58.encode(Data((64..<128).map(UInt8.init)))
    ) {
        self.keypair = keypair
        self.userPublicKey = userPublicKey
        self.sessionToken = sessionToken
        self.messageSignature = messageSignature
        self.transactionSignature = transactionSignature
    }

    /// Returns the callback URL the wallet would open, or `nil` for accepted
    /// methods such as disconnect that do not need a callback in this adapter.
    public func callback(for walletURL: URL, redirectLink: URL) throws -> URL? {
        let method = methodName(from: walletURL)
        let params = queryParameters(walletURL)
        switch method {
        case "connect":
            return try connectCallback(params: params, redirectLink: redirectLink)
        case "disconnect":
            _ = try encryptedRequestPayload(params: params, redirectLink: redirectLink)
            return nil
        case "signMessage":
            let payload = try encryptedRequestPayload(params: params, redirectLink: redirectLink)
            guard payload["session"] as? String == sessionToken else {
                return try errorCallback(code: "INVALID_SESSION", message: "Mock wallet session mismatch.", redirectLink: redirectLink)
            }
            return try encryptedCallback(
                payload: ["signature": Base58.encode(messageSignature)],
                params: params,
                redirectLink: redirectLink
            )
        case "signTransaction":
            let payload = try encryptedRequestPayload(params: params, redirectLink: redirectLink)
            guard payload["session"] as? String == sessionToken else {
                return try errorCallback(code: "INVALID_SESSION", message: "Mock wallet session mismatch.", redirectLink: redirectLink)
            }
            guard let transaction = payload["transaction"] as? String else {
                return try errorCallback(code: "MALFORMED_PAYLOAD", message: "Mock signTransaction missing transaction.", redirectLink: redirectLink)
            }
            return try encryptedCallback(payload: ["transaction": transaction], params: params, redirectLink: redirectLink)
        case "signAllTransactions":
            let payload = try encryptedRequestPayload(params: params, redirectLink: redirectLink)
            guard payload["session"] as? String == sessionToken else {
                return try errorCallback(code: "INVALID_SESSION", message: "Mock wallet session mismatch.", redirectLink: redirectLink)
            }
            guard let transactions = payload["transactions"] as? [String] else {
                return try errorCallback(code: "MALFORMED_PAYLOAD", message: "Mock signAllTransactions missing transactions.", redirectLink: redirectLink)
            }
            return try encryptedCallback(payload: ["transactions": transactions], params: params, redirectLink: redirectLink)
        case "signAndSendTransaction":
            let payload = try encryptedRequestPayload(params: params, redirectLink: redirectLink)
            guard payload["session"] as? String == sessionToken else {
                return try errorCallback(code: "INVALID_SESSION", message: "Mock wallet session mismatch.", redirectLink: redirectLink)
            }
            return try encryptedCallback(payload: ["signature": transactionSignature], params: params, redirectLink: redirectLink)
        default:
            return try errorCallback(code: "UNSUPPORTED_METHOD", message: "Mock wallet does not support \(method).", redirectLink: redirectLink)
        }
    }

    private func connectCallback(params: [String: String], redirectLink: URL) throws -> URL {
        guard let dappKeyString = params["dapp_encryption_public_key"],
              let dappKey = Base58.decode(dappKeyString),
              dappKey.count == NaClBox.keyLength else {
            return try errorCallback(code: "MALFORMED_PAYLOAD", message: "Mock connect missing dapp key.", redirectLink: redirectLink)
        }
        return try encryptedCallback(
            payload: [
                "public_key": userPublicKey,
                "session": sessionToken,
            ],
            dappPublicKey: dappKey,
            redirectLink: redirectLink,
            extraQueryItems: [
                URLQueryItem(name: "wallet_encryption_public_key", value: Base58.encode(keypair.publicKey)),
            ]
        )
    }

    private func encryptedRequestPayload(params: [String: String], redirectLink: URL) throws -> [String: Any] {
        guard let dappKeyString = params["dapp_encryption_public_key"],
              let dappKey = Base58.decode(dappKeyString),
              dappKey.count == NaClBox.keyLength,
              let nonceString = params["nonce"],
              let nonce = Base58.decode(nonceString),
              nonce.count == NaClBox.nonceLength,
              let payloadString = params["payload"],
              let payload = Base58.decode(payloadString),
              let plaintext = NaClBox.open(
                  box: payload,
                  nonce: nonce,
                  theirPublicKey: dappKey,
                  mySecretKey: keypair.secretKey
              ),
              let object = try JSONSerialization.jsonObject(with: plaintext) as? [String: Any] else {
            throw WalletAdapterError.malformedPayload("Mock wallet could not decrypt request for \(WalletAdapterDebugFormatter.urlShape(redirectLink)).")
        }
        return object
    }

    private func encryptedCallback(
        payload: [String: Any],
        params: [String: String],
        redirectLink: URL
    ) throws -> URL {
        guard let dappKeyString = params["dapp_encryption_public_key"],
              let dappKey = Base58.decode(dappKeyString),
              dappKey.count == NaClBox.keyLength else {
            return try errorCallback(code: "MALFORMED_PAYLOAD", message: "Mock callback missing dapp key.", redirectLink: redirectLink)
        }
        return try encryptedCallback(payload: payload, dappPublicKey: dappKey, redirectLink: redirectLink)
    }

    private func encryptedCallback(
        payload: [String: Any],
        dappPublicKey: Data,
        redirectLink: URL,
        extraQueryItems: [URLQueryItem] = []
    ) throws -> URL {
        guard JSONSerialization.isValidJSONObject(payload) else {
            throw WalletAdapterError.malformedPayload("Mock response payload is not valid JSON.")
        }
        let plaintext = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let nonce = NaClBox.randomNonce()
        let sealed = NaClBox.seal(
            message: plaintext,
            nonce: nonce,
            theirPublicKey: dappPublicKey,
            mySecretKey: keypair.secretKey
        )
        guard !sealed.isEmpty else {
            throw WalletAdapterError.malformedPayload("Mock wallet could not encrypt callback.")
        }
        return try callbackURL(
            redirectLink: redirectLink,
            queryItems: extraQueryItems + [
                URLQueryItem(name: "nonce", value: Base58.encode(nonce)),
                URLQueryItem(name: "data", value: Base58.encode(sealed)),
            ]
        )
    }

    private func errorCallback(code: String, message: String, redirectLink: URL) throws -> URL {
        try callbackURL(
            redirectLink: redirectLink,
            queryItems: [
                URLQueryItem(name: "errorCode", value: code),
                URLQueryItem(name: "errorMessage", value: message),
            ]
        )
    }

    private func callbackURL(redirectLink: URL, queryItems: [URLQueryItem]) throws -> URL {
        guard var components = URLComponents(url: redirectLink, resolvingAgainstBaseURL: false) else {
            throw WalletAdapterError.malformedPayload("Mock redirectLink is not a valid URL.")
        }
        components.queryItems = (components.queryItems ?? []) + queryItems
        guard let url = components.url else {
            throw WalletAdapterError.malformedPayload("Mock callback URL could not be built.")
        }
        return url
    }

    private func methodName(from url: URL) -> String {
        url.path.split(separator: "/").last.map(String.init) ?? ""
    }

    private func queryParameters(_ url: URL) -> [String: String] {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: items.compactMap { item in
            item.value.map { (item.name, $0) }
        })
    }
}
