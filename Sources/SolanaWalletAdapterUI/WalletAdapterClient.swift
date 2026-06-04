import Foundation
import SolanaWalletAdapter
import SolanaWalletAdapterCore

@MainActor
public final class WalletAdapterClient {
    public private(set) var adapter: WalletAdapter
    public let redirectLink: URL
    public let appURL: URL
    private let opener: any WalletURLOpening
    private let stateStore: (any WalletAdapterStateStore)?
    private let lastActiveStore: (any LastActiveWalletStoring)?
    private let logger: any WalletAdapterLogger
    private let logLevel: WalletAdapterLogLevel
    private let payloadPolicy: WalletAdapterLogPayloadPolicy
    private var pending: PendingRequest?
    private var nextFlowNumber = 1

    // Extended auth cache. These live on the client (not on WalletAdapter) so
    // the underlying adapter stays focused on URL/callback work and the cache
    // can be persisted alongside the adapter's exportable state.
    private var walletLabel: String?
    private var cachedCapabilities: WalletCapabilities?
    private var lastSuccessAt: Date?
    private var preferredProviderId: String?
    private(set) var lastKnownClusterCache: Cluster?

    public init(
        provider: any WalletProvider,
        appURL: URL,
        redirectLink: URL,
        cluster: Cluster = .mainnetBeta,
        keypair: EphemeralKeypair = .generate(),
        opener: any WalletURLOpening,
        stateStore: (any WalletAdapterStateStore)? = nil,
        lastActiveStore: (any LastActiveWalletStoring)? = nil,
        logger: any WalletAdapterLogger = WalletAdapterLoggers.disabled,
        logLevel: WalletAdapterLogLevel = .off,
        payloadPolicy: WalletAdapterLogPayloadPolicy = .redacted
    ) {
        self.adapter = WalletAdapter(
            provider: provider,
            keypair: keypair,
            cluster: cluster,
            logger: logger,
            logLevel: logLevel,
            payloadPolicy: payloadPolicy
        )
        self.redirectLink = redirectLink
        self.appURL = appURL
        self.opener = opener
        self.stateStore = stateStore
        self.lastActiveStore = lastActiveStore
        self.logger = logger
        self.logLevel = logLevel
        self.payloadPolicy = payloadPolicy
        log("init", "STEP_1_READY", .debug, "wallet adapter client initialized", [
            "wallet": provider.walletId,
            "cluster": cluster.rawValue,
            "payload_policy": "\(payloadPolicy)",
        ].merging(rawURLMetadata(["app_url_raw": appURL, "redirect_raw": redirectLink])) { _, new in new })
    }

    public convenience init(
        restoredState: WalletAdapterState,
        appURL: URL,
        redirectLink: URL,
        opener: any WalletURLOpening,
        stateStore: (any WalletAdapterStateStore)? = nil,
        lastActiveStore: (any LastActiveWalletStoring)? = nil,
        logger: any WalletAdapterLogger = WalletAdapterLoggers.disabled,
        logLevel: WalletAdapterLogLevel = .off,
        payloadPolicy: WalletAdapterLogPayloadPolicy = .redacted
    ) throws {
        guard let provider = WalletProviderRegistry.provider(for: restoredState.providerId) else {
            throw WalletAdapterError.malformedPayload("Unsupported wallet provider id: \(restoredState.providerId).")
        }
        self.init(
            provider: provider,
            appURL: appURL,
            redirectLink: redirectLink,
            cluster: restoredState.cluster,
            opener: opener,
            stateStore: stateStore,
            lastActiveStore: lastActiveStore,
            logger: logger,
            logLevel: logLevel,
            payloadPolicy: payloadPolicy
        )
        self.adapter = WalletAdapter(
            provider: provider,
            keypair: restoredState.keypair,
            cluster: restoredState.cluster,
            logger: logger,
            logLevel: logLevel,
            payloadPolicy: payloadPolicy
        )
        self.adapter.restoreSession(restoredState.session)
        self.walletLabel = restoredState.walletLabel
        self.cachedCapabilities = restoredState.cachedCapabilities
        self.lastKnownClusterCache = restoredState.lastKnownCluster
        self.lastSuccessAt = restoredState.lastSuccessAt
        self.preferredProviderId = restoredState.preferredProviderId
    }

    public static func restore(
        from stateStore: any WalletAdapterStateStore,
        fallbackProvider: any WalletProvider,
        appURL: URL,
        redirectLink: URL,
        cluster: Cluster = .mainnetBeta,
        keypair: EphemeralKeypair = .generate(),
        opener: any WalletURLOpening,
        lastActiveStore: (any LastActiveWalletStoring)? = nil,
        logger: any WalletAdapterLogger = WalletAdapterLoggers.disabled,
        logLevel: WalletAdapterLogLevel = .off,
        payloadPolicy: WalletAdapterLogPayloadPolicy = .redacted
    ) throws -> WalletAdapterClient {
        if let state = try stateStore.loadState() {
            return try WalletAdapterClient(
                restoredState: state,
                appURL: appURL,
                redirectLink: redirectLink,
                opener: opener,
                stateStore: stateStore,
                lastActiveStore: lastActiveStore,
                logger: logger,
                logLevel: logLevel,
                payloadPolicy: payloadPolicy
            )
        }
        return WalletAdapterClient(
            provider: fallbackProvider,
            appURL: appURL,
            redirectLink: redirectLink,
            cluster: cluster,
            keypair: keypair,
            opener: opener,
            stateStore: stateStore,
            lastActiveStore: lastActiveStore,
            logger: logger,
            logLevel: logLevel,
            payloadPolicy: payloadPolicy
        )
    }

    public func selectProvider(_ provider: any WalletProvider, cluster: Cluster? = nil) throws {
        let flowID = makeFlowID("selectProvider")
        do {
            log("selectProvider", "STEP_1_START", .info, "select provider started", [
                "flow_id": flowID,
                "current_wallet": adapter.provider.walletId,
                "next_wallet": provider.walletId,
                "target_cluster": (cluster ?? adapter.cluster).rawValue,
            ])
            guard pending == nil else {
                throw WalletAdapterError.operationInProgress
            }
            adapter = WalletAdapter(provider: provider, cluster: cluster ?? adapter.cluster, logger: logger, logLevel: logLevel, payloadPolicy: payloadPolicy)
            try persistState(flowID: flowID)
            log("selectProvider", "STEP_2_SUCCESS", .info, "provider selected", [
                "flow_id": flowID,
                "wallet": adapter.provider.walletId,
                "cluster": adapter.cluster.rawValue,
            ])
        } catch {
            logFailure("selectProvider", flowID: flowID, error: error, metadata: pendingMetadata())
            throw error
        }
    }

