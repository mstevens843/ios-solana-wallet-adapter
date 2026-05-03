import XCTest
import SolanaWalletAdapter
import SolanaWalletAdapterCore
import SolanaWalletAdapterPhantom
import SolanaWalletAdapterSolflare
import SolanaWalletAdapterBackpack

final class DeeplinkURLTests: XCTestCase {
    private func makeRequest(cluster: Cluster = .devnet) -> ConnectRequest {
        ConnectRequest(
            dappEncryptionPublicKey: "DappKeyB58xxxxxxxxxxxxxxxxxxxxxxxxxxx",
            redirectLink: URL(string: "myapp://wallet/callback")!,
            appURL: URL(string: "https://example.com")!,
            cluster: cluster
        )
    }

    func testPhantomConnectURLShape() throws {
        let url = try PhantomAdapter().connectURL(request: makeRequest())
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "phantom.app")
        XCTAssertEqual(components.path, "/ul/v1/connect")
        let params = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(params["app_url"], "https://example.com")
        XCTAssertEqual(params["dapp_encryption_public_key"], "DappKeyB58xxxxxxxxxxxxxxxxxxxxxxxxxxx")
        XCTAssertEqual(params["redirect_link"], "myapp://wallet/callback")
        XCTAssertEqual(params["cluster"], "devnet")
    }

    func testSolflareConnectURLShape() throws {
        let url = try SolflareAdapter().connectURL(request: makeRequest(cluster: .mainnetBeta))
        XCTAssertTrue(url.absoluteString.hasPrefix("https://solflare.com/ul/v1/connect?"))
        XCTAssertTrue(url.absoluteString.contains("cluster=mainnet-beta"))
    }

    func testBackpackConnectURLShape() throws {
        let url = try BackpackAdapter().connectURL(request: makeRequest(cluster: .testnet))
        XCTAssertTrue(url.absoluteString.hasPrefix("https://backpack.app/ul/v1/connect?"))
        XCTAssertTrue(url.absoluteString.contains("cluster=testnet"))
    }

    func testProvidersExposeStableIdentity() {
        XCTAssertEqual(PhantomAdapter().walletId, "phantom")
        XCTAssertEqual(SolflareAdapter().walletId, "solflare")
        XCTAssertEqual(BackpackAdapter().walletId, "backpack")
    }
}
