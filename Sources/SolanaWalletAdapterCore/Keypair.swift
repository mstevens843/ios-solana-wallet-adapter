import Foundation

/// X25519 ephemeral keypair the consumer app generates per session and uses
/// to derive the NaCl-box shared secret with the wallet.
///
/// Phase 1 ships the type only. Phase 2 wires generation through
/// `Curve25519.KeyAgreement.PrivateKey` from CryptoKit.
public struct EphemeralKeypair: Sendable {
    public let publicKey: Data   // 32 bytes
    public let secretKey: Data   // 32 bytes

    public init(publicKey: Data, secretKey: Data) {
        self.publicKey = publicKey
        self.secretKey = secretKey
    }

    public static func generate() -> EphemeralKeypair {
        fatalError("EphemeralKeypair.generate: not implemented in Phase 1; ships in Phase 2.")
    }
}