    /// Wipe persisted state, drop the in-memory session, cancel any pending
    /// request, and rotate the ephemeral encryption keypair. After this call
    /// the client behaves like a fresh instance — the next connect produces a
    /// new shared secret with the wallet.
    public func clearState() async throws {
        let flowID = makeFlowID("clearState")
        log("clearState", "STEP_1_START", .info, "clearing wallet adapter state", [
            "flow_id": flowID,
            "had_session": "\(adapter.session != nil)",
            "had_preferred": "\(preferredProviderId != nil)",
            "pending": pending?.name ?? "none",
        ])

        if pending != nil {
            log("clearState", "STEP_2_CANCEL_PENDING", .info, "cancelling pending request before clear", [
                "flow_id": flowID,
                "pending": pending?.name ?? "none",
            ])
            _ = cancelPendingRequest()
        }

        adapter = WalletAdapter(
            provider: adapter.provider,
            keypair: .generate(),
            cluster: adapter.cluster,
            logger: logger,
            logLevel: logLevel,
            payloadPolicy: payloadPolicy
        )
        walletLabel = nil
        cachedCapabilities = nil
        lastSuccessAt = nil
        lastKnownClusterCache = nil
        preferredProviderId = nil

        do {
            try stateStore?.saveState(nil)
            // Clear the last-active pointer too so the next launch doesn't try to
            // restore a wiped wallet.
            try? lastActiveStore?.saveLastActiveWalletId(nil)
            log("clearState", "STEP_3_SUCCESS", .info, "wallet adapter state cleared", [
                "flow_id": flowID,
                "wallet": adapter.provider.walletId,
            ])
        } catch {
            log("clearState", "STEP_FAIL_PERSIST", .error, "wallet adapter state clear failed", failureMetadata(error, flowID: flowID))
            throw error
        }
    }

    /// Forget the "Always" picker choice without dropping the current session.
    /// Use this when the user wants the picker to appear next time without
    /// signing out of the connected wallet.
    public func forgetPreferredWallet() async throws {
        let flowID = makeFlowID("forgetPreferredWallet")
        log("forgetPreferredWallet", "STEP_1_START", .info, "clearing preferred provider", [
            "flow_id": flowID,
            "previous_preferred": preferredProviderId ?? "nil",
        ])
        preferredProviderId = nil
        do {
            try persistState(flowID: flowID)
            log("forgetPreferredWallet", "STEP_2_SUCCESS", .info, "preferred provider cleared", [
                "flow_id": flowID,
            ])
        } catch {
            log("forgetPreferredWallet", "STEP_FAIL_PERSIST", .error, "failed to persist after clearing preferred", failureMetadata(error, flowID: flowID))
            throw error
        }
    }

    /// Record that the user selected this wallet with "Always" in the picker.
    /// Subsequent launches can call `reconnectIfPossible` to skip the picker.
    public func rememberPreferredWallet(_ providerId: String) async throws {
        let flowID = makeFlowID("rememberPreferredWallet")
        log("rememberPreferredWallet", "STEP_1_START", .info, "setting preferred provider", [
            "flow_id": flowID,
            "preferred": providerId,
            "previous": preferredProviderId ?? "nil",
        ])
        preferredProviderId = providerId
        do {
            try persistState(flowID: flowID)
            log("rememberPreferredWallet", "STEP_2_SUCCESS", .info, "preferred provider set", [
                "flow_id": flowID,
                "preferred": providerId,
            ])
        } catch {
            log("rememberPreferredWallet", "STEP_FAIL_PERSIST", .error, "failed to persist preferred provider", failureMetadata(error, flowID: flowID))
            throw error
        }
    }

    /// Returns `true` if the cached state has a session for an installed wallet
    /// — meaning the caller can use the existing session without showing the
    /// picker or re-running connect. Does not open any URL; the caller decides
    /// what to do next.
    public func reconnectIfPossible(detector: any InstalledWalletDetecting = InstalledWalletDetector.default) async -> Bool {
        let flowID = makeFlowID("reconnectIfPossible")
        guard adapter.session != nil else {
            log("reconnectIfPossible", "STEP_1_NO_SESSION", .debug, "no cached session", [
                "flow_id": flowID,
            ])
            return false
        }
        guard WalletProviderRegistry.provider(for: adapter.provider.walletId) != nil else {
            log("reconnectIfPossible", "STEP_1_PROVIDER_MISSING", .debug, "cached providerId not in registry", [
                "flow_id": flowID,
                "wallet": adapter.provider.walletId,
            ])
            return false
        }
        let scheme = adapter.provider.customScheme
        guard detector.isInstalled(scheme: scheme) else {
            log("reconnectIfPossible", "STEP_1_NOT_INSTALLED", .debug, "wallet app not installed", [
                "flow_id": flowID,
                "wallet": adapter.provider.walletId,
                "scheme": scheme,
            ])
            return false
        }
        log("reconnectIfPossible", "STEP_2_SUCCESS", .info, "cached session can be resumed", [
            "flow_id": flowID,
            "wallet": adapter.provider.walletId,
            "scheme": scheme,
        ])
        return true
    }

    /// Reload the keychain-cached session into the active adapter with **no**
    /// wallet interaction (no connect/sign deeplink). Use after
    /// `signOutLocally()` to resume the previously authorized session locally.
    /// Returns `true` if a cached session was found and restored.
    ///
    /// The ephemeral keypair is deliberately left untouched: the cached session
    /// can only be decrypted with the keypair that established it, which the
    /// `restore(...)`-built client already holds. Rotating it (as `clearState`
    /// does) would make the cached session undecryptable.
    @discardableResult
    public func resumeCachedSession() async -> Bool {
        let flowID = makeFlowID("resumeCachedSession")
        guard let stateStore else {
            log("resumeCachedSession", "STEP_1_NO_STORE", .debug, "no state store configured", ["flow_id": flowID])
            return false
        }
        let cached: WalletAdapterState?
        do {
            cached = try stateStore.loadState()
        } catch {
            logFailure("resumeCachedSession", flowID: flowID, error: error)
            return false
        }
        guard let cached, let session = cached.session else {
            log("resumeCachedSession", "STEP_1_NO_SESSION", .debug, "no cached session to resume", ["flow_id": flowID])
            return false
        }
        adapter.restoreSession(session)
        walletLabel = cached.walletLabel
        cachedCapabilities = cached.cachedCapabilities
        lastKnownClusterCache = cached.lastKnownCluster
        lastSuccessAt = cached.lastSuccessAt
        preferredProviderId = cached.preferredProviderId
        log("resumeCachedSession", "STEP_2_SUCCESS", .info, "cached session resumed locally", [
            "flow_id": flowID,
            "wallet": adapter.provider.walletId,
            "user_public_key": WalletAdapterDebugFormatter.shortBase58(session.userPublicKey),
        ])
        return true
    }

    /// Read-only access to the persisted preference, used by UIs that want to
    /// skip the picker on launch.
    public var preferredWalletId: String? {
        preferredProviderId
    }

    public func getCapabilities() async throws -> WalletCapabilities {
        let flowID = makeFlowID("getCapabilities")
        log("getCapabilities", "STEP_1_START", .debug, "resolving native deeplink capabilities", [
            "flow_id": flowID,
            "wallet": adapter.provider.walletId,
            "cluster": adapter.cluster.rawValue,
        ])
        let capabilities = WalletCapabilities.nativeDeeplink(providerCapabilities: adapter.provider.capabilities)
        log("getCapabilities", "STEP_2_SUCCESS", .info, "native deeplink capabilities resolved", capabilityMetadata(capabilities, flowID: flowID))
        return capabilities
    }

    /// Rotate the ephemeral encryption keypair for a brand-new connect, so the
    /// handshake the wallet sees always matches the session it issues. No-op when
    /// a session is active (rotating would orphan it). `resumeCachedSession()` /
    /// `restore()` (reconnect-cached and extended auth cache) must NOT call this —
    /// they reuse the matching cached keypair. Call this before a user-initiated
    /// fresh connect so a soft logout (`signOutLocally`) can't leave a desynced
    /// keypair that the wallet then rejects with a decryption error.
    public func rotateEphemeralKeypair() {
        guard adapter.session == nil else { return }
        adapter = WalletAdapter(
            provider: adapter.provider,
            keypair: .generate(),
            cluster: adapter.cluster,
            logger: logger,
            logLevel: logLevel,
            payloadPolicy: payloadPolicy
        )
    }

