# iOS Wallet Adapter Protocol - iWA v0.1 (draft)

> **Status:** draft, implemented by the Swift package through the pure URL/callback layer. Subject to breaking changes until v1.0.

## Goal

Define a single iOS-native protocol for dApps to request Solana wallet operations (connect, sign message, sign transaction, sign and send) from a user-controlled wallet app over universal links and custom URL schemes, with explicit user approval.

The dApp never sees the user's private key. Each operation surfaces an approval screen inside the wallet app and bounces the user back to the dApp via a redirect URL.

This is **not** the Mobile Wallet Adapter (MWA). MWA is Android-only by design (Android Intents + localhost WebSocket). iWA is a different protocol class - universal-link / custom-scheme based, request/response, no persistent session at the OS level.

## Non-goals

- Persistent connections. iOS suspends backgrounded apps and disables ongoing network communication. The wallet cannot stream events back to the dApp; every operation is a discrete URL bounce.
- Replacing wallet-as-a-service / embedded-wallet flows (Web3Auth, Privy, Magic). Those serve a different custody model.
- Replacing Safari Web Extensions. Wallets that ship Safari extensions can support both surfaces; iWA targets native dApps that don't run inside Safari.
- Cross-platform scope. Android dApps target MWA; web dApps target Wallet Standard. iWA is iOS-only.

## Transport

Wallets that support iWA expose endpoints of the form:

- Universal link (recommended): `https://<wallet-host>/ul/<version>/<method>`
- Custom URL scheme (fallback): `<wallet-scheme>://<version>/<method>`

`<version>` is `v1` for this draft.

The dApp constructs the URL with required query parameters, calls `UIApplication.open` (or `openURL:` from a SwiftUI view), and the OS routes the user into the wallet app. The wallet renders an approval screen, the user accepts or declines, and the wallet calls `redirect_link` (URL-encoded query parameter on every request) with the response payload.

iOS provides **no app-chooser** when multiple wallets register the same scheme; the OS opens the first installed wallet that handles it. iWA-conformant dApps therefore SHOULD select a specific wallet (via the per-wallet adapter) rather than dispatching through a shared scheme.

## Wallet host registry (v0.1)

| Wallet | Universal-link host | Custom scheme | Status |
|--------|--------------------|---------------|--------|
| Phantom | `phantom.app` | `phantom` | implemented |
| Solflare | `solflare.com` | `solflare` | implemented |
| Backpack | `backpack.app` | `backpack` | implemented |
| Glow | TBD | TBD | candidate, pending verification (see `docs/research/glow.md`) |

Adding a wallet requires (1) a published deeplink spec from the wallet team that conforms to the request/response shape below, and (2) a reference adapter in `Sources/SolanaWalletAdapter<Wallet>/`.

## Cryptography

- **Key agreement:** X25519 (Curve25519). The dApp generates an ephemeral X25519 keypair per session. The wallet returns its own X25519 public key in the connect response. Both sides derive the shared secret.
- **Encryption:** XSalsa20-Poly1305, as packaged by NaCl `box`. Same primitive used by `tweetnacl` (the JS reference) and `Tokr-Labs/phantom-connect` (the existing Swift Phantom-only implementation).
- **Wire encoding:** Base58 (Bitcoin alphabet) for public keys, nonces, and ciphertexts.

The Swift package implements this layer with CryptoKit X25519 key agreement and a vendored TweetNaCl-compatible XSalsa20-Poly1305 implementation. The test suite includes deterministic vectors and authentication-failure cases.

## Swift Package API

The high-level app API is `WalletAdapter`. It owns the selected provider, the dApp ephemeral keypair, the active session, and the selected cluster. It builds request URLs and decodes callback URLs, but it does not open URLs or hold app lifecycle continuations.

```swift
let adapter = WalletAdapter(provider: PhantomAdapter(), cluster: .devnet)
let url = try adapter.connectURL(appURL: appURL, redirectLink: redirect, cluster: .devnet)
let session = try adapter.handleConnectCallback(callbackURL)
```

After connect, the same adapter builds encrypted signing URLs and decodes the encrypted callback payloads for `signMessage`, `signTransaction`, `signAllTransactions`, `signAndSendTransaction`, and `disconnect`.

## Methods

### `connect`

**Request URL:** `https://<host>/ul/v1/connect`

**Required query params:**

- `app_url` - URL the wallet uses to fetch metadata (title, icon). Must be URL-encoded.
- `dapp_encryption_public_key` - base58 of the dApp's ephemeral X25519 public key.
- `redirect_link` - URL the wallet will open with the response. Must be URL-encoded.

**Optional:**

- `cluster` - one of `mainnet-beta`, `devnet`, `testnet`. Default: `mainnet-beta`.

**Success response (delivered as query params on `redirect_link`):**

