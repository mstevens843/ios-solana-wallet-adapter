# WalletConnect / Reown Track

`SolanaWalletAdapterWalletConnect` is the companion path for wallets that use WalletConnect/Reown instead of native iWA deeplinks.

This is intentionally separate from `WalletProvider`. Native iWA wallets open URLs like `https://phantom.app/ul/v1/connect` and return encrypted callback query params. WalletConnect/Reown wallets establish a relay-backed session, then approve Solana JSON-RPC signing requests.

## Current target

Jupiter Mobile is the first target for this track.

Public Jupiter docs and the published `@jup-ag/jup-mobile-adapter` package point to Reown AppKit / WalletConnect. The package exposes a Jupiter Mobile adapter by wrapping a Reown wallet provider, not by publishing Phantom-style `/ul/v1` deeplinks.

## What the Swift target provides

- `ReownProjectConfiguration` and `ReownAppMetadata` for app-supplied Reown configuration.
- `JupiterMobileWalletConnect` constants for Jupiter Mobile display metadata and Reown wallet button targeting.
- `WalletConnectSolanaNamespace` for the Solana session permissions.
- Typed builders for:
  - `solana_getAccounts`
  - `solana_requestAccounts`
  - `solana_signMessage`
  - `solana_signTransaction`
  - `solana_signAllTransactions`
  - `solana_signAndSendTransaction`
- Typed response helpers for accounts, signatures, signed transactions, and transaction signatures.
- `WalletConnectSolanaTransport`, a small protocol for an app-level Reown/WalletConnect Sign SDK bridge.
- `WalletConnectSolanaClient`, an async facade that calls the transport after a session is connected, including `getCapabilities()`, `getAccounts()`, `requestAccounts()`, and the signing methods.

The package does not hardcode a Reown Project ID and does not commit any dashboard credentials. Apps should read the Project ID from local configuration, build settings, or environment-specific app config.

## Encoding differences from iWA

- WalletConnect `solana_signMessage` uses base58 message bytes.
- WalletConnect transaction methods use base64 serialized transactions.
- iWA deeplinks use base58 for transaction bytes because that is what Phantom/Solflare/Backpack deeplink docs use.

Do not reuse iWA payload encoders for WalletConnect transaction requests.

## Minimal app integration shape

```swift
import SolanaWalletAdapterWalletConnect

let config = try ReownProjectConfiguration(
    projectId: reownProjectIdFromLocalConfig,
    metadata: ReownAppMetadata(
        name: "Example",
        description: "Example Solana app",
        url: URL(string: "https://example.com")!,
        icons: [URL(string: "https://example.com/icon.png")!],
        redirect: ReownRedirectMetadata(native: "example://walletconnect")
    )
)

let namespace = WalletConnectSolanaNamespace.proposal(chains: [.mainnet])
```

The app still needs a concrete `WalletConnectSolanaTransport` backed by Reown/WalletConnect Swift. That transport owns pairing, QR/deeplink display, session approval, JSON-RPC request delivery, and session disconnect.

## Real-device smoke gate

Jupiter Mobile should not be marked supported until a real-device smoke run proves:

- Reown project configuration loads from local app config.
- Jupiter Mobile can approve the WalletConnect session.
- The app receives a Solana account public key.
- `solana_signMessage` returns a valid signature.
- `solana_signTransaction` returns a signed transaction or documented wallet error.
- `solana_signAndSendTransaction` returns a signature or documented wallet error.
- Disconnect clears the session.

## References

- Jupiter Mobile Adapter: <https://developers.jup.ag/docs/tool-kits/wallet-kit/jupiter-mobile-adapter>
- Jupiter Mobile user docs: <https://docs.jup.ag/user-docs/manage/mobile>
- Reown supported chains: <https://docs.reown.com/appkit/networks/supported-chains>
- WalletConnect Solana methods: <https://docs.walletconnect.network/wallet-sdk/chain-support/solana>
