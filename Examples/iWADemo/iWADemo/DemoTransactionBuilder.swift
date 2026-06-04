import Foundation
import SolanaWalletAdapter

enum DemoTransactionBuilder {
    static let memoProgramId = "MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr"
    static let memoText = "Hello from iWADemo"

    /// Builds an unsigned legacy Solana transaction that invokes the SPL Memo v2
    /// program with `memoText`. Fetches a recent blockhash from `rpcURL` so the
    /// wallet can sign and (optionally) broadcast it.
    ///
    /// `rpcSource`/`action` are logged only (e.g. "SOLANA_RPC_URL",
    /// "signTransaction") so the [iWA] trace shows which RPC endpoint is hit.
    static func buildMemoTransaction(
        sender: String,
        rpcURL: URL,
        rpcSource: String = "unknown",
        action: String = "buildMemoTransaction",
        logger: any WalletAdapterLogger = WalletAdapterLoggers.disabled,
        logLevel: WalletAdapterLogLevel = .off,
        payloadPolicy: WalletAdapterLogPayloadPolicy = .redacted
    ) async throws -> Data {
        log(logger, logLevel, "buildMemoTransaction", "STEP_1A_RPC_ENDPOINT", .info,
            "resolving RPC endpoint for transaction build", [
                "rpc_url": WalletAdapterDebugFormatter.urlShape(rpcURL),
                "rpc_source": rpcSource,
                "action": action,
            ])
        let blockhash = try await fetchLatestBlockhash(
            rpcURL: rpcURL,
            logger: logger,
            logLevel: logLevel,
            payloadPolicy: payloadPolicy
        )

        guard let senderBytes = DemoBase58.decode(sender), senderBytes.count == 32 else {
            throw WalletAdapterError.malformedPayload("Sender public key is not a valid 32-byte base58 string.")
        }
        guard let memoBytes = DemoBase58.decode(memoProgramId), memoBytes.count == 32 else {
            throw WalletAdapterError.malformedPayload("Memo program ID failed to decode.")
        }
        guard let blockhashBytes = DemoBase58.decode(blockhash), blockhashBytes.count == 32 else {
            throw WalletAdapterError.malformedPayload("Recent blockhash from RPC was not a valid 32-byte base58 string.")
        }

        var transaction = Data()

        // Signatures: compact-u16 count + 64 zero bytes per signature.
        transaction.append(contentsOf: encodeCompactU16(1))
        transaction.append(Data(repeating: 0, count: 64))

        // Message header: 1 required signature, 0 readonly signed, 1 readonly unsigned.
        transaction.append(contentsOf: [1, 0, 1])

        // Account keys: sender (writable signer) + memo program (readonly).
        transaction.append(contentsOf: encodeCompactU16(2))
        transaction.append(senderBytes)
        transaction.append(memoBytes)

        // Recent blockhash.
        transaction.append(blockhashBytes)

        // One instruction: program_id_index = 1, no account indices, memo bytes as data.
        transaction.append(contentsOf: encodeCompactU16(1))
        transaction.append(1)
        transaction.append(contentsOf: encodeCompactU16(0))
        let memoData = Data(memoText.utf8)
        transaction.append(contentsOf: encodeCompactU16(UInt16(memoData.count)))
        transaction.append(memoData)

        return transaction
    }

