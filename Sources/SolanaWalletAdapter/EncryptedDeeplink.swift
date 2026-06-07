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
        nonce: Data = NaClBox.randomNonce(),
        logger: any WalletAdapterLogger = WalletAdapterLoggers.disabled,
        logLevel: WalletAdapterLogLevel = .off,
        payloadPolicy: WalletAdapterLogPayloadPolicy = .redacted
    ) throws -> URL {
        try encryptedURL(
            method: "disconnect",
            payload: ["session": session.token],
            session: session,
            keypair: keypair,
            redirectLink: redirectLink,
            nonce: nonce,
            logger: logger,
            logLevel: logLevel,
            payloadPolicy: payloadPolicy
        )
    }

    func signMessageURL(
        message: Data,
        session: Session,
        keypair: EphemeralKeypair,
        redirectLink: URL,
        display: WalletSigningDisplay = .utf8,
        nonce: Data = NaClBox.randomNonce(),
        logger: any WalletAdapterLogger = WalletAdapterLoggers.disabled,
        logLevel: WalletAdapterLogLevel = .off,
        payloadPolicy: WalletAdapterLogPayloadPolicy = .redacted
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
            nonce: nonce,
            logger: logger,
            logLevel: logLevel,
            payloadPolicy: payloadPolicy
        )
    }

    func signTransactionURL(
        transaction: Data,
        session: Session,
        keypair: EphemeralKeypair,
        redirectLink: URL,
        nonce: Data = NaClBox.randomNonce(),
        logger: any WalletAdapterLogger = WalletAdapterLoggers.disabled,
        logLevel: WalletAdapterLogLevel = .off,
        payloadPolicy: WalletAdapterLogPayloadPolicy = .redacted
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
            nonce: nonce,
            logger: logger,
            logLevel: logLevel,
            payloadPolicy: payloadPolicy
        )
    }

    func signAllTransactionsURL(
        transactions: [Data],
        session: Session,
        keypair: EphemeralKeypair,
        redirectLink: URL,
        nonce: Data = NaClBox.randomNonce(),
        logger: any WalletAdapterLogger = WalletAdapterLoggers.disabled,
        logLevel: WalletAdapterLogLevel = .off,
        payloadPolicy: WalletAdapterLogPayloadPolicy = .redacted
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
            nonce: nonce,
            logger: logger,
            logLevel: logLevel,
            payloadPolicy: payloadPolicy
        )
    }

    func signAndSendTransactionURL(
        transaction: Data,
        session: Session,
        keypair: EphemeralKeypair,
        redirectLink: URL,
        sendOptions: SendOptions = .init(),
        nonce: Data = NaClBox.randomNonce(),
        logger: any WalletAdapterLogger = WalletAdapterLoggers.disabled,
        logLevel: WalletAdapterLogLevel = .off,
        payloadPolicy: WalletAdapterLogPayloadPolicy = .redacted
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
            nonce: nonce,
            logger: logger,
            logLevel: logLevel,
            payloadPolicy: payloadPolicy
        )
    }

    private func encryptedURL(
        method: String,
        payload: [String: Any],
        session: Session,
        keypair: EphemeralKeypair,
        redirectLink: URL,
        nonce: Data,
        logger: any WalletAdapterLogger,
        logLevel: WalletAdapterLogLevel,
        payloadPolicy: WalletAdapterLogPayloadPolicy
    ) throws -> URL {
        guard JSONSerialization.isValidJSONObject(payload) else {
            let error = WalletAdapterError.malformedPayload("Payload is not valid JSON.")
            log(logger, logLevel, "encryptedURL", "STEP_FAIL", .error, "request payload is not valid JSON", [
                "wallet": walletId,
                "method": method,
                "payload_description": "\(payload)",
            ].merging(WalletAdapterLogDiagnostics.failureMetadata(for: error)) { _, new in new })
            throw error
        }
        let payloadData = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        log(logger, logLevel, "encryptedURL", "STEP_1_PAYLOAD_JSON", .debug, "request payload serialized", [
            "wallet": walletId,
            "method": method,
            "payload_bytes": "\(payloadData.count)",
        ].merging(rawRequestMetadata(payload: payload, payloadData: payloadData, nonce: nonce, payloadPolicy: payloadPolicy)) { _, new in new })
        let sealed = NaClBox.seal(
            message: payloadData,
            nonce: nonce,
            theirPublicKey: session.walletEncryptionPublicKey,
            mySecretKey: keypair.secretKey
        )
        guard !sealed.isEmpty else {
            let error = WalletAdapterError.malformedPayload("Unable to encrypt payload.")
            log(logger, logLevel, "encryptedURL", "STEP_FAIL", .error, "request payload encryption failed", [
                "wallet": walletId,
                "method": method,
                "nonce_bytes": "\(nonce.count)",
                "wallet_public_key_bytes": "\(session.walletEncryptionPublicKey.count)",
                "dapp_secret_key_bytes": "\(keypair.secretKey.count)",
            ].merging(WalletAdapterLogDiagnostics.failureMetadata(for: error)) { _, new in new })
            throw error
        }
        log(logger, logLevel, "encryptedURL", "STEP_2_PAYLOAD_ENCRYPTED", .debug, "request payload encrypted", [
            "wallet": walletId,
            "method": method,
            "ciphertext_bytes": "\(sealed.count)",
            "nonce_bytes": "\(nonce.count)",
        ].merging(payloadPolicy.includesRawPayloads ? [
            "ciphertext_raw": Base58.encode(sealed),
            "nonce_raw": Base58.encode(nonce),
        ] : [:]) { _, new in new })
        let host = DeeplinkURL.WalletHost(
            universalLinkHost: universalLinkHost,
            customScheme: customScheme
        )
        return try DeeplinkURL.make(
            host: host,
            method: method,
            transport: deeplinkTransport,
            params: [
                ("dapp_encryption_public_key", Base58.encode(keypair.publicKey)),
                ("nonce", Base58.encode(nonce)),
                ("redirect_link", redirectLink.absoluteString),
                ("payload", Base58.encode(sealed)),
            ]
        )
    }

    private func rawRequestMetadata(
        payload: [String: Any],
        payloadData: Data,
        nonce: Data,
        payloadPolicy: WalletAdapterLogPayloadPolicy
    ) -> [String: String] {
        guard payloadPolicy.includesRawPayloads else { return [:] }
        return [
            "payload_json_raw": WalletAdapterDebugFormatter.json(payload),
            "payload_utf8_raw": WalletAdapterDebugFormatter.utf8OrBase58(payloadData),
            "nonce_raw": Base58.encode(nonce),
        ]
    }

    private func log(
        _ logger: any WalletAdapterLogger,
        _ logLevel: WalletAdapterLogLevel,
        _ method: String,
        _ step: String,
        _ level: WalletAdapterLogLevel,
        _ message: String,
        _ metadata: [String: String] = [:]
    ) {
        guard logLevel != .off, level <= logLevel else { return }
        logger.log(
            WalletAdapterLogEvent(
                component: "WalletProvider",
                method: method,
                step: step,
                phase: level == .error ? "FAIL" : "INFO",
                message: message,
                metadata: metadata
            )
        )
    }
}

