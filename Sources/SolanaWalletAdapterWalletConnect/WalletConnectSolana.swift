import Foundation
import SolanaWalletAdapter
import SolanaWalletAdapterCore

/// Solana JSON-RPC methods documented by WalletConnect/Reown for wallet signing.
public enum WalletConnectSolanaMethod: String, Sendable, Codable, CaseIterable {
    case getAccounts = "solana_getAccounts"
    case requestAccounts = "solana_requestAccounts"
    case signMessage = "solana_signMessage"
    case signTransaction = "solana_signTransaction"
    case signAllTransactions = "solana_signAllTransactions"
    case signAndSendTransaction = "solana_signAndSendTransaction"
}

/// CAIP-2 chain identifiers WalletConnect v2 wallets (Jupiter, etc.) expect:
/// `solana:` + the first 32 base58 chars of the cluster's genesis hash. The
/// `solana:mainnet` "Wallet Standard" form is rejected by spec-strict WC
/// wallets, so it must not be sent on the wire (`namespace.chains` / `chainId`).
public enum WalletConnectSolanaChain: String, Sendable, Codable, CaseIterable {
    case mainnet = "solana:5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp"
    case devnet = "solana:EtWTRABZaYq6iMfeYKouRu166VU2xqai"
    case testnet = "solana:4uhcVJyU9pJkvQyS88uRDiswHXSCkY3z"
}

public extension WalletConnectSolanaChain {
    init(cluster: Cluster) {
        switch cluster {
        case .mainnetBeta:
            self = .mainnet
        case .devnet:
            self = .devnet
        case .testnet:
            self = .testnet
        }
    }
}

/// Minimal namespace proposal data an app can pass into a WalletConnect/Reown Sign session.
public struct WalletConnectSolanaNamespace: Sendable, Equatable, Codable {
    public let chains: [String]
    public let methods: [String]
    public let events: [String]

    public init(chains: [String], methods: [String], events: [String] = Self.defaultEvents) {
        self.chains = chains
        self.methods = methods
        self.events = events
    }

    public static let defaultEvents = ["chainChanged", "accountsChanged"]

    public static func proposal(
        chains: [WalletConnectSolanaChain] = [.mainnet],
        methods: [WalletConnectSolanaMethod] = Self.defaultMethods,
        events: [String] = Self.defaultEvents
    ) -> WalletConnectSolanaNamespace {
        WalletConnectSolanaNamespace(
            chains: chains.map(\.rawValue),
            methods: methods.map(\.rawValue),
            events: events
        )
    }

    public static let defaultMethods: [WalletConnectSolanaMethod] = [
        .getAccounts,
        .requestAccounts,
        .signMessage,
        .signTransaction,
        .signAllTransactions,
        .signAndSendTransaction,
    ]
}

/// Local-only Reown/AppKit project configuration. Do not hardcode project IDs in package source.
public struct ReownProjectConfiguration: Sendable, Equatable, Codable {
    public let projectId: String
    public let metadata: ReownAppMetadata

    public init(projectId: String, metadata: ReownAppMetadata) throws {
        let trimmedProjectId = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedProjectId.isEmpty else {
            throw WalletAdapterError.malformedPayload("Reown projectId must not be empty.")
        }
        self.projectId = trimmedProjectId
        self.metadata = metadata
    }
}

public struct ReownAppMetadata: Sendable, Equatable, Codable {
    public let name: String
    public let description: String
    public let url: URL
    public let icons: [URL]
    public let redirect: ReownRedirectMetadata?

    public init(
        name: String,
        description: String,
        url: URL,
        icons: [URL],
        redirect: ReownRedirectMetadata? = nil
    ) {
        self.name = name
        self.description = description
        self.url = url
        self.icons = icons
        self.redirect = redirect
    }
}

public struct ReownRedirectMetadata: Sendable, Equatable, Codable {
    public let native: String?
    public let universal: URL?

    public init(native: String? = nil, universal: URL? = nil) {
        self.native = native
        self.universal = universal
    }
}

public enum JupiterMobileWalletConnect {
    public static let walletId = "jupiter"
    public static let displayName = "Jupiter Mobile"
    public static let url = URL(string: "https://jup.ag/mobile")!
    /// The Jupiter adapter published on npm targets this wallet button id through Reown.
    public static let reownWalletButtonId = "jupiter"
}

