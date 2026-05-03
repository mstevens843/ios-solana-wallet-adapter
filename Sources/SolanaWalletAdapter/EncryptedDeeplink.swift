import Foundation
import SolanaWalletAdapterCore

public enum WalletSigningDisplay: String, Sendable {
    case utf8
    case hex
}

public struct SignMessageResult: Equatable, Sendable {
    public let signature: Data

    public init(signature: Data) {
        self.signature = signature
    }
}

public struct SignTransactionResult: Equatable, Sendable {
    public let transaction: Data

    public init(transaction: Data) {
        self.transaction = transaction
    }
}

public struct SignAllTransactionsResult: Equatable, Sendable {
    public let transactions: [Data]

    public init(transactions: [Data]) {
        self.transactions = transactions
    }
}

public struct SignAndSendTransactionResult: Equatable, Sendable {
    public let signature: String

    public init(signature: String) {
        self.signature = signature
    }
}

public extension WalletProvider {
    func disconnectURL(
        session: Session,
        keypair: EphemeralKeypair,
        redirectLink: URL,
        nonce: Data = NaClBox.randomNonce()
    ) throws -> URL {
        try encryptedURL(
            method: "disconnect",
            payload: ["session": session.token],
            session: session,
            keypair: keypair,
            redirectLink: redirectLink,
            nonce: nonce
        )
    }

    func signMessageURL(
        message: Data,
        session: Session,
        keypair: EphemeralKeypair,
        redirectLink: URL,
        display: WalletSigningDisplay = .utf8,
        nonce: Data = NaClBox.randomNonce()
    ) throws -> URL {
        try encryptedURL(
            method: "signMessage",
            payload: [
                "message": Base58.encode(message),
                "session": session.token,
                "display": display.rawValue,
            ],
            session: session,
            keypair: keypair,
            redirectLink: redirectLink,
            nonce: nonce
        )
    }

    func signTransactionURL(
        transaction: Data,
        session: Session,
        keypair: EphemeralKeypair,
        redirectLink: URL,
        nonce: Data = NaClBox.randomNonce()
    ) throws -> URL {
        try encryptedURL(
            method: "signTransaction",
            payload: [
                "transaction": Base58.encode(transaction),
                "session": session.token,
            ],
            session: session,
            keypair: keypair,
            redirectLink: redirectLink,
            nonce: nonce
        )
    }

    func signAllTransactionsURL(
        transactions: [Data],
        session: Session,
        keypair: EphemeralKeypair,
        redirectLink: URL,
        nonce: Data = NaClBox.randomNonce()
    ) throws -> URL {
        try encryptedURL(
            method: "signAllTransactions",
            payload: [
                "transactions": transactions.map(Base58.encode),
                "session": session.token,
            ],
            session: session,
            keypair: keypair,
            redirectLink: redirectLink,
            nonce: nonce
        )
    }

    func signAndSendTransactionURL(
        transaction: Data,
        session: Session,
        keypair: EphemeralKeypair,
        redirectLink: URL,
        sendOptions: SendOptions = .init(),
        nonce: Data = NaClBox.randomNonce()
    ) throws -> URL {
        var options: [String: Any] = ["skipPreflight": sendOptions.skipPreflight]
        if let preflightCommitment = sendOptions.preflightCommitment {
            options["preflightCommitment"] = preflightCommitment
        }
        if let maxRetries = sendOptions.maxRetries {
            options["maxRetries"] = maxRetries
        }
        return try encryptedURL(
            method: "signAndSendTransaction",
            payload: [
                "transaction": Base58.encode(transaction),
                "session": session.token,
                "sendOptions": options,
            ],
            session: session,
            keypair: keypair,
            redirectLink: redirectLink,
            nonce: nonce
        )
    }

    private func encryptedURL(
        method: String,
        payload: [String: Any],
        session: Session,
        keypair: EphemeralKeypair,
        redirectLink: URL,
        nonce: Data
    ) throws -> URL {
        guard JSONSerialization.isValidJSONObject(payload) else {
            throw WalletAdapterError.malformedPayload("Payload is not valid JSON.")
        }
        let payloadData = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let sealed = NaClBox.seal(
            message: payloadData,
            nonce: nonce,
            theirPublicKey: session.walletEncryptionPublicKey,
            mySecretKey: keypair.secretKey
        )
        guard !sealed.isEmpty else {
            throw WalletAdapterError.malformedPayload("Unable to encrypt payload.")
        }
        let host = DeeplinkURL.WalletHost(
            universalLinkHost: universalLinkHost,
            customScheme: customScheme
        )
        return try DeeplinkURL.make(
            host: host,
            method: method,
            params: [
                ("dapp_encryption_public_key", Base58.encode(keypair.publicKey)),
                ("nonce", Base58.encode(nonce)),
                ("redirect_link", redirectLink.absoluteString),
                ("payload", Base58.encode(sealed)),
            ]
        )
    }
}

public enum WalletResponseDecoder {
    public static func error(from url: URL, expectedCluster: Cluster = .mainnetBeta) -> WalletAdapterError? {
        let params = queryParameters(url)
        guard let code = params["errorCode"] else { return nil }
        return mapError(code: code, message: params["errorMessage"] ?? "", expectedCluster: expectedCluster)
    }