public enum WalletResponseDecoder {
    public static func error(from url: URL, expectedCluster: Cluster = .mainnetBeta) -> WalletAdapterError? {
        let params = queryParameters(url)
        guard let code = params["errorCode"] else { return nil }
        return mapError(code: code, message: params["errorMessage"] ?? "", expectedCluster: expectedCluster)
    }

    public static func connectSession(
        from url: URL,
        keypair: EphemeralKeypair,
        expectedCluster: Cluster = .mainnetBeta,
        logger: any WalletAdapterLogger = WalletAdapterLoggers.disabled,
        logLevel: WalletAdapterLogLevel = .off,
        payloadPolicy: WalletAdapterLogPayloadPolicy = .redacted
    ) throws -> Session {
        let method = "connectSession"
        log(logger, logLevel, method, "STEP_1_START", .info, "decoding connect response", [
            "callback": WalletAdapterDebugFormatter.urlShape(url),
        ].merging(rawCallbackMetadata(url, payloadPolicy: payloadPolicy)) { _, new in new })
        if let error = error(from: url, expectedCluster: expectedCluster) {
            logWalletError(logger, logLevel, method, error, url, payloadPolicy)
            throw error
        }
        let params = queryParameters(url)
        log(logger, logLevel, method, "STEP_2_QUERY_PARSED", .debug, "query parameters parsed", [
            "query_keys": params.keys.sorted().joined(separator: ","),
        ])
        let walletKeyNames = [
            "phantom_encryption_public_key",
            "solflare_encryption_public_key",
            "jupiter_encryption_public_key",
            "wallet_encryption_public_key",
        ]
        guard let walletKeyName = walletEncryptionPublicKeyName(in: params, knownNames: walletKeyNames),
              let walletKeyString = params[walletKeyName] else {
            let error = WalletAdapterError.malformedPayload("Missing wallet encryption public key.")
            log(logger, logLevel, method, "STEP_FAIL", .error, "missing wallet encryption public key", [
                "expected_aliases": (walletKeyNames + ["wallet_*"]).joined(separator: ","),
            ].merging(WalletAdapterLogDiagnostics.failureMetadata(for: error)) { _, new in new })
            throw error
        }
        guard let walletKey = Base58.decode(walletKeyString), walletKey.count == NaClBox.keyLength else {
            let error = WalletAdapterError.malformedPayload("Missing wallet encryption public key.")
            log(logger, logLevel, method, "STEP_FAIL", .error, "invalid wallet encryption public key", [
                "alias": walletKeyName,
                "value": WalletAdapterDebugFormatter.shortBase58(walletKeyString),
            ].merging(WalletAdapterLogDiagnostics.failureMetadata(for: error)) { _, new in new })
            throw error
        }
        log(logger, logLevel, method, "STEP_3_WALLET_KEY_OK", .debug, "wallet encryption public key decoded", [
            "alias": walletKeyName,
            "wallet_public_key": WalletAdapterDebugFormatter.shortBase58(walletKeyString),
        ])
        let payload = try decryptDataPayload(from: params, theirPublicKey: walletKey, mySecretKey: keypair.secretKey, logger: logger, logLevel: logLevel, method: method, payloadPolicy: payloadPolicy)
        guard let publicKey = payload["public_key"] as? String,
              let token = payload["session"] as? String else {
            let error = WalletAdapterError.malformedPayload("Connect response is missing public_key or session.")
            log(logger, logLevel, method, "STEP_FAIL", .error, "connect response missing required fields", [
                "payload_keys": payload.keys.sorted().joined(separator: ","),
            ].merging(WalletAdapterLogDiagnostics.failureMetadata(for: error)) { _, new in new })
            throw error
        }
        log(logger, logLevel, method, "STEP_5_RESULT_DECODED", .info, "connect response decoded", [
            "user_public_key": WalletAdapterDebugFormatter.shortBase58(publicKey),
            "session_present": "true",
        ].merging(payloadPolicy.includesRawPayloads ? [
            "user_public_key_raw": publicKey,
            "session_token_raw": token,
            "wallet_encryption_public_key_raw": Base58.encode(walletKey),
        ] : [:]) { _, new in new })
        return Session(walletEncryptionPublicKey: walletKey, token: token, userPublicKey: publicKey)
    }

