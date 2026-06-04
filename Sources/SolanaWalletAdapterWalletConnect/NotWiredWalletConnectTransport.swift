import Foundation
import SolanaWalletAdapter

/// Placeholder `WalletConnectSolanaTransport` used until a real Reown/WalletConnect
/// Sign transport (relay + pairing + session) is integrated.
///
/// Every operation throws `WalletAdapterError.other(code:
/// "WALLETCONNECT_TRANSPORT_NOT_WIRED", ...)` with a message that carries the
/// project-id presence and the requested chains/methods. Because
/// `WalletConnectSolanaClient` already logs `STEP_1_START` then `STEP_FAIL`
/// (mapping `.other` to `wallet_error_code`/`wallet_error_message` via
/// `WalletAdapterLogDiagnostics`), selecting Jupiter produces a fixed, greppable
/// trace that explains exactly why connect/sign/send cannot complete yet —
/// without leaking the project id.
///
/// Swapping in a real transport is a drop-in: implement `WalletConnectSolanaTransport`
/// over the Reown Swift SDK and pass it to `WalletConnectSolanaClient` instead of this.
public struct NotWiredWalletConnectTransport: WalletConnectSolanaTransport {
    public static let errorCode = "WALLETCONNECT_TRANSPORT_NOT_WIRED"

    public init() {}

    public func connect(
        configuration: ReownProjectConfiguration,
        namespace: WalletConnectSolanaNamespace
    ) async throws -> WalletConnectSolanaSession {
        throw WalletAdapterError.other(
            code: Self.errorCode,
            message: "No Reown/WalletConnect transport is wired. "
                + "project_id_present=\(!configuration.projectId.isEmpty) "
                + "chains=\(namespace.chains.joined(separator: ",")) "
                + "methods=\(namespace.methods.joined(separator: ","))"
        )
    }

    public func request<Params, Result>(
        _ request: WalletConnectSolanaJSONRPCRequest<Params>,
        chain: String,
        session: WalletConnectSolanaSession,
        responseType: Result.Type
    ) async throws -> Result
    where Params: Sendable & Equatable & Encodable, Result: Sendable & Decodable {
        throw WalletAdapterError.other(
            code: Self.errorCode,
            message: "request unavailable: no Reown transport wired "
                + "(method=\(request.method.rawValue) chain=\(chain))."
        )
    }

    public func disconnect(session: WalletConnectSolanaSession) async throws {
        // Nothing to tear down: no real session is ever established.
    }
}
