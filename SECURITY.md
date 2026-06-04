# Security

## Supported Versions

This package is pre-1.0. Breaking API changes may happen until the first stable release.

## Reporting

Report security issues privately to the maintainer before opening a public issue.

## Security Model

- The dApp never receives the user's Solana private key.
- The app generates an X25519 keypair and uses NaCl box encryption for wallet request/response payloads.
- The wallet approval screen is the signing authority.
- Logs are disabled by default and intentionally omit session tokens, decrypted payloads, full callback URLs, messages, transactions, signatures, and secret keys.
- Unsafe raw-payload logs are for local debugging only and must not be pasted into public issues, pull requests, screenshots, or launch assets.
- `scripts/secret-scan.sh` checks for common keyed RPC URLs, Jupiter keys, private-key env names, and raw wallet log fragments before release.

## Known Limits

- iOS deeplinks are request/response bounces, not persistent wallet connections.
- Wallets may invalidate sessions at any time.
- Real-device smoke testing is required before promoting a wallet/provider combination as stable.
- `SimulatorMockWalletProvider` is a local simulator harness, not a real wallet or security boundary.
