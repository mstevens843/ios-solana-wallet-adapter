import Foundation
import SolanaWalletAdapterCore

/// A connected dApp session held by the wallet side.
///
/// Keyed by the dApp's ephemeral encryption public key, which is present
/// (unencrypted) on every jWA request — so the wallet can pick the right
/// `walletKeypair` to decrypt a request *before* reading the encrypted session
/// token inside it.
public struct JWAStoredSession: Sendable, Equatable {
    /// The dApp's ephemeral X25519 public key (32 bytes) — the session key.
    public let dappEncryptionPublicKey: Data
    /// The wallet's per-session X25519 encryption keypair.
    public let walletKeypair: EphemeralKeypair
    /// Opaque session token echoed by the dApp in every signing payload.
    public let token: String
    /// The Solana account the wallet authorized for this dApp.
    public let userPublicKey: String

    public init(
        dappEncryptionPublicKey: Data,
        walletKeypair: EphemeralKeypair,
        token: String,
        userPublicKey: String
    ) {
        self.dappEncryptionPublicKey = dappEncryptionPublicKey
        self.walletKeypair = walletKeypair
        self.token = token
        self.userPublicKey = userPublicKey
    }
}

public protocol JWASessionStore: Sendable {
    func store(_ session: JWAStoredSession)
    func session(forDappKey dappKey: Data) -> JWAStoredSession?
    func session(forToken token: String) -> JWAStoredSession?
    func removeSession(token: String)
}

/// Default in-memory store. Wallets that need persistence across launches can
/// provide their own (e.g. Keychain-backed) conformance.
public final class InMemoryJWASessionStore: JWASessionStore, @unchecked Sendable {
    private let lock = NSLock()
    private var byDappKey: [Data: JWAStoredSession] = [:]
    private var order: [Data] = []   // dApp keys, oldest first, for eviction
    private let maxSessions: Int

    /// - Parameter maxSessions: cap on concurrent sessions. Past the cap the
    ///   oldest session is evicted, so repeated reconnects (each with a fresh dApp
    ///   ephemeral key) can't grow memory unbounded.
    public init(maxSessions: Int = 64) {
        self.maxSessions = max(1, maxSessions)
    }

    public func store(_ session: JWAStoredSession) {
        lock.lock(); defer { lock.unlock() }
        let key = session.dappEncryptionPublicKey
        if byDappKey[key] == nil {
            order.append(key)
        }
        byDappKey[key] = session
        while order.count > maxSessions {
            let oldest = order.removeFirst()
            byDappKey[oldest] = nil
        }
    }

    public func session(forDappKey dappKey: Data) -> JWAStoredSession? {
        lock.lock(); defer { lock.unlock() }
        return byDappKey[dappKey]
    }

    public func session(forToken token: String) -> JWAStoredSession? {
        lock.lock(); defer { lock.unlock() }
        return byDappKey.values.first { $0.token == token }
    }

    public func removeSession(token: String) {
        lock.lock(); defer { lock.unlock() }
        if let key = byDappKey.first(where: { $0.value.token == token })?.key {
            byDappKey[key] = nil
            order.removeAll { $0 == key }
        }
    }
}
