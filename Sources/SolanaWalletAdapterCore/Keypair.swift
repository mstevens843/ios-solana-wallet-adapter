import Foundation
import CryptoKit

/// X25519 ephemeral keypair the consumer app generates per session and uses
/// to derive the NaCl-box shared secret with the wallet.
///
public struct EphemeralKeypair: Sendable {
    public let publicKey: Data   // 32 bytes
    public let secretKey: Data   // 32 bytes

    public init(publicKey: Data, secretKey: Data) {
        self.publicKey = publicKey
        self.secretKey = secretKey
    }

    public static func generate() -> EphemeralKeypair {
        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        return EphemeralKeypair(
            publicKey: privateKey.publicKey.rawRepresentation,
            secretKey: privateKey.rawRepresentation
        )
    }
}
