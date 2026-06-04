import Foundation

public struct SignInWithSolanaInput: Sendable, Equatable, Codable {
    public let nonce: String
    public let domain: String?
    public let statement: String?
    public let uri: URL?
    public let chainId: String?
    public let issuedAt: Date?
    public let expirationTime: Date?
    public let notBefore: Date?
    public let requestId: String?
    public let resources: [URL]

    public init(
        nonce: String,
        domain: String? = nil,
        statement: String? = nil,
        uri: URL? = nil,
        chainId: String? = nil,
        issuedAt: Date? = nil,
        expirationTime: Date? = nil,
        notBefore: Date? = nil,
        requestId: String? = nil,
        resources: [URL] = []
    ) {
        self.nonce = nonce
        self.domain = domain
        self.statement = statement
        self.uri = uri
        self.chainId = chainId
        self.issuedAt = issuedAt
        self.expirationTime = expirationTime
        self.notBefore = notBefore
        self.requestId = requestId
        self.resources = resources
    }
}

public enum SignInWithSolanaSignatureType: String, Sendable, Codable {
    case ed25519
}

public struct SignInWithSolanaResult: Sendable, Equatable, Codable {
    public let account: String
    public let signedMessage: Data
    public let signature: Data
    public let signatureType: SignInWithSolanaSignatureType
    public let session: Session

    public init(
        account: String,
        signedMessage: Data,
        signature: Data,
        signatureType: SignInWithSolanaSignatureType = .ed25519,
        session: Session
    ) {
        self.account = account
        self.signedMessage = signedMessage
        self.signature = signature
        self.signatureType = signatureType
        self.session = session
    }

    public var signedMessageString: String? {
        String(data: signedMessage, encoding: .utf8)
    }
}

public enum SignInWithSolanaMessage {
    public static let version = "1"
    public static let allowedChainIds: Set<String> = [
        "mainnet",
        "testnet",
        "devnet",
        "localnet",
        "solana:mainnet",
        "solana:testnet",
        "solana:devnet",
    ]

    public static func make(
        input: SignInWithSolanaInput,
        address: String,
        defaultDomain: String? = nil,
        defaultURI: URL? = nil,
        defaultChainId: String? = nil,
        defaultIssuedAt: Date = Date()
    ) throws -> String {
        try validate(input)

        guard let domain = nonEmpty(input.domain ?? defaultDomain) else {
            throw WalletAdapterError.malformedPayload("SIWS domain is required.")
        }
        guard let uri = input.uri ?? defaultURI else {
            throw WalletAdapterError.malformedPayload("SIWS URI is required.")
        }

        var lines = [
            "\(domain) wants you to sign in with your Solana account:",
            address,
            "",
        ]

        if let statement = nonEmpty(input.statement) {
            lines.append(statement)
            lines.append("")
        }

        lines.append("URI: \(uri.absoluteString)")
        lines.append("Version: \(version)")
        if let chainId = nonEmpty(input.chainId ?? defaultChainId) {
            lines.append("Chain ID: \(chainId)")
        }
        lines.append("Nonce: \(input.nonce)")
        lines.append("Issued At: \(formatISO8601(input.issuedAt ?? defaultIssuedAt))")
        if let expirationTime = input.expirationTime {
            lines.append("Expiration Time: \(formatISO8601(expirationTime))")
        }
        if let notBefore = input.notBefore {
            lines.append("Not Before: \(formatISO8601(notBefore))")
        }
        if let requestId = nonEmpty(input.requestId) {
            lines.append("Request ID: \(requestId)")
        }
        if !input.resources.isEmpty {
            lines.append("Resources:")
            lines.append(contentsOf: input.resources.map { "- \($0.absoluteString)" })
        }

        return lines.joined(separator: "\n")
    }

    public static func validate(_ input: SignInWithSolanaInput) throws {
        guard input.nonce.count >= 8, input.nonce.unicodeScalars.allSatisfy(isASCIIAlphanumeric) else {
            throw WalletAdapterError.malformedPayload("SIWS nonce must be at least 8 ASCII alphanumeric characters.")
        }
        if let statement = input.statement, statement.contains("\n") || statement.contains("\r") {
            throw WalletAdapterError.malformedPayload("SIWS statement must not contain newline characters.")
        }
        if let chainId = nonEmpty(input.chainId), !allowedChainIds.contains(chainId) {
            throw WalletAdapterError.malformedPayload("SIWS chainId is not supported.")
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func isASCIIAlphanumeric(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 48...57, 65...90, 97...122:
            return true
        default:
            return false
        }
    }

    private static func formatISO8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}

public extension Cluster {
    var signInWithSolanaChainId: String {
        switch self {
        case .mainnetBeta:
            return "solana:mainnet"
        case .devnet:
            return "solana:devnet"
        case .testnet:
            return "solana:testnet"
        }
    }

    var signInWithSolanaShortChainId: String {
        switch self {
        case .mainnetBeta:
            return "mainnet"
        case .devnet:
            return "devnet"
        case .testnet:
            return "testnet"
        }
    }

    func matchesSignInWithSolanaChainId(_ chainId: String) -> Bool {
        chainId == signInWithSolanaChainId || chainId == signInWithSolanaShortChainId
    }
}
