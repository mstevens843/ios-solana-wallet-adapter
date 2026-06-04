import Foundation

public enum WalletMethod: String, Sendable, Codable, CaseIterable {
    case connect
    case disconnect
    case getCapabilities
    case getAccounts
    case requestAccounts
    case signMessage
    case signTransaction
    case signAllTransactions
    case signAndSendTransaction
    case signInWithSolana
    case authorize
    case deauthorize
    case signMessages
    case signTransactions
    case signAndSendTransactions

    public static let nativeDeeplinkProtocolMethods: [WalletMethod] = [
        .connect,
        .disconnect,
        .signMessage,
        .signTransaction,
        .signAllTransactions,
        .signAndSendTransaction,
    ]
}

public struct WalletMethodSupport: Sendable, Equatable, Codable {
    public let method: WalletMethod
    public let isSupported: Bool
    public let isDeprecated: Bool
    public let note: String?

    public init(
        method: WalletMethod,
        isSupported: Bool = true,
        isDeprecated: Bool = false,
        note: String? = nil
    ) {
        self.method = method
        self.isSupported = isSupported
        self.isDeprecated = isDeprecated
        self.note = note
    }
}

public enum WalletTransportKind: String, Sendable, Equatable, Codable {
    case nativeDeeplink = "native-deeplink"
    case walletConnect = "wallet-connect"
}

public struct WalletCapabilityLimits: Sendable, Equatable, Codable {
    public let maxMessagesPerRequest: Int?
    public let maxTransactionsPerRequest: Int?
    public let maxSignAndSendTransactionsPerRequest: Int?
    public let maxTransactionBytes: Int?
    public let supportedTransactionVersions: [String]?

    public init(
        maxMessagesPerRequest: Int? = nil,
        maxTransactionsPerRequest: Int? = nil,
        maxSignAndSendTransactionsPerRequest: Int? = nil,
        maxTransactionBytes: Int? = nil,
        supportedTransactionVersions: [String]? = nil
    ) {
        self.maxMessagesPerRequest = maxMessagesPerRequest
        self.maxTransactionsPerRequest = maxTransactionsPerRequest
        self.maxSignAndSendTransactionsPerRequest = maxSignAndSendTransactionsPerRequest
        self.maxTransactionBytes = maxTransactionBytes
        self.supportedTransactionVersions = supportedTransactionVersions
    }

    public static let unknown = WalletCapabilityLimits()
}

public struct WalletProviderCapabilities: Sendable, Equatable, Codable {
    public let walletId: String
    public let displayName: String
    public let universalLinkHost: String
    public let customScheme: String
    public let methods: [WalletMethodSupport]
    public let featureIdentifiers: [String]
    public let limits: WalletCapabilityLimits

    public init(
        walletId: String,
        displayName: String,
        universalLinkHost: String,
        customScheme: String,
        methods: [WalletMethodSupport],
        featureIdentifiers: [String] = [],
        limits: WalletCapabilityLimits = .unknown
    ) {
        self.walletId = walletId
        self.displayName = displayName
        self.universalLinkHost = universalLinkHost
        self.customScheme = customScheme
        self.methods = methods
        self.featureIdentifiers = featureIdentifiers
        self.limits = limits
    }

    public func support(for method: WalletMethod) -> WalletMethodSupport? {
        methods.first { $0.method == method }
    }
}

public struct WalletCapabilities: Sendable, Equatable, Codable {
    public let walletId: String
    public let displayName: String
    public let transport: WalletTransportKind
    public let universalLinkHost: String?
    public let customScheme: String?
    public let methods: [WalletMethodSupport]
    public let featureIdentifiers: [String]
    public let limits: WalletCapabilityLimits

    public init(
        walletId: String,
        displayName: String,
        transport: WalletTransportKind,
        universalLinkHost: String? = nil,
        customScheme: String? = nil,
        methods: [WalletMethodSupport],
        featureIdentifiers: [String] = [],
        limits: WalletCapabilityLimits = .unknown
    ) {
        self.walletId = walletId
        self.displayName = displayName
        self.transport = transport
        self.universalLinkHost = universalLinkHost
        self.customScheme = customScheme
        self.methods = methods
        self.featureIdentifiers = featureIdentifiers
        self.limits = limits
    }

    public func support(for method: WalletMethod) -> WalletMethodSupport? {
        methods.first { $0.method == method }
    }

