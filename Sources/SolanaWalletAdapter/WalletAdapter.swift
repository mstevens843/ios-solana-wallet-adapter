import Foundation
import SolanaWalletAdapterCore

/// High-level URL/callback coordinator for one selected wallet.
///
/// The adapter is intentionally transport-agnostic: it builds URLs for the app
/// to open and decodes callback URLs delivered through `.onOpenURL` or an app
/// delegate. It does not call UIKit, open URLs, or hold async continuations.
public final class WalletAdapter {
    public let provider: WalletProvider
    public let keypair: EphemeralKeypair
    public private(set) var session: Session?
    public private(set) var cluster: Cluster
    public var logLevel: WalletAdapterLogLevel
    public var payloadPolicy: WalletAdapterLogPayloadPolicy
    private let logger: any WalletAdapterLogger

    public init(
        provider: WalletProvider,
        keypair: EphemeralKeypair = .generate(),
        cluster: Cluster = .mainnetBeta,
        logger: any WalletAdapterLogger = WalletAdapterLoggers.disabled,
        logLevel: WalletAdapterLogLevel = .off,
        payloadPolicy: WalletAdapterLogPayloadPolicy = .redacted
    ) {
        self.provider = provider
        self.keypair = keypair
        self.cluster = cluster
        self.logger = logger
        self.logLevel = logLevel
        self.payloadPolicy = payloadPolicy
        log(
            method: "init",
            step: "STEP_1_READY",
            level: .debug,
            message: "adapter initialized",
                metadata: baseMetadata().merging([
                    "public_key": WalletAdapterDebugFormatter.shortBase58(Base58.encode(keypair.publicKey)),
                    "secret_key_bytes": "\(keypair.secretKey.count)",
                    "payload_policy": "\(payloadPolicy)",
                ]) { _, new in new }
        )
    }

    public func connectURL(
        appURL: URL,
        redirectLink: URL,
        cluster: Cluster? = nil
    ) throws -> URL {
        let method = "connectURL"
        do {
            let targetCluster = cluster ?? self.cluster
            log(
                method: method,
                step: "STEP_1_START",
                level: .info,
                message: "building connect URL",
                metadata: baseMetadata().merging(["target_cluster": targetCluster.rawValue]) { _, new in new }
            )
            log(
                method: method,
                step: "STEP_2_PARAMS",
                level: .debug,
                message: "connect parameters prepared",
                metadata: [
                    "app_url": WalletAdapterDebugFormatter.urlShape(appURL),
                    "redirect": WalletAdapterDebugFormatter.urlShape(redirectLink),
                    "dapp_public_key": WalletAdapterDebugFormatter.shortBase58(Base58.encode(keypair.publicKey)),
                ].merging(rawURLMetadata([
                    "app_url_raw": appURL,
                    "redirect_raw": redirectLink,
                ])) { _, new in new }
            )
            self.cluster = targetCluster
            let url = try provider.connectURL(
                request: ConnectRequest(
                    dappEncryptionPublicKey: Base58.encode(keypair.publicKey),
                    redirectLink: redirectLink,
                    appURL: appURL,
                    cluster: targetCluster
                )
            )
            log(
                method: method,
                step: "STEP_3_URL_BUILT",
                level: .info,
                message: "connect URL built",
                metadata: ["url": WalletAdapterDebugFormatter.urlShape(url)]
                    .merging(rawURLMetadata(["url_raw": url])) { _, new in new }
            )
            return url
        } catch {
            logFailure(method: method, error: error)
            throw error
        }
    }

    @discardableResult
    public func handleConnectCallback(_ url: URL) throws -> Session {
        let method = "handleConnectCallback"
        do {
            log(
                method: method,
                step: "STEP_1_START",
                level: .info,
                message: "decoding connect callback",
                metadata: ["callback": WalletAdapterDebugFormatter.urlShape(url)]
                    .merging(rawURLMetadata(["callback_raw": url])) { _, new in new }
            )
            let decoded = try WalletResponseDecoder.connectSession(
                from: url,
                keypair: keypair,
                expectedCluster: cluster,
                logger: logger,
                logLevel: logLevel,
                payloadPolicy: payloadPolicy
            )
            session = decoded
            log(
                method: method,
                step: "STEP_3_SESSION_STORED",
                level: .info,
                message: "connect session stored",
                metadata: [
                    "user_public_key": WalletAdapterDebugFormatter.shortBase58(decoded.userPublicKey),
                    "wallet_encryption_public_key": WalletAdapterDebugFormatter.shortBase58(Base58.encode(decoded.walletEncryptionPublicKey)),
                    "session_present": "true",
                ]
            )
            return decoded
        } catch {
            logFailure(method: method, error: error)
            throw error
        }
    }

