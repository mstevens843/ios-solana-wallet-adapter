import Foundation
import SolanaWalletAdapter
import Security

/// Persists the id of the wallet the user most recently connected, independent
/// of the per-wallet adapter blob, so a host app can restore the *correct*
/// wallet's session on launch (extended auth cache) — not just a hardcoded
/// default. Distinct from `preferredProviderId` (the "Always" picker choice),
/// which is only set when the user opts in; this records every successful
/// connect regardless.
///
/// It is deliberately readable standalone, before any per-wallet
/// `WalletAdapterClient` exists, so launch code can pick the wallet first.
public protocol LastActiveWalletStoring: Sendable {
    func loadLastActiveWalletId() throws -> String?
    func saveLastActiveWalletId(_ walletId: String?) throws
}

/// Keychain-backed `LastActiveWalletStoring`. Stores a plain UTF-8 wallet id
/// under the same `service` as `KeychainWalletAdapterStateStore` but a distinct
/// `account`, so it never collides with a per-wallet blob and needs no schema
/// versioning.
public struct KeychainLastActiveWalletStore: LastActiveWalletStoring {
    public let service: String
    public let account: String

    public init(
        service: String = "ios-solana-wallet-adapter",
        account: String = "last-active-wallet-id"
    ) {
        self.service = service
        self.account = account
    }

    public func loadLastActiveWalletId() throws -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw WalletAdapterError.malformedPayload("Unable to load last-active wallet id from Keychain.")
        }
        return String(data: data, encoding: .utf8)
    }

    public func saveLastActiveWalletId(_ walletId: String?) throws {
        guard let walletId, let data = walletId.data(using: .utf8) else {
            let status = SecItemDelete(baseQuery() as CFDictionary)
            if status != errSecSuccess && status != errSecItemNotFound {
                throw WalletAdapterError.malformedPayload("Unable to delete last-active wallet id from Keychain.")
            }
            return
        }
        var addQuery = baseQuery()
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let update: [String: Any] = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(baseQuery() as CFDictionary, update as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw WalletAdapterError.malformedPayload("Unable to update last-active wallet id in Keychain.")
            }
        } else if status != errSecSuccess {
            throw WalletAdapterError.malformedPayload("Unable to save last-active wallet id in Keychain.")
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
