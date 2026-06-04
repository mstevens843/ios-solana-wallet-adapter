import Foundation
import SolanaWalletAdapterCore

public struct WalletAdapterState: Sendable, Equatable, Codable {
    public let providerId: String
    public let cluster: Cluster
    public let keypair: EphemeralKeypair
    public let session: Session?

    /// Human-readable wallet label captured at connect time. Used by UI affordances
    /// like "Reconnect to Phantom (8xK…fG2)" without re-prompting the wallet.
    public let walletLabel: String?

    /// Capabilities snapshot for the connected wallet. Resolved locally from
    /// static provider metadata, so it's always safe to cache. `nil` for older
    /// persisted state from before this field existed.
    public let cachedCapabilities: WalletCapabilities?

    /// Last cluster the user actually transacted on. Distinct from `cluster`
    /// (the adapter's currently selected cluster) so a logged-out user can still
    /// be reconnected against the right network.
    public let lastKnownCluster: Cluster?

    /// Timestamp of the most recent successful wallet callback. Used by UI to
    /// decide whether a cached session is "fresh enough" to surface a
    /// Reconnect button without re-authenticating.
    public let lastSuccessAt: Date?

    /// The wallet the user picked with "Always" in the picker sheet. When set,
    /// the picker should be skipped until the user explicitly forgets it.
    public let preferredProviderId: String?

    public init(
        providerId: String,
        cluster: Cluster,
        keypair: EphemeralKeypair,
        session: Session?,
        walletLabel: String? = nil,
        cachedCapabilities: WalletCapabilities? = nil,
        lastKnownCluster: Cluster? = nil,
        lastSuccessAt: Date? = nil,
        preferredProviderId: String? = nil
    ) {
        self.providerId = providerId
        self.cluster = cluster
        self.keypair = keypair
        self.session = session
        self.walletLabel = walletLabel
        self.cachedCapabilities = cachedCapabilities
        self.lastKnownCluster = lastKnownCluster
        self.lastSuccessAt = lastSuccessAt
        self.preferredProviderId = preferredProviderId
    }
}

public protocol WalletAdapterStateStore: Sendable {
    func loadState() throws -> WalletAdapterState?
    func saveState(_ state: WalletAdapterState?) throws
}
