# Real-Device Smoke Testing

Use `Examples/iWADemo/iWADemo.xcodeproj` for real wallet validation.

Use `Mock Wallet (Simulator)` only to verify app wiring when no iPhone is available. It does not satisfy the real-wallet smoke gate.

## Before Testing

- Build and run on a physical iPhone.
- Install the wallet under test: Phantom, Solflare, or Backpack.
- Use the `devnet` cluster in the demo.
- Keep `Raw Payload Logs` off for normal capture.
- Enable `Raw Payload Logs` only when a flow fails and redacted logs are not enough.

Jupiter Mobile is not part of this native iWA flow. Test it through the WalletConnect/Reown checklist in [`smoke/jupiter-walletconnect.md`](./smoke/jupiter-walletconnect.md) after a concrete Reown transport is wired into an app.

## Per-Wallet Flow

Run each wallet independently:

1. Select the wallet in the picker.
2. Tap Connect.
3. Confirm the wallet opens through a universal link.
4. Approve the connection.
5. Confirm the app shows the public key.
6. Tap Sign Message.
7. Approve the signing request.
8. Confirm the app shows signature byte count.
9. Tap Disconnect.
10. Save logs and screenshots.

If the wallet opens but never redirects back, return to the demo and tap `Cancel Pending Request` before trying the next flow.

## Acceptance Criteria

A wallet passes the 0.2 smoke gate only when all of these are true:

- Connect opens the selected wallet and returns a public key to the demo.
- Sign Message opens the same wallet and returns a signature byte count.
- Disconnect opens the wallet and clears the demo session.
- Redacted logs include the expected checkpoints below.
- Screenshots capture the wallet approval screen and the app result state.
- The result file records the wallet app version, iOS version, device, app commit, and cluster.

## Expected Log Checkpoints

Connect should include:

- `WalletAdapterClient connect | STEP_1_OPEN_URL`
- `WalletAdapter connectURL | STEP_3_URL_BUILT`
- `WalletAdapterClient handleOpenURL | STEP_1_CALLBACK_RECEIVED`
- `WalletResponseDecoder connectSession | STEP_4_PAYLOAD_DECRYPTED`
- `WalletAdapter handleConnectCallback | STEP_3_SESSION_STORED`

Sign message should include:

- `WalletAdapterClient signMessage | STEP_1_OPEN_URL`
- `WalletProvider encryptedURL | STEP_1_PAYLOAD_JSON`
- `WalletProvider encryptedURL | STEP_2_PAYLOAD_ENCRYPTED`
- `WalletResponseDecoder signMessageResult | STEP_4_PAYLOAD_DECRYPTED`
- `WalletAdapterClient handleOpenURL | STEP_2_RESUME_SUCCESS`

## Raw Payload Logs

Raw payload mode may include full callback URLs, session tokens, messages, transactions, signatures, encrypted payloads, and decrypted wallet JSON. Use it only for local debugging and remove it before sharing logs.

Raw mode still must not include dApp secret keys, shared secrets, or raw Keychain state blobs.

## Results

Record results using:

- [`smoke/phantom.md`](./smoke/phantom.md)
- [`smoke/solflare.md`](./smoke/solflare.md)
- [`smoke/backpack.md`](./smoke/backpack.md)
- [`smoke/jupiter-walletconnect.md`](./smoke/jupiter-walletconnect.md)

Use [`smoke/wallet-smoke-template.md`](./smoke/wallet-smoke-template.md) when adding a new wallet.
