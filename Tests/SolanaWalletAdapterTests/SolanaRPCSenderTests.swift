import XCTest
import SolanaWalletAdapter
import SolanaWalletAdapterUI

final class SolanaRPCSenderTests: XCTestCase {
    private let rpcURL = URL(string: "https://rpc.example.com")!

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    private func makeSender() -> SolanaRPCSender {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return SolanaRPCSender(session: URLSession(configuration: config))
    }

    /// A successful `sendTransaction` returns the txid from `result`, and the
    /// request body base64-encodes the signed bytes with `encoding: base64`.
    func testSendTransactionEncodesBodyAndReturnsTxid() async throws {
        StubURLProtocol.responseBody = #"{"jsonrpc":"2.0","id":1,"result":"TxidSignature111"}"#.data(using: .utf8)
        StubURLProtocol.statusCode = 200

        let signed = Data([0x01, 0x02, 0x03, 0x04])
        let txid = try await makeSender().sendTransaction(signed, rpcURL: rpcURL, sendOptions: .init(skipPreflight: true, preflightCommitment: "confirmed"))

        XCTAssertEqual(txid, "TxidSignature111")

        let body = try XCTUnwrap(StubURLProtocol.capturedBody)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["method"] as? String, "sendTransaction")
        let params = try XCTUnwrap(json["params"] as? [Any])
        XCTAssertEqual(params.first as? String, signed.base64EncodedString())
        let options = try XCTUnwrap(params.last as? [String: Any])
        XCTAssertEqual(options["encoding"] as? String, "base64")
        XCTAssertEqual(options["skipPreflight"] as? Bool, true)
        XCTAssertEqual(options["preflightCommitment"] as? String, "confirmed")
    }

    /// An RPC `error` is surfaced verbatim as `.other(code:"rpc_send_failed", message:)`.
    func testRPCErrorIsMappedToWalletAdapterError() async {
        StubURLProtocol.responseBody = #"{"jsonrpc":"2.0","id":1,"error":{"code":-32002,"message":"Transaction simulation failed: Blockhash not found"}}"#.data(using: .utf8)
        StubURLProtocol.statusCode = 200

        do {
            _ = try await makeSender().sendTransaction(Data([0x09]), rpcURL: rpcURL)
            XCTFail("expected an error")
        } catch let error as WalletAdapterError {
            guard case let .other(code, message) = error else {
                return XCTFail("expected .other, got \(error)")
            }
            XCTAssertEqual(code, "rpc_send_failed")
            XCTAssertEqual(message, "Transaction simulation failed: Blockhash not found")
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    func testNon2xxStatusThrows() async {
        StubURLProtocol.responseBody = Data("Bad Gateway".utf8)
        StubURLProtocol.statusCode = 502

        do {
            _ = try await makeSender().sendTransaction(Data([0x09]), rpcURL: rpcURL)
            XCTFail("expected an error")
        } catch let error as WalletAdapterError {
            guard case let .other(code, _) = error else {
                return XCTFail("expected .other, got \(error)")
            }
            XCTAssertEqual(code, "rpc_send_failed")
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

}

/// Minimal URLProtocol stub: captures the outgoing request body and returns a
/// canned response so the RPC sender can be tested without a network.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responseBody: Data?
    nonisolated(unsafe) static var statusCode: Int = 200
    nonisolated(unsafe) static var capturedBody: Data?

    static func reset() {
        responseBody = nil
        statusCode = 200
        capturedBody = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        StubURLProtocol.capturedBody = Self.body(from: request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let body = Self.responseBody {
            client?.urlProtocol(self, didLoad: body)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// URLSession often moves `httpBody` to `httpBodyStream`, so read both.
    private static func body(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
