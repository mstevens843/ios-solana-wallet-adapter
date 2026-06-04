# iWADemo

`iWADemo` is a minimal SwiftUI reference app for smoke testing iOS wallet deeplinks on a real device.

## Open

Open the checked-in project:

```text
Examples/iWADemo/iWADemo.xcodeproj
```

The app links the local package from the repo root and uses:

- `SolanaWalletAdapter`
- `SolanaWalletAdapterPhantom`
- `SolanaWalletAdapterSolflare`
- `SolanaWalletAdapterBackpack`
- `SolanaWalletAdapterUI`

Jupiter Mobile is not included in this deeplink demo. Jupiter's documented path is WalletConnect/Reown; see [`../../docs/walletconnect-reown.md`](../../docs/walletconnect-reown.md).

The `Mock Wallet (Simulator)` option is local-only. It lets you run connect, sign message, and disconnect through the same URL/encryption/callback code path without installing wallet apps. Use a physical iPhone for real Phantom, Solflare, or Backpack validation.

The callback URL used by the demo is:

```text
iwademo://wallet/callback
```

## Local Build

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project Examples/iWADemo/iWADemo.xcodeproj \
  -scheme iWADemo \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Smoke Flow

- Install Phantom, Solflare, or Backpack on the device.
- Run the app on device, not the simulator.
- Pick one wallet.
- Use `Mock Wallet (Simulator)` only for simulator wiring checks.
- Tap connect.
- Approve in the wallet.
- Return to the app and sign the message.
- Disconnect.

The demo restores the saved session for each wallet from Keychain. If a wallet opens but does not redirect back, return to the demo and tap `Cancel Pending Request` before retrying.

The app shows deterministic logs in the Logs section. Keep `Raw Payload Logs` off for normal screenshots. Turn it on only while debugging a failing local device flow; raw mode can show full URLs, query values, encrypted payloads, decrypted wallet JSON, sessions, messages, transactions, and signatures.

Do not paste raw payload logs into public issues.

## Local Network Env

The demo reads the shared service configuration on launch. Add these values to the Xcode scheme environment when you want to test a non-default RPC or Jupiter setup:

```sh
SOLANA_CLUSTER=devnet
SOLANA_RPC_URL=https://your-rpc.example
HELIUS_RPC_URL=https://your-helius-rpc.example
JUP_API_URL=https://api.jup.ag
JUP_API_KEY=your-local-jupiter-key
JUPITER_API_KEY=your-local-jupiter-key
JUP_FETCH_TIMEOUT_MS=8000
```

`SOLANA_RPC_URL` wins over `HELIUS_RPC_URL`. The on-screen network status and logs show only URL shape, source, and key presence; they do not print API keys or keyed RPC query values.
