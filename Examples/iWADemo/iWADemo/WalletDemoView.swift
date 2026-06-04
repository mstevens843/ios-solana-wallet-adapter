import SwiftUI
import UIKit
import SolanaWalletAdapter
import SolanaWalletAdapterBackpack
import SolanaWalletAdapterPhantom
import SolanaWalletAdapterSolflare
import SolanaWalletAdapterUI
import SolanaWalletAdapterPicker
import SolanaWalletAdapterWalletConnect

/// Jupiter Mobile signs over WalletConnect/Reown (relay), so it is driven by a
/// `WalletConnectSolanaClient` rather than the native-deeplink `WalletAdapterClient`.
typealias JupiterClient = WalletConnectSolanaClient<ReownWalletConnectSolanaTransport>

struct WalletDemoView: View {
    @Environment(\.openURL) private var openURL
    @StateObject private var logs = DemoLogRecorder()
    @State private var mockWallet = SimulatorMockWalletResponder()
    @State private var selectedWallet: DemoWallet = .phantom
    @State private var client: WalletAdapterClient?
    @State private var siwsAccount: String?
    @State private var solanaRPCURL: URL?
    @State private var lastResult: String = "Ready"
    @State private var isBusy: Bool = false
    @State private var showingPicker: Bool = false
    @State private var canReconnect: Bool = false
    @State private var cachedPubkeyCaption: String?
    @State private var preferredWalletId: String?
    @State private var logConfiguration: WalletAdapterLogConfiguration?
    @State private var serviceConfiguration: WalletAdapterServiceConfiguration?
    @State private var toast: DemoToast?
    @State private var toastDismissTask: Task<Void, Never>?
    @State private var jupiterClient: JupiterClient?
    @State private var jupiterSession: WalletConnectSolanaSession?