    private static func walletEncryptionPublicKeyName(in params: [String: String], knownNames: [String]) -> String? {
        if let knownName = knownNames.first(where: { params[$0] != nil }) {
            return knownName
        }
        return params.keys
            .filter { $0.hasPrefix("wallet_") }
            .sorted()
            .first
    }

    public static func signMessageResult(from url: URL, session: Session, keypair: EphemeralKeypair, expectedCluster: Cluster = .mainnetBeta, logger: any WalletAdapterLogger = WalletAdapterLoggers.disabled, logLevel: WalletAdapterLogLevel = .off, payloadPolicy: WalletAdapterLogPayloadPolicy = .redacted) throws -> SignMessageResult {
        let method = "signMessageResult"
        logDecodeStart(logger, logLevel, method, url, payloadPolicy)
        if let error = error(from: url, expectedCluster: expectedCluster) { logWalletError(logger, logLevel, method, error, url, payloadPolicy); throw error }
        let payload = try decryptDataPayload(from: queryParameters(url), theirPublicKey: session.walletEncryptionPublicKey, mySecretKey: keypair.secretKey, logger: logger, logLevel: logLevel, method: method, payloadPolicy: payloadPolicy)
        guard let encoded = payload["signature"] as? String,
              let signature = Base58.decode(encoded) else {
            logMissingResult(logger, logLevel, method, "signature", payload)
            throw WalletAdapterError.malformedPayload("Sign message response is missing signature.")
        }
        log(logger, logLevel, method, "STEP_5_RESULT_DECODED", .info, "sign message result decoded", [
            "signature_bytes": "\(signature.count)",
        ].merging(payloadPolicy.includesRawPayloads ? [
            "signature_raw": encoded,
        ] : [:]) { _, new in new })
        return SignMessageResult(signature: signature)
    }

