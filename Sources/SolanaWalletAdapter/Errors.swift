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
    case other(code: String, message: String)
}