    private let appURL = URL(string: "https://example.com")!
    private let redirect = URL(string: "iwademo://wallet/callback")!
    private let lastActiveStore = KeychainLastActiveWalletStore()

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.06, blue: 0.10).ignoresSafeArea()

            if let jupiterSession {
                HomeView(
                    publicKey: jupiterSession.primaryPubkey ?? "",
                    walletLabel: "Jupiter Mobile",
                    status: lastResult,
                    isBusy: isBusy,
                    onSignMessage: { run { try await jupiterSignMessageAction() } },
                    onSignTransaction: { run { try await jupiterSignTransactionAction() } },
                    onSignAndSend: { run { try await jupiterSignAndSendAction() } },
                    onSignAll: { run { try await jupiterSignAllAction() } },
                    onGetCapabilities: { run { try await jupiterGetCapabilitiesAction() } },
                    onDisconnect: { run(neutralStatusOnSuccess: true) { try await jupiterDisconnectAction() } },
                    onDeleteAccount: { run(neutralStatusOnSuccess: true) { try await jupiterDisconnectAction() } }
                )
            } else if let client, client.adapter.session != nil {
                HomeView(
                    publicKey: client.adapter.session?.userPublicKey ?? "",
                    walletLabel: selectedWallet.title,
                    status: lastResult,
                    isBusy: isBusy,
                    onSignMessage: { run { try await signMessageAction() } },
                    onSignTransaction: { run { try await signTransactionAction() } },
                    onSignAndSend: { run { try await signAndSendAction() } },
                    onSignAll: { run { try await signAllTransactionsAction() } },
                    onGetCapabilities: { run { try await getCapabilitiesAction() } },
                    onDisconnect: { run(neutralStatusOnSuccess: true) { try await disconnectAction() } },
                    onDeleteAccount: { run(neutralStatusOnSuccess: true) { try await deleteAccountAction() } }
                )
            } else {
                ConnectView(
                    status: lastResult,
                    isBusy: isBusy,
                    canReconnect: canReconnect,
                    cachedPubkeyCaption: cachedPubkeyCaption,
                    onConnect: { showingPicker = true },
                    onReconnect: { run { try await reconnectCachedAction() } }
                )
            }
        }
        .overlay(alignment: .bottom) {
            if let toast {
                DemoToastView(toast: toast)
                    .padding(.bottom, 40)
                    .padding(.horizontal, 24)
                    .id(toast.id)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: toast)
        .onAppear {
            logBootBanner()
            logDetectionSnapshot()
        }
        .task {
            // Bootstrap once, AFTER the first render. Mutating `selectedWallet`
            // (and the cascade of @State in configureClient) inside `.onAppear`
            // runs during the view-update cycle and blanks the screen whenever the
            // restored wallet differs from the default. A `.task` runs outside that
            // cycle. When the wallet changes, `.onChange` configures; otherwise we
            // configure directly — exactly one configureClient() either way.
            guard client == nil else { return }
            if let last = lastActiveWalletOnLaunch(), last != selectedWallet {
                selectedWallet = last
            } else {
                configureClient()
            }
        }
        .onChange(of: selectedWallet) { _ in configureClient() }
        .onOpenURL { url in handleCallback(url) }
        .walletPickerSheet(
            isPresented: $showingPicker,
            detector: LoggingInstalledWalletDetector(
                wrapping: InstalledWalletDetector.default,
                logger: logs.logger(prefix: logPrefix),
                logLevel: logLevel
            ),
            preferredWalletId: preferredWalletId,
            brands: pickerBrands,
            onSelect: handlePickerSelection
        )
    }

    // MARK: - Logging helpers

    private var logPrefix: String { logConfiguration?.prefix ?? "[iWA Demo]" }
    private var logLevel: WalletAdapterLogLevel { logConfiguration?.logLevel ?? .debug }
    private var payloadPolicy: WalletAdapterLogPayloadPolicy { logConfiguration?.payloadPolicy ?? .redacted }
    private var currentLogger: any WalletAdapterLogger { logs.logger(prefix: logPrefix) }

    /// Debug builds default to full-payload logging (signatures / txids / decrypted
    /// JSON appear on-device); Release stays redacted so a shipped build never leaks
    /// raw artifacts. `SOLANA_WALLET_ADAPTER_*` env vars still override either way.
    private func resolvedLogConfiguration() -> WalletAdapterLogConfiguration {
        #if DEBUG
        let defaultPayloadPolicy: WalletAdapterLogPayloadPolicy = .unsafeRawPayloads
        #else
        let defaultPayloadPolicy: WalletAdapterLogPayloadPolicy = .redacted
        #endif
        return WalletAdapterLogConfiguration.fromEnvironment(
            DemoEnvironment.resolved(),
            defaultLogLevel: .debug,
            defaultPayloadPolicy: defaultPayloadPolicy
        )
    }

    /// First line on launch — instant proof logging is live and which build / payload
    /// mode is running. If you DON'T see this in `idevicesyslog`, you're on a stale
    /// build: rebuild + reinstall (idevicesyslog only sees the installed build).
    private func logBootBanner() {
        let configuration = logConfiguration ?? resolvedLogConfiguration()
        let info = Bundle.main.infoDictionary
        let version = (info?["CFBundleShortVersionString"] as? String) ?? "?"
        let build = (info?["CFBundleVersion"] as? String) ?? "?"
        #if DEBUG
        let buildConfig = "DEBUG"
        #else
        let buildConfig = "RELEASE"
        #endif
        logs.logger(prefix: configuration.prefix).log(WalletAdapterLogEvent(
            component: "iWADemo",
            method: "boot",
            step: "STEP_0_BOOT",
            phase: "INFO",
            message: "iWA demo launched — logging is live",
            metadata: [
                "build_config": buildConfig,
                "log_level": "\(configuration.logLevel)",
                "payload_policy": "\(configuration.payloadPolicy)",
                "app_version": "\(version)+\(build)",
                "bundle_id": (info?["CFBundleIdentifier"] as? String) ?? "?",
            ]
        ))
    }

    /// Routes a wallet callback into the client, logging delivery and the
    /// cold-launch case where the callback arrives before `configureClient`.
    private func handleCallback(_ url: URL) {
        if logLevel != .off {
            currentLogger.log(WalletAdapterLogEvent(
                component: "WalletAdapterClient",
                method: "onOpenURL",
                step: "STEP_1_DELIVERED",
                phase: "INFO",
                message: "app received wallet callback URL",
                metadata: [
                    "callback": WalletAdapterDebugFormatter.urlShape(url),
                    "client_present": "\(client != nil)",
                ]
            ))
        }
        guard let client else {
            if logLevel != .off {
                currentLogger.log(WalletAdapterLogEvent(
                    component: "WalletAdapterClient",
                    method: "onOpenURL",
                    step: "STEP_FAIL_NO_CLIENT",
                    phase: "FAIL",
                    message: "callback arrived before wallet client was configured",
                    metadata: ["callback": WalletAdapterDebugFormatter.urlShape(url)]
                ))
            }
            return
        }
        _ = client.handleOpenURL(url)
    }

    /// Emits one deterministic install-probe line per bundled brand at startup so
    /// the logs show, for all four wallets, whether the device sees them installed.
    private func logDetectionSnapshot() {
        guard logLevel != .off else { return }
        let logger = currentLogger
        let detector = LoggingInstalledWalletDetector(
            wrapping: InstalledWalletDetector.default,
            logger: logger,
            logLevel: logLevel
        )
        for brand in WalletBrandRegistry.defaults {
            if let scheme = brand.urlScheme {
                _ = detector.isInstalled(scheme: scheme)
            } else {
                logger.log(WalletAdapterLogEvent(
                    component: "InstalledWalletDetector",
                    method: "isInstalled",
                    step: "STEP_0_NO_SCHEME",
                    phase: "INFO",
                    message: "wallet exposes no native scheme",
                    metadata: [
                        "wallet": brand.id,
                        "scheme": "none",
                        "installed": "true",
                        "reason": "walletconnect_only",
                    ]
                ))
            }
        }
    }

    /// On a real device the four shipped brands are correct. On the iOS
    /// simulator, real wallet apps cannot be installed — surface the mock
    /// wallet so the connect flow stays testable end-to-end without a phone.
    private var pickerBrands: [WalletBrand] {
        #if targetEnvironment(simulator)
        return WalletBrandRegistry.defaults + [
            WalletBrand(
                id: "mock",
                displayName: "Mock Wallet (Simulator)",
                urlScheme: nil,
                logoAssetName: nil,
                brandColorHex: "#6B7280"
            )
        ]
        #else
        return WalletBrandRegistry.defaults
        #endif
    }

    private func handlePickerSelection(_ selection: WalletPickerSelection) {
        switch selection {
        case .cancelled:
            lastResult = "Picker dismissed"
        case .picked(let walletId, _) where walletId == JupiterMobileWalletConnect.walletId:
            run { try await connectJupiterAction() }
        case .picked(let walletId, let remember):
            guard let pick = DemoWallet(rawValue: walletId) else {
                lastResult = "\(walletId) is not yet supported on native iOS deeplinks."
                return
            }
            let previous = selectedWallet
            selectedWallet = pick
            if previous != pick {
                configureClient()
            }
            run {
                if remember {
                    try await requireClient().rememberPreferredWallet(walletId)
                    preferredWalletId = walletId
                }
                return try await connectWithSIWSAction()
            }
        }
    }

    // MARK: - Actions
    //
    // Each action returns a success message. `run(_:)` surfaces it as a green
    // success toast and routes any thrown error to a red, deterministic fail
    // toast — so every wallet action gives a clear pass/fail signal.

    private func connectWithSIWSAction() async throws -> String {
        let client = try requireClient()
        // Fresh handshake on a user-initiated connect (no-op if a session is
        // already active): guarantees the dapp keypair matches the session the
        // wallet issues, so Disconnect → Connect reliably recovers from a
        // desynced session the wallet would otherwise reject.
        client.rotateEphemeralKeypair()
        let input = SignInWithSolanaInput(
            nonce: makeNonce(),
            statement: "Sign in to the iWADemo example app."
        )
        let result = try await client.signInWithSolana(input)
        siwsAccount = result.account
        return "Signed in with Solana: \(HomeView.shortAddress(result.account))"
    }

    private func signMessageAction() async throws -> String {
        let result = try await requireClient().signMessage(Data("Hello from iWADemo".utf8))
        return "Message signed (\(result.signature.count)-byte sig)"
    }

    private func signTransactionAction() async throws -> String {
        let client = try requireClient()
        guard let session = client.adapter.session else {
            throw WalletAdapterError.invalidSession
        }
        guard let rpcURL = solanaRPCURL else {
            throw WalletAdapterError.other(code: "missing_rpc", message: "Solana RPC URL is not configured.")
        }
        let tx = try await DemoTransactionBuilder.buildMemoTransaction(
            sender: session.userPublicKey,
            rpcURL: rpcURL,
            rpcSource: serviceConfiguration?.solanaRPCURLSource.rawValue ?? "unknown",
            action: "signTransaction",
            logger: currentLogger,
            logLevel: logLevel,
            payloadPolicy: payloadPolicy
        )
        let result = try await client.signTransaction(tx)
        return "Transaction signed (\(result.transaction.count) bytes)"
    }

    private func signAllTransactionsAction() async throws -> String {
        let client = try requireClient()
        guard let session = client.adapter.session else {
            throw WalletAdapterError.invalidSession
        }
        guard let rpcURL = solanaRPCURL else {
            throw WalletAdapterError.other(code: "missing_rpc", message: "Solana RPC URL is not configured.")
        }
        let rpcSource = serviceConfiguration?.solanaRPCURLSource.rawValue ?? "unknown"
        let tx1 = try await DemoTransactionBuilder.buildMemoTransaction(
            sender: session.userPublicKey, rpcURL: rpcURL, rpcSource: rpcSource,
            action: "signAllTransactions", logger: currentLogger, logLevel: logLevel, payloadPolicy: payloadPolicy
        )
        let tx2 = try await DemoTransactionBuilder.buildMemoTransaction(
            sender: session.userPublicKey, rpcURL: rpcURL, rpcSource: rpcSource,
            action: "signAllTransactions", logger: currentLogger, logLevel: logLevel, payloadPolicy: payloadPolicy
        )
        let result = try await client.signAllTransactions([tx1, tx2])
        return "Signed \(result.transactions.count) transactions"
    }

    /// Phantom deprecates native sign-and-send, so we build our own transaction
    /// and use the reusable SDK helper: sign via the wallet, then broadcast
    /// through the configured Helius RPC. Works the same for all four wallets.
    private func signAndSendAction() async throws -> String {
        let client = try requireClient()
        guard let session = client.adapter.session else {
            throw WalletAdapterError.invalidSession
        }
        guard let rpcURL = solanaRPCURL else {
            throw WalletAdapterError.other(code: "missing_rpc", message: "Solana RPC URL is not configured.")
        }
        let tx = try await DemoTransactionBuilder.buildMemoTransaction(
            sender: session.userPublicKey,
            rpcURL: rpcURL,
            rpcSource: serviceConfiguration?.solanaRPCURLSource.rawValue ?? "unknown",
            action: "signAndSend",
            logger: currentLogger,
            logLevel: logLevel,
            payloadPolicy: payloadPolicy
        )
        let txid = try await client.signAndSendViaRPC(tx, rpcURL: rpcURL)
        let short = txid.count > 12 ? "\(txid.prefix(6))…\(txid.suffix(6))" : txid
        return "Sent ✓ \(short)"
    }

    private func getCapabilitiesAction() async throws -> String {
        let capabilities = try await requireClient().getCapabilities()
        let supported = capabilities.methods.filter { $0.isSupported }.count
        return "\(capabilities.displayName) · \(supported) methods"
    }

    /// Soft local logout: drops the in-memory session and returns to the connect
    /// screen, but keeps the keychain cache so "Reconnect (Cached)" can resume
    /// with zero wallet round-trips.
    private func disconnectAction() async throws -> String {
        let client = try requireClient()
        let cachedKey = client.adapter.session?.userPublicKey
        try await client.signOutLocally()
        siwsAccount = nil
        canReconnect = true
        if let cachedKey {
            cachedPubkeyCaption = "Cached session found: \(shortPubkey(cachedKey))"
        }
        return "Disconnected"
    }

    /// Hard delete, gated by a wallet signature. The user must sign a "delete"
    /// message; rejecting in the wallet aborts and keeps the account. Only a real
    /// signature triggers the revoke + keychain wipe.
    private func deleteAccountAction() async throws -> String {
        let client = try requireClient()
        let message = "Delete account / revoke iWADemo authorization\nNonce: \(makeNonce())"
        do {
            _ = try await client.signMessage(Data(message.utf8))
        } catch let error as WalletAdapterError where error == .userRejected {
            throw WalletAdapterError.other(code: "delete_cancelled", message: "Delete cancelled")
        }
        try? await client.disconnect()
        try await client.clearState()
        siwsAccount = nil
        canReconnect = false
        cachedPubkeyCaption = nil
        return "Account deleted"
    }

    /// Resume the keychain-cached session locally — no wallet round-trip.
    private func reconnectCachedAction() async throws -> String {
        let client = try requireClient()
        let resumed = await client.resumeCachedSession()
        guard resumed, client.adapter.session != nil else {
            throw WalletAdapterError.invalidSession
        }
        return "Reconnected (cached)"
    }

    // MARK: - Jupiter (WalletConnect / Reown)

    /// dApp metadata advertised to Jupiter over WalletConnect. The `url` points
    /// at a domain on the Reown project's allowlist so Verify doesn't flag it.
    private func jupiterMetadata() -> ReownAppMetadata {
        ReownAppMetadata(
            name: "iWADemo",
            description: "iWA example app",
            url: URL(string: "https://trade.solpulse.app")!,
            icons: [],
            redirect: ReownRedirectMetadata(native: "iwademo://")
        )
    }

    private func requireJupiter() throws -> JupiterClient {
        guard let jupiterClient else {
            throw WalletAdapterError.invalidSession
        }
        return jupiterClient
    }

    /// Connect Jupiter Mobile over the WalletConnect relay: build the Reown
    /// transport + client, open Jupiter with the pairing URI, await session
    /// settlement, and surface the connected account.
    private func connectJupiterAction() async throws -> String {
        guard let projectId = serviceConfiguration?.walletConnectProjectID, !projectId.isEmpty else {
            throw WalletAdapterError.other(code: "jupiter_missing_project_id", message: "Jupiter requires WALLETCONNECT_PROJECT_ID (missing in .env / bundled secrets).")
        }
        let cluster = serviceConfiguration?.cluster ?? .mainnetBeta
        let metadata = jupiterMetadata()
        let configuration = try ReownProjectConfiguration(projectId: projectId, metadata: metadata)
        let opener: @Sendable (URL) -> Void = { url in
            Task { @MainActor in UIApplication.shared.open(url) }
        }
        let transport = ReownWalletConnectSolanaTransport(
            projectId: projectId,
            metadata: metadata,
            groupIdentifier: "group.com.mstevens843.iWADemo",
            walletNativeLink: "jupiter://",
            openURL: opener
        )
        let wcClient = WalletConnectSolanaClient(
            configuration: configuration,
            namespace: .proposal(
                chains: [WalletConnectSolanaChain(cluster: cluster)],
                methods: [.signMessage, .signTransaction, .signAndSendTransaction]
            ),
            transport: transport,
            logger: currentLogger,
            logLevel: logLevel == .off ? .debug : logLevel,
            payloadPolicy: payloadPolicy
        )
        jupiterClient = wcClient
        let session = try await wcClient.connect()
        jupiterSession = session
        return "Connected \(HomeView.shortAddress(session.primaryPubkey ?? ""))"
    }

    private func jupiterSignMessageAction() async throws -> String {
        let result = try await requireJupiter().signMessage(Data("Hello from iWADemo".utf8))
        let bytes = result.signatureData?.count ?? 0
        return "Message signed (\(bytes)-byte sig)"
    }

    private func jupiterSignTransactionAction() async throws -> String {
        let tx = try await buildJupiterMemoTransaction(action: "jupiterSignTransaction")
        let result = try await requireJupiter().signTransaction(tx)
        let bytes = result.transactionData?.count ?? result.signatureData?.count ?? 0
        return "Transaction signed (\(bytes) bytes)"
    }

    private func jupiterSignAllAction() async throws -> String {
        let tx1 = try await buildJupiterMemoTransaction(action: "jupiterSignAllTransactions")
        let tx2 = try await buildJupiterMemoTransaction(action: "jupiterSignAllTransactions")
        let result = try await requireJupiter().signAllTransactions([tx1, tx2])
        return "Signed \(result.transactions.count) transactions"
    }

    private func jupiterSignAndSendAction() async throws -> String {
        let tx = try await buildJupiterMemoTransaction(action: "jupiterSignAndSend")
        let result = try await requireJupiter().signAndSendTransaction(tx)
        let txid = result.signature
        let short = txid.count > 12 ? "\(txid.prefix(6))…\(txid.suffix(6))" : txid
        return "Sent ✓ \(short)"
    }

    private func jupiterGetCapabilitiesAction() async throws -> String {
        let capabilities = try await requireJupiter().getCapabilities()
        let supported = capabilities.methods.filter { $0.isSupported }.count
        return "\(capabilities.displayName) · \(supported) methods"
    }

    private func jupiterDisconnectAction() async throws -> String {
        try? await requireJupiter().disconnect()
        jupiterSession = nil
        jupiterClient = nil
        return "Disconnected"
    }

    private func buildJupiterMemoTransaction(action: String) async throws -> Data {
        guard let pubkey = jupiterSession?.primaryPubkey else {
            throw WalletAdapterError.invalidSession
        }
        guard let rpcURL = solanaRPCURL else {
            throw WalletAdapterError.other(code: "missing_rpc", message: "Solana RPC URL is not configured.")
        }
        return try await DemoTransactionBuilder.buildMemoTransaction(
            sender: pubkey,
            rpcURL: rpcURL,
            rpcSource: serviceConfiguration?.solanaRPCURLSource.rawValue ?? "unknown",
            action: action,
            logger: currentLogger,
            logLevel: logLevel,
            payloadPolicy: payloadPolicy
        )
    }

    // MARK: - Client lifecycle

    private func configureClient() {
        let environment = DemoEnvironment.resolved()
        let logConfiguration = resolvedLogConfiguration()
        self.logConfiguration = logConfiguration
        let logger = logs.logger(prefix: logConfiguration.prefix)
        let payloadPolicy = logConfiguration.payloadPolicy
        let serviceConfiguration: WalletAdapterServiceConfiguration
        do {
            serviceConfiguration = try WalletAdapterServiceConfiguration.fromEnvironment(environment, defaultCluster: .mainnetBeta)
            self.serviceConfiguration = serviceConfiguration
            solanaRPCURL = serviceConfiguration.solanaRPCURL
            if logConfiguration.logLevel != .off {
                logger.log(WalletAdapterLogEvent(
                    component: "WalletAdapterServiceConfiguration",
                    method: "fromEnvironment",
                    step: "STEP_1_READY",
                    phase: "INFO",
                    message: "service configuration loaded",
                    metadata: serviceConfiguration.sanitizedMetadata
                ))
            }
        } catch {
            client = nil
            siwsAccount = nil
            solanaRPCURL = nil
            self.serviceConfiguration = nil
            lastResult = "\(error)"
            logger.log(WalletAdapterLogEvent(
                component: "WalletAdapterServiceConfiguration",
                method: "fromEnvironment",
                step: "STEP_FAIL",
                phase: "FAIL",
                message: "service configuration failed",
                metadata: WalletAdapterLogDiagnostics.failureMetadata(for: error)
            ))
            return
        }

        if selectedWallet == .mock {
            let opener = DemoMockWalletOpener(
                responder: mockWallet,
                redirectLink: redirect,
                logger: logger,
                logLevel: logConfiguration.logLevel
            )
            let mockClient = WalletAdapterClient(
                provider: selectedWallet.provider,
                appURL: appURL,
                redirectLink: redirect,
                cluster: serviceConfiguration.cluster,
                opener: opener,
                logger: logger,
                logLevel: logConfiguration.logLevel,
                payloadPolicy: payloadPolicy
            )
            opener.client = mockClient
            client = mockClient
            siwsAccount = nil
            lastResult = "Ready"
            return
        }

        let stateStore = KeychainWalletAdapterStateStore(
            account: selectedWallet.rawValue,
            logger: logger,
            logLevel: logConfiguration.logLevel,
            payloadPolicy: payloadPolicy
        )

        do {
            let restoredClient = try WalletAdapterClient.restore(
                from: stateStore,
                fallbackProvider: selectedWallet.provider,
                appURL: appURL,
                redirectLink: redirect,
                cluster: serviceConfiguration.cluster,
                opener: SwiftUIWalletURLOpener(openURL: openURL),
                lastActiveStore: lastActiveStore,
                logger: logger,
                logLevel: logConfiguration.logLevel,
                payloadPolicy: payloadPolicy
            )
            client = restoredClient
            preferredWalletId = restoredClient.preferredWalletId
            if let session = restoredClient.adapter.session {
                lastResult = "Restored \(selectedWallet.title) session"
                cachedPubkeyCaption = "Cached session found: \(shortPubkey(session.userPublicKey))"
                Task { @MainActor in
                    canReconnect = await restoredClient.reconnectIfPossible()
                }
            } else {
                siwsAccount = nil
                lastResult = "Ready"
                canReconnect = false
                cachedPubkeyCaption = nil
            }
        } catch {
            client = WalletAdapterClient(
                provider: selectedWallet.provider,
                appURL: appURL,
                redirectLink: redirect,
                cluster: serviceConfiguration.cluster,
                opener: SwiftUIWalletURLOpener(openURL: openURL),
                stateStore: stateStore,
                lastActiveStore: lastActiveStore,
                logger: logger,
                logLevel: logConfiguration.logLevel,
                payloadPolicy: payloadPolicy
            )
            siwsAccount = nil
            lastResult = "\(error)"
        }
    }

    // MARK: - Helpers

    private func requireClient() throws -> WalletAdapterClient {
        guard let client else {
            throw WalletAdapterError.malformedPayload("Wallet client is not configured.")
        }
        return client
    }

    /// Runs a wallet action and turns its outcome into a toast: the returned
    /// success string becomes a green (or SIWS) toast; a thrown error becomes a
    /// red toast with a deterministic, user-facing message.
    ///
    /// `neutralStatusOnSuccess` is for terminal actions (disconnect/delete) that
    /// return to the connect screen: the action still toasts its result, but the
    /// persistent status line resets to "Ready" so the connect screen reads "Tap
    /// Connect…" instead of a stale "Disconnected"/"Account deleted".
    private func run(neutralStatusOnSuccess: Bool = false, _ operation: @escaping () async throws -> String) {
        isBusy = true
        Task { @MainActor in
            do {
                let message = try await operation()
                if !message.isEmpty {
                    lastResult = neutralStatusOnSuccess ? "Ready" : message
                    let style: DemoToast.Style = message.hasPrefix("Signed in with Solana") ? .siws : .success
                    showToast(message, style: style)
                }
            } catch is CancellationError {
                // Not user-facing.
            } catch {
                let message = userFacingMessage(for: error)
                lastResult = message
                showToast(message, style: .failure)
            }
            isBusy = false
        }
    }

    private func userFacingMessage(for error: Error) -> String {
        (error as? WalletAdapterError)?.userMessage ?? "\(error)"
    }

    private func showToast(_ message: String, style: DemoToast.Style) {
        toastDismissTask?.cancel()
        toast = DemoToast(message: message, style: style)
        toastDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation { toast = nil }
        }
    }

    /// Reads the last-connected wallet from the keychain pointer so launch lands
    /// on the correct wallet's cached session (extended auth cache).
    private func lastActiveWalletOnLaunch() -> DemoWallet? {
        guard let id = try? lastActiveStore.loadLastActiveWalletId() else { return nil }
        return DemoWallet(rawValue: id)
    }

    private func makeNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private func shortPubkey(_ pubkey: String) -> String {
        guard pubkey.count > 10 else { return pubkey }
        return "\(pubkey.prefix(8))…"
    }
}