    public static func connectSession(from url: URL, keypair: EphemeralKeypair, expectedCluster: Cluster = .mainnetBeta) throws -> Session {
        if let error = error(from: url, expectedCluster: expectedCluster) { throw error }
        let params = queryParameters(url)
        let walletKeyNames = [
            "phantom_encryption_public_key",
            "solflare_encryption_public_key",
            "wallet_encryption_public_key",
        ]
        guard let walletKeyString = walletKeyNames.compactMap({ params[$0] }).first,
              let walletKey = Base58.decode(walletKeyString),
              walletKey.count == NaClBox.keyLength else {
            throw WalletAdapterError.malformedPayload("Missing wallet encryption public key.")
        }
        let payload = try decryptDataPayload(from: params, theirPublicKey: walletKey, mySecretKey: keypair.secretKey)
        guard let publicKey = payload["public_key"] as? String,
              let token = payload["session"] as? String else {
            throw WalletAdapterError.malformedPayload("Connect response is missing public_key or session.")
        }
        return Session(walletEncryptionPublicKey: walletKey, token: token, userPublicKey: publicKey)
    }

    public static func signMessageResult(from url: URL, session: Session, keypair: EphemeralKeypair, expectedCluster: Cluster = .mainnetBeta) throws -> SignMessageResult {
        if let error = error(from: url, expectedCluster: expectedCluster) { throw error }
        let payload = try decryptDataPayload(from: queryParameters(url), theirPublicKey: session.walletEncryptionPublicKey, mySecretKey: keypair.secretKey)
        guard let encoded = payload["signature"] as? String,
              let signature = Base58.decode(encoded) else {
            throw WalletAdapterError.malformedPayload("Sign message response is missing signature.")
        }
        return SignMessageResult(signature: signature)
    }

    public static func signTransactionResult(from url: URL, session: Session, keypair: EphemeralKeypair, expectedCluster: Cluster = .mainnetBeta) throws -> SignTransactionResult {
        if let error = error(from: url, expectedCluster: expectedCluster) { throw error }
        let payload = try decryptDataPayload(from: queryParameters(url), theirPublicKey: session.walletEncryptionPublicKey, mySecretKey: keypair.secretKey)
        guard let encoded = payload["transaction"] as? String,
              let transaction = Base58.decode(encoded) else {
            throw WalletAdapterError.malformedPayload("Sign transaction response is missing transaction.")
        }
        return SignTransactionResult(transaction: transaction)
    }

    public static func signAllTransactionsResult(from url: URL, session: Session, keypair: EphemeralKeypair, expectedCluster: Cluster = .mainnetBeta) throws -> SignAllTransactionsResult {
        if let error = error(from: url, expectedCluster: expectedCluster) { throw error }
        let payload = try decryptDataPayload(from: queryParameters(url), theirPublicKey: session.walletEncryptionPublicKey, mySecretKey: keypair.secretKey)
        guard let encodedTransactions = payload["transactions"] as? [String] else {
            throw WalletAdapterError.malformedPayload("Sign all transactions response is missing transactions.")
        }
        let transactions = encodedTransactions.compactMap(Base58.decode)
        guard transactions.count == encodedTransactions.count else {
            throw WalletAdapterError.malformedPayload("Sign all transactions response contains invalid base58.")
        }
        return SignAllTransactionsResult(transactions: transactions)
    }

    public static func signAndSendTransactionResult(from url: URL, session: Session, keypair: EphemeralKeypair, expectedCluster: Cluster = .mainnetBeta) throws -> SignAndSendTransactionResult {
        if let error = error(from: url, expectedCluster: expectedCluster) { throw error }
        let payload = try decryptDataPayload(from: queryParameters(url), theirPublicKey: session.walletEncryptionPublicKey, mySecretKey: keypair.secretKey)
        guard let signature = payload["signature"] as? String else {
            throw WalletAdapterError.malformedPayload("Sign and send response is missing signature.")
        }
        return SignAndSendTransactionResult(signature: signature)
    }

    public static func mapError(code: String, message: String, expectedCluster: Cluster = .mainnetBeta) -> WalletAdapterError {
        switch code {
        case "USER_REJECTED":
            return .userRejected
        case "INVALID_SESSION":
            return .invalidSession
        case "UNSUPPORTED_METHOD":
            return .unsupportedMethod(message)
        case "MALFORMED_PAYLOAD":
            return .malformedPayload(message)
        case "WALLET_UNREACHABLE":
            return .walletUnreachable
        case "DECRYPTION_FAILED":
            return .decryptionFailed
        case "CLUSTER_MISMATCH":
            return .clusterMismatch(expected: expectedCluster, got: message)
        default:
            return .other(code: code, message: message)
        }
    }

    private static func decryptDataPayload(from params: [String: String], theirPublicKey: Data, mySecretKey: Data) throws -> [String: Any] {
        guard let nonceString = params["nonce"],
              let payloadString = params["data"],
              let nonce = Base58.decode(nonceString),
              let box = Base58.decode(payloadString) else {
            throw WalletAdapterError.malformedPayload("Response is missing nonce or data.")
        }
        guard let plaintext = NaClBox.open(box: box, nonce: nonce, theirPublicKey: theirPublicKey, mySecretKey: mySecretKey) else {
            throw WalletAdapterError.decryptionFailed
        }
        guard let json = try JSONSerialization.jsonObject(with: plaintext) as? [String: Any] else {
            throw WalletAdapterError.malformedPayload("Response data is not a JSON object.")
        }
        return json
    }

    private static func queryParameters(_ url: URL) -> [String: String] {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var result: [String: String] = [:]
        for item in components?.queryItems ?? [] {
            result[item.name] = item.value ?? ""
        }
        return result
    }
}
