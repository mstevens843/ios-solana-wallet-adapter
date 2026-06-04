import XCTest
import SolanaWalletAdapter
import SolanaWalletAdapterCore
import SolanaWalletAdapterPhantom

final class WalletAdapterStateTests: XCTestCase {
    func testWalletAdapterStateRoundTripsThroughCodable() throws {
        let state = WalletAdapterState(
            providerId: "phantom",
            cluster: .devnet,
            keypair: EphemeralKeypair(publicKey: Data(repeating: 1, count: 32), secretKey: Data(repeating: 2, count: 32)),
            session: Session(
                walletEncryptionPublicKey: Data(repeating: 3, count: 32),
                token: "session-token",
                userPublicKey: "User1111111111111111111111111111111111"
            )
        )

        let data = try JSONEncoder().encode(state)
        XCTAssertEqual(try JSONDecoder().decode(WalletAdapterState.self, from: data), state)
    }

    func testPhantomMarksSignAndSendTransactionDeprecated() {
        let support = PhantomAdapter().capabilities.support(for: .signAndSendTransaction)

        XCTAssertEqual(support?.isSupported, true)
        XCTAssertEqual(support?.isDeprecated, true)
        XCTAssertTrue(support?.note?.contains("deprecated") == true)
    }
}