    public func connect(cluster: Cluster? = nil) async throws -> Session {
        let flowID = makeFlowID("connect")
        do {
            log("connect", "STEP_1_START", .info, "connect request started", [
                "flow_id": flowID,
                "wallet": adapter.provider.walletId,
                "cluster": adapter.cluster.rawValue,
                "target_cluster": (cluster ?? adapter.cluster).rawValue,
            ])
            try ensureNoPendingRequest(method: "connect", flowID: flowID)
            let url = try adapter.connectURL(appURL: appURL, redirectLink: redirectLink, cluster: cluster)
            log("connect", "STEP_2_OPEN_URL", .info, "opening connect URL", [
                "flow_id": flowID,
                "pending": "connect",
                "url": WalletAdapterDebugFormatter.urlShape(url),
            ].merging(rawURLMetadata(["url_raw": url])) { _, new in new })
            return try await withCheckedThrowingContinuation { continuation in
                pending = .connect(flowID: flowID, continuation)
                Task { @MainActor in
                    await openOrFail(url, flowID: flowID)
                }
            }
        } catch {
            logFailure("connect", flowID: flowID, error: error)
            throw error
        }
    }

    public func signMessage(_ message: Data, display: WalletSigningDisplay = .utf8) async throws -> SignMessageResult {
        let flowID = makeFlowID("signMessage")
        do {
            log("signMessage", "STEP_1_START", .info, "sign message request started", [
                "flow_id": flowID,
                "pending": "signMessage",
                "message_bytes": "\(message.count)",
                "display": display.rawValue,
            ].merging(payloadPolicy.includesRawPayloads ? [
                "message_raw": WalletAdapterDebugFormatter.utf8OrBase58(message),
                "message_base58_raw": Base58.encode(message),
            ] : [:]) { _, new in new })
            try ensureNoPendingRequest(method: "signMessage", flowID: flowID)
            let url = try adapter.signMessageURL(message, redirectLink: redirectLink, display: display)
            log("signMessage", "STEP_2_OPEN_URL", .info, "opening sign message URL", [
                "flow_id": flowID,
                "pending": "signMessage",
                "url": WalletAdapterDebugFormatter.urlShape(url),
            ].merging(rawURLMetadata(["url_raw": url])) { _, new in new })
            return try await withCheckedThrowingContinuation { continuation in
                pending = .signMessage(flowID: flowID, continuation)
                Task { @MainActor in
                    await openOrFail(url, flowID: flowID)
                }
            }
        } catch {
            logFailure("signMessage", flowID: flowID, error: error)
            throw error
        }
    }

    public func signInWithSolana(_ input: SignInWithSolanaInput, cluster: Cluster? = nil) async throws -> SignInWithSolanaResult {
        let flowID = makeFlowID("signInWithSolana")
        do {
            log("signInWithSolana", "STEP_1_START", .info, "SIWS request started", siwsInputMetadata(input, flowID: flowID, cluster: cluster))
            try SignInWithSolanaMessage.validate(input)
            let expectedCluster = cluster ?? adapter.cluster
            log("signInWithSolana", "STEP_2_VALIDATE_OK", .debug, "SIWS input validated", [
                "flow_id": flowID,
                "expected_cluster": expectedCluster.rawValue,
                "input_chain_id": nonEmpty(input.chainId) ?? "nil",
            ])
            if let inputChainId = nonEmpty(input.chainId),
               !expectedCluster.matchesSignInWithSolanaChainId(inputChainId) {
                let error = WalletAdapterError.clusterMismatch(expected: expectedCluster, got: inputChainId)
                logFailure("signInWithSolana", flowID: flowID, error: error, metadata: [
                    "expected": expectedCluster.signInWithSolanaChainId,
                    "actual": inputChainId,
                ])
                throw error
            }

            let session: Session
            if let activeSession = adapter.session {
                if expectedCluster != adapter.cluster {
                    let error = WalletAdapterError.clusterMismatch(expected: expectedCluster, got: adapter.cluster.rawValue)
                    logFailure("signInWithSolana", flowID: flowID, error: error, metadata: [
                        "expected": expectedCluster.rawValue,
                        "actual": adapter.cluster.rawValue,
                    ])
                    throw error
                }
                session = activeSession
                log("signInWithSolana", "STEP_3_SESSION_OK", .debug, "active session will sign SIWS message", sessionMetadata(session, flowID: flowID))
            } else {
                log("signInWithSolana", "STEP_3_CONNECT_REQUIRED", .info, "no active session; connecting before SIWS signing", [
                    "flow_id": flowID,
                    "expected_cluster": expectedCluster.rawValue,
                ])
                session = try await connect(cluster: expectedCluster)
                log("signInWithSolana", "STEP_4_CONNECT_SUCCESS", .info, "connect completed for SIWS signing", sessionMetadata(session, flowID: flowID))
            }

            let message = try SignInWithSolanaMessage.make(
                input: input,
                address: session.userPublicKey,
                defaultDomain: appAuthority(),
                defaultURI: appURL,
                defaultChainId: adapter.cluster.signInWithSolanaChainId
            )
            let signedMessage = Data(message.utf8)
            log("signInWithSolana", "STEP_5_MESSAGE_BUILT", .debug, "SIWS message built", [
                "flow_id": flowID,
                "message_bytes": "\(signedMessage.count)",
                "account": WalletAdapterDebugFormatter.shortBase58(session.userPublicKey),
            ].merging(payloadPolicy.includesRawPayloads ? [
                "siws_message_raw": message,
                "siws_message_base58_raw": Base58.encode(signedMessage),
            ] : [:]) { _, new in new })
            let result = try await signMessage(signedMessage, display: .utf8)
            let siwsResult = SignInWithSolanaResult(
                account: session.userPublicKey,
                signedMessage: signedMessage,
                signature: result.signature,
                signatureType: .ed25519,
                session: session
            )
            log("signInWithSolana", "STEP_6_SUCCESS", .info, "SIWS request completed", [
                "flow_id": flowID,
                "account": WalletAdapterDebugFormatter.shortBase58(siwsResult.account),
                "signature_bytes": "\(siwsResult.signature.count)",
                "signature_type": siwsResult.signatureType.rawValue,
            ].merging(payloadPolicy.includesRawPayloads ? [
                "account_raw": siwsResult.account,
                "signature_raw": Base58.encode(siwsResult.signature),
                "signed_message_raw": message,
            ] : [:]) { _, new in new })
            return siwsResult
        } catch {
            logFailure("signInWithSolana", flowID: flowID, error: error)
            throw error
        }
    }

    public func signTransaction(_ transaction: Data) async throws -> SignTransactionResult {
        let flowID = makeFlowID("signTransaction")
        do {
            log("signTransaction", "STEP_1_START", .info, "sign transaction request started", [
                "flow_id": flowID,
                "pending": "signTransaction",
                "transaction_bytes": "\(transaction.count)",
            ].merging(payloadPolicy.includesRawPayloads ? ["transaction_raw": Base58.encode(transaction)] : [:]) { _, new in new })
            try ensureNoPendingRequest(method: "signTransaction", flowID: flowID)
            let url = try adapter.signTransactionURL(transaction, redirectLink: redirectLink)
            log("signTransaction", "STEP_2_OPEN_URL", .info, "opening sign transaction URL", [
                "flow_id": flowID,
                "pending": "signTransaction",
                "url": WalletAdapterDebugFormatter.urlShape(url),
            ].merging(rawURLMetadata(["url_raw": url])) { _, new in new })
            return try await withCheckedThrowingContinuation { continuation in
                pending = .signTransaction(flowID: flowID, continuation)
                Task { @MainActor in
                    await openOrFail(url, flowID: flowID)
                }
            }
        } catch {
            logFailure("signTransaction", flowID: flowID, error: error)
            throw error
        }
    }

