import Foundation

/// Status of a wallet hand-off, surfaced in the Live Activity "tap-to-return"
/// pill. Transport-agnostic: works with the WalletConnect/Reown stopgap today and
/// the native iWA/jWA path once a wallet adopts the handler.
///
/// On iOS there is no silent auto-return for a separate native wallet that does
/// not cooperate (only the foreground wallet can re-open the dApp). The Live
/// Activity is the best-in-class substitute: a glanceable, one-tap return that
/// also tells the user the action succeeded.
public enum WalletHandoffStatus: String, Sendable, Codable, Equatable {
    /// User has been handed off to the wallet to approve.
    case waiting
    /// The action completed (e.g. signature/txid received or on-chain confirmed).
    case signed
    /// The action failed or was rejected.
    case failed
}
