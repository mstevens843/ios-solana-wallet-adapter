import Foundation

/// Stable error vocabulary referenced by `spec/protocol.md`. Wallet-specific
/// `errorCode` strings are mapped to these by each adapter so consumers can
/// branch on a single enum.
public enum WalletAdapterError: Error, Equatable, Sendable {
    case userRejected
    case invalidSession
    case unsupportedMethod(String)
    case malformedPayload(String)
    case walletUnreachable
    case decryptionFailed
    case clusterMismatch(expected: Cluster, got: String)
    case operationInProgress
    case noPendingRequest
    case requestCancelled
    case other(code: String, message: String)
}

public extension WalletAdapterError {
    /// Terse, deterministic, user-facing copy suitable for a toast. This is
    /// distinct from the developer-facing diagnostics in
    /// `WalletAdapterLogDiagnostics`; every case maps to a stable string so UIs
    /// can show a clear success/fail outcome instead of a raw `Error` dump.
    var userMessage: String {
        switch self {
        case .userRejected: return "Rejected in wallet"
        case .invalidSession: return "Session expired — reconnect"
        case .unsupportedMethod: return "Not supported by this wallet"
        case .malformedPayload: return "Invalid request"
        case .walletUnreachable: return "Couldn't reach wallet"
        case .decryptionFailed: return "Secure response failed"
        case .clusterMismatch: return "Wrong network"
        case .operationInProgress: return "Another request is in progress"
        case .noPendingRequest: return "No active request"
        case .requestCancelled: return "Request cancelled"
        case .other(_, let message): return message
        }
    }
}
