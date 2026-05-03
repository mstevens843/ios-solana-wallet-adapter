import Foundation
import SolanaWalletAdapterCore

/// High-level URL/callback coordinator for one selected wallet.
///
/// The adapter is intentionally transport-agnostic: it builds URLs for the app
/// to open and decodes callback URLs delivered through `.onOpenURL` or an app
/// delegate. It does not call UIKit, open URLs, or hold async continuations.
public final class WalletAdapter {
    public let provider: WalletProvider
    public let keypair: EphemeralKeypair
    public private(set) var session: Session?
    public private(set) var cluster: Cluster

    public init(
        provider: WalletProvider,
        keypair: EphemeralKeypair = .generate(),
        cluster: Cluster = .mainnetBeta
    ) {
        self.provider = provider
        self.keypair = keypair
        self.cluster = cluster
    }

    public func connectURL(
        appURL: URL,
        redirectLink: URL,
        cluster: Cluster? = nil
    ) throws -> URL {
        let targetCluster = cluster ?? self.cluster
        self.cluster = targetCluster
        return try provider.connectURL(
            request: ConnectRequest(
                dappEncryptionPublicKey: Base58.encode(keypair.publicKey),
                redirectLink: redirectLink,
                appURL: appURL,
                cluster: targetCluster
            )
        )
    }

    @discardableResult
    public func handleConnectCallback(_ url: URL) throws -> Session {
        let decoded = try WalletResponseDecoder.connectSession(
            from: url,
            keypair: keypair,
            expectedCluster: cluster
        )
        session = decoded
        return decoded
    }

    public func disconnectURL(redirectLink: URL) throws -> URL {
        try provider.disconnectURL(
            session: requireSession(),
            keypair: keypair,
            redirectLink: redirectLink
        )
    }

    public func signMessageURL(
        _ message: Data,
        redirectLink: URL,
        display: WalletSigningDisplay = .utf8
    ) throws -> URL {
        try provider.signMessageURL(
            message: message,
            session: requireSession(),
            keypair: keypair,
            redirectLink: redirectLink,
            display: display
        )
    }

    public func signTransactionURL(_ transaction: Data, redirectLink: URL) throws -> URL {
        try provider.signTransactionURL(
            transaction: transaction,
            session: requireSession(),
            keypair: keypair,
            redirectLink: redirectLink
        )
    }

    public func signAllTransactionsURL(_ transactions: [Data], redirectLink: URL) throws -> URL {
        try provider.signAllTransactionsURL(
            transactions: transactions,
            session: requireSession(),
            keypair: keypair,
            redirectLink: redirectLink
        )
    }

    public func signAndSendTransactionURL(
        _ transaction: Data,
        redirectLink: URL,
        sendOptions: SendOptions = .init()
    ) throws -> URL {
        try provider.signAndSendTransactionURL(
            transaction: transaction,
            session: requireSession(),
            keypair: keypair,
            redirectLink: redirectLink,
            sendOptions: sendOptions
        )
    }

    public func handleSignMessageCallback(_ url: URL) throws -> SignMessageResult {
        try WalletResponseDecoder.signMessageResult(
            from: url,
            session: requireSession(),
            keypair: keypair,
            expectedCluster: cluster
        )
    }

    public func handleSignTransactionCallback(_ url: URL) throws -> SignTransactionResult {
        try WalletResponseDecoder.signTransactionResult(
            from: url,
            session: requireSession(),
            keypair: keypair,
            expectedCluster: cluster
        )
    }

    public func handleSignAllTransactionsCallback(_ url: URL) throws -> SignAllTransactionsResult {
        try WalletResponseDecoder.signAllTransactionsResult(
            from: url,
            session: requireSession(),
            keypair: keypair,
            expectedCluster: cluster
        )
    }

    public func handleSignAndSendTransactionCallback(_ url: URL) throws -> SignAndSendTransactionResult {
        try WalletResponseDecoder.signAndSendTransactionResult(
            from: url,
            session: requireSession(),
            keypair: keypair,
            expectedCluster: cluster
        )
    }

    public func clearSession() {
        session = nil
    }

    private func requireSession() throws -> Session {
        guard let session else {
            throw WalletAdapterError.invalidSession
        }
        return session
    }
}
