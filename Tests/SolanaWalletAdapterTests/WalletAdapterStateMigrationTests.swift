import XCTest
import SolanaWalletAdapter
import SolanaWalletAdapterCore
@testable import SolanaWalletAdapterUI

final class WalletAdapterStateMigrationTests: XCTestCase {
    func testV0RawBlobDecodesThroughFallback() throws {
        // Hand-crafted v0 blob: a JSON-encoded `WalletAdapterState` written before
        // the PersistedEnvelope wrapper existed. Older SDKs persisted this shape
        // directly into Keychain; the new decoder must still accept it.
        let v0 = WalletAdapterState(
            providerId: "phantom",
            cluster: .mainnetBeta,
            keypair: EphemeralKeypair(
                publicKey: Data(repeating: 1, count: 32),
                secretKey: Data(repeating: 2, count: 32)
            ),
            session: Session(
                walletEncryptionPublicKey: Data(repeating: 3, count: 32),
                token: "session-token",
                userPublicKey: "User1111111111111111111111111111111111"
            )
        )
        let rawBlob = try JSONEncoder().encode(v0)

        let restored = try KeychainWalletAdapterStateStore.decodePersistedState(from: rawBlob)

        XCTAssertEqual(restored.providerId, v0.providerId)
        XCTAssertEqual(restored.cluster, v0.cluster)
        XCTAssertEqual(restored.session?.token, v0.session?.token)
        XCTAssertNil(restored.preferredProviderId)
        XCTAssertNil(restored.cachedCapabilities)
        XCTAssertNil(restored.walletLabel)
        XCTAssertNil(restored.lastKnownCluster)
        XCTAssertNil(restored.lastSuccessAt)
    }

    func testV1EnvelopeRoundTrip() throws {
        let original = WalletAdapterState(
            providerId: "solflare",
            cluster: .mainnetBeta,
            keypair: EphemeralKeypair(
                publicKey: Data(repeating: 4, count: 32),
                secretKey: Data(repeating: 5, count: 32)
            ),
            session: nil,
            walletLabel: "Solflare",
            cachedCapabilities: nil,
            lastKnownCluster: .mainnetBeta,
            lastSuccessAt: Date(timeIntervalSince1970: 1_700_000_000),
            preferredProviderId: "solflare"
        )
        let envelope = PersistedEnvelope(state: original)
        let data = try JSONEncoder().encode(envelope)

        let restored = try KeychainWalletAdapterStateStore.decodePersistedState(from: data)

        XCTAssertEqual(restored, original)
    }

    func testV1EnvelopePreferredOverRawDecode() throws {
        // The envelope decode path must take priority when the blob is in the
        // versioned shape, even though a raw WalletAdapterState would also fail
        // to match because envelope has different top-level keys.
        let original = WalletAdapterState(
            providerId: "backpack",
            cluster: .mainnetBeta,
            keypair: EphemeralKeypair(
                publicKey: Data(repeating: 6, count: 32),
                secretKey: Data(repeating: 7, count: 32)
            ),
            session: nil,
            preferredProviderId: "backpack"
        )
        let envelope = PersistedEnvelope(state: original, version: 1)
        let data = try JSONEncoder().encode(envelope)

        let restored = try KeychainWalletAdapterStateStore.decodePersistedState(from: data)

        XCTAssertEqual(restored.preferredProviderId, "backpack")
    }
}