enum DemoWallet: String, CaseIterable, Identifiable {
    case mock
    case phantom
    case solflare
    case backpack

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mock: "Mock Wallet"
        case .phantom: "Phantom"
        case .solflare: "Solflare"
        case .backpack: "Backpack"
        }
    }

    var provider: any WalletProvider {
        switch self {
        case .mock: SimulatorMockWalletProvider()
        case .phantom: PhantomAdapter()
        case .solflare: SolflareAdapter()
        case .backpack: BackpackAdapter()
        }
    }
}

@MainActor
final class DemoMockWalletOpener: WalletURLOpening, @unchecked Sendable {
    var client: WalletAdapterClient?
    private let responder: SimulatorMockWalletResponder
    private let redirectLink: URL
    private let logger: any WalletAdapterLogger
    private let logLevel: WalletAdapterLogLevel

    init(
        responder: SimulatorMockWalletResponder,
        redirectLink: URL,
        logger: any WalletAdapterLogger,
        logLevel: WalletAdapterLogLevel
    ) {
        self.responder = responder
        self.redirectLink = redirectLink
        self.logger = logger
        self.logLevel = logLevel
    }

    func openWalletURL(_ url: URL) async -> Bool {
        log("STEP_1_RECEIVED", "mock wallet received URL", [
            "url": WalletAdapterDebugFormatter.urlShape(url),
        ])
        do {
            guard let callback = try responder.callback(for: url, redirectLink: redirectLink) else {
                log("STEP_2_ACCEPTED_NO_CALLBACK", "mock wallet accepted URL without callback")
                return true
            }
            log("STEP_2_CALLBACK_BUILT", "mock wallet built callback", [
                "callback": WalletAdapterDebugFormatter.urlShape(callback),
            ])
            let handled = client?.handleOpenURL(callback) ?? false
            log("STEP_3_CALLBACK_ROUTED", "mock wallet routed callback", [
                "handled": "\(handled)",
            ])
            return handled
        } catch {
            logger.log(WalletAdapterLogEvent(
                component: "SimulatorMockWallet",
                method: "openWalletURL",
                step: "STEP_FAIL",
                phase: "FAIL",
                message: "mock wallet failed",
                metadata: WalletAdapterLogDiagnostics.failureMetadata(for: error)
            ))
            return false
        }
    }

    private func log(_ step: String, _ message: String, _ metadata: [String: String] = [:]) {
        guard logLevel != .off else { return }
        logger.log(WalletAdapterLogEvent(
            component: "SimulatorMockWallet",
            method: "openWalletURL",
            step: step,
            phase: "INFO",
            message: message,
            metadata: metadata
        ))
    }
}
