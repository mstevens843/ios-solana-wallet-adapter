import Foundation

/// What the picker hands back to the caller. The caller is responsible for the
/// async connect/sign flow that follows — the picker's job ends at selection.
public enum WalletPickerSelection: Sendable, Equatable {
    /// User chose `walletId`. `remember == true` means "Always" (the picker
    /// should call `WalletAdapterClient.rememberPreferredWallet` before
    /// triggering the connect flow).
    case picked(walletId: String, remember: Bool)
    /// Sheet was dismissed without a choice.
    case cancelled
}