    public func signAllTransactions(_ transactions: [Data]) async throws -> SignAllTransactionsResult {
        let flowID = makeFlowID("signAllTransactions")
        do {
            log("signAllTransactions", "STEP_1_START", .info, "sign all transactions request started", [
                "flow_id": flowID,
                "pending": "signAllTransactions",
                "transaction_count": "\(transactions.count)",
                "transaction_bytes": transactions.map(\.count).map(String.init).joined(separator: ","),
            ].merging(payloadPolicy.includesRawPayloads ? ["transactions_raw": transactions.map(Base58.encode).joined(separator: ",")] : [:]) { _, new in new })
            try ensureNoPendingRequest(method: "signAllTransactions", flowID: flowID)
            let url = try adapter.signAllTransactionsURL(transactions, redirectLink: redirectLink)
            log("signAllTransactions", "STEP_2_OPEN_URL", .info, "opening sign all transactions URL", [
                "flow_id": flowID,
                "pending": "signAllTransactions",
                "url": WalletAdapterDebugFormatter.urlShape(url),
            ].merging(rawURLMetadata(["url_raw": url])) { _, new in new })
            return try await withCheckedThrowingContinuation { continuation in
                pending = .signAllTransactions(flowID: flowID, continuation)
                Task { @MainActor in
                    await openOrFail(url, flowID: flowID)
                }
            }
        } catch {
            logFailure("signAllTransactions", flowID: flowID, error: error)
            throw error
        }
    }

    public func signAndSendTransaction(_ transaction: Data, sendOptions: SendOptions = .init()) async throws -> SignAndSendTransactionResult {
        let flowID = makeFlowID("signAndSendTransaction")
        do {
            log("signAndSendTransaction", "STEP_1_START", .info, "sign and send transaction request started", [
                "flow_id": flowID,
                "pending": "signAndSendTransaction",
                "transaction_bytes": "\(transaction.count)",
                "skip_preflight": "\(sendOptions.skipPreflight)",
                "preflight_commitment": sendOptions.preflightCommitment ?? "nil",
                "max_retries": sendOptions.maxRetries.map(String.init) ?? "nil",
            ].merging(payloadPolicy.includesRawPayloads ? ["transaction_raw": Base58.encode(transaction)] : [:]) { _, new in new })
            try ensureNoPendingRequest(method: "signAndSendTransaction", flowID: flowID)
            let url = try adapter.signAndSendTransactionURL(transaction, redirectLink: redirectLink, sendOptions: sendOptions)
            log("signAndSendTransaction", "STEP_2_OPEN_URL", .info, "opening sign and send transaction URL", [
                "flow_id": flowID,
                "pending": "signAndSendTransaction",
                "url": WalletAdapterDebugFormatter.urlShape(url),
            ].merging(rawURLMetadata(["url_raw": url])) { _, new in new })
            return try await withCheckedThrowingContinuation { continuation in
                pending = .signAndSendTransaction(flowID: flowID, continuation)
                Task { @MainActor in
                    await openOrFail(url, flowID: flowID)
                }
            }
        } catch {
            logFailure("signAndSendTransaction", flowID: flowID, error: error)
            throw error
        }
    }

    /// Sign locally via the wallet, then broadcast through a Solana JSON-RPC
    /// endpoint. Use this instead of native `signAndSendTransaction` when the
    /// wallet deprecates/doesn't support sign-and-send (e.g. Phantom), or when
    /// you want to control the RPC endpoint. Reusable across every provider.
    /// Returns the transaction signature (txid).
    public func signAndSendViaRPC(
        _ transaction: Data,
        rpcURL: URL,
        sendOptions: SendOptions = .init(),
        sender: SolanaRPCSender = SolanaRPCSender()
    ) async throws -> String {
        let flowID = makeFlowID("signAndSendViaRPC")
        do {
            log("signAndSendViaRPC", "STEP_1_START", .info, "sign-then-broadcast started", [
                "flow_id": flowID,
                "wallet": adapter.provider.walletId,
                "transaction_bytes": "\(transaction.count)",
                "skip_preflight": "\(sendOptions.skipPreflight)",
                "rpc_url": WalletAdapterDebugFormatter.urlShape(rpcURL),
            ].merging(rawURLMetadata(["rpc_url_raw": rpcURL])) { _, new in new })
            let signed = try await signTransaction(transaction)
            log("signAndSendViaRPC", "STEP_2_SIGNED", .info, "transaction signed; broadcasting", [
                "flow_id": flowID,
                "signed_bytes": "\(signed.transaction.count)",
            ])
            let txid = try await sender.sendTransaction(signed.transaction, rpcURL: rpcURL, sendOptions: sendOptions)
            touchLastSuccess()
            log("signAndSendViaRPC", "STEP_3_SUCCESS", .info, "transaction broadcast", [
                "flow_id": flowID,
                "txid": WalletAdapterDebugFormatter.shortBase58(txid),
            ].merging(payloadPolicy.includesRawPayloads ? ["txid_raw": txid] : [:]) { _, new in new })
            return txid
        } catch {
            logFailure("signAndSendViaRPC", flowID: flowID, error: error)
            throw error
        }
    }

    public func disconnect() async throws {
        let flowID = makeFlowID("disconnect")
        do {
            log("disconnect", "STEP_1_START", .info, "disconnect request started", [
                "flow_id": flowID,
                "wallet": adapter.provider.walletId,
                "has_session": "\(adapter.session != nil)",
            ])
            try ensureNoPendingRequest(method: "disconnect", flowID: flowID)
            let url = try adapter.disconnectURL(redirectLink: redirectLink)
            log("disconnect", "STEP_2_OPEN_URL", .info, "opening disconnect URL", [
                "flow_id": flowID,
                "url": WalletAdapterDebugFormatter.urlShape(url),
            ].merging(rawURLMetadata(["url_raw": url])) { _, new in new })
            guard await opener.openWalletURL(url) else {
                let error = WalletAdapterError.walletUnreachable
                logFailure("disconnect", flowID: flowID, error: error, metadata: rawURLMetadata(["url_raw": url]))
                throw error
            }
            log("disconnect", "STEP_3_OPEN_ACCEPTED", .debug, "wallet URL opener accepted disconnect URL", [
                "flow_id": flowID,
            ].merging(rawURLMetadata(["url_raw": url])) { _, new in new })
            adapter.clearSession()
            try persistState(flowID: flowID)
            log("disconnect", "STEP_4_SUCCESS", .info, "disconnect completed", [
                "flow_id": flowID,
                "has_session": "\(adapter.session != nil)",
            ])
        } catch {
            logFailure("disconnect", flowID: flowID, error: error)
            throw error
        }
    }