    public func disconnectURL(redirectLink: URL) throws -> URL {
        try encryptedRequestURL(
            method: "disconnectURL",
            walletMethod: "disconnect",
            redirectLink: redirectLink
        ) { session in
            try provider.disconnectURL(
                session: session,
                keypair: keypair,
                redirectLink: redirectLink,
                logger: logger,
                logLevel: logLevel,
                payloadPolicy: payloadPolicy
            )
        }
    }

    public func signMessageURL(
        _ message: Data,
        redirectLink: URL,
        display: WalletSigningDisplay = .utf8
    ) throws -> URL {
        try encryptedRequestURL(
            method: "signMessageURL",
            walletMethod: "signMessage",
            redirectLink: redirectLink,
            metadata: [
                "message_bytes": WalletAdapterDebugFormatter.byteCount(message),
                "display": display.rawValue,
            ].merging(payloadPolicy.includesRawPayloads ? [
                "message_raw": WalletAdapterDebugFormatter.utf8OrBase58(message),
                "message_base58_raw": Base58.encode(message),
            ] : [:]) { _, new in new }
        ) { session in
            try provider.signMessageURL(
                message: message,
                session: session,
                keypair: keypair,
                redirectLink: redirectLink,
                display: display,
                logger: logger,
                logLevel: logLevel,
                payloadPolicy: payloadPolicy
            )
        }
    }

    public func signTransactionURL(_ transaction: Data, redirectLink: URL) throws -> URL {
        try encryptedRequestURL(
            method: "signTransactionURL",
            walletMethod: "signTransaction",
            redirectLink: redirectLink,
            metadata: ["transaction_bytes": WalletAdapterDebugFormatter.byteCount(transaction)]
                .merging(payloadPolicy.includesRawPayloads ? ["transaction_raw": Base58.encode(transaction)] : [:]) { _, new in new }
        ) { session in
            try provider.signTransactionURL(
                transaction: transaction,
                session: session,
                keypair: keypair,
                redirectLink: redirectLink,
                logger: logger,
                logLevel: logLevel,
                payloadPolicy: payloadPolicy
            )
        }
    }

    public func signAllTransactionsURL(_ transactions: [Data], redirectLink: URL) throws -> URL {
        try encryptedRequestURL(
            method: "signAllTransactionsURL",
            walletMethod: "signAllTransactions",
            redirectLink: redirectLink,
            metadata: [
                "transaction_count": "\(transactions.count)",
                "transaction_bytes": transactions.map(\.count).map(String.init).joined(separator: ","),
            ].merging(payloadPolicy.includesRawPayloads ? ["transactions_raw": transactions.map(Base58.encode).joined(separator: ",")] : [:]) { _, new in new }
        ) { session in
            try provider.signAllTransactionsURL(
                transactions: transactions,
                session: session,
                keypair: keypair,
                redirectLink: redirectLink,
                logger: logger,
                logLevel: logLevel,
                payloadPolicy: payloadPolicy
            )
        }
    }

    public func signAndSendTransactionURL(
        _ transaction: Data,
        redirectLink: URL,
        sendOptions: SendOptions = .init()
    ) throws -> URL {
        try encryptedRequestURL(
            method: "signAndSendTransactionURL",
            walletMethod: "signAndSendTransaction",
            redirectLink: redirectLink,
            metadata: [
                "transaction_bytes": WalletAdapterDebugFormatter.byteCount(transaction),
                "skip_preflight": "\(sendOptions.skipPreflight)",
                "preflight_commitment": sendOptions.preflightCommitment ?? "nil",
                "max_retries": sendOptions.maxRetries.map(String.init) ?? "nil",
            ].merging(payloadPolicy.includesRawPayloads ? ["transaction_raw": Base58.encode(transaction)] : [:]) { _, new in new }
        ) { session in
            try provider.signAndSendTransactionURL(
                transaction: transaction,
                session: session,
                keypair: keypair,
                redirectLink: redirectLink,
                sendOptions: sendOptions,
                logger: logger,
                logLevel: logLevel,
                payloadPolicy: payloadPolicy
            )
        }
    }

