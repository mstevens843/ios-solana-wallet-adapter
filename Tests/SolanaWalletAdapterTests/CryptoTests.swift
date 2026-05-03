import XCTest
@testable import SolanaWalletAdapterCore

final class CryptoTests: XCTestCase {
    private let dappSecret = Base58.decode("4wBqpZM9xaSheZzJSMawUKKwhdpChKbZ5eu5ky4Vigw")!
    private let dappPublic = Base58.decode("WpSggvhoqoVW4XJvfjsB52dvVunYSQWrz6XiuMQVsCf")!
    private let walletSecret = Base58.decode("7ppk9w8NHnH6ehajvJyU31VcMafwZ3ybRtJWumSyD2wd")!
    private let walletPublic = Base58.decode("6rvZvM15TRkYozYPXwXPiAMFpXPmiVoTPtCT6uqSLd1X")!
    private let nonce = Base58.decode("KPym5Vq98pYDgiKHQQu8Ty122PDwRNgJ3")!
    private let message = Base58.decode("2TMegyxqxL3KrmkLbro66ydjuYZP")!
    private let expectedBox = Base58.decode("K5bXjRiQ358owNRNQTZtSNsqkP3zjcZVE7jvSwXdHt3drwVMC")!

    func testEphemeralKeypairGenerateProduces32ByteMaterials() {
        let keypair = EphemeralKeypair.generate()
        XCTAssertEqual(keypair.publicKey.count, 32)
        XCTAssertEqual(keypair.secretKey.count, 32)
        XCTAssertEqual(Base58.decode(Base58.encode(keypair.publicKey)), keypair.publicKey)
        XCTAssertEqual(Base58.decode(Base58.encode(keypair.secretKey)), keypair.secretKey)
    }

    func testNaClBoxSealMatchesTweetNaClVectorAndOpens() {
        let box = NaClBox.seal(message: message, nonce: nonce, theirPublicKey: walletPublic, mySecretKey: dappSecret)
        XCTAssertEqual(box, expectedBox)
        XCTAssertEqual(
            NaClBox.open(box: box, nonce: nonce, theirPublicKey: dappPublic, mySecretKey: walletSecret),
            message
        )
    }

    func testNaClBoxOpenFailsForWrongKeyWrongNonceAndTampering() {
        let box = NaClBox.seal(message: message, nonce: nonce, theirPublicKey: walletPublic, mySecretKey: dappSecret)
        let wrongKey = EphemeralKeypair.generate()
        XCTAssertNil(NaClBox.open(box: box, nonce: nonce, theirPublicKey: wrongKey.publicKey, mySecretKey: walletSecret))

        var wrongNonce = nonce
        wrongNonce[0] ^= 1
        XCTAssertNil(NaClBox.open(box: box, nonce: wrongNonce, theirPublicKey: dappPublic, mySecretKey: walletSecret))

        var tampered = box
        tampered[tampered.count - 1] ^= 1
        XCTAssertNil(NaClBox.open(box: tampered, nonce: nonce, theirPublicKey: dappPublic, mySecretKey: walletSecret))
    }
}