    public static func signTransactionResult(from url: URL, session: Session, keypair: EphemeralKeypair, expectedCluster: Cluster = .mainnetBeta, logger: any WalletAdapterLogger = WalletAdapterLoggers.disabled, logLevel: WalletAdapterLogLevel = .off, payloadPolicy: WalletAdapterLogPayloadPolicy = .redacted) throws -> SignTransactionResult {
        let method = "signTransactionResult"
        logDecodeStart(logger, logLevel, method, url, payloadPolicy)
        if let error = error(from: url, expectedCluster: expectedCluster) { logWalletError(logger, logLevel, method, error, url, payloadPolicy); throw error }
        let payload = try decryptDataPayload(from: queryParameters(url), theirPublicKey: session.walletEncryptionPublicKey, mySecretKey: keypair.secretKey, logger: logger, logLevel: logLevel, method: method, payloadPolicy: payloadPolicy)
        guard let encoded = payload["transaction"] as? String,
              let transaction = Base58.decode(encoded) else {
            logMissingResult(logger, logLevel, method, "transaction", payload)
            throw WalletAdapterError.malformedPayload("Sign transaction response is missing transaction.")
        }
        log(logger, logLevel, method, "STEP_5_RESULT_DECODED", .info, "sign transaction result decoded", [
            "transaction_bytes": "\(transaction.count)",
        ].merging(payloadPolicy.includesRawPayloads ? [
            "transaction_raw": encoded,
        ] : [:]) { _, new in new })
        return SignTransactionResult(transaction: transaction)
    }

    public static func signAllTransactionsResult(from url: URL, session: Session, keypair: EphemeralKeypair, expectedCluster: Cluster = .mainnetBeta, logger: any WalletAdapterLogger = WalletAdapterLoggers.disabled, logLevel: WalletAdapterLogLevel = .off, payloadPolicy: WalletAdapterLogPayloadPolicy = .redacted) throws -> SignAllTransactionsResult {
        let method = "signAllTransactionsResult"
        logDecodeStart(logger, logLevel, method, url, payloadPolicy)
        if let error = error(from: url, expectedCluster: expectedCluster) { logWalletError(logger, logLevel, method, error, url, payloadPolicy); throw error }
        let payload = try decryptDataPayload(from: queryParameters(url), theirPublicKey: session.walletEncryptionPublicKey, mySecretKey: keypair.secretKey, logger: logger, logLevel: logLevel, method: method, payloadPolicy: payloadPolicy)
        guard let encodedTransactions = payload["transactions"] as? [String] else {
            logMissingResult(logger, logLevel, method, "transactions", payload)
            throw WalletAdapterError.malformedPayload("Sign all transactions response is missing transactions.")
        }
        let transactions = encodedTransactions.compactMap(Base58.decode)
        guard transactions.count == encodedTransactions.count else {
            let error = WalletAdapterError.malformedPayload("Sign all transactions response contains invalid base58.")
            log(logger, logLevel, method, "STEP_FAIL", .error, "invalid transaction base58 in response", [
                "transaction_count": "\(encodedTransactions.count)",
            ].merging(WalletAdapterLogDiagnostics.failureMetadata(for: error)) { _, new in new })
            throw error
        }
        log(logger, logLevel, method, "STEP_5_RESULT_DECODED", .info, "sign all transactions result decoded", [
            "transaction_count": "\(transactions.count)",
        ].merging(payloadPolicy.includesRawPayloads ? [
            "transactions_raw": encodedTransactions.joined(separator: ","),
        ] : [:]) { _, new in new })
        return SignAllTransactionsResult(transactions: transactions)
    }

