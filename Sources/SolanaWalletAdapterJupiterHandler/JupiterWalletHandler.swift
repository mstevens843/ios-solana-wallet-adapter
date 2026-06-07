import Foundation
import SolanaWalletAdapter
import SolanaWalletAdapterCore

/// Wallet-side reference handler for the jWA profile of iWA v0.1.
///
/// A wallet integrates jWA by:
/// 1. Registering its custom URL scheme (e.g. `jupiter`) in `CFBundleURLTypes`.
/// 2. Conforming its keystore/approval/app-switch to `JWASigner` / `JWAApprovalUI`
///    / `JWAReturnOpening` (UIKit default provided).
/// 3. Forwarding inbound URLs from `scene(_:openURLContexts:)` / `.onOpenURL`
///    to ``handleIncomingURL(_:)``.
///
/// The handler parses the request, decrypts it, asks the wallet to approve, signs
/// via the wallet's keystore, builds the encrypted callback, and **fires
/// `redirect_link`** — the leg that produces clean auto-return. All crypto/wire
/// handling matches the dApp side (`NaClBox` / `Base58`), so it round-trips with
/// `JupiterAdapter` + `WalletResponseDecoder` (proven by the loopback tests).
@MainActor
public final class JupiterWalletHandler {
    private let signer: JWASigner
    private let approvalUI: JWAApprovalUI
    private let returnOpener: JWAReturnOpening
    private let sessionStore: JWASessionStore
    private let keypairFactory: @Sendable () -> EphemeralKeypair
    private let logger: any WalletAdapterLogger
    private let logLevel: WalletAdapterLogLevel

    public init(
        signer: JWASigner,
        approvalUI: JWAApprovalUI,
        returnOpener: JWAReturnOpening,
        sessionStore: JWASessionStore = InMemoryJWASessionStore(),
        keypairFactory: @escaping @Sendable () -> EphemeralKeypair = { EphemeralKeypair.generate() },
        logger: any WalletAdapterLogger = WalletAdapterLoggers.disabled,
        logLevel: WalletAdapterLogLevel = .off
    ) {
        self.signer = signer
        self.approvalUI = approvalUI
        self.returnOpener = returnOpener
        self.sessionStore = sessionStore
        self.keypairFactory = keypairFactory
        self.logger = logger
        self.logLevel = logLevel
    }

    /// Handle one inbound jWA URL. Returns `true` if it was a jWA request this
    /// handler consumed (and a callback was fired), `false` if the URL is not a
    /// recognizable jWA request the wallet should forward elsewhere.
    @discardableResult
    public func handleIncomingURL(_ url: URL) async -> Bool {
        guard let methodName = Self.methodName(from: url),
              let method = WalletMethod(rawValue: methodName) else {
            return false
        }
        let params = Self.queryParameters(url)
        guard let redirectString = params["redirect_link"],
              let redirectLink = URL(string: redirectString) else {
            // Without a redirect target there is no way to return a response.
            return false
        }

        log("handleIncomingURL", "STEP_1_RECEIVED", .info, "jWA request received", ["method": methodName])
        switch method {
        case .connect:
            await handleConnect(params: params, redirectLink: redirectLink)
        case .disconnect:
            await handleDisconnect(params: params, redirectLink: redirectLink)
        case .signMessage, .signTransaction, .signAllTransactions, .signAndSendTransaction:
            await handleSigning(method: method, params: params, redirectLink: redirectLink)
        default:
            await fireError(methodName, code: "UNSUPPORTED_METHOD", message: "jWA handler does not support \(methodName).", redirectLink: redirectLink)
        }
        return true
    }

    // MARK: - connect

    private func handleConnect(params: [String: String], redirectLink: URL) async {
        guard let dappKey = Self.decodedKey(params["dapp_encryption_public_key"]) else {
            await fireError("connect", code: "MALFORMED_PAYLOAD", message: "Missing or invalid dapp_encryption_public_key.", redirectLink: redirectLink)
            return
        }
        let cluster = params["cluster"].flatMap(Cluster.init(rawValue:)) ?? .mainnetBeta
        let appURL = params["app_url"].flatMap { URL(string: $0) }
        let request = JWAIncomingRequest(method: .connect, dappEncryptionPublicKey: dappKey, redirectLink: redirectLink, appURL: appURL, cluster: cluster)

        guard await approvalUI.requestApproval(request) == .approve else {
            await fireError("connect", code: "USER_REJECTED", message: "User rejected connect.", redirectLink: redirectLink)
            return
        }

        let walletKeypair = keypairFactory()
        let token = Base58.encode(NaClBox.randomNonce())
        sessionStore.store(JWAStoredSession(
            dappEncryptionPublicKey: dappKey,
            walletKeypair: walletKeypair,
            token: token,
            userPublicKey: signer.userPublicKey
        ))

        let payload: [String: Any] = ["public_key": signer.userPublicKey, "session": token]
        guard let callback = encryptedCallback(
            payload: payload,
            dappKey: dappKey,
            walletSecret: walletKeypair.secretKey,
            redirectLink: redirectLink,
            extraItems: [URLQueryItem(name: "jupiter_encryption_public_key", value: Base58.encode(walletKeypair.publicKey))]
        ) else {
            await fireError("connect", code: "MALFORMED_PAYLOAD", message: "Failed to build connect callback.", redirectLink: redirectLink)
            return
        }
        log("connect", "STEP_SUCCESS", .info, "connect approved; returning session", ["cluster": cluster.rawValue])
        await fire(callback)
    }