    private static func fetchLatestBlockhash(
        rpcURL: URL,
        logger: any WalletAdapterLogger,
        logLevel: WalletAdapterLogLevel,
        payloadPolicy: WalletAdapterLogPayloadPolicy
    ) async throws -> String {
        var request = URLRequest(url: rpcURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "getLatestBlockhash",
            "params": [["commitment": "finalized"]],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        log(logger, logLevel, "fetchLatestBlockhash", "STEP_1_RPC_REQUEST", .info,
            "sending RPC request", [
                "rpc_url": WalletAdapterDebugFormatter.urlShape(rpcURL),
                "rpc_method": "getLatestBlockhash",
                "commitment": "finalized",
                "http_method": "POST",
                "request_bytes": "\(request.httpBody?.count ?? 0)",
            ])

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            let failure = WalletAdapterError.other(code: "blockhash_fetch_failed", message: "Network error fetching blockhash: \(error.localizedDescription)")
            logFailure(logger, logLevel, "fetchLatestBlockhash", "STEP_FAIL_NETWORK", failure, [
                "rpc_url": WalletAdapterDebugFormatter.urlShape(rpcURL),
            ])
            throw failure
        }

        let httpStatus = (response as? HTTPURLResponse)?.statusCode
        log(logger, logLevel, "fetchLatestBlockhash", "STEP_2_RPC_RESPONSE", .debug,
            "received RPC response", [
                "http_status": httpStatus.map(String.init) ?? "nil",
                "response_bytes": "\(data.count)",
            ])

        if let httpStatus, !(200..<300).contains(httpStatus) {
            let failure = WalletAdapterError.other(code: "blockhash_fetch_failed", message: "RPC returned HTTP \(httpStatus).")
            logFailure(logger, logLevel, "fetchLatestBlockhash", "STEP_FAIL_HTTP", failure, [
                "http_status": "\(httpStatus)",
                "rpc_url": WalletAdapterDebugFormatter.urlShape(rpcURL),
            ])
            throw failure
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            let failure = WalletAdapterError.other(code: "blockhash_fetch_failed", message: "RPC response was not valid JSON.")
            logFailure(logger, logLevel, "fetchLatestBlockhash", "STEP_FAIL_DECODE", failure, [
                "reason": "not_json",
                "response_bytes": "\(data.count)",
            ])
            throw failure
        }
        if let rpcError = json["error"] as? [String: Any], let message = rpcError["message"] as? String {
            let failure = WalletAdapterError.other(code: "blockhash_fetch_failed", message: "RPC error: \(message)")
            logFailure(logger, logLevel, "fetchLatestBlockhash", "STEP_FAIL_RPC_ERROR", failure, [
                "rpc_error_message": message,
            ])
            throw failure
        }
        guard
            let result = json["result"] as? [String: Any],
            let value = result["value"] as? [String: Any],
            let blockhash = value["blockhash"] as? String
        else {
            let failure = WalletAdapterError.other(code: "blockhash_fetch_failed", message: "RPC response missing result.value.blockhash.")
            logFailure(logger, logLevel, "fetchLatestBlockhash", "STEP_FAIL_DECODE", failure, [
                "reason": "missing_result_value_blockhash",
                "response_bytes": "\(data.count)",
            ])
            throw failure
        }

        log(logger, logLevel, "fetchLatestBlockhash", "STEP_3_RESULT_DECODED", .info,
            "decoded recent blockhash", [
                "blockhash": WalletAdapterDebugFormatter.shortBase58(blockhash),
            ].merging(payloadPolicy.includesRawPayloads ? ["blockhash_raw": blockhash] : [:]) { _, new in new })
        return blockhash
    }

    private static func log(
        _ logger: any WalletAdapterLogger,
        _ logLevel: WalletAdapterLogLevel,
        _ method: String,
        _ step: String,
        _ level: WalletAdapterLogLevel,
        _ message: String,
        _ metadata: [String: String]
    ) {
        guard logLevel != .off, level <= logLevel else { return }
        logger.log(WalletAdapterLogEvent(
            component: "DemoTransactionBuilder",
            method: method,
            step: step,
            phase: level == .error ? "FAIL" : "INFO",
            message: message,
            metadata: metadata
        ))
    }

    private static func logFailure(
        _ logger: any WalletAdapterLogger,
        _ logLevel: WalletAdapterLogLevel,
        _ method: String,
        _ step: String,
        _ error: Error,
        _ metadata: [String: String]
    ) {
        log(logger, logLevel, method, step, .error, "RPC step failed",
            WalletAdapterLogDiagnostics.failureMetadata(for: error, metadata: metadata))
    }

    /// Solana shortvec / compact-u16 encoding: 7 bits per byte, MSB is continuation.
    static func encodeCompactU16(_ value: UInt16) -> [UInt8] {
        var remaining = UInt32(value)
        var out: [UInt8] = []
        while true {
            let chunk = UInt8(remaining & 0x7F)
            remaining >>= 7
            if remaining == 0 {
                out.append(chunk)
                return out
            }
            out.append(chunk | 0x80)
        }
    }
}

/// Vendored Base58 decoder — Core's `Base58` lives in `SolanaWalletAdapterCore`
/// which isn't exposed as a public library product. Kept tiny so the demo
/// doesn't grow a dependency.
enum DemoBase58 {
    private static let alphabet: [UInt8] = Array(
        "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz".utf8
    )

    static func decode(_ string: String) -> Data? {
        guard !string.isEmpty else { return Data() }

        var leadingOnes = 0
        for ch in string {
            if ch == "1" { leadingOnes += 1 } else { break }
        }

        var bytes: [UInt8] = []
        for ch in string {
            guard let asciiValue = ch.asciiValue,
                  let digit = alphabet.firstIndex(of: asciiValue) else {
                return nil
            }
            var carry = digit
            for i in (0..<bytes.count).reversed() {
                let value = Int(bytes[i]) * 58 + carry
                bytes[i] = UInt8(value & 0xff)
                carry = value >> 8
            }
            while carry > 0 {
                bytes.insert(UInt8(carry & 0xff), at: 0)
                carry >>= 8
            }
        }

        var result = [UInt8](repeating: 0, count: leadingOnes)
        result.append(contentsOf: bytes)
        return Data(result)
    }
}
