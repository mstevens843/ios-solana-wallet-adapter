import Foundation
import SolanaWalletAdapterCore

public enum WalletAdapterLogLevel: Int, Sendable, Comparable {
    case off = 0
    case error = 1
    case info = 2
    case debug = 3

    public static func < (lhs: WalletAdapterLogLevel, rhs: WalletAdapterLogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum WalletAdapterLogPayloadPolicy: Sendable, Equatable {
    case redacted
    case unsafeRawPayloads

    public var includesRawPayloads: Bool {
        self == .unsafeRawPayloads
    }
}

public struct WalletAdapterLogConfiguration: Sendable, Equatable {
    public static let logLevelEnvironmentKey = "SOLANA_WALLET_ADAPTER_LOG_LEVEL"
    public static let unsafeLogsEnvironmentKey = "SOLANA_WALLET_ADAPTER_UNSAFE_LOGS"
    public static let logPrefixEnvironmentKey = "SOLANA_WALLET_ADAPTER_LOG_PREFIX"

    public let logLevel: WalletAdapterLogLevel
    public let payloadPolicy: WalletAdapterLogPayloadPolicy
    public let prefix: String

    public init(
        logLevel: WalletAdapterLogLevel = .off,
        payloadPolicy: WalletAdapterLogPayloadPolicy = .redacted,
        prefix: String = "[iWA]"
    ) {
        self.logLevel = logLevel
        self.payloadPolicy = payloadPolicy
        self.prefix = prefix
    }

    public static func fromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment,
        defaultLogLevel: WalletAdapterLogLevel = .off,
        defaultPayloadPolicy: WalletAdapterLogPayloadPolicy = .redacted,
        defaultPrefix: String = "[iWA]"
    ) -> WalletAdapterLogConfiguration {
        WalletAdapterLogConfiguration(
            logLevel: parseLogLevel(environment[logLevelEnvironmentKey]) ?? defaultLogLevel,
            payloadPolicy: parseUnsafeLogs(environment[unsafeLogsEnvironmentKey]) ?? defaultPayloadPolicy,
            prefix: nonEmpty(environment[logPrefixEnvironmentKey]) ?? defaultPrefix
        )
    }

    public var printLogger: PrintWalletAdapterLogger {
        WalletAdapterLoggers.print(prefix: prefix)
    }

    private static func parseLogLevel(_ value: String?) -> WalletAdapterLogLevel? {
        switch normalized(value) {
        case "off", "0", "false", "no":
            return .off
        case "error", "1":
            return .error
        case "info", "2":
            return .info
        case "debug", "3", "true", "yes", "on":
            return .debug
        default:
            return nil
        }
    }

    private static func parseUnsafeLogs(_ value: String?) -> WalletAdapterLogPayloadPolicy? {
        switch normalized(value) {
        case "1", "true", "yes", "on", "unsafe", "raw", "debug":
            return .unsafeRawPayloads
        case "0", "false", "no", "off", "redacted", "safe":
            return .redacted
        default:
            return nil
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func normalized(_ value: String?) -> String {
        nonEmpty(value)?.lowercased() ?? ""
    }
}

public struct WalletAdapterLogEvent: Sendable, Equatable {
    public let component: String
    public let method: String
    public let step: String
    public let phase: String
    public let message: String
    public let metadata: [String: String]

    public init(
        component: String,
        method: String,
        step: String,
        phase: String,
        message: String,
        metadata: [String: String] = [:]
    ) {
        self.component = component
        self.method = method
        self.step = step
        self.phase = phase
        self.message = message
        self.metadata = metadata
    }
}

public protocol WalletAdapterLogger: Sendable {
    func log(_ event: WalletAdapterLogEvent)
}

public struct DisabledWalletAdapterLogger: WalletAdapterLogger {
    public init() {}
    public func log(_ event: WalletAdapterLogEvent) {}
}

public struct PrintWalletAdapterLogger: WalletAdapterLogger {
    public let prefix: String

    public init(prefix: String = "[iWA]") {
        self.prefix = prefix
    }

    public func log(_ event: WalletAdapterLogEvent) {
        print(WalletAdapterDebugFormatter.format(event, prefix: prefix))
    }
}

public enum WalletAdapterLoggers {
    public static let disabled = DisabledWalletAdapterLogger()

    public static func print(prefix: String = "[iWA]") -> PrintWalletAdapterLogger {
        PrintWalletAdapterLogger(prefix: prefix)
    }
}

public enum WalletAdapterLogDiagnostics {
    public static func failureMetadata(
        for error: Error,
        flowID: String? = nil,
        metadata: [String: String] = [:]
    ) -> [String: String] {
        let diagnostics = diagnostics(for: error)
        var result = [
            "error": "\(error)",
            "error_type": "\(type(of: error))",
            "error_code": errorCode(error),
            "failure_hint": diagnostics.failureHint,
            "fix_hint": diagnostics.fixHint,
        ]
        if let flowID {
            result["flow_id"] = flowID
        }
        if let adapterError = error as? WalletAdapterError {
            switch adapterError {
            case .clusterMismatch(let expected, let got):
                result["expected"] = expected.rawValue
                result["actual"] = got
            case .unsupportedMethod(let message):
                result["unsupported_message"] = message
            case .malformedPayload(let message):
                result["malformed_message"] = message
            case .other(let code, let message):
                result["wallet_error_code"] = code
                result["wallet_error_message"] = message
            default:
                break
            }
        }
        return result.merging(metadata) { _, new in new }
    }

    public static func diagnostics(for error: Error) -> (failureHint: String, fixHint: String) {
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

    public static func errorCode(_ error: Error) -> String {
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
}

public enum WalletAdapterDebugFormatter {
    public static func shortBase58(_ value: String, prefix: Int = 8, suffix: Int = 8) -> String {
        guard value.count > prefix + suffix else { return value }
        return "\(value.prefix(prefix))...\(value.suffix(suffix))"
    }

    public static func byteCount(_ data: Data) -> String {
        "\(data.count)"
    }

    public static func base58(_ data: Data) -> String {
        Base58.encode(data)
    }

    public static func utf8OrBase58(_ data: Data) -> String {
        if let string = String(data: data, encoding: .utf8) {
            return string
        }
        return Base58.encode(data)
    }

    public static func json(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return "\(value)"
        }
        return string
    }

    public static func queryValues(_ url: URL) -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return "{}"
        }
        let pairs = (components.queryItems ?? [])
            .sorted { $0.name < $1.name }
            .map { "\($0.name)=\($0.value ?? "")" }
            .joined(separator: "&")
        return pairs
    }

    public static func urlShape(_ url: URL) -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return "invalid_url"
        }
        let scheme = components.scheme ?? "none"
        let host = components.host ?? "none"
        let path = components.path.isEmpty ? "/" : components.path
        let keys = (components.queryItems ?? []).map(\.name).sorted().joined(separator: ",")
        return "scheme=\(scheme) host=\(host) path=\(path) query_keys=\(keys)"
    }

    public static func queryKeys(_ url: URL) -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return ""
        }
        return (components.queryItems ?? []).map(\.name).sorted().joined(separator: ",")
    }

    public static func format(_ event: WalletAdapterLogEvent, prefix: String = "[iWA]") -> String {
        let metadata = event.metadata
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\(escape($0.value))" }
            .joined(separator: " ")
        let suffix = metadata.isEmpty ? "" : " \(metadata)"
        return "\(prefix) [\(event.component)] \(event.method) | \(event.step) phase=\(event.phase) message=\"\(event.message)\"\(suffix)"
    }

    private static func escape(_ value: String) -> String {
        let needsQuotes = value.contains { character in
            character.isWhitespace || character == "\"" || character == "{" || character == "}" || character == "[" || character == "]"
        }
        guard needsQuotes else { return value }
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }
}