    // MARK: - signing

    private func handleSigning(method: WalletMethod, params: [String: String], redirectLink: URL) async {
        guard let dappKey = Self.decodedKey(params["dapp_encryption_public_key"]) else {
            await fireError(method.rawValue, code: "MALFORMED_PAYLOAD", message: "Missing dapp_encryption_public_key.", redirectLink: redirectLink)
            return
        }
        guard let session = sessionStore.session(forDappKey: dappKey) else {
            await fireError(method.rawValue, code: "INVALID_SESSION", message: "No session for this dApp; reconnect.", redirectLink: redirectLink)
            return
        }
        guard let payload = decryptRequest(params: params, dappKey: dappKey, walletSecret: session.walletKeypair.secretKey) else {
            await fireError(method.rawValue, code: "DECRYPTION_FAILED", message: "Could not decrypt request.", redirectLink: redirectLink)
            return
        }
        guard (payload["session"] as? String) == session.token else {
            await fireError(method.rawValue, code: "INVALID_SESSION", message: "Session token mismatch.", redirectLink: redirectLink)
            return
        }

        guard let signingRequest = decodeSigningRequest(method: method, payload: payload) else {
            await fireError(method.rawValue, code: "MALFORMED_PAYLOAD", message: "Missing or invalid \(method.rawValue) payload.", redirectLink: redirectLink)
            return
        }

        let request = JWAIncomingRequest(
            method: method,
            dappEncryptionPublicKey: dappKey,
            redirectLink: redirectLink,
            appURL: nil,
            cluster: .mainnetBeta,
            signingRequest: signingRequest
        )
        guard await approvalUI.requestApproval(request) == .approve else {
            await fire(errorURL(code: "USER_REJECTED", message: "User rejected \(method.rawValue).", redirectLink: redirectLink))
            return
        }

        let responsePayload: [String: Any]
        do {
            responsePayload = try await sign(signingRequest)
        } catch {
            await fireError(method.rawValue, code: "SIGNING_FAILED", message: "Wallet failed to sign \(method.rawValue).", redirectLink: redirectLink)
            return
        }

        guard let callback = encryptedCallback(payload: responsePayload, dappKey: dappKey, walletSecret: session.walletKeypair.secretKey, redirectLink: redirectLink) else {
            await fireError(method.rawValue, code: "MALFORMED_PAYLOAD", message: "Failed to build callback.", redirectLink: redirectLink)
            return
        }
        log(method.rawValue, "STEP_SUCCESS", .info, "request approved; returning result")
        await fire(callback)
    }

    /// Decode the encrypted payload into a `SigningRequest` (the content the wallet
    /// will display + sign). Returns nil for malformed payloads.
    private func decodeSigningRequest(method: WalletMethod, payload: [String: Any]) -> SigningRequest? {
        switch method {
        case .signMessage:
            guard let encoded = payload["message"] as? String, let message = Base58.decode(encoded) else { return nil }
            return .message(message)
        case .signTransaction:
            guard let encoded = payload["transaction"] as? String, let transaction = Base58.decode(encoded) else { return nil }
            return .transaction(transaction)
        case .signAllTransactions:
            guard let encoded = payload["transactions"] as? [String] else { return nil }
            let transactions = encoded.compactMap(Base58.decode)
            guard transactions.count == encoded.count else { return nil }
            return .allTransactions(transactions)
        case .signAndSendTransaction:
            guard let encoded = payload["transaction"] as? String, let transaction = Base58.decode(encoded) else { return nil }
            return .signAndSend(transaction, sendOptions: Self.sendOptions(from: payload["sendOptions"]))
        default:
            return nil
        }
    }