    /// Soft local logout. Drops the in-memory active session and cancels any
    /// pending request, but does **not** fire the wallet disconnect deeplink and
    /// does **not** wipe the keychain-cached state. The session token stays valid
    /// in the cache so `resumeCachedSession()` can restore it with zero wallet
    /// round-trips, and a later app launch still auto-restores it (extended auth
    /// cache). Use the hard `disconnect()` + `clearState()` to fully revoke.
    public func signOutLocally() async throws {
        let flowID = makeFlowID("signOutLocally")
        log("signOutLocally", "STEP_1_START", .info, "soft local logout started", [
            "flow_id": flowID,
            "wallet": adapter.provider.walletId,
            "has_session": "\(adapter.session != nil)",
            "pending": pending?.name ?? "none",
        ])
        if pending != nil {
            _ = cancelPendingRequest()
        }
        // In-memory drop only. Intentionally NOT persisting: `currentPersistableState()`
        // would read the now-nil session from `adapter.exportState()` and overwrite
        // the cached token, breaking offline reconnect. The on-disk blob keeps the
        // valid session.
        adapter.clearSession()
        log("signOutLocally", "STEP_2_SUCCESS", .info, "soft local logout complete; cache retained", [
            "flow_id": flowID,
            "has_session": "\(adapter.session != nil)",
        ])
    }

    public func authorize(cluster: Cluster? = nil) async throws -> Session {
        let flowID = makeFlowID("authorize")
        do {
            log("authorize", "STEP_1_ALIAS_START", .info, "authorize alias mapped to connect", [
                "flow_id": flowID,
                "target_method": "connect",
                "target_cluster": (cluster ?? adapter.cluster).rawValue,
            ])
            let session = try await connect(cluster: cluster)
            log("authorize", "STEP_2_ALIAS_SUCCESS", .info, "authorize alias completed", sessionMetadata(session, flowID: flowID))
            return session
        } catch {
            logFailure("authorize", flowID: flowID, error: error)
            throw error
        }
    }

    public func authorize(signInWithSolana input: SignInWithSolanaInput, cluster: Cluster? = nil) async throws -> SignInWithSolanaResult {
        let flowID = makeFlowID("authorize")
        do {
            log("authorize", "STEP_1_ALIAS_START", .info, "authorize SIWS alias mapped to signInWithSolana", siwsInputMetadata(input, flowID: flowID, cluster: cluster).merging([
                "target_method": "signInWithSolana",
            ]) { _, new in new })
            let result = try await signInWithSolana(input, cluster: cluster)
            log("authorize", "STEP_2_ALIAS_SUCCESS", .info, "authorize SIWS alias completed", [
                "flow_id": flowID,
                "account": WalletAdapterDebugFormatter.shortBase58(result.account),
                "signature_bytes": "\(result.signature.count)",
            ].merging(payloadPolicy.includesRawPayloads ? [
                "account_raw": result.account,
                "signature_raw": Base58.encode(result.signature),
                "signed_message_raw": WalletAdapterDebugFormatter.utf8OrBase58(result.signedMessage),
            ] : [:]) { _, new in new })
            return result
        } catch {
            logFailure("authorize", flowID: flowID, error: error)
            throw error
        }
    }

    public func deauthorize() async throws {
        let flowID = makeFlowID("deauthorize")
        do {
            log("deauthorize", "STEP_1_ALIAS_START", .info, "deauthorize alias mapped to disconnect", [
                "flow_id": flowID,
                "target_method": "disconnect",
            ])
            try await disconnect()
            log("deauthorize", "STEP_2_ALIAS_SUCCESS", .info, "deauthorize alias completed", [
                "flow_id": flowID,
                "has_session": "\(adapter.session != nil)",
            ])
        } catch {
            logFailure("deauthorize", flowID: flowID, error: error)
            throw error
        }
    }

    public func signMessages(_ messages: [Data], display: WalletSigningDisplay = .utf8) async throws -> [SignMessageResult] {
        let flowID = makeFlowID("signMessages")
        do {
            log("signMessages", "STEP_1_ALIAS_START", .info, "signMessages alias started", [
                "flow_id": flowID,
                "target_method": "signMessage",
                "message_count": "\(messages.count)",
                "message_bytes": messages.map(\.count).map(String.init).joined(separator: ","),
                "display": display.rawValue,
            ].merging(payloadPolicy.includesRawPayloads ? [
                "messages_raw": messages.map(WalletAdapterDebugFormatter.utf8OrBase58).joined(separator: ","),
            ] : [:]) { _, new in new })
            guard messages.count == 1, let message = messages.first else {
                let error = WalletAdapterError.unsupportedMethod("signMessages currently supports exactly one message on native iOS deeplinks.")
                logFailure("signMessages", flowID: flowID, error: error, metadata: [
                    "expected": "1",
                    "actual": "\(messages.count)",
                ])
                throw error
            }
            let result = try await signMessage(message, display: display)
            log("signMessages", "STEP_2_ALIAS_SUCCESS", .info, "signMessages alias completed", [
                "flow_id": flowID,
                "result_count": "1",
                "signature_bytes": "\(result.signature.count)",
            ].merging(payloadPolicy.includesRawPayloads ? [
                "signature_raw": Base58.encode(result.signature),
            ] : [:]) { _, new in new })
            return [result]
        } catch {
            logFailure("signMessages", flowID: flowID, error: error)
            throw error
        }
    }

    public func signTransactions(_ transactions: [Data]) async throws -> SignAllTransactionsResult {
        let flowID = makeFlowID("signTransactions")
        do {
            log("signTransactions", "STEP_1_ALIAS_START", .info, "signTransactions alias mapped to signAllTransactions", [
                "flow_id": flowID,
                "target_method": "signAllTransactions",
                "transaction_count": "\(transactions.count)",
                "transaction_bytes": transactions.map(\.count).map(String.init).joined(separator: ","),
            ].merging(payloadPolicy.includesRawPayloads ? ["transactions_raw": transactions.map(Base58.encode).joined(separator: ",")] : [:]) { _, new in new })
            let result = try await signAllTransactions(transactions)
            log("signTransactions", "STEP_2_ALIAS_SUCCESS", .info, "signTransactions alias completed", [
                "flow_id": flowID,
                "transaction_count": "\(result.transactions.count)",
                "transaction_bytes": result.transactions.map(\.count).map(String.init).joined(separator: ","),
            ].merging(payloadPolicy.includesRawPayloads ? ["transactions_raw": result.transactions.map(Base58.encode).joined(separator: ",")] : [:]) { _, new in new })
            return result
        } catch {
            logFailure("signTransactions", flowID: flowID, error: error)
            throw error
        }
    }

    public func signAndSendTransactions(_ transactions: [Data], sendOptions: SendOptions = .init()) async throws -> [SignAndSendTransactionResult] {
        let flowID = makeFlowID("signAndSendTransactions")
        do {
            log("signAndSendTransactions", "STEP_1_ALIAS_START", .info, "signAndSendTransactions alias started", [
                "flow_id": flowID,
                "target_method": "signAndSendTransaction",
                "transaction_count": "\(transactions.count)",
                "transaction_bytes": transactions.map(\.count).map(String.init).joined(separator: ","),
            ].merging(payloadPolicy.includesRawPayloads ? ["transactions_raw": transactions.map(Base58.encode).joined(separator: ",")] : [:]) { _, new in new })
            guard transactions.count == 1, let transaction = transactions.first else {
                let error = WalletAdapterError.unsupportedMethod("signAndSendTransactions currently supports exactly one transaction on native iOS deeplinks.")
                logFailure("signAndSendTransactions", flowID: flowID, error: error, metadata: [
                    "expected": "1",
                    "actual": "\(transactions.count)",
                ])
                throw error
            }
            let result = try await signAndSendTransaction(transaction, sendOptions: sendOptions)
            log("signAndSendTransactions", "STEP_2_ALIAS_SUCCESS", .info, "signAndSendTransactions alias completed", [
                "flow_id": flowID,
                "result_count": "1",
                "txid": WalletAdapterDebugFormatter.shortBase58(result.signature),
            ].merging(payloadPolicy.includesRawPayloads ? ["txid_raw": result.signature] : [:]) { _, new in new })
            return [result]
        } catch {
            logFailure("signAndSendTransactions", flowID: flowID, error: error)
            throw error
        }
    }