    public func handleSignMessageCallback(_ url: URL) throws -> SignMessageResult {
        try decodeSigningCallback(method: "handleSignMessageCallback", url: url) { session in
            let result = try WalletResponseDecoder.signMessageResult(
                from: url,
                session: session,
                keypair: keypair,
                expectedCluster: cluster,
                logger: logger,
                logLevel: logLevel,
                payloadPolicy: payloadPolicy
            )
            return ("signature_bytes", WalletAdapterDebugFormatter.byteCount(result.signature), result)
        }
    }

    public func handleSignTransactionCallback(_ url: URL) throws -> SignTransactionResult {
        try decodeSigningCallback(method: "handleSignTransactionCallback", url: url) { session in
            let result = try WalletResponseDecoder.signTransactionResult(
                from: url,
                session: session,
                keypair: keypair,
                expectedCluster: cluster,
                logger: logger,
                logLevel: logLevel,
                payloadPolicy: payloadPolicy
            )
            return ("transaction_bytes", WalletAdapterDebugFormatter.byteCount(result.transaction), result)
        }
    }

    public func handleSignAllTransactionsCallback(_ url: URL) throws -> SignAllTransactionsResult {
        try decodeSigningCallback(method: "handleSignAllTransactionsCallback", url: url) { session in
            let result = try WalletResponseDecoder.signAllTransactionsResult(
                from: url,
                session: session,
                keypair: keypair,
                expectedCluster: cluster,
                logger: logger,
                logLevel: logLevel,
                payloadPolicy: payloadPolicy
            )
            return ("transaction_count", "\(result.transactions.count)", result)
        }
    }

    public func handleSignAndSendTransactionCallback(_ url: URL) throws -> SignAndSendTransactionResult {
        try decodeSigningCallback(method: "handleSignAndSendTransactionCallback", url: url) { session in
            let result = try WalletResponseDecoder.signAndSendTransactionResult(
                from: url,
                session: session,
                keypair: keypair,
                expectedCluster: cluster,
                logger: logger,
                logLevel: logLevel,
                payloadPolicy: payloadPolicy
            )
            return ("txid", WalletAdapterDebugFormatter.shortBase58(result.signature), result)
        }
    }

    public func clearSession() {
        log(
            method: "clearSession",
            step: "STEP_1_CLEAR",
            level: .info,
            message: "clearing session",
            metadata: baseMetadata().merging(["had_session": "\(session != nil)"]) { _, new in new }
        )
        session = nil
    }

    public func exportState() -> WalletAdapterState {
        WalletAdapterState(
            providerId: provider.walletId,
            cluster: cluster,
            keypair: keypair,
            session: session
        )
    }

    public func restoreSession(_ session: Session?) {
        self.session = session
    }

    private func encryptedRequestURL(
        method: String,
        walletMethod: String,
        redirectLink: URL,
        metadata: [String: String] = [:],
        build: (Session) throws -> URL
    ) throws -> URL {
        do {
            log(
                method: method,
                step: "STEP_1_START",
                level: .info,
                message: "building encrypted request URL",
                metadata: baseMetadata().merging(["wallet_method": walletMethod]) { _, new in new }.merging(metadata) { _, new in new }
            )
            let session = try requireSession(method: method)
            log(
                method: method,
                step: "STEP_3_PAYLOAD_BUILD",
                level: .debug,
                message: "request payload ready for encryption",
                metadata: [
                    "redirect": WalletAdapterDebugFormatter.urlShape(redirectLink),
                    "wallet_public_key": WalletAdapterDebugFormatter.shortBase58(Base58.encode(session.walletEncryptionPublicKey)),
                ].merging(metadata) { _, new in new }
                    .merging(rawURLMetadata(["redirect_raw": redirectLink])) { _, new in new }
            )
            let url = try build(session)
            log(
                method: method,
                step: "STEP_4_URL_BUILT",
                level: .info,
                message: "encrypted request URL built",
                metadata: ["url": WalletAdapterDebugFormatter.urlShape(url)]
                    .merging(rawURLMetadata(["url_raw": url])) { _, new in new }
                    .merging(envelopeMetadata(url)) { _, new in new }
            )
            return url
        } catch {
            logFailure(method: method, error: error)
            throw error
        }
    }

