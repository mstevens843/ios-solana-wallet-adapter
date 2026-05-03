import Foundation

/// NaCl `box` (X25519 ECDH + XSalsa20-Poly1305) wrapper.
///
/// Phase 1 ships the type and signature only. Phase 2 wires the actual
/// implementation against either Apple's `CryptoKit` (Curve25519 + XSalsa20
/// re-implementation) or a vendored TweetNaCl port. Calling either method in
/// Phase 1 traps so misuse is caught immediately during smoke tests.
public enum NaClBox {
    public static func seal(message: Data, nonce: Data, theirPublicKey: Data, mySecretKey: Data) -> Data {
        fatalError("NaClBox.seal: not implemented in Phase 1; ships in Phase 2.")
    }

    public static func open(box: Data, nonce: Data, theirPublicKey: Data, mySecretKey: Data) -> Data? {
        fatalError("NaClBox.open: not implemented in Phase 1; ships in Phase 2.")
    }
}