    @discardableResult
    public func cancelPendingRequest() -> Bool {
        guard let pending else {
            log("cancelPendingRequest", "STEP_1_NO_PENDING_REQUEST", .debug, "no pending wallet request to cancel", [
                "failure_hint": "No async wallet request is currently waiting for a callback.",
                "fix_hint": "Only call cancelPendingRequest after an API method has opened a wallet URL.",
            ])
            return false
        }
        self.pending = nil
        log("cancelPendingRequest", "STEP_1_CANCELLED", .info, "pending wallet request cancelled", [
            "flow_id": pending.flowID,
            "pending": pending.name,
        ])
        pending.resume(throwing: WalletAdapterError.requestCancelled)
        return true
    }

    @discardableResult
    public func handleOpenURL(_ url: URL) -> Bool {
        guard let pending else {
            // A hard disconnect/revoke comes back with an empty / identity-less
            // query and no pending request — a benign ack, not a failure. Only
            // treat it as FAIL when the callback actually carries an error or a
            // real encrypted response (errorCode / data / nonce), so genuine
            // stray-callback bugs still surface.
            let params = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let looksLikeRealResponse = params.contains {
                $0.name == "errorCode" || $0.name == "data" || $0.name == "nonce"
            }
            if !looksLikeRealResponse {
                log("handleOpenURL", "STEP_NO_PENDING_BENIGN_ACK", .debug, "callback with no pending request and empty/identity-less query (likely disconnect ack)", [
                    "callback": WalletAdapterDebugFormatter.urlShape(url),
                ].merging(rawURLMetadata(["callback_raw": url])) { _, new in new })
                return false
            }
            log("handleOpenURL", "STEP_FAIL_NO_PENDING_REQUEST", .error, "callback received without pending request", [
                "callback": WalletAdapterDebugFormatter.urlShape(url),
                "failure_hint": "A wallet callback arrived when no API request was pending.",
                "fix_hint": "Verify the app is not rebuilding the client before .onOpenURL and that only wallet callbacks are routed here.",
            ].merging(rawURLMetadata(["callback_raw": url])) { _, new in new })
            return false
        }
        guard matchesRedirectLink(url) else {
            log("handleOpenURL", "STEP_IGNORE_UNRELATED_CALLBACK", .debug, "callback does not match redirect link", [
                "flow_id": pending.flowID,
                "pending": pending.name,
                "callback": WalletAdapterDebugFormatter.urlShape(url),
                "redirect": WalletAdapterDebugFormatter.urlShape(redirectLink),
                "failure_hint": "The callback scheme, host, or path did not match the configured redirectLink.",
                "fix_hint": "Check the wallet redirect_link parameter and iOS URL scheme/universal link routing.",
            ].merging(rawURLMetadata(["callback_raw": url, "redirect_raw": redirectLink])) { _, new in new })
            return false
        }
        log("handleOpenURL", "STEP_1_CALLBACK_RECEIVED", .info, "routing wallet callback", [
            "flow_id": pending.flowID,
            "pending": pending.name,
            "callback": WalletAdapterDebugFormatter.urlShape(url),
        ].merging(rawURLMetadata(["callback_raw": url])) { _, new in new })
        self.pending = nil
        do {
            switch pending {
            case .connect(_, let continuation):
                let session = try adapter.handleConnectCallback(url)
                recordConnectSuccess(session: session)
                try persistState(flowID: pending.flowID)
                log("handleOpenURL", "STEP_2_RESUME_SUCCESS", .info, "connect callback resumed", [
                    "pending": pending.name,
                ].merging(sessionMetadata(session, flowID: pending.flowID)) { _, new in new })
                continuation.resume(returning: session)
            case .signMessage(_, let continuation):
                let result = try adapter.handleSignMessageCallback(url)
                touchLastSuccess()
                log("handleOpenURL", "STEP_2_RESUME_SUCCESS", .info, "sign message callback resumed", [
                    "pending": pending.name,
                ].merging(signMessageResultMetadata(result, flowID: pending.flowID)) { _, new in new })
                continuation.resume(returning: result)
            case .signTransaction(_, let continuation):
                let result = try adapter.handleSignTransactionCallback(url)
                touchLastSuccess()
                log("handleOpenURL", "STEP_2_RESUME_SUCCESS", .info, "sign transaction callback resumed", [
                    "pending": pending.name,
                ].merging(signTransactionResultMetadata(result, flowID: pending.flowID)) { _, new in new })
                continuation.resume(returning: result)
            case .signAllTransactions(_, let continuation):
                let result = try adapter.handleSignAllTransactionsCallback(url)
                touchLastSuccess()
                log("handleOpenURL", "STEP_2_RESUME_SUCCESS", .info, "sign all transactions callback resumed", [
                    "pending": pending.name,
                ].merging(signAllTransactionsResultMetadata(result, flowID: pending.flowID)) { _, new in new })
                continuation.resume(returning: result)
            case .signAndSendTransaction(_, let continuation):
                let result = try adapter.handleSignAndSendTransactionCallback(url)
                touchLastSuccess()
                log("handleOpenURL", "STEP_2_RESUME_SUCCESS", .info, "sign and send callback resumed", [
                    "pending": pending.name,
                ].merging(signAndSendResultMetadata(result, flowID: pending.flowID)) { _, new in new })
                continuation.resume(returning: result)
            }
        } catch {
            log("handleOpenURL", "STEP_FAIL_CALLBACK", .error, "callback handling failed", failureMetadata(error, flowID: pending.flowID, metadata: [
                "pending": pending.name,
            ].merging(rawURLMetadata(["callback_raw": url])) { _, new in new }))
            pending.resume(throwing: error)
        }
        return true
    }

    private func ensureNoPendingRequest(method: String, flowID: String) throws {
        if let pending {
            log(method, "STEP_FAIL_PENDING_REQUEST", .error, "operation already pending", failureMetadata(WalletAdapterError.operationInProgress, flowID: flowID, metadata: [
                "pending": pending.name,
                "pending_flow_id": pending.flowID,
            ]))
            throw WalletAdapterError.operationInProgress
        }
    }

    private func openOrFail(_ url: URL, flowID: String) async {
        guard await opener.openWalletURL(url) else {
            let pending = self.pending
            self.pending = nil
            log("openOrFail", "STEP_FAIL_OPEN_URL", .error, "wallet URL opener rejected URL", failureMetadata(WalletAdapterError.walletUnreachable, flowID: flowID, metadata: [
                "pending": pending?.name ?? "none",
                "url": WalletAdapterDebugFormatter.urlShape(url),
            ].merging(rawURLMetadata(["url_raw": url])) { _, new in new }))
            pending?.resume(throwing: WalletAdapterError.walletUnreachable)
            return
        }
        log("openOrFail", "STEP_3_OPEN_ACCEPTED", .debug, "wallet URL opener accepted URL", [
            "flow_id": flowID,
            "url": WalletAdapterDebugFormatter.urlShape(url),
        ].merging(rawURLMetadata(["url_raw": url])) { _, new in new })
    }

