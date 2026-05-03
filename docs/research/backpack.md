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

- Index references "base58-encoded encryption public key to build a shared secret" + "nonce encoded in base58 used to encrypt the response."
- Encryption sub-page is referenced (`/deeplinks/encryption.md`) but not yet fetched.
- TODO: confirm cipher (presumed XSalsa20-Poly1305).

## References

- Connect: <https://docs.backpack.app/deeplinks/provider-methods/connect>
- SignAndSendTransaction: <https://docs.backpack.app/deeplinks/provider-methods/signandsendtransaction>
- Backpack Exchange mirror: <https://support.backpack.exchange/wallet/technical-docs/deeplinks/provider-methods/signandsendtransaction>