public struct WalletConnectSolanaSession: Sendable, Equatable, Codable {
    public let topic: String
    public let chain: String
    public let accounts: [WalletConnectSolanaAccount]

    public init(topic: String, chain: String, accounts: [WalletConnectSolanaAccount]) {
        self.topic = topic
        self.chain = chain
        self.accounts = accounts
    }

    public var primaryPubkey: String? {
        accounts.first?.pubkey
    }
}

public struct WalletConnectSolanaAccount: Sendable, Equatable, Codable {
    public let pubkey: String

    public init(pubkey: String) {
        self.pubkey = pubkey
    }
}

public struct WalletConnectSolanaJSONRPCRequest<Params>: Sendable, Equatable, Encodable
where Params: Sendable & Equatable & Encodable {
    public let id: Int
    public let jsonrpc: String
    public let method: WalletConnectSolanaMethod
    public let params: Params

    public init(id: Int, method: WalletConnectSolanaMethod, params: Params) {
        self.id = id
        self.jsonrpc = "2.0"
        self.method = method
        self.params = params
    }
}

public struct WalletConnectEmptyParams: Sendable, Equatable, Encodable {
    public init() {}
}

public struct WalletConnectSolanaSignMessageParams: Sendable, Equatable, Encodable {
    /// Base58-encoded message bytes.
    public let message: String
    public let pubkey: String

    public init(message: String, pubkey: String) {
        self.message = message
        self.pubkey = pubkey
    }
}

public struct WalletConnectSolanaSignTransactionParams: Sendable, Equatable, Encodable {
    /// Base64-encoded serialized Solana transaction.
    public let transaction: String

    public init(transaction: String) {
        self.transaction = transaction
    }
}

public struct WalletConnectSolanaSignAllTransactionsParams: Sendable, Equatable, Encodable {
    /// Base64-encoded serialized Solana transactions.
    public let transactions: [String]

    public init(transactions: [String]) {
        self.transactions = transactions
    }
}

public struct WalletConnectSolanaSignAndSendTransactionParams: Sendable, Equatable, Encodable {
    /// Base64-encoded serialized Solana transaction.
    public let transaction: String
    public let sendOptions: WalletConnectSolanaSendOptions

    public init(transaction: String, sendOptions: WalletConnectSolanaSendOptions = .init()) {
        self.transaction = transaction
        self.sendOptions = sendOptions
    }
}

public struct WalletConnectSolanaSendOptions: Sendable, Equatable, Encodable {
    public let skipPreflight: Bool
    public let preflightCommitment: String?
    public let maxRetries: Int?
    public let minContextSlot: UInt64?

    public init(
        skipPreflight: Bool = false,
        preflightCommitment: String? = nil,
        maxRetries: Int? = nil,
        minContextSlot: UInt64? = nil
    ) {
        self.skipPreflight = skipPreflight
        self.preflightCommitment = preflightCommitment
        self.maxRetries = maxRetries
        self.minContextSlot = minContextSlot
    }

    public init(_ sendOptions: SendOptions, minContextSlot: UInt64? = nil) {
        self.init(
            skipPreflight: sendOptions.skipPreflight,
            preflightCommitment: sendOptions.preflightCommitment,
            maxRetries: sendOptions.maxRetries,
            minContextSlot: minContextSlot
        )
    }
}

public enum WalletConnectSolanaRequests {
    public static func getAccounts(id: Int = 1) -> WalletConnectSolanaJSONRPCRequest<WalletConnectEmptyParams> {
        WalletConnectSolanaJSONRPCRequest(id: id, method: .getAccounts, params: WalletConnectEmptyParams())
    }

    public static func requestAccounts(id: Int = 1) -> WalletConnectSolanaJSONRPCRequest<WalletConnectEmptyParams> {
        WalletConnectSolanaJSONRPCRequest(id: id, method: .requestAccounts, params: WalletConnectEmptyParams())
    }

    public static func signMessage(
        _ message: Data,
        pubkey: String,
        id: Int = 1
    ) -> WalletConnectSolanaJSONRPCRequest<WalletConnectSolanaSignMessageParams> {
        WalletConnectSolanaJSONRPCRequest(
            id: id,
            method: .signMessage,
            params: WalletConnectSolanaSignMessageParams(message: Base58.encode(message), pubkey: pubkey)
        )
    }

