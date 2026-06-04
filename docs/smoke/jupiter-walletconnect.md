# Jupiter Mobile WalletConnect Smoke Result

## Status

- Result: pending
- Date:
- Tester:
- Device:
- iOS version:
- Jupiter Mobile version:
- Region:
- Reown Project ID source: local config / build setting / other

## Scenario

- Integration path: WalletConnect/Reown
- Swift target: `SolanaWalletAdapterWalletConnect`
- Native iWA provider: no

## Checklist

- [ ] Reown project configuration loaded without hardcoding the Project ID.
- [ ] Jupiter Mobile approved the WalletConnect session.
- [ ] App received at least one Solana account public key.
- [ ] `solana_signMessage` approval returned a signature.
- [ ] Message signature verified against the connected public key.
- [ ] `solana_signTransaction` returned a signed transaction or documented wallet error.
- [ ] `solana_signAndSendTransaction` returned a transaction signature or documented wallet error.
- [ ] Disconnect cleared the WalletConnect session.

## Notes

Record exact user-visible failures, WalletConnect/Reown errors, and Jupiter wallet errors. Do not include Reown Project IDs, session topics, pairing URIs, raw transactions, signatures, private keys, or recovery phrases in public reports.