    public static func signAndSendTransactionResult(from url: URL, session: Session, keypair: EphemeralKeypair, expectedCluster: Cluster = .mainnetBeta, logger: any WalletAdapterLogger = WalletAdapterLoggers.disabled, logLevel: WalletAdapterLogLevel = .off, payloadPolicy: WalletAdapterLogPayloadPolicy = .redacted) throws -> SignAndSendTransactionResult {
        let method = "signAndSendTransactionResult"
        logDecodeStart(logger, logLevel, method, url, payloadPolicy)
        if let error = error(from: url, expectedCluster: expectedCluster) { logWalletError(logger, logLevel, method, error, url, payloadPolicy); throw error }
        let payload = try decryptDataPayload(from: queryParameters(url), theirPublicKey: session.walletEncryptionPublicKey, mySecretKey: keypair.secretKey, logger: logger, logLevel: logLevel, method: method, payloadPolicy: payloadPolicy)
        guard let signature = payload["signature"] as? String else {
            logMissingResult(logger, logLevel, method, "signature", payload)
            throw WalletAdapterError.malformedPayload("Sign and send response is missing signature.")
        }
        guard Base58.decode(signature) != nil else {
            logMissingResult(logger, logLevel, method, "signature", payload)
            throw WalletAdapterError.malformedPayload("Sign and send response signature is not valid base58.")
        }
        log(logger, logLevel, method, "STEP_5_RESULT_DECODED", .info, "sign and send result decoded", [
            "txid": WalletAdapterDebugFormatter.shortBase58(signature),
        ].merging(payloadPolicy.includesRawPayloads ? [
            "txid_raw": signature,
        ] : [:]) { _, new in new })
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

    private static func decryptDataPayload(
        from params: [String: String],
        theirPublicKey: Data,
        mySecretKey: Data,
        logger: any WalletAdapterLogger,
        logLevel: WalletAdapterLogLevel,
        method: String,
        payloadPolicy: WalletAdapterLogPayloadPolicy
    ) throws -> [String: Any] {
        guard let nonceString = params["nonce"] else {
            let error = WalletAdapterError.malformedPayload("Response is missing nonce or data.")
            log(logger, logLevel, method, "STEP_FAIL", .error, "response missing nonce", [
                "query_keys": params.keys.sorted().joined(separator: ","),
                "query_raw": payloadPolicy.includesRawPayloads ? params.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "&") : "redacted",
            ].merging(WalletAdapterLogDiagnostics.failureMetadata(for: error)) { _, new in new })
            throw error
        }
        guard let payloadString = params["data"] else {
            let error = WalletAdapterError.malformedPayload("Response is missing nonce or data.")
            log(logger, logLevel, method, "STEP_FAIL", .error, "response missing data", [
                "query_keys": params.keys.sorted().joined(separator: ","),
                "query_raw": payloadPolicy.includesRawPayloads ? params.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "&") : "redacted",
            ].merging(WalletAdapterLogDiagnostics.failureMetadata(for: error)) { _, new in new })
            throw error
        }
        guard let nonce = Base58.decode(nonceString), nonce.count == NaClBox.nonceLength else {
            let error = WalletAdapterError.malformedPayload("Response is missing nonce or data.")
            log(logger, logLevel, method, "STEP_FAIL", .error, "invalid nonce base58 or length", [
                "nonce": WalletAdapterDebugFormatter.shortBase58(nonceString),
                "nonce_raw": payloadPolicy.includesRawPayloads ? nonceString : "redacted",
            ].merging(WalletAdapterLogDiagnostics.failureMetadata(for: error)) { _, new in new })
            throw error
        }
        guard let box = Base58.decode(payloadString) else {
            let error = WalletAdapterError.malformedPayload("Response is missing nonce or data.")
            log(logger, logLevel, method, "STEP_FAIL", .error, "invalid encrypted data base58", [
                "data": WalletAdapterDebugFormatter.shortBase58(payloadString),
                "data_raw": payloadPolicy.includesRawPayloads ? payloadString : "redacted",
            ].merging(WalletAdapterLogDiagnostics.failureMetadata(for: error)) { _, new in new })
            throw error
        }
        log(logger, logLevel, method, "STEP_3_ENVELOPE_OK", .debug, "encrypted response envelope decoded", [
            "nonce_bytes": "\(nonce.count)",
            "ciphertext_bytes": "\(box.count)",
        ].merging(payloadPolicy.includesRawPayloads ? [
            "nonce_raw": nonceString,
            "data_raw": payloadString,
        ] : [:]) { _, new in new })
        guard let plaintext = NaClBox.open(box: box, nonce: nonce, theirPublicKey: theirPublicKey, mySecretKey: mySecretKey) else {
            let error = WalletAdapterError.decryptionFailed
            log(logger, logLevel, method, "STEP_FAIL", .error, "response decryption failed", [
                "nonce_bytes": "\(nonce.count)",
                "ciphertext_bytes": "\(box.count)",
            ].merging(payloadPolicy.includesRawPayloads ? [
                "nonce_raw": nonceString,
                "data_raw": payloadString,
            ] : [:]) { _, new in new }
                .merging(WalletAdapterLogDiagnostics.failureMetadata(for: error)) { _, new in new })
            throw error
        }
        guard let json = try JSONSerialization.jsonObject(with: plaintext) as? [String: Any] else {
            let error = WalletAdapterError.malformedPayload("Response data is not a JSON object.")
            log(logger, logLevel, method, "STEP_FAIL", .error, "response data is not JSON object", [
                "plaintext_bytes": "\(plaintext.count)",
                "plaintext_raw": payloadPolicy.includesRawPayloads ? WalletAdapterDebugFormatter.utf8OrBase58(plaintext) : "redacted",
            ].merging(WalletAdapterLogDiagnostics.failureMetadata(for: error)) { _, new in new })
            throw error
        }
        log(logger, logLevel, method, "STEP_4_PAYLOAD_DECRYPTED", .debug, "response payload decrypted", [
            "plaintext_bytes": "\(plaintext.count)",
            "payload_keys": json.keys.sorted().joined(separator: ","),
        ].merging(payloadPolicy.includesRawPayloads ? [
            "payload_json_raw": WalletAdapterDebugFormatter.json(json),
        ] : [:]) { _, new in new })
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