    private func matchesRedirectLink(_ url: URL) -> Bool {
        guard let callback = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let redirect = URLComponents(url: redirectLink, resolvingAgainstBaseURL: false) else {
            return false
        }
        return callback.scheme?.lowercased() == redirect.scheme?.lowercased() &&
            callback.host?.lowercased() == redirect.host?.lowercased() &&
            normalizedPath(callback.path) == normalizedPath(redirect.path)
    }

    private func normalizedPath(_ path: String) -> String {
        path.isEmpty ? "/" : path
    }

    private func persistState(flowID: String? = nil) throws {
        do {
            try stateStore?.saveState(currentPersistableState())
            log("persistState", "STEP_1_SAVED", .debug, "adapter state persisted", optionalFlowMetadata(flowID).merging([
                "wallet": adapter.provider.walletId,
                "cluster": adapter.cluster.rawValue,
                "has_session": "\(adapter.session != nil)",
                "preferred_provider": preferredProviderId ?? "nil",
                "cached_capabilities": "\(cachedCapabilities != nil)",
            ]) { _, new in new })
        } catch {
            log("persistState", "STEP_FAIL_SAVE", .error, "adapter state persistence failed", failureMetadata(error, flowID: flowID ?? "none", metadata: [
                "wallet": adapter.provider.walletId,
            ]))
            throw error
        }
    }

    /// Update the cache on successful connect: capture wallet label, snapshot
    /// capabilities, refresh the success timestamp, and pin the cluster.
    private func recordConnectSuccess(session: Session) {
        walletLabel = adapter.provider.capabilities.displayName
        cachedCapabilities = WalletCapabilities.nativeDeeplink(providerCapabilities: adapter.provider.capabilities)
        lastKnownClusterCache = adapter.cluster
        lastSuccessAt = Date()
        // Record which wallet was last connected so a host app can restore the
        // correct wallet's session on launch (extended auth cache). Best-effort:
        // a keychain write failure must not fail the connect that just succeeded.
        try? lastActiveStore?.saveLastActiveWalletId(adapter.provider.walletId)
    }

    /// Bump the cache's success timestamp after any non-connect wallet
    /// callback returns successfully. Lets UIs surface "last used N min ago".
    private func touchLastSuccess() {
        lastSuccessAt = Date()
    }

    /// Merge the adapter's transport-level state with the client's extended
    /// auth cache. This is what gets persisted to Keychain on every state
    /// transition (connect, disconnect, selectProvider, clearState, …).
    private func currentPersistableState() -> WalletAdapterState {
        let base = adapter.exportState()
        return WalletAdapterState(
            providerId: base.providerId,
            cluster: base.cluster,
            keypair: base.keypair,
            session: base.session,
            walletLabel: walletLabel,
            cachedCapabilities: cachedCapabilities,
            lastKnownCluster: lastKnownClusterCache ?? base.cluster,
            lastSuccessAt: lastSuccessAt,
            preferredProviderId: preferredProviderId
        )
    }

    private func log(_ method: String, _ step: String, _ level: WalletAdapterLogLevel, _ message: String, _ metadata: [String: String] = [:]) {
        guard logLevel != .off, level <= logLevel else { return }
        logger.log(WalletAdapterLogEvent(component: "WalletAdapterClient", method: method, step: step, phase: level == .error ? "FAIL" : "INFO", message: message, metadata: metadata))
    }

    private func logFailure(_ method: String, flowID: String, error: Error, metadata: [String: String] = [:]) {
        log(method, "STEP_FAIL", .error, "operation failed", failureMetadata(error, flowID: flowID, metadata: metadata))
    }

    private func makeFlowID(_ method: String) -> String {
        let flowID = "\(method)-\(nextFlowNumber)"
        nextFlowNumber += 1
        return flowID
    }

    private func failureMetadata(_ error: Error, flowID: String, metadata: [String: String] = [:]) -> [String: String] {
        let diagnostics = diagnostics(for: error)
        var result = [
            "flow_id": flowID,
            "error": "\(error)",
            "error_type": "\(type(of: error))",
            "error_code": errorCode(error),
            "failure_hint": diagnostics.failureHint,
            "fix_hint": diagnostics.fixHint,
        ]
        if let adapterError = error as? WalletAdapterError {
            switch adapterError {
            case .clusterMismatch(let expected, let got):
                result["expected"] = expected.rawValue
                result["actual"] = got
            case .unsupportedMethod(let message):
                result["unsupported_message"] = message
            case .malformedPayload(let message):
                result["malformed_message"] = message
            default:
                break
            }
        }
        return result.merging(metadata) { _, new in new }
    }

    private func diagnostics(for error: Error) -> (failureHint: String, fixHint: String) {
        guard let adapterError = error as? WalletAdapterError else {
            return (
                "A non-wallet-adapter error was thrown by storage, URL opening, or app integration code.",
                "Inspect the error text and the immediately preceding log step."
            )
        }
        switch adapterError {
        case .userRejected:
            return ("The wallet reported that the user rejected the request.", "Retry only after explicit user action.")
        case .invalidSession:
            return ("No valid wallet session was available for this request.", "Call connect/authorize again and ensure restored state matches the selected wallet.")
        case .unsupportedMethod:
            return ("The selected wallet or iOS deeplink compatibility layer does not support this method shape.", "Check getCapabilities and reduce batch size or route through WalletConnect when needed.")
        case .malformedPayload:
            return ("A request or callback payload was missing required fields or failed validation.", "Enable unsafe payload logs locally and compare the exact callback/request JSON to the wallet deeplink spec.")
        case .walletUnreachable:
            return ("iOS rejected the wallet URL open request or the wallet app is unavailable.", "Install the wallet, verify URL scheme/universal link handling, and check the opener result.")
        case .decryptionFailed:
            return ("The encrypted callback could not be decrypted with the current session/keypair.", "Verify the callback belongs to this pending request and that the client instance/keypair was not recreated.")
        case .clusterMismatch:
            return ("The requested SIWS chain/cluster does not match the active adapter cluster.", "Use a matching cluster and SIWS chainId before signing.")
        case .operationInProgress:
            return ("Another wallet request is already waiting for a callback.", "Wait for handleOpenURL, cancelPendingRequest, or the open failure before starting a new request.")
        case .noPendingRequest:
            return ("The operation expected an active request/session but none was present.", "Start the request flow first or reconnect the WalletConnect session.")
        case .requestCancelled:
            return ("The pending wallet request was cancelled by the app.", "Start a new request if the user still wants to continue.")
        case .other:
            return ("The wallet returned a wallet-specific error code.", "Inspect error_code/error_message and wallet-specific documentation.")
        }
    }

    private func errorCode(_ error: Error) -> String {
        guard let adapterError = error as? WalletAdapterError else { return "NON_WALLET_ADAPTER_ERROR" }
        switch adapterError {
        case .userRejected:
            return "USER_REJECTED"
        case .invalidSession:
            return "INVALID_SESSION"
        case .unsupportedMethod:
            return "UNSUPPORTED_METHOD"
        case .malformedPayload:
            return "MALFORMED_PAYLOAD"
        case .walletUnreachable:
            return "WALLET_UNREACHABLE"
        case .decryptionFailed:
            return "DECRYPTION_FAILED"
        case .clusterMismatch:
            return "CLUSTER_MISMATCH"
        case .operationInProgress:
            return "OPERATION_IN_PROGRESS"
        case .noPendingRequest:
            return "NO_PENDING_REQUEST"
        case .requestCancelled:
            return "REQUEST_CANCELLED"
        case .other(let code, _):
            return code
        }
    }