    private func decodeSigningCallback<Result>(
        method: String,
        url: URL,
        decode: (Session) throws -> (String, String, Result)
    ) throws -> Result {
        do {
            log(
                method: method,
                step: "STEP_1_START",
                level: .info,
                message: "decoding signing callback",
                metadata: ["callback": WalletAdapterDebugFormatter.urlShape(url)]
                    .merging(rawURLMetadata(["callback_raw": url])) { _, new in new }
            )
            let session = try requireSession(method: method)
            let (key, value, result) = try decode(session)
            log(
                method: method,
                step: "STEP_3_RESULT_DECODED",
                level: .info,
                message: "callback result decoded",
                metadata: [key: value]
            )
            return result
        } catch {
            logFailure(method: method, error: error)
            throw error
        }
    }

    private func requireSession(method: String) throws -> Session {
        guard let session else {
            log(
                method: method,
                step: "STEP_2_SESSION_FAIL",
                level: .error,
                message: "no active session",
                metadata: WalletAdapterLogDiagnostics.failureMetadata(
                    for: WalletAdapterError.invalidSession,
                    metadata: baseMetadata()
                )
            )
            throw WalletAdapterError.invalidSession
        }
        log(
            method: method,
            step: "STEP_2_SESSION_OK",
            level: .debug,
            message: "active session found",
            metadata: [
                "user_public_key": WalletAdapterDebugFormatter.shortBase58(session.userPublicKey),
                "wallet_public_key": WalletAdapterDebugFormatter.shortBase58(Base58.encode(session.walletEncryptionPublicKey)),
            ]
        )
        return session
    }

    private func log(
        method: String,
        step: String,
        level: WalletAdapterLogLevel,
        message: String,
        metadata: [String: String] = [:]
    ) {
        guard logLevel != .off, level <= logLevel else { return }
        logger.log(
            WalletAdapterLogEvent(
                component: "WalletAdapter",
                method: method,
                step: step,
                phase: level == .error ? "FAIL" : "INFO",
                message: message,
                metadata: metadata
            )
        )
    }

    private func logFailure(method: String, error: Error) {
        log(
            method: method,
            step: "STEP_FAIL",
            level: .error,
            message: "operation failed",
            metadata: WalletAdapterLogDiagnostics.failureMetadata(for: error, metadata: baseMetadata())
        )
    }

    private func baseMetadata() -> [String: String] {
        [
            "wallet": provider.walletId,
            "cluster": cluster.rawValue,
            "has_session": "\(session != nil)",
        ]
    }

    private func envelopeMetadata(_ url: URL) -> [String: String] {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return [:]
        }
        let params = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        var result = [
            "nonce_chars": "\(params["nonce"]?.count ?? 0)",
            "payload_chars": "\(params["payload"]?.count ?? 0)",
            "dapp_public_key": WalletAdapterDebugFormatter.shortBase58(params["dapp_encryption_public_key"] ?? ""),
        ]
        if payloadPolicy.includesRawPayloads {
            result["nonce_raw"] = params["nonce"] ?? ""
            result["payload_raw"] = params["payload"] ?? ""
            result["query_raw"] = WalletAdapterDebugFormatter.queryValues(url)
        }
        return result
    }

    private func rawURLMetadata(_ values: [String: URL]) -> [String: String] {
        guard payloadPolicy.includesRawPayloads else { return [:] }
        return Dictionary(uniqueKeysWithValues: values.map { key, url in
            (key, url.absoluteString)
        })
    }
}
