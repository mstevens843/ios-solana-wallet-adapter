import Foundation
import SolanaWalletAdapter
import SolanaWalletAdapterCore

/// Wallet-side integration points for the jWA reference handler.
///
/// A wallet adopts jWA (the iWA custom-scheme profile, see `spec/jwa-protocol.md`)
/// by conforming its existing keystore, approval UI, and app-switch call to the
/// three protocols below and forwarding inbound URLs to `JupiterWalletHandler`.
/// These types are wallet-agnostic: although the target is named for Jupiter
/// (its first intended adopter), any iOS Solana wallet can use it unchanged.

// MARK: - Signing

/// The wallet's signing keystore. Conform your existing key management to this.
public protocol JWASigner: Sendable {
    /// Base58-encoded Solana account public key the wallet signs for.
    var userPublicKey: String { get }

    /// Sign an arbitrary message. Returns the raw signature bytes.
    func signMessage(_ message: Data) async throws -> Data

    /// Sign a serialized transaction. Returns the signed transaction wire bytes.
    func signTransaction(_ transaction: Data) async throws -> Data

    /// Sign multiple serialized transactions, preserving order.
    func signAllTransactions(_ transactions: [Data]) async throws -> [Data]

    /// Sign and broadcast a transaction. Returns the base58 transaction signature (txid).
    /// Reuses the package's `SendOptions` (from `SigningRequest.swift`).
    func signAndSendTransaction(_ transaction: Data, options: SendOptions) async throws -> String
}

// MARK: - Approval UI

public enum JWAApprovalDecision: Sendable, Equatable {
    case approve
    case reject
}

/// Sendable description of an inbound request for the approval sheet, including
/// the decoded operation so the wallet can render exactly what will be signed.
public struct JWAIncomingRequest: Sendable {
    public let method: WalletMethod
    public let dappEncryptionPublicKey: Data
    public let redirectLink: URL
    public let appURL: URL?
    public let cluster: Cluster
    /// The decoded operation the dApp is requesting — `nil` for connect/disconnect,
    /// otherwise the `.message` / `.transaction` / `.allTransactions` / `.signAndSend`
    /// content (reusing the package's `SigningRequest`) so the approval sheet can
    /// show the message text or transaction(s) being signed.
    public let signingRequest: SigningRequest?

    public init(
        method: WalletMethod,
        dappEncryptionPublicKey: Data,
        redirectLink: URL,
        appURL: URL?,
        cluster: Cluster,
        signingRequest: SigningRequest? = nil
    ) {
        self.method = method
        self.dappEncryptionPublicKey = dappEncryptionPublicKey
        self.redirectLink = redirectLink
        self.appURL = appURL
        self.cluster = cluster
        self.signingRequest = signingRequest
    }
}

/// The wallet presents its approval sheet and returns the user's decision.
public protocol JWAApprovalUI: Sendable {
    func requestApproval(_ request: JWAIncomingRequest) async -> JWAApprovalDecision
}

/// Auto-approve everything — useful for tests and the loopback harness only.
public struct JWAAlwaysApprove: JWAApprovalUI {
    public init() {}
    public func requestApproval(_ request: JWAIncomingRequest) async -> JWAApprovalDecision { .approve }
}

// MARK: - Return (the auto-return leg)

/// Opens a URL to send the user back to the calling dApp. In a real wallet this
/// wraps `UIApplication.open`; the handler calls it after every terminal outcome.
/// This is the leg that gives clean auto-return — see `spec/jwa-protocol.md`.
public protocol JWAReturnOpening: Sendable {
    @MainActor func open(_ url: URL) async -> Bool
}