    public static func signTransaction(
        _ transaction: Data,
        id: Int = 1
    ) -> WalletConnectSolanaJSONRPCRequest<WalletConnectSolanaSignTransactionParams> {
        WalletConnectSolanaJSONRPCRequest(
            id: id,
            method: .signTransaction,
            params: WalletConnectSolanaSignTransactionParams(transaction: transaction.base64EncodedString())
        )
    }

    public static func signAllTransactions(
        _ transactions: [Data],
        id: Int = 1
    ) -> WalletConnectSolanaJSONRPCRequest<WalletConnectSolanaSignAllTransactionsParams> {
        WalletConnectSolanaJSONRPCRequest(
            id: id,
            method: .signAllTransactions,
            params: WalletConnectSolanaSignAllTransactionsParams(
                transactions: transactions.map { $0.base64EncodedString() }
            )
        )
    }

    public static func signAndSendTransaction(
        _ transaction: Data,
        sendOptions: WalletConnectSolanaSendOptions = .init(),
        id: Int = 1
    ) -> WalletConnectSolanaJSONRPCRequest<WalletConnectSolanaSignAndSendTransactionParams> {
        WalletConnectSolanaJSONRPCRequest(
            id: id,
            method: .signAndSendTransaction,
            params: WalletConnectSolanaSignAndSendTransactionParams(
                transaction: transaction.base64EncodedString(),
                sendOptions: sendOptions
            )
        )
    }
}

public struct WalletConnectSolanaJSONRPCResponse<Result>: Sendable, Equatable, Decodable
where Result: Sendable & Equatable & Decodable {
    public let id: Int
    public let jsonrpc: String
    public let result: Result?
    public let error: WalletConnectSolanaJSONRPCError?

    public init(id: Int, jsonrpc: String = "2.0", result: Result?, error: WalletConnectSolanaJSONRPCError? = nil) {
        self.id = id
        self.jsonrpc = jsonrpc
        self.result = result
        self.error = error
    }
}

public struct WalletConnectSolanaJSONRPCError: Sendable, Equatable, Decodable {
    public let code: Int
    public let message: String

    public init(code: Int, message: String) {
        self.code = code
        self.message = message
    }
}

public struct WalletConnectSolanaAccountsResult: Sendable, Equatable, Decodable {
    public let accounts: [WalletConnectSolanaAccount]

    public init(accounts: [WalletConnectSolanaAccount]) {
        self.accounts = accounts
    }

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var accounts: [WalletConnectSolanaAccount] = []
        while !container.isAtEnd {
            accounts.append(try container.decode(WalletConnectSolanaAccount.self))
        }
        self.accounts = accounts
    }
}

public struct WalletConnectSolanaSignMessageResult: Sendable, Equatable, Decodable {
    public let signature: String

    public init(signature: String) {
        self.signature = signature
    }

    public var signatureData: Data? {
        Base58.decode(signature)
    }
}

public struct WalletConnectSolanaSignTransactionResult: Sendable, Equatable, Decodable {
    public let signature: String?
    public let transaction: String?

    public init(signature: String? = nil, transaction: String? = nil) {
        self.signature = signature
        self.transaction = transaction
    }

    public var signatureData: Data? {
        signature.flatMap(Base58.decode)
    }

    public var transactionData: Data? {
        transaction.flatMap { Data(base64Encoded: $0) }
    }
}

public struct WalletConnectSolanaSignAllTransactionsResult: Sendable, Equatable, Decodable {
    public let transactions: [String]

    public init(transactions: [String]) {
        self.transactions = transactions
    }

    public var transactionData: [Data]? {
        let decoded = transactions.compactMap { Data(base64Encoded: $0) }
        guard decoded.count == transactions.count else { return nil }
        return decoded
    }
}

public struct WalletConnectSolanaSignAndSendTransactionResult: Sendable, Equatable, Decodable {
    public let signature: String

    public init(signature: String) {
        self.signature = signature
    }

    public var signatureData: Data? {
        Base58.decode(signature)
    }
}

