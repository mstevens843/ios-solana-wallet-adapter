import Foundation
import Combine
import SolanaWalletAdapter
import SolanaWalletAdapterWalletConnect
import WalletConnectSign
import WalletConnectNetworking
import WalletConnectPairing

/// Real `WalletConnectSolanaTransport` backed by the Reown (WalletConnect v2)
/// Swift SDK. Drop-in replacement for `NotWiredWalletConnectTransport`: the
/// `WalletConnectSolanaClient` calls `connect` / `request` / `disconnect` and
/// this bridges to `Sign.instance` over the relay.
///
/// Lives in the iOS demo target (not the SPM package) because reown's
/// `WalletConnectSign` uses `UIApplication` and does not build on macOS, which
/// would break the package's macOS `swift build` / tests / CI.
///
/// `openURL` is how the app brings Jupiter (or any WC wallet) to the foreground
/// with the pairing URI.
struct ReownWalletConnectSolanaTransport: WalletConnectSolanaTransport {
    private let projectId: String
    private let metadata: ReownAppMetadata
    private let groupIdentifier: String
    /// The target wallet's native deeplink scheme, e.g. Jupiter's `jupiter://`
    /// (from the Reown wallet registry). Used to open the wallet directly with
    /// the pairing URI (`<link>wc?uri=…`) on connect and to foreground it on each
    /// request. iOS does not route the bare `wc:` URI, so this is required to
    /// reach a specific wallet; when nil we fall back to opening the raw URI.
    private let walletNativeLink: String?
    private let connectTimeout: TimeInterval
    private let requestTimeout: TimeInterval
    private let openURL: @Sendable (URL) -> Void

    init(
        projectId: String,
        metadata: ReownAppMetadata,
        groupIdentifier: String,
        walletNativeLink: String? = nil,
        connectTimeout: TimeInterval = 180,
        requestTimeout: TimeInterval = 180,
        openURL: @escaping @Sendable (URL) -> Void
    ) {
        self.projectId = projectId
        self.metadata = metadata
        self.groupIdentifier = groupIdentifier
        self.walletNativeLink = walletNativeLink
        self.connectTimeout = connectTimeout
        self.requestTimeout = requestTimeout
        self.openURL = openURL
    }

    // MARK: WalletConnectSolanaTransport

    func connect(
        configuration: ReownProjectConfiguration,
        namespace: WalletConnectSolanaNamespace
    ) async throws -> WalletConnectSolanaSession {
        try Self.configureIfNeeded(projectId: projectId, metadata: metadata, groupIdentifier: groupIdentifier)

        let chains = namespace.chains.compactMap { Blockchain($0) }
        guard !chains.isEmpty else {
            throw WalletAdapterError.malformedPayload("No valid CAIP-2 Solana chains in the namespace.")
        }
        let proposal = ProposalNamespace(
            chains: chains,
            methods: Set(namespace.methods),
            events: Set(namespace.events)
        )
        let opener = openURL
        let link = walletNativeLink

        let settled = try await firstValue(
            from: Sign.instance.sessionSettlePublisher,
            timeout: connectTimeout,
            where: { _ in true }
        ) {
            let uri = try await Sign.instance.connect(namespaces: ["solana": proposal])
            // Open the wallet directly with the pairing URI. iOS won't route the
            // bare `wc:` URI, so build `<wallet scheme>wc?uri=<encoded>`.
            let target: URL? = link.flatMap { URL(string: "\($0)wc?uri=\(uri.deeplinkUri)") }
                ?? URL(string: uri.absoluteString)
            if let target {
                opener(target)
            }
        }

        let session = settled.session
        let solanaAccounts = session.namespaces["solana"]?.accounts ?? []
        let accounts = solanaAccounts.map { WalletConnectSolanaAccount(pubkey: $0.address) }
        let chain = chains.first?.absoluteString ?? namespace.chains.first ?? ""
        return WalletConnectSolanaSession(topic: session.topic, chain: chain, accounts: accounts)
    }

    func request<Params, Result>(
        _ request: WalletConnectSolanaJSONRPCRequest<Params>,
        chain: String,
        session: WalletConnectSolanaSession,
        responseType: Result.Type
    ) async throws -> Result
    where Params: Sendable & Equatable & Encodable, Result: Sendable & Decodable {
        guard let blockchain = Blockchain(chain) else {
            throw WalletAdapterError.malformedPayload("Invalid CAIP-2 chain: \(chain).")
        }
        // Re-encode our typed params into Reown's AnyCodable via JSON so the
        // exact JSON shape (base58 message / base64 tx) is preserved.
        let paramsData = try JSONEncoder().encode(request.params)
        let anyParams = try JSONDecoder().decode(AnyCodable.self, from: paramsData)
        let wcRequest = try Request(
            topic: session.topic,
            method: request.method.rawValue,
            params: anyParams,
            chainId: blockchain
        )
        let requestId = wcRequest.id
        let opener = openURL
        let link = walletNativeLink

        let response = try await firstValue(
            from: Sign.instance.sessionResponsePublisher,
            timeout: requestTimeout,
            where: { $0.id == requestId }
        ) {
            try await Sign.instance.request(params: wcRequest)
            // Foreground the wallet so the user sees the pending request.
            if let link, let url = URL(string: link) {
                opener(url)
            }
        }

        switch response.result {
        case .response(let value):
            let data = try JSONEncoder().encode(value)
            return try JSONDecoder().decode(Result.self, from: data)
        case .error(let error):
            throw WalletAdapterError.other(
                code: "WALLETCONNECT_REQUEST_ERROR",
                message: "\(error.message) (code \(error.code))"
            )
        }
    }

