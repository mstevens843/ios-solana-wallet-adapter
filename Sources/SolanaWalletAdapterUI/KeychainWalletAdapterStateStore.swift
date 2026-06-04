import Foundation
import SolanaWalletAdapter
import Security

public struct KeychainWalletAdapterStateStore: WalletAdapterStateStore {
    public let service: String
    public let account: String
    private let logger: any WalletAdapterLogger
    private let logLevel: WalletAdapterLogLevel
    private let payloadPolicy: WalletAdapterLogPayloadPolicy

    public init(
        service: String = "ios-solana-wallet-adapter",
        account: String = "default-wallet-adapter-state",
        logger: any WalletAdapterLogger = WalletAdapterLoggers.disabled,
        logLevel: WalletAdapterLogLevel = .off,
        payloadPolicy: WalletAdapterLogPayloadPolicy = .redacted
    ) {
        self.service = service
        self.account = account
        self.logger = logger
        self.logLevel = logLevel
        self.payloadPolicy = payloadPolicy
    }

    public func loadState() throws -> WalletAdapterState? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            log("loadState", "STEP_1_NOT_FOUND", .debug, "wallet adapter state not found", ["status": "\(status)"])
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            log("loadState", "STEP_FAIL_KEYCHAIN", .error, "unable to load wallet adapter state from Keychain", [
                "status": "\(status)",
                "result_type": result.map { "\(type(of: $0))" } ?? "nil",
                "failure_hint": "Keychain returned a non-success status while loading adapter state.",
                "fix_hint": "Check app entitlements, simulator keychain state, service/account names, and device lock state.",
            ])
            throw WalletAdapterError.malformedPayload("Unable to load wallet adapter state from Keychain.")
        }
        do {
            let state = try Self.decodePersistedState(from: data)
            log("loadState", "STEP_2_DECODED", .debug, "wallet adapter state decoded", [
                "provider": state.providerId,
                "cluster": state.cluster.rawValue,
                "has_session": "\(state.session != nil)",
                "encoded_bytes": "\(data.count)",
                "schema_version": "\(PersistedEnvelope.currentVersion)",
            ])
            return state
        } catch {
            log("loadState", "STEP_FAIL_DECODE", .error, "wallet adapter state decode failed", [
                "encoded_bytes": "\(data.count)",
                "error": "\(error)",
                "failure_hint": "Persisted adapter state could not be decoded as a v0 raw blob or a versioned envelope.",
                "fix_hint": "Clear this Keychain item or migrate the stored state format.",
            ].merging(payloadPolicy.includesRawPayloads ? ["encoded_state_raw": "redacted_keychain_blob"] : [:]) { _, new in new })
            throw error
        }
    }

    /// Decode a persisted Keychain blob into a `WalletAdapterState`. Tries the
    /// current versioned envelope first; falls back to a raw v0 decode for state
    /// written by older SDK versions. The next `saveState` call automatically
    /// re-writes the blob in the current envelope format.
    static func decodePersistedState(from data: Data) throws -> WalletAdapterState {
        let decoder = JSONDecoder()
        if let envelope = try? decoder.decode(PersistedEnvelope.self, from: data) {
            return envelope.state
        }
        return try decoder.decode(WalletAdapterState.self, from: data)
    }

    public func saveState(_ state: WalletAdapterState?) throws {
        if state == nil {
            let status = SecItemDelete(baseQuery() as CFDictionary)
            if status != errSecSuccess && status != errSecItemNotFound {
                log("saveState", "STEP_FAIL_DELETE", .error, "unable to delete wallet adapter state from Keychain", [
                    "status": "\(status)",
                    "failure_hint": "Keychain refused to delete adapter state.",
                    "fix_hint": "Check app entitlements and whether the service/account pair matches the saved item.",
                ])
                throw WalletAdapterError.malformedPayload("Unable to delete wallet adapter state from Keychain.")
            }
            log("saveState", "STEP_1_DELETED", .debug, "wallet adapter state deleted", ["status": "\(status)"])
            return
        }

        let stateToSave = state!
        let data = try JSONEncoder().encode(PersistedEnvelope(state: stateToSave))
        log("saveState", "STEP_1_ENCODED", .debug, "wallet adapter state encoded", [
            "provider": stateToSave.providerId,
            "cluster": stateToSave.cluster.rawValue,
            "has_session": "\(stateToSave.session != nil)",
            "encoded_bytes": "\(data.count)",
            "schema_version": "\(PersistedEnvelope.currentVersion)",
        ])
        var addQuery = baseQuery()
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let update: [String: Any] = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(baseQuery() as CFDictionary, update as CFDictionary)
            guard updateStatus == errSecSuccess else {
                log("saveState", "STEP_FAIL_UPDATE", .error, "unable to update wallet adapter state in Keychain", [
                    "status": "\(updateStatus)",
                    "failure_hint": "Keychain refused to update an existing adapter state item.",
                    "fix_hint": "Check app entitlements, accessible class, service/account names, and device lock state.",
                ])
                throw WalletAdapterError.malformedPayload("Unable to update wallet adapter state in Keychain.")
            }
            log("saveState", "STEP_2_UPDATED", .debug, "wallet adapter state updated", ["status": "\(updateStatus)"])
        } else if status != errSecSuccess {
            log("saveState", "STEP_FAIL_ADD", .error, "unable to save wallet adapter state in Keychain", [
                "status": "\(status)",
                "failure_hint": "Keychain refused to add a new adapter state item.",
                "fix_hint": "Check app entitlements, accessible class, service/account names, and simulator/device keychain availability.",
            ])
            throw WalletAdapterError.malformedPayload("Unable to save wallet adapter state in Keychain.")
        } else {
            log("saveState", "STEP_2_ADDED", .debug, "wallet adapter state added", ["status": "\(status)"])
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func log(_ method: String, _ step: String, _ level: WalletAdapterLogLevel, _ message: String, _ metadata: [String: String] = [:]) {
        guard logLevel != .off, level <= logLevel else { return }
        logger.log(WalletAdapterLogEvent(component: "KeychainWalletAdapterStateStore", method: method, step: step, phase: level == .error ? "FAIL" : "INFO", message: message, metadata: [
            "service": service,
            "account": account,
        ].merging(metadata) { _, new in new }))
    }
}

/// Versioned wrapper around `WalletAdapterState` in the Keychain blob. v0
/// blobs (pre-envelope) are decoded by falling back to a raw `WalletAdapterState`
/// decode in `decodePersistedState(from:)`. Future schema migrations bump
/// `currentVersion` and add branching in the decode path.
struct PersistedEnvelope: Codable {
    static let currentVersion = 1

    let version: Int
    let state: WalletAdapterState

    init(state: WalletAdapterState, version: Int = PersistedEnvelope.currentVersion) {
        self.version = version
        self.state = state
    }
}