    private static func logDecodeStart(
        _ logger: any WalletAdapterLogger,
        _ logLevel: WalletAdapterLogLevel,
        _ method: String,
        _ url: URL,
        _ payloadPolicy: WalletAdapterLogPayloadPolicy = .redacted
    ) {
        log(logger, logLevel, method, "STEP_1_START", .info, "decoding wallet response", [
            "callback": WalletAdapterDebugFormatter.urlShape(url),
            "query_keys": WalletAdapterDebugFormatter.queryKeys(url),
        ].merging(rawCallbackMetadata(url, payloadPolicy: payloadPolicy)) { _, new in new })
    }

    private static func logMissingResult(
        _ logger: any WalletAdapterLogger,
        _ logLevel: WalletAdapterLogLevel,
        _ method: String,
        _ field: String,
        _ payload: [String: Any]
    ) {
        let error = WalletAdapterError.malformedPayload("Wallet response is missing \(field).")
        log(logger, logLevel, method, "STEP_FAIL", .error, "response missing required result field", [
            "field": field,
            "payload_keys": payload.keys.sorted().joined(separator: ","),
        ].merging(WalletAdapterLogDiagnostics.failureMetadata(for: error)) { _, new in new })
    }

    private static func logWalletError(
        _ logger: any WalletAdapterLogger,
        _ logLevel: WalletAdapterLogLevel,
        _ method: String,
        _ error: WalletAdapterError,
        _ url: URL,
        _ payloadPolicy: WalletAdapterLogPayloadPolicy
    ) {
        let params = queryParameters(url)
        log(logger, logLevel, method, "STEP_FAIL_WALLET_ERROR", .error, "wallet returned error response", WalletAdapterLogDiagnostics.failureMetadata(for: error, metadata: [
            "error_code": params["errorCode"] ?? "",
            "error_message": params["errorMessage"] ?? "",
            "query_keys": params.keys.sorted().joined(separator: ","),
        ].merging(rawCallbackMetadata(url, payloadPolicy: payloadPolicy)) { _, new in new }))
    }

    private static func rawCallbackMetadata(
        _ url: URL,
        payloadPolicy: WalletAdapterLogPayloadPolicy
    ) -> [String: String] {
        guard payloadPolicy.includesRawPayloads else { return [:] }
        return [
            "callback_raw": url.absoluteString,
            "query_raw": WalletAdapterDebugFormatter.queryValues(url),
        ]
    }

    private static func log(
        _ logger: any WalletAdapterLogger,
        _ logLevel: WalletAdapterLogLevel,
        _ method: String,
        _ step: String,
        _ level: WalletAdapterLogLevel,
        _ message: String,
        _ metadata: [String: String] = [:]
    ) {
        guard logLevel != .off, level <= logLevel else { return }
        logger.log(
            WalletAdapterLogEvent(
                component: "WalletResponseDecoder",
                method: method,
                step: step,
                phase: level == .error ? "FAIL" : "INFO",
                message: message,
                metadata: metadata
            )
        )
    }
}