    private func optionalFlowMetadata(_ flowID: String?) -> [String: String] {
        guard let flowID else { return [:] }
        return ["flow_id": flowID]
    }

    private func capabilityMetadata(_ capabilities: WalletCapabilities, flowID: String) -> [String: String] {
        let methods = capabilities.methods.map { $0.method.rawValue }.joined(separator: ",")
        let supportedMethods = capabilities.methods.filter { $0.isSupported }.map { $0.method.rawValue }.joined(separator: ",")
        let maxMessages = capabilities.limits.maxMessagesPerRequest.map(String.init) ?? "nil"
        let maxSignAndSend = capabilities.limits.maxSignAndSendTransactionsPerRequest.map(String.init) ?? "nil"
        var metadata: [String: String] = [
            "flow_id": flowID,
            "wallet": capabilities.walletId,
            "display_name": capabilities.displayName,
            "transport": capabilities.transport.rawValue,
            "method_count": "\(capabilities.methods.count)",
            "methods": methods,
            "supported_methods": supportedMethods,
            "feature_identifiers": capabilities.featureIdentifiers.joined(separator: ","),
            "max_messages_per_request": maxMessages,
            "max_sign_and_send_transactions_per_request": maxSignAndSend,
        ]
        metadata.merge(rawJSONMetadata("capabilities_json_raw", capabilities)) { _, new in new }
        return metadata
    }

    private func sessionMetadata(_ session: Session, flowID: String) -> [String: String] {
        [
            "flow_id": flowID,
            "wallet": adapter.provider.walletId,
            "user_public_key": WalletAdapterDebugFormatter.shortBase58(session.userPublicKey),
            "wallet_encryption_public_key": WalletAdapterDebugFormatter.shortBase58(Base58.encode(session.walletEncryptionPublicKey)),
            "session_present": "true",
        ].merging(payloadPolicy.includesRawPayloads ? [
            "user_public_key_raw": session.userPublicKey,
            "wallet_encryption_public_key_raw": Base58.encode(session.walletEncryptionPublicKey),
            "session_token_raw": session.token,
        ] : [:]) { _, new in new }
    }

    private func signMessageResultMetadata(_ result: SignMessageResult, flowID: String) -> [String: String] {
        [
            "flow_id": flowID,
            "wallet": adapter.provider.walletId,
            "signature_bytes": "\(result.signature.count)",
        ].merging(payloadPolicy.includesRawPayloads ? [
            "signature_raw": Base58.encode(result.signature),
        ] : [:]) { _, new in new }
    }

    private func signTransactionResultMetadata(_ result: SignTransactionResult, flowID: String) -> [String: String] {
        [
            "flow_id": flowID,
            "wallet": adapter.provider.walletId,
            "transaction_bytes": "\(result.transaction.count)",
        ].merging(payloadPolicy.includesRawPayloads ? [
            "transaction_raw": Base58.encode(result.transaction),
        ] : [:]) { _, new in new }
    }

    private func signAllTransactionsResultMetadata(_ result: SignAllTransactionsResult, flowID: String) -> [String: String] {
        [
            "flow_id": flowID,
            "wallet": adapter.provider.walletId,
            "transaction_count": "\(result.transactions.count)",
            "transaction_bytes": result.transactions.map(\.count).map(String.init).joined(separator: ","),
        ].merging(payloadPolicy.includesRawPayloads ? [
            "transactions_raw": result.transactions.map(Base58.encode).joined(separator: ","),
        ] : [:]) { _, new in new }
    }

    private func signAndSendResultMetadata(_ result: SignAndSendTransactionResult, flowID: String) -> [String: String] {
        [
            "flow_id": flowID,
            "wallet": adapter.provider.walletId,
            "txid": WalletAdapterDebugFormatter.shortBase58(result.signature),
        ].merging(payloadPolicy.includesRawPayloads ? [
            "txid_raw": result.signature,
        ] : [:]) { _, new in new }
    }

    private func siwsInputMetadata(_ input: SignInWithSolanaInput, flowID: String, cluster: Cluster?) -> [String: String] {
        [
            "flow_id": flowID,
            "wallet": adapter.provider.walletId,
            "nonce_length": "\(input.nonce.count)",
            "has_domain": "\(nonEmpty(input.domain) != nil)",
            "has_statement": "\(nonEmpty(input.statement) != nil)",
            "has_uri": "\(input.uri != nil)",
            "input_chain_id": nonEmpty(input.chainId) ?? "nil",
            "target_cluster": (cluster ?? adapter.cluster).rawValue,
            "resource_count": "\(input.resources.count)",
        ].merging(rawJSONMetadata("siws_input_json_raw", input)) { _, new in new }
    }

    private func rawJSONMetadata<T: Encodable>(_ key: String, _ value: T) -> [String: String] {
        guard payloadPolicy.includesRawPayloads else { return [:] }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return [key: "unavailable"]
        }
        return [key: string]
    }

    private func rawURLMetadata(_ values: [String: URL]) -> [String: String] {
        guard payloadPolicy.includesRawPayloads else { return [:] }
        return Dictionary(uniqueKeysWithValues: values.map { key, url in (key, url.absoluteString) })
    }

    private func pendingMetadata() -> [String: String] {
        [
            "pending": pending?.name ?? "none",
            "pending_flow_id": pending?.flowID ?? "none",
        ]
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func appAuthority() -> String? {
        guard let components = URLComponents(url: appURL, resolvingAgainstBaseURL: false),
              let host = components.host else {
            return nil
        }
        if let port = components.port {
            return "\(host):\(port)"
        }
        return host
    }
}

private enum PendingRequest {
    case connect(flowID: String, CheckedContinuation<Session, Error>)
    case signMessage(flowID: String, CheckedContinuation<SignMessageResult, Error>)
    case signTransaction(flowID: String, CheckedContinuation<SignTransactionResult, Error>)
    case signAllTransactions(flowID: String, CheckedContinuation<SignAllTransactionsResult, Error>)
    case signAndSendTransaction(flowID: String, CheckedContinuation<SignAndSendTransactionResult, Error>)

    var name: String {
        switch self {
        case .connect: "connect"
        case .signMessage: "signMessage"
        case .signTransaction: "signTransaction"
        case .signAllTransactions: "signAllTransactions"
        case .signAndSendTransaction: "signAndSendTransaction"
        }
    }

    var flowID: String {
        switch self {
        case .connect(let flowID, _),
             .signMessage(let flowID, _),
             .signTransaction(let flowID, _),
             .signAllTransactions(let flowID, _),
             .signAndSendTransaction(let flowID, _):
            flowID
        }
    }

    func resume(throwing error: Error) {
        switch self {
        case .connect(_, let continuation):
            continuation.resume(throwing: error)
        case .signMessage(_, let continuation):
            continuation.resume(throwing: error)
        case .signTransaction(_, let continuation):
            continuation.resume(throwing: error)
        case .signAllTransactions(_, let continuation):
            continuation.resume(throwing: error)
        case .signAndSendTransaction(_, let continuation):
            continuation.resume(throwing: error)
        }
    }
}
