import XCTest
import SolanaWalletAdapter

final class SignInWithSolanaTests: XCTestCase {
    func testMessageBuildsSIWSV1Shape() throws {
        let input = SignInWithSolanaInput(
            nonce: "bZQJ0SL6gJ",
            domain: "magiceden.io",
            statement: "Click Sign or Approve only means you have proved this wallet is owned by you.",
            uri: URL(string: "https://magiceden.io")!,
            chainId: "solana:mainnet",
            issuedAt: date("2022-10-25T16:52:02.748Z"),
            resources: [
                URL(string: "https://foo.com")!,
                URL(string: "https://bar.com")!,
            ]
        )

        let message = try SignInWithSolanaMessage.make(
            input: input,
            address: "FYpB58cLw5cwiN763ayB2sFT8HLF2MRUBbbyRgHYiRpK"
        )

        XCTAssertEqual(message, """
        magiceden.io wants you to sign in with your Solana account:
        FYpB58cLw5cwiN763ayB2sFT8HLF2MRUBbbyRgHYiRpK

        Click Sign or Approve only means you have proved this wallet is owned by you.

        URI: https://magiceden.io
        Version: 1
        Chain ID: solana:mainnet
        Nonce: bZQJ0SL6gJ
        Issued At: 2022-10-25T16:52:02.748Z
        Resources:
        - https://foo.com
        - https://bar.com
        """)
    }

    func testMessageUsesDefaultsAndShortChainId() throws {
        let input = SignInWithSolanaInput(
            nonce: "bZQJ0SL6gJ",
            chainId: "devnet",
            issuedAt: date("2022-10-25T16:52:02.748Z")
        )

        let message = try SignInWithSolanaMessage.make(
            input: input,
            address: "FYpB58cLw5cwiN763ayB2sFT8HLF2MRUBbbyRgHYiRpK",
            defaultDomain: "example.com",
            defaultURI: URL(string: "https://example.com")!
        )

        XCTAssertEqual(message, """
        example.com wants you to sign in with your Solana account:
        FYpB58cLw5cwiN763ayB2sFT8HLF2MRUBbbyRgHYiRpK

        URI: https://example.com
        Version: 1
        Chain ID: devnet
        Nonce: bZQJ0SL6gJ
        Issued At: 2022-10-25T16:52:02.748Z
        """)
    }

    func testMessageRejectsInvalidNonce() {
        let input = SignInWithSolanaInput(nonce: "short")

        XCTAssertThrowsError(try SignInWithSolanaMessage.make(
            input: input,
            address: "User1111111111111111111111111111111111",
            defaultDomain: "example.com",
            defaultURI: URL(string: "https://example.com")!,
            defaultChainId: "solana:devnet"
        )) { error in
            XCTAssertEqual(
                error as? WalletAdapterError,
                .malformedPayload("SIWS nonce must be at least 8 ASCII alphanumeric characters.")
            )
        }
    }

    func testMessageRejectsUnsupportedChainId() {
        let input = SignInWithSolanaInput(nonce: "bZQJ0SL6gJ", chainId: "solana:eclipse")

        XCTAssertThrowsError(try SignInWithSolanaMessage.validate(input)) { error in
            XCTAssertEqual(
                error as? WalletAdapterError,
                .malformedPayload("SIWS chainId is not supported.")
            )
        }
    }

    func testMessageRejectsStatementNewlines() {
        let input = SignInWithSolanaInput(nonce: "bZQJ0SL6gJ", statement: "line one\nline two")

        XCTAssertThrowsError(try SignInWithSolanaMessage.validate(input)) { error in
            XCTAssertEqual(
                error as? WalletAdapterError,
                .malformedPayload("SIWS statement must not contain newline characters.")
            )
        }
    }

    func testClusterMapsToSIWSChainId() {
        XCTAssertEqual(Cluster.mainnetBeta.signInWithSolanaChainId, "solana:mainnet")
        XCTAssertEqual(Cluster.devnet.signInWithSolanaChainId, "solana:devnet")
        XCTAssertEqual(Cluster.testnet.signInWithSolanaChainId, "solana:testnet")
        XCTAssertTrue(Cluster.devnet.matchesSignInWithSolanaChainId("devnet"))
        XCTAssertTrue(Cluster.devnet.matchesSignInWithSolanaChainId("solana:devnet"))
        XCTAssertFalse(Cluster.devnet.matchesSignInWithSolanaChainId("solana:mainnet"))
    }

    private func date(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)!
    }
}