    func disconnect(session: WalletConnectSolanaSession) async throws {
        try? await Sign.instance.disconnect(topic: session.topic)
    }

    // MARK: - One-time SDK configuration

    private static let configLock = NSLock()
    private nonisolated(unsafe) static var configured = false

    private static func configureIfNeeded(
        projectId: String,
        metadata: ReownAppMetadata,
        groupIdentifier: String
    ) throws {
        configLock.lock()
        defer { configLock.unlock() }
        guard !configured else { return }

        let redirect = try AppMetadata.Redirect(
            native: metadata.redirect?.native ?? "",
            universal: metadata.redirect?.universal?.absoluteString,
            linkMode: false
        )
        let appMetadata = AppMetadata(
            name: metadata.name,
            description: metadata.description,
            url: metadata.url.absoluteString,
            icons: metadata.icons.map(\.absoluteString),
            redirect: redirect
        )
        Networking.configure(
            groupIdentifier: groupIdentifier,
            projectId: projectId,
            socketFactory: ReownURLSessionWebSocketFactory()
        )
        Pair.configure(metadata: appMetadata)
        // REQUIRED before any `Sign.instance` access — without it the SDK traps
        // with a fatalError ("you must call Sign.configure(_:)…"). The crypto
        // provider's methods are EVM/SIWE-only and are never invoked for Solana
        // sign flows, so a stub is safe here.
        Sign.configure(crypto: SolanaWalletConnectCryptoProvider())
        configured = true
    }

    // MARK: - Publisher → async bridge

    /// Subscribe to `publisher`, run `start` (which triggers the wallet round
    /// trip), and resume with the first value matching `predicate`, or throw on
    /// timeout / cancellation. One-shot.
    private func firstValue<Output>(
        from publisher: AnyPublisher<Output, Never>,
        timeout: TimeInterval,
        where predicate: @escaping @Sendable (Output) -> Bool,
        after start: @escaping @Sendable () async throws -> Void
    ) async throws -> Output {
        let box = ReownResumeBox<Output>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Output, Error>) in
                box.attach(continuation)
                let cancellable = publisher.sink { value in
                    if predicate(value) { box.resume(returning: value) }
                }
                box.store(cancellable)
                let timeoutTask = Task {
                    try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    box.resume(throwing: WalletAdapterError.walletUnreachable)
                }
                box.store(timeoutTask)
                Task {
                    do { try await start() }
                    catch { box.resume(throwing: error) }
                }
            }
        } onCancel: {
            box.resume(throwing: WalletAdapterError.requestCancelled)
        }
    }
}

/// Reown's `Sign.configure(crypto:)` requires a `CryptoProvider`, but its two
/// methods are only used for EVM SIWE signature recovery — never for Solana
/// sign-message / sign-transaction. This stub satisfies the requirement; if a
/// path ever calls it on Solana, that's a misuse we want to surface.
struct SolanaWalletConnectCryptoProvider: CryptoProvider {
    func recoverPubKey(signature: EthereumSignature, message: Data) throws -> Data {
        throw WalletAdapterError.unsupportedMethod("EVM pubkey recovery is not used on Solana WalletConnect.")
    }

    func keccak256(_ data: Data) -> Data {
        Data()
    }
}

/// Thread-safe one-shot resume holding the continuation + its subscription and
/// timeout task, cancelling both on first resume.
private final class ReownResumeBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    private var cancellable: AnyCancellable?
    private var tasks: [Task<Void, Never>] = []
    private var finished = false

    func attach(_ continuation: CheckedContinuation<T, Error>) {
        lock.lock(); self.continuation = continuation; lock.unlock()
    }

    func store(_ cancellable: AnyCancellable) {
        lock.lock(); self.cancellable = cancellable; lock.unlock()
    }

    func store(_ task: Task<Void, Never>) {
        lock.lock(); tasks.append(task); lock.unlock()
    }

    func resume(returning value: T) { finish { $0.resume(returning: value) } }
    func resume(throwing error: Error) { finish { $0.resume(throwing: error) } }

    private func finish(_ body: (CheckedContinuation<T, Error>) -> Void) {
        lock.lock()
        guard !finished, let continuation else { lock.unlock(); return }
        finished = true
        self.continuation = nil
        let cancellable = self.cancellable
        let tasks = self.tasks
        self.cancellable = nil
        self.tasks = []
        lock.unlock()
        cancellable?.cancel()
        tasks.forEach { $0.cancel() }
        body(continuation)
    }
}