    public static func nativeDeeplink(providerCapabilities: WalletProviderCapabilities) -> WalletCapabilities {
        var supports: [WalletMethod: WalletMethodSupport] = [:]
        for support in providerCapabilities.methods {
            supports[support.method] = support
        }

        func add(_ method: WalletMethod, isSupported: Bool = true, isDeprecated: Bool = false, note: String? = nil) {
            if supports[method] == nil {
                supports[method] = WalletMethodSupport(
                    method: method,
                    isSupported: isSupported,
                    isDeprecated: isDeprecated,
                    note: note
                )
            }
        }

        let connectSupport = providerCapabilities.support(for: .connect)
        let disconnectSupport = providerCapabilities.support(for: .disconnect)
        let signMessageSupport = providerCapabilities.support(for: .signMessage)
        let signTransactionSupport = providerCapabilities.support(for: .signTransaction)
        let signAllTransactionsSupport = providerCapabilities.support(for: .signAllTransactions)
        let signAndSendSupport = providerCapabilities.support(for: .signAndSendTransaction)

        add(.getCapabilities, note: "Resolved locally from adapter metadata; no wallet round trip.")
        add(.signInWithSolana, isSupported: signMessageSupport?.isSupported ?? false, isDeprecated: signMessageSupport?.isDeprecated ?? false, note: "Built as a SIWS v1 UTF-8 message and signed through the native signMessage deeplink.")
        add(.authorize, isSupported: connectSupport?.isSupported ?? false, isDeprecated: connectSupport?.isDeprecated ?? false, note: "Compatibility alias for connect.")
        add(.deauthorize, isSupported: disconnectSupport?.isSupported ?? false, isDeprecated: disconnectSupport?.isDeprecated ?? false, note: "Compatibility alias for disconnect.")
        add(.signMessages, isSupported: signMessageSupport?.isSupported ?? false, isDeprecated: signMessageSupport?.isDeprecated ?? false, note: "Compatibility alias supports one message per request.")
        add(.signTransactions, isSupported: providerCapabilities.support(for: .signAllTransactions)?.isSupported ?? false, note: "Compatibility alias for signAllTransactions.")
        add(.signAndSendTransactions, isSupported: signAndSendSupport?.isSupported ?? false, isDeprecated: signAndSendSupport?.isDeprecated ?? false, note: "Compatibility alias supports one transaction per request.")

        let orderedMethods = WalletMethod.allCases.compactMap { supports[$0] }
        var featureIdentifiers = Set(providerCapabilities.featureIdentifiers)
        featureIdentifiers.insert("iwa:native-deeplink")
        if signMessageSupport?.isSupported == true {
            featureIdentifiers.insert("solana:sign-message")
            featureIdentifiers.insert("solana:siws-v1-message")
        }
        if signTransactionSupport?.isSupported == true || signAllTransactionsSupport?.isSupported == true {
            featureIdentifiers.insert("solana:sign-transaction")
        }
        return WalletCapabilities(
            walletId: providerCapabilities.walletId,
            displayName: providerCapabilities.displayName,
            transport: .nativeDeeplink,
            universalLinkHost: providerCapabilities.universalLinkHost,
            customScheme: providerCapabilities.customScheme,
            methods: orderedMethods,
            featureIdentifiers: featureIdentifiers.sorted(),
            limits: WalletCapabilityLimits(
                maxMessagesPerRequest: providerCapabilities.limits.maxMessagesPerRequest ?? 1,
                maxTransactionsPerRequest: providerCapabilities.limits.maxTransactionsPerRequest,
                maxSignAndSendTransactionsPerRequest: providerCapabilities.limits.maxSignAndSendTransactionsPerRequest ?? 1,
                maxTransactionBytes: providerCapabilities.limits.maxTransactionBytes,
                supportedTransactionVersions: providerCapabilities.limits.supportedTransactionVersions
            )
        )
    }
}

public extension WalletProvider {
    var capabilities: WalletProviderCapabilities {
        WalletProviderCapabilities(
            walletId: walletId,
            displayName: walletId.prefix(1).uppercased() + walletId.dropFirst(),
            universalLinkHost: universalLinkHost,
            customScheme: customScheme,
            methods: WalletMethod.nativeDeeplinkProtocolMethods.map { WalletMethodSupport(method: $0) }
        )
    }
}