- `<wallet>_encryption_public_key` (or wallet-specific name like Backpack's `wallet_xxx`) - wallet's X25519 public key, base58.
- `nonce` - base58, 24 bytes for XSalsa20.
- `data` - base58 of the NaCl-box ciphertext over a JSON object `{ "public_key": "<user-base58>", "session": "<token>" }`.

**Error response:** `errorCode` and `errorMessage` query params.

### `disconnect`

Best-effort. Tells the wallet to forget the session. No response payload is required from the wallet (the redirect happens immediately). Still requires `dapp_encryption_public_key`, `nonce`, `payload`, and `redirect_link` because the request is encrypted to prove session ownership.

### `signMessage`

Encrypted JSON payload (after NaCl-open):

```json
{
  "message": "<base58 of the message bytes>",
  "session": "<token from connect>",
  "display": "utf8" | "hex"
}
```

Encrypted JSON response:

```json
{ "signature": "<base58 of the 64-byte ed25519 signature>" }
```

### `signTransaction`

Request payload:

```json
{
  "transaction": "<base58 of the wire-format transaction>",
  "session": "<token>"
}
```

Response payload:

```json
{ "transaction": "<base58 of the signed wire-format transaction>" }
```

### `signAllTransactions`

Request:

```json
{
  "transactions": ["<b58>", "<b58>", ...],
  "session": "<token>"
}
```

Response:

```json
{ "transactions": ["<b58>", "<b58>", ...] }
```

### `signAndSendTransaction`

Request:

```json
{
  "transaction": "<b58 of the wire-format tx>",
  "session": "<token>",
  "sendOptions": {
    "skipPreflight": false,
    "preflightCommitment": "confirmed",
    "maxRetries": 3
  }
}
```

Response:

```json
{ "signature": "<base58 of the txid>" }
```

## Session lifecycle

A `connect` exchange establishes a `session` token plus the wallet's encryption public key. All subsequent calls echo `session` inside the encrypted payload. The wallet MAY invalidate the session at any time; clients receiving `errorCode = INVALID_SESSION` MUST re-`connect` and obtain a new token.

Sessions are not persisted across wallet app restarts unless the wallet chooses to store them.

## Error codes

| Code | Meaning |
|------|---------|
| `USER_REJECTED` | The user dismissed the approval screen. |
| `INVALID_SESSION` | The session token is unknown to the wallet. |
| `UNSUPPORTED_METHOD` | The wallet does not implement this method (e.g. an older wallet seeing `signAllTransactions`). |
| `MALFORMED_PAYLOAD` | The encrypted payload could not be decrypted or parsed. |
| `WALLET_UNREACHABLE` | The OS could not open any handler for the URL. |
| `DECRYPTION_FAILED` | The dApp could not decrypt the wallet's response. |
| `CLUSTER_MISMATCH` | The session is bound to a different cluster than the one requested. |

Wallet-specific `errorCode` strings MUST map cleanly to one of the above. Adapters surface the mapped enum (`WalletAdapterError`) plus the original wallet code/message via `.other(code:message:)`.

## App-chooser problem (informational)

iOS does not surface a system-level chooser when multiple wallets register the same custom URL scheme; the OS routes the request to whichever wallet was installed first. Universal links partially mitigate this because each wallet's `apple-app-site-association` is host-specific, but a user with multiple wallets installed will still get whichever the OS picks.

iWA-conformant dApps therefore SHOULD:

- Present the user with an explicit wallet picker UI.
- Construct deeplinks against the chosen wallet's specific universal link host.
- Never use a generic `solana-wallet://` scheme.

## Known gaps for v0.2

- Multi-tx approval batching with structured display metadata.
- UIKit / SwiftUI convenience wrappers that call `openURL` and bridge callbacks into async continuations.
- Real-device smoke logs against Phantom, Solflare, and Backpack.
- Hardware wallet hand-off (Ledger over BLE).
- SIWS (Sign-In With Solana) as a first-class method instead of overloading `signMessage`.
- Deferred-response delivery for cases where the dApp is killed mid-flow.
- Standardized wallet-discovery resource (so dApps know which wallets are installed without probing each scheme, which iOS limits via `LSApplicationQueriesSchemes`).

## References

- Phantom deeplink docs: <https://docs.phantom.com/phantom-deeplinks/deeplinks-ios-and-android>
- Solflare deeplink docs: <https://docs.solflare.com/solflare/technical/deeplinks>
- Backpack deeplink docs: <https://docs.backpack.app/deeplinks/provider-methods/connect>
- Solana Mobile blog (iOS wallet signing): <https://docs.solanamobile.com/blog/ios-wallet-signing>
- Tokr-Labs/phantom-connect (Swift Phantom-only reference): <https://github.com/Tokr-Labs/phantom-connect>
- Solflare deep-link sample (React Native): <https://github.com/solflare-wallet/deep-link-sample-app>
