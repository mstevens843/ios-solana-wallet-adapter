# Contributing

## Development

Use full Xcode when running XCTest locally:

```sh
scripts/verify-local.sh
```

Keep changes scoped. The package is intentionally split between:

- core URL/crypto primitives
- wallet provider targets
- app lifecycle helpers in `SolanaWalletAdapterUI`

## Wallet Compatibility

Provider changes should include:

- a doc link or captured research note
- URL shape tests
- encrypted request/response tests
- real-device smoke notes when possible

## Privacy

Do not commit logs containing full callback URLs, session tokens, decrypted payloads, transaction bytes, signatures, or private keys.

Run `scripts/secret-scan.sh` before opening a PR if you touched docs, demo logging, env configuration, or smoke-test output.
