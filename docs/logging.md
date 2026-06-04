# Deterministic Logging

iWA logging is opt-in and disabled by default. Enable it while testing real wallet flows so every URL build, callback decode, and failure point has a stable log line.

## Enable Print Logs

```swift
let adapter = WalletAdapter(
    provider: PhantomAdapter(),
    cluster: .devnet,
    logger: WalletAdapterLoggers.print(),
    logLevel: .debug
)
```

For app-level clients, read the local environment and pass the resulting level and payload policy:

```swift
let logConfiguration = WalletAdapterLogConfiguration.fromEnvironment()

let client = WalletAdapterClient(
    provider: PhantomAdapter(),
    appURL: appURL,
    redirectLink: redirectLink,
    opener: opener,
    logger: logConfiguration.printLogger,
    logLevel: logConfiguration.logLevel,
    payloadPolicy: logConfiguration.payloadPolicy
)
```

Environment flags:

```sh
SOLANA_WALLET_ADAPTER_LOG_LEVEL=debug
SOLANA_WALLET_ADAPTER_UNSAFE_LOGS=1
SOLANA_WALLET_ADAPTER_LOG_PREFIX='[iWA]'
```

`SOLANA_WALLET_ADAPTER_UNSAFE_LOGS=1` enables exact local payload/result diagnostics. Use `0`, `false`, or `off` to force redacted mode.

Log format:

```text
[iWA] [WalletAdapter] connectURL | STEP_1_START phase=INFO message="building connect URL" cluster=devnet has_session=false wallet=phantom
```

The shape is:

```text
[prefix] [component] method | STEP_NAME phase=PHASE message="..." key=value
```

Async API logs include a stable `flow_id` such as `connect-1` or `signMessage-2`. The same `flow_id` appears on URL opening, callback routing, success results, and failure logs for that API call.

## Levels

- `.off`: no logs.
- `.error`: only failure points.
- `.info`: start, success, and failure points.
- `.debug`: parameters, query keys, envelope sizes, and decode checkpoints.

## Expected Connect Flow

```text
[iWA] [WalletAdapter] connectURL | STEP_1_START ...
[iWA] [WalletAdapter] connectURL | STEP_2_PARAMS ...
[iWA] [WalletAdapter] connectURL | STEP_3_URL_BUILT ...
[iWA] [WalletAdapter] handleConnectCallback | STEP_1_START ...
[iWA] [WalletResponseDecoder] connectSession | STEP_1_START ...
[iWA] [WalletResponseDecoder] connectSession | STEP_2_QUERY_PARSED ...
[iWA] [WalletResponseDecoder] connectSession | STEP_3_WALLET_KEY_OK ...
[iWA] [WalletResponseDecoder] connectSession | STEP_3_ENVELOPE_OK ...
[iWA] [WalletResponseDecoder] connectSession | STEP_4_PAYLOAD_DECRYPTED ...
[iWA] [WalletResponseDecoder] connectSession | STEP_5_RESULT_DECODED ...
[iWA] [WalletAdapter] handleConnectCallback | STEP_3_SESSION_STORED ...
```

## Expected Sign Message Flow

```text
[iWA] [WalletAdapter] signMessageURL | STEP_1_START ...
[iWA] [WalletAdapter] signMessageURL | STEP_2_SESSION_OK ...
[iWA] [WalletAdapter] signMessageURL | STEP_3_PAYLOAD_BUILD ...
[iWA] [WalletAdapter] signMessageURL | STEP_4_URL_BUILT ...
[iWA] [WalletAdapter] handleSignMessageCallback | STEP_1_START ...
[iWA] [WalletAdapter] handleSignMessageCallback | STEP_2_SESSION_OK ...
[iWA] [WalletResponseDecoder] signMessageResult | STEP_1_START ...
[iWA] [WalletResponseDecoder] signMessageResult | STEP_3_ENVELOPE_OK ...
[iWA] [WalletResponseDecoder] signMessageResult | STEP_4_PAYLOAD_DECRYPTED ...
[iWA] [WalletResponseDecoder] signMessageResult | STEP_5_RESULT_DECODED ...
[iWA] [WalletAdapter] handleSignMessageCallback | STEP_3_RESULT_DECODED ...
```

## Failure Examples

Signing before connect:

```text
[iWA] [WalletAdapter] signMessageURL | STEP_1_START ...
[iWA] [WalletAdapter] signMessageURL | STEP_2_SESSION_FAIL phase=FAIL message="no active session" ...
[iWA] [WalletAdapter] signMessageURL | STEP_FAIL phase=FAIL message="operation failed" error=invalidSession
```

Malformed callback with no `data`:

```text
[iWA] [WalletResponseDecoder] signMessageResult | STEP_FAIL phase=FAIL message="response missing data" query_keys=nonce
```

Tampered ciphertext:

```text
[iWA] [WalletResponseDecoder] signMessageResult | STEP_FAIL phase=FAIL message="response decryption failed" ciphertext_bytes=...
```

## Privacy Rules

Default logs intentionally include:

- wallet id
- cluster
- URL shape: scheme, host, path, query key names
- byte counts
- short public key prefixes
- short txid prefixes

Default logs intentionally do not include:

- secret keys
- shared secrets
- decrypted JSON payloads
- full callback URLs
- full ciphertexts
- full messages
- full transactions
- full signatures
- session tokens

During real-device smoke, capture the logs plus screenshots of the wallet approval screen. Do not paste full callback URLs into public issues.

## Unsafe Raw Payload Mode

When a real-device smoke flow is failing and redacted logs are not enough, enable raw payload diagnostics:

```swift
let adapter = WalletAdapter(
    provider: PhantomAdapter(),
    cluster: .devnet,
    logger: WalletAdapterLoggers.print(),
    logLevel: .debug,
    payloadPolicy: .unsafeRawPayloads
)
```

`WalletAdapterClient` accepts the same `payloadPolicy`.

Raw mode can include:

- full request URLs and callback URLs
- full query parameter values
- serialized request JSON before encryption
- Base58 nonce and encrypted payload values
- decrypted wallet response JSON
- session tokens
- messages, transactions, and signatures
- wallet error code and message

Raw mode still never logs:

- dApp secret keys
- shared secrets or derived NaCl keys
- raw Keychain state blobs

Use raw mode only on local devices while debugging. Turn it off before sharing logs publicly.

## API Method Coverage

`WalletAdapterClient` logs every public API method:

- `connect`
- `getCapabilities`
- `signMessage`
- `signTransaction`
- `signAllTransactions`
- `signAndSendTransaction`
- `signInWithSolana`
- `disconnect`
- `authorize`
- `deauthorize`
- `signMessages`
- `signTransactions`
- `signAndSendTransactions`

`WalletConnectSolanaClient` logs:

- `connect`
- `disconnect`
- `getCapabilities`
- `getAccounts`
- `requestAccounts`
- `signMessage`
- `signTransaction`
- `signAllTransactions`
- `signAndSendTransaction`

Failure logs include `error_code`, `failure_hint`, and `fix_hint` so the failing step explains both what failed and what to inspect next.

## Troubleshooting By Step

| Step / error | Likely cause | Next check |
| --- | --- | --- |
| `STEP_FAIL_OPEN_URL` | iOS rejected the wallet URL or the wallet is not installed. | Verify wallet install, universal link/custom scheme, and opener result. |
| `STEP_FAIL_PENDING_REQUEST` | Another request is waiting for a callback. | Wait for `handleOpenURL`, call `cancelPendingRequest`, or fix the missing callback. |
| `STEP_FAIL_NO_PENDING_REQUEST` | A callback reached the client after the pending request was lost. | Check client lifetime and `.onOpenURL` routing. |
| `STEP_IGNORE_UNRELATED_CALLBACK` | Callback scheme/host/path did not match `redirectLink`. | Compare `callback`, `redirect`, and unsafe `callback_raw`. |
| `STEP_FAIL_WALLET_ERROR` | Wallet returned an explicit error code. | Inspect `error_code`, `error_message`, and the wallet approval screen. |
| `response missing nonce/data` | Callback query is incomplete. | Inspect unsafe `query_raw` and wallet redirect configuration. |
| `response decryption failed` | Callback belongs to another keypair/session or was tampered. | Ensure the client/keypair was not recreated before callback handling. |
| `CLUSTER_MISMATCH` | SIWS chain id and adapter cluster disagree. | Use a matching `cluster` and `chainId`. |
