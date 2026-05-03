import XCTest
@testable import SolanaWalletAdapterCore

final class Base58Tests: XCTestCase {
    // Vectors cross-checked against `bs58` (npm) and `solana_sdk::bs58`.
    func testKnownVectors() {
        let cases: [(String, [UInt8])] = [
            ("", []),
            ("1", [0x00]),
            ("11", [0x00, 0x00]),
            ("5Q", [0xff]),
            ("15Q", [0x00, 0xff]),
            ("StV1DL6CwTryKyV", [0x68, 0x65, 0x6c, 0x6c, 0x6f, 0x20, 0x77, 0x6f, 0x72, 0x6c, 0x64]),
        ]
        for (encoded, bytes) in cases {
            let data = Data(bytes)
            XCTAssertEqual(Base58.encode(data), encoded, "encode mismatch for \(bytes)")
            XCTAssertEqual(Base58.decode(encoded), data, "decode mismatch for \(encoded)")
        }
    }

    func testRoundTripRandom() {
        var bytes = [UInt8](repeating: 0, count: 64)
        for i in 0..<bytes.count { bytes[i] = UInt8(truncatingIfNeeded: i &* 7) }
        let data = Data(bytes)
        let encoded = Base58.encode(data)
        XCTAssertEqual(Base58.decode(encoded), data)
    }

    func testInvalidStringReturnsNil() {
        XCTAssertNil(Base58.decode("0OIl")) // contains forbidden chars
    }
}