public protocol WalletConnectSolanaTransport: Sendable {
    func connect(
        configuration: ReownProjectConfiguration,
        namespace: WalletConnectSolanaNamespace
    ) async throws -> WalletConnectSolanaSession

    func request<Params, Result>(
        _ request: WalletConnectSolanaJSONRPCRequest<Params>,
        chain: String,
        session: WalletConnectSolanaSession,
        responseType: Result.Type
    ) async throws -> Result
    where Params: Sendable & Equatable & Encodable, Result: Sendable & Decodable

    func disconnect(session: WalletConnectSolanaSession) async throws
}

/// High-level Solana signing facade for apps that provide a WalletConnect/Reown transport.
public actor WalletConnectSolanaClient<Transport: WalletConnectSolanaTransport> {
    public let configuration: ReownProjectConfiguration
    public let namespace: WalletConnectSolanaNamespace
    private let transport: Transport
    private let logger: any WalletAdapterLogger
    private let logLevel: WalletAdapterLogLevel
    private let payloadPolicy: WalletAdapterLogPayloadPolicy
    private var activeSession: WalletConnectSolanaSession?
    private var nextFlowNumber = 1

    public init(
        configuration: ReownProjectConfiguration,
        namespace: WalletConnectSolanaNamespace = .proposal(),
        transport: Transport,
        logger: any WalletAdapterLogger = WalletAdapterLoggers.disabled,
        logLevel: WalletAdapterLogLevel = .off,
        payloadPolicy: WalletAdapterLogPayloadPolicy = .redacted
    ) {
        self.configuration = configuration
        self.namespace = namespace
        self.transport = transport
        self.logger = logger
        self.logLevel = logLevel
        self.payloadPolicy = payloadPolicy
        if logLevel != .off, WalletAdapterLogLevel.debug <= logLevel {
            logger.log(WalletAdapterLogEvent(
                component: "WalletConnectSolanaClient",
                method: "init",
                step: "STEP_1_READY",
                phase: "INFO",
                message: "WalletConnect Solana client initialized",
                metadata: [
                    "chains": namespace.chains.joined(separator: ","),
                    "methods": namespace.methods.joined(separator: ","),
                    "event_count": "\(namespace.events.count)",
                    "project_id_present": "\(!configuration.projectId.isEmpty)",
                    "project_id_chars": "\(configuration.projectId.count)",
                    "payload_policy": "\(payloadPolicy)",
                ]
            ))
        }
    }

    public var session: WalletConnectSolanaSession? {
        activeSession
    }

    public func getCapabilities() async throws -> WalletCapabilities {
        let flowID = makeFlowID("getCapabilities")
        log("getCapabilities", "STEP_1_START", .debug, "resolving WalletConnect Solana capabilities", [
            "flow_id": flowID,
            "chains": namespace.chains.joined(separator: ","),
            "methods": namespace.methods.joined(separator: ","),
        ])
        let capabilities = WalletCapabilities(
            walletId: "walletconnect",
            displayName: "WalletConnect Solana",
            transport: .walletConnect,
            methods: walletConnectMethodSupports(),
            featureIdentifiers: [
                "reown:sign",
                "solana:walletconnect",
            ],
            limits: .unknown
        )
        log("getCapabilities", "STEP_2_SUCCESS", .info, "WalletConnect Solana capabilities resolved", capabilityMetadata(capabilities, flowID: flowID))
        return capabilities
    }

    @discardableResult
    public func connect() async throws -> WalletConnectSolanaSession {
        let flowID = makeFlowID("connect")
        do {
            log("connect", "STEP_1_START", .info, "WalletConnect connect started", [
                "flow_id": flowID,
                "chains": namespace.chains.joined(separator: ","),
                "methods": namespace.methods.joined(separator: ","),
                "event_count": "\(namespace.events.count)",
                "project_id_present": "\(!configuration.projectId.isEmpty)",
                "project_id_chars": "\(configuration.projectId.count)",
            ].merging(rawJSONMetadata("namespace_json_raw", namespace)) { _, new in new })
            let session = try await transport.connect(configuration: configuration, namespace: namespace)
            activeSession = session
            log("connect", "STEP_2_SUCCESS", .info, "WalletConnect session established", sessionMetadata(session, flowID: flowID))
            return session
        } catch {
            logFailure("connect", flowID: flowID, error: error)
            throw error
        }
    }

    public func disconnect() async throws {
        let flowID = makeFlowID("disconnect")
        do {
            log("disconnect", "STEP_1_START", .info, "WalletConnect disconnect started", [
                "flow_id": flowID,
                "has_session": "\(activeSession != nil)",
            ])
            guard let session = activeSession else {
                throw WalletAdapterError.noPendingRequest
            }
            log("disconnect", "STEP_2_SESSION_OK", .debug, "active WalletConnect session found", sessionMetadata(session, flowID: flowID))
            try await transport.disconnect(session: session)
            activeSession = nil
            log("disconnect", "STEP_3_SUCCESS", .info, "WalletConnect session disconnected", [
                "flow_id": flowID,
                "has_session": "\(activeSession != nil)",
            ])
        } catch {
            logFailure("disconnect", flowID: flowID, error: error)
            throw error
        }
    }

    public func getAccounts(id: Int = 1) async throws -> WalletConnectSolanaAccountsResult {
        let flowID = makeFlowID("getAccounts")
        do {
            log("getAccounts", "STEP_1_START", .info, "WalletConnect get accounts started", ["flow_id": flowID, "request_id": "\(id)"])
            let session = try requireSession(method: "getAccounts", flowID: flowID)
            return try await performRequest(
                WalletConnectSolanaRequests.getAccounts(id: id),
                session: session,
                responseType: WalletConnectSolanaAccountsResult.self,
                method: "getAccounts",
                flowID: flowID,
                resultMetadata: accountsResultMetadata
            )
        } catch {
            logFailure("getAccounts", flowID: flowID, error: error)
            throw error
        }
    }

    public func requestAccounts(id: Int = 1) async throws -> WalletConnectSolanaAccountsResult {
        let flowID = makeFlowID("requestAccounts")
        do {
            log("requestAccounts", "STEP_1_START", .info, "WalletConnect request accounts started", ["flow_id": flowID, "request_id": "\(id)"])
            let session = try requireSession(method: "requestAccounts", flowID: flowID)
            return try await performRequest(
                WalletConnectSolanaRequests.requestAccounts(id: id),
                session: session,
                responseType: WalletConnectSolanaAccountsResult.self,
                method: "requestAccounts",
                flowID: flowID,
                resultMetadata: accountsResultMetadata
            )
        } catch {
            logFailure("requestAccounts", flowID: flowID, error: error)
            throw error
        }
    }

    public func signMessage(
        _ message: Data,
        pubkey: String? = nil,
        id: Int = 1
    ) async throws -> WalletConnectSolanaSignMessageResult {
        let flowID = makeFlowID("signMessage")
        do {
            log("signMessage", "STEP_1_START", .info, "WalletConnect sign message started", [
                "flow_id": flowID,
                "request_id": "\(id)",
                "message_bytes": "\(message.count)",
                "pubkey_source": pubkey == nil ? "session_primary" : "explicit",
            ].merging(payloadPolicy.includesRawPayloads ? [
                "message_raw": WalletAdapterDebugFormatter.utf8OrBase58(message),
                "message_base58_raw": Base58.encode(message),
            ] : [:]) { _, new in new })
            let session = try requireSession(method: "signMessage", flowID: flowID)
            let signer = try pubkey ?? requirePrimaryPubkey(session, method: "signMessage", flowID: flowID)
            return try await performRequest(
                WalletConnectSolanaRequests.signMessage(message, pubkey: signer, id: id),
                session: session,
                responseType: WalletConnectSolanaSignMessageResult.self,
                method: "signMessage",
                flowID: flowID,
                requestMetadata: [
                    "signer": WalletAdapterDebugFormatter.shortBase58(signer),
                ].merging(payloadPolicy.includesRawPayloads ? ["signer_raw": signer] : [:]) { _, new in new },
                resultMetadata: signMessageResultMetadata
            )
        } catch {
            logFailure("signMessage", flowID: flowID, error: error)
            throw error
        }
    }

    public func signTransaction(
        _ transaction: Data,
        id: Int = 1
    ) async throws -> WalletConnectSolanaSignTransactionResult {
        let flowID = makeFlowID("signTransaction")
        do {
            log("signTransaction", "STEP_1_START", .info, "WalletConnect sign transaction started", [
                "flow_id": flowID,
                "request_id": "\(id)",
                "transaction_bytes": "\(transaction.count)",
            ].merging(payloadPolicy.includesRawPayloads ? ["transaction_raw": transaction.base64EncodedString()] : [:]) { _, new in new })
            let session = try requireSession(method: "signTransaction", flowID: flowID)
            return try await performRequest(
                WalletConnectSolanaRequests.signTransaction(transaction, id: id),
                session: session,
                responseType: WalletConnectSolanaSignTransactionResult.self,
                method: "signTransaction",
                flowID: flowID,
                resultMetadata: signTransactionResultMetadata
            )
        } catch {
            logFailure("signTransaction", flowID: flowID, error: error)
            throw error
        }
    }

    public func signAllTransactions(
        _ transactions: [Data],
        id: Int = 1
    ) async throws -> WalletConnectSolanaSignAllTransactionsResult {
        let flowID = makeFlowID("signAllTransactions")
        do {
            log("signAllTransactions", "STEP_1_START", .info, "WalletConnect sign all transactions started", [
                "flow_id": flowID,
                "request_id": "\(id)",
                "transaction_count": "\(transactions.count)",
                "transaction_bytes": transactions.map(\.count).map(String.init).joined(separator: ","),
            ].merging(payloadPolicy.includesRawPayloads ? ["transactions_raw": transactions.map { $0.base64EncodedString() }.joined(separator: ",")] : [:]) { _, new in new })
            let session = try requireSession(method: "signAllTransactions", flowID: flowID)
            return try await performRequest(
                WalletConnectSolanaRequests.signAllTransactions(transactions, id: id),
                session: session,
                responseType: WalletConnectSolanaSignAllTransactionsResult.self,
                method: "signAllTransactions",
                flowID: flowID,
                resultMetadata: signAllTransactionsResultMetadata
            )
        } catch {
            logFailure("signAllTransactions", flowID: flowID, error: error)
            throw error
        }
    }

    public func signAndSendTransaction(
        _ transaction: Data,
        sendOptions: WalletConnectSolanaSendOptions = .init(),
        id: Int = 1
    ) async throws -> WalletConnectSolanaSignAndSendTransactionResult {
        let flowID = makeFlowID("signAndSendTransaction")
        do {
            log("signAndSendTransaction", "STEP_1_START", .info, "WalletConnect sign and send transaction started", [
                "flow_id": flowID,
                "request_id": "\(id)",
                "transaction_bytes": "\(transaction.count)",
                "skip_preflight": "\(sendOptions.skipPreflight)",
                "preflight_commitment": sendOptions.preflightCommitment ?? "nil",
                "max_retries": sendOptions.maxRetries.map(String.init) ?? "nil",
                "min_context_slot": sendOptions.minContextSlot.map(String.init) ?? "nil",
            ].merging(payloadPolicy.includesRawPayloads ? ["transaction_raw": transaction.base64EncodedString()] : [:]) { _, new in new })
            let session = try requireSession(method: "signAndSendTransaction", flowID: flowID)
            return try await performRequest(
                WalletConnectSolanaRequests.signAndSendTransaction(transaction, sendOptions: sendOptions, id: id),
                session: session,
                responseType: WalletConnectSolanaSignAndSendTransactionResult.self,
                method: "signAndSendTransaction",
                flowID: flowID,
                resultMetadata: signAndSendResultMetadata
            )
        } catch {
            logFailure("signAndSendTransaction", flowID: flowID, error: error)
            throw error
        }
    }

    private func performRequest<Params, Result>(
        _ request: WalletConnectSolanaJSONRPCRequest<Params>,
        session: WalletConnectSolanaSession,
        responseType: Result.Type,
        method: String,
        flowID: String,
        requestMetadata: [String: String] = [:],
        resultMetadata: (Result, String) -> [String: String]
    ) async throws -> Result where Params: Sendable & Equatable & Encodable, Result: Sendable & Decodable {
        log(method, "STEP_3_REQUEST_BUILT", .debug, "WalletConnect JSON-RPC request built", [
            "flow_id": flowID,
            "request_id": "\(request.id)",
            "jsonrpc": request.jsonrpc,
            "jsonrpc_method": request.method.rawValue,
            "chain": session.chain,
            "topic": WalletAdapterDebugFormatter.shortBase58(session.topic),
        ].merging(requestMetadata) { _, new in new }
            .merging(rawJSONMetadata("request_json_raw", request)) { _, new in new })
        let result = try await transport.request(
            request,
            chain: session.chain,
            session: session,
            responseType: responseType
        )
        log(method, "STEP_4_SUCCESS", .info, "WalletConnect JSON-RPC request completed", resultMetadata(result, flowID).merging([
            "request_id": "\(request.id)",
            "jsonrpc_method": request.method.rawValue,
            "chain": session.chain,
        ]) { _, new in new })
        return result
    }

    private func requireSession(method: String, flowID: String) throws -> WalletConnectSolanaSession {
        guard let activeSession else {
            let error = WalletAdapterError.invalidSession
            log(method, "STEP_FAIL_SESSION", .error, "no active WalletConnect session", WalletAdapterLogDiagnostics.failureMetadata(for: error, flowID: flowID, metadata: [
                "has_session": "false",
            ]))
            throw error
        }
        log(method, "STEP_2_SESSION_OK", .debug, "active WalletConnect session found", sessionMetadata(activeSession, flowID: flowID))
        return activeSession
    }

    private func requirePrimaryPubkey(_ session: WalletConnectSolanaSession, method: String, flowID: String) throws -> String {
        guard let pubkey = session.primaryPubkey else {
            let error = WalletAdapterError.malformedPayload("WalletConnect session has no Solana account.")
            log(method, "STEP_FAIL_PRIMARY_PUBKEY", .error, "WalletConnect session has no primary Solana account", WalletAdapterLogDiagnostics.failureMetadata(for: error, flowID: flowID, metadata: [
                "account_count": "\(session.accounts.count)",
                "chain": session.chain,
            ]))
            throw error
        }
        return pubkey
    }

    private func log(_ method: String, _ step: String, _ level: WalletAdapterLogLevel, _ message: String, _ metadata: [String: String] = [:]) {
        guard logLevel != .off, level <= logLevel else { return }
        logger.log(WalletAdapterLogEvent(component: "WalletConnectSolanaClient", method: method, step: step, phase: level == .error ? "FAIL" : "INFO", message: message, metadata: metadata))
    }

    private func logFailure(_ method: String, flowID: String, error: Error, metadata: [String: String] = [:]) {
        log(method, "STEP_FAIL", .error, "operation failed", WalletAdapterLogDiagnostics.failureMetadata(for: error, flowID: flowID, metadata: metadata))
    }

    private func makeFlowID(_ method: String) -> String {
        let flowID = "\(method)-\(nextFlowNumber)"
        nextFlowNumber += 1
        return flowID
    }

    private func capabilityMetadata(_ capabilities: WalletCapabilities, flowID: String) -> [String: String] {
        [
            "flow_id": flowID,
            "wallet": capabilities.walletId,
            "transport": capabilities.transport.rawValue,
            "method_count": "\(capabilities.methods.count)",
            "methods": capabilities.methods.map { $0.method.rawValue }.joined(separator: ","),
            "supported_methods": capabilities.methods.filter { $0.isSupported }.map { $0.method.rawValue }.joined(separator: ","),
            "feature_identifiers": capabilities.featureIdentifiers.joined(separator: ","),
        ].merging(rawJSONMetadata("capabilities_json_raw", capabilities)) { _, new in new }
    }

    private func sessionMetadata(_ session: WalletConnectSolanaSession, flowID: String) -> [String: String] {
        [
            "flow_id": flowID,
            "topic": WalletAdapterDebugFormatter.shortBase58(session.topic),
            "chain": session.chain,
            "account_count": "\(session.accounts.count)",
            "primary_pubkey": session.primaryPubkey.map { WalletAdapterDebugFormatter.shortBase58($0) } ?? "nil",
        ].merging(payloadPolicy.includesRawPayloads ? [
            "topic_raw": session.topic,
            "accounts_raw": session.accounts.map(\.pubkey).joined(separator: ","),
            "primary_pubkey_raw": session.primaryPubkey ?? "nil",
        ] : [:]) { _, new in new }
    }

    private func accountsResultMetadata(_ result: WalletConnectSolanaAccountsResult, flowID: String) -> [String: String] {
        [
            "flow_id": flowID,
            "account_count": "\(result.accounts.count)",
            "primary_pubkey": result.accounts.first.map { WalletAdapterDebugFormatter.shortBase58($0.pubkey) } ?? "nil",
        ].merging(payloadPolicy.includesRawPayloads ? [
            "accounts_raw": result.accounts.map(\.pubkey).joined(separator: ","),
        ] : [:]) { _, new in new }
    }

    private func signMessageResultMetadata(_ result: WalletConnectSolanaSignMessageResult, flowID: String) -> [String: String] {
        [
            "flow_id": flowID,
            "signature": WalletAdapterDebugFormatter.shortBase58(result.signature),
            "signature_bytes": result.signatureData.map { "\($0.count)" } ?? "nil",
        ].merging(payloadPolicy.includesRawPayloads ? [
            "signature_raw": result.signature,
        ] : [:]) { _, new in new }
    }

    private func signTransactionResultMetadata(_ result: WalletConnectSolanaSignTransactionResult, flowID: String) -> [String: String] {
        [
            "flow_id": flowID,
            "has_signature": "\(result.signature != nil)",
            "has_transaction": "\(result.transaction != nil)",
            "signature": result.signature.map { WalletAdapterDebugFormatter.shortBase58($0) } ?? "nil",
            "transaction_bytes": result.transactionData.map { "\($0.count)" } ?? "nil",
        ].merging(payloadPolicy.includesRawPayloads ? [
            "signature_raw": result.signature ?? "nil",
            "transaction_raw": result.transaction ?? "nil",
        ] : [:]) { _, new in new }
    }

    private func signAllTransactionsResultMetadata(_ result: WalletConnectSolanaSignAllTransactionsResult, flowID: String) -> [String: String] {
        [
            "flow_id": flowID,
            "transaction_count": "\(result.transactions.count)",
            "transaction_bytes": result.transactionData?.map(\.count).map(String.init).joined(separator: ",") ?? "decode_failed",
        ].merging(payloadPolicy.includesRawPayloads ? [
            "transactions_raw": result.transactions.joined(separator: ","),
        ] : [:]) { _, new in new }
    }

    private func signAndSendResultMetadata(_ result: WalletConnectSolanaSignAndSendTransactionResult, flowID: String) -> [String: String] {
        [
            "flow_id": flowID,
            "signature": WalletAdapterDebugFormatter.shortBase58(result.signature),
            "signature_bytes": result.signatureData.map { "\($0.count)" } ?? "nil",
        ].merging(payloadPolicy.includesRawPayloads ? [
            "signature_raw": result.signature,
        ] : [:]) { _, new in new }
    }

    private func rawJSONMetadata<T: Encodable>(_ key: String, _ value: T) -> [String: String] {
        guard payloadPolicy.includesRawPayloads else { return [:] }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return [key: "unavailable"]
        }
        return [key: string]
    }

    private func walletConnectMethodSupports() -> [WalletMethodSupport] {
        var supports: [WalletMethod: WalletMethodSupport] = [
            .connect: WalletMethodSupport(method: .connect, note: "Establishes a WalletConnect/Reown Sign session."),
            .disconnect: WalletMethodSupport(method: .disconnect, note: "Disconnects the active WalletConnect/Reown Sign session."),
            .getCapabilities: WalletMethodSupport(method: .getCapabilities, note: "Resolved locally from the namespace proposal."),
        ]
        for methodName in namespace.methods {
            guard let method = WalletConnectSolanaMethod(rawValue: methodName) else { continue }
            supports[method.capabilityMethod] = WalletMethodSupport(method: method.capabilityMethod)
        }
        return WalletMethod.allCases.compactMap { supports[$0] }
    }
}

private extension WalletConnectSolanaMethod {
    var capabilityMethod: WalletMethod {
        switch self {
        case .getAccounts:
            return .getAccounts
        case .requestAccounts:
            return .requestAccounts
        case .signMessage:
            return .signMessage
        case .signTransaction:
            return .signTransaction
        case .signAllTransactions:
            return .signAllTransactions
        case .signAndSendTransaction:
            return .signAndSendTransaction
        }
    }
}
