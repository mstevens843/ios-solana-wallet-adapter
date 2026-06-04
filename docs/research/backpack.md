# Backpack - research notes (2026-05-03)

Source: <https://docs.backpack.app/deeplinks/provider-methods/connect>

## Transport

- Universal link: `https://backpack.app/ul/v1/<method>`

## `connect` - required params

- `app_url` - URL providing app metadata (title, icon). Must be URL-encoded.
- `dapp_encryption_public_key` - public key for end-to-end encryption.
- `redirect_link` - URI where Backpack should redirect on completion.

## `connect` - optional params

- `cluster` - defaults to `mainnet-beta` if unset.

## Response shape (from Backpack docs)

- Approval (success):
  - `wallet_xxx` - wallet's encryption public key (base58)
  - `nonce` - base58, used for decryption
  - `data` - base58 of the encrypted payload
- Decrypted payload contains:
  - `public_key`
  - `session`
- Rejection / error:
  - `errorCode`
  - `errorMessage`

## Crypto

- Backpack's encryption page documents `dapp_encryption_public_key`, a fresh x25519 keypair for each connect session, and a wallet-returned `wallet_encryption_public_key`.
- The same page points implementers to TweetNaCl resources for encryption/decryption.
- The Swift implementation uses CryptoKit X25519 key agreement and a TweetNaCl-compatible NaCl box layer.

## References

- Connect: <https://docs.backpack.app/deeplinks/provider-methods/connect>
- Encryption: <https://docs.backpack.app/deeplinks/encryption>
- SignAndSendTransaction: <https://docs.backpack.app/deeplinks/provider-methods/signandsendtransaction>
- Backpack Exchange mirror: <https://support.backpack.exchange/wallet/technical-docs/deeplinks/provider-methods/signandsendtransaction>
