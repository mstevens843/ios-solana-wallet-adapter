import Foundation
import CryptoKit
import Security

/// NaCl `box` (X25519 ECDH + XSalsa20-Poly1305) wrapper.
///
public enum NaClBox {
    public static let nonceLength = 24
    public static let keyLength = 32
    public static let tagLength = 16

    public static func randomNonce() -> Data {
        var bytes = [UInt8](repeating: 0, count: nonceLength)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            for i in 0..<bytes.count {
                bytes[i] = UInt8.random(in: .min ... .max)
            }
        }
        return Data(bytes)
    }

    public static func seal(message: Data, nonce: Data, theirPublicKey: Data, mySecretKey: Data) -> Data {
        guard let sharedKey = sharedKey(theirPublicKey: theirPublicKey, mySecretKey: mySecretKey),
              nonce.count == nonceLength else {
            return Data()
        }
        return TweetNaCl.secretBoxSeal(message: message, nonce: nonce, key: sharedKey)
    }

    public static func open(box: Data, nonce: Data, theirPublicKey: Data, mySecretKey: Data) -> Data? {
        guard let sharedKey = sharedKey(theirPublicKey: theirPublicKey, mySecretKey: mySecretKey),
              nonce.count == nonceLength else {
            return nil
        }
        return TweetNaCl.secretBoxOpen(box: box, nonce: nonce, key: sharedKey)
    }

    private static func sharedKey(theirPublicKey: Data, mySecretKey: Data) -> Data? {
        guard theirPublicKey.count == keyLength, mySecretKey.count == keyLength else {
            return nil
        }
        do {
            let privateKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: mySecretKey)
            let publicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: theirPublicKey)
            let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: publicKey)
            let rawShared = sharedSecret.withUnsafeBytes { Data($0) }
            return TweetNaCl.boxBeforeNM(sharedSecret: rawShared)
        } catch {
            return nil
        }
    }
}