    private func sign(_ request: SigningRequest) async throws -> [String: Any] {
        switch request {
        case .message(let message):
            let signature = try await signer.signMessage(message)
            return ["signature": Base58.encode(signature)]
        case .transaction(let transaction):
            let signed = try await signer.signTransaction(transaction)
            return ["transaction": Base58.encode(signed)]
        case .allTransactions(let transactions):
            let signed = try await signer.signAllTransactions(transactions)
            return ["transactions": signed.map(Base58.encode)]
        case .signAndSend(let transaction, let sendOptions):
            let txid = try await signer.signAndSendTransaction(transaction, options: sendOptions)
            return ["signature": txid]
        }
    }

    // MARK: - disconnect

    private func handleDisconnect(params: [String: String], redirectLink: URL) async {
        if let dappKey = Self.decodedKey(params["dapp_encryption_public_key"]),
           let session = sessionStore.session(forDappKey: dappKey),
           let payload = decryptRequest(params: params, dappKey: dappKey, walletSecret: session.walletKeypair.secretKey),
           let token = payload["session"] as? String {
            sessionStore.removeSession(token: token)
        }
        log("disconnect", "STEP_SUCCESS", .info, "session cleared; returning to dApp")
        // Disconnect carries no response payload — just bounce the user back.
        await fire(redirectLink)
    }

    // MARK: - crypto / URL helpers

    private func decryptRequest(params: [String: String], dappKey: Data, walletSecret: Data) -> [String: Any]? {
        guard let nonceString = params["nonce"], let nonce = Base58.decode(nonceString), nonce.count == NaClBox.nonceLength,
              let payloadString = params["payload"], let box = Base58.decode(payloadString),
              let plaintext = NaClBox.open(box: box, nonce: nonce, theirPublicKey: dappKey, mySecretKey: walletSecret),
              let object = (try? JSONSerialization.jsonObject(with: plaintext)) as? [String: Any] else {
            return nil
        }
        return object
    }

    private func encryptedCallback(
        payload: [String: Any],
        dappKey: Data,
        walletSecret: Data,
        redirectLink: URL,
        extraItems: [URLQueryItem] = []
    ) -> URL? {
        guard JSONSerialization.isValidJSONObject(payload),
              let plaintext = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else {
            return nil
        }
        let nonce = NaClBox.randomNonce()
        let sealed = NaClBox.seal(message: plaintext, nonce: nonce, theirPublicKey: dappKey, mySecretKey: walletSecret)
        guard !sealed.isEmpty else { return nil }
        return Self.appendQuery(to: redirectLink, extraItems + [
            URLQueryItem(name: "nonce", value: Base58.encode(nonce)),
            URLQueryItem(name: "data", value: Base58.encode(sealed)),
        ])
    }

    private func errorURL(code: String, message: String, redirectLink: URL) -> URL {
        Self.appendQuery(to: redirectLink, [
            URLQueryItem(name: "errorCode", value: code),
            URLQueryItem(name: "errorMessage", value: message),
        ])
    }

    @discardableResult
    private func fire(_ url: URL) async -> Bool {
        await returnOpener.open(url)
    }

    /// Log + return the error callback to the dApp in one place.
    @discardableResult
    private func fireError(_ method: String, code: String, message: String, redirectLink: URL) async -> Bool {
        log(method, "STEP_FAIL", .error, message, ["error_code": code])
        return await fire(errorURL(code: code, message: message, redirectLink: redirectLink))
    }

    private func log(_ method: String, _ step: String, _ level: WalletAdapterLogLevel, _ message: String, _ metadata: [String: String] = [:]) {
        guard logLevel != .off, level <= logLevel else { return }
        logger.log(WalletAdapterLogEvent(
            component: "JupiterWalletHandler",
            method: method,
            step: step,
            phase: level == .error ? "FAIL" : "INFO",
            message: message,
            metadata: metadata
        ))
    }

    private static func decodedKey(_ value: String?) -> Data? {
        guard let value, let key = Base58.decode(value), key.count == NaClBox.keyLength else { return nil }
        return key
    }

    private static func appendQuery(to base: URL, _ items: [URLQueryItem]) -> URL {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return base }
        components.queryItems = (components.queryItems ?? []) + items
        return components.url ?? base
    }

    private static func methodName(from url: URL) -> String? {
        let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.path ?? ""
        return path.split(separator: "/").map(String.init).last
    }

    private static func queryParameters(_ url: URL) -> [String: String] {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return [:] }
        var out: [String: String] = [:]
        for item in items { out[item.name] = item.value ?? "" }
        return out
    }

    private static func sendOptions(from raw: Any?) -> SendOptions {
        guard let dict = raw as? [String: Any] else { return SendOptions() }
        return SendOptions(
            skipPreflight: dict["skipPreflight"] as? Bool ?? false,
            preflightCommitment: dict["preflightCommitment"] as? String,
            maxRetries: dict["maxRetries"] as? Int
        )
    }
}
