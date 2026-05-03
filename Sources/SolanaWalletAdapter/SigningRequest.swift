import Foundation

/// Variants of the signing request a consumer can ask the wallet to fulfill.
/// Mirrors the methods enumerated in `spec/protocol.md`.
public enum SigningRequest: Sendable {
    /// Sign an arbitrary message. Wallet returns a 64-byte ed25519 signature.
    case message(Data)
    /// Sign a Solana transaction without broadcasting. Wallet returns the signed wire-format bytes.
    case transaction(Data)
    /// Sign a batch of transactions. Wallet returns one signed wire-format payload per input.
    case allTransactions([Data])
    /// Sign and broadcast in one approval. Wallet returns the txid.
    case signAndSend(Data, sendOptions: SendOptions = .init())
}

public struct SendOptions: Sendable, Equatable {
    public let skipPreflight: Bool
    public let preflightCommitment: String?
    public let maxRetries: Int?

    public init(skipPreflight: Bool = false, preflightCommitment: String? = nil, maxRetries: Int? = nil) {
        self.skipPreflight = skipPreflight
        self.preflightCommitment = preflightCommitment
        self.maxRetries = maxRetries
    }
}
