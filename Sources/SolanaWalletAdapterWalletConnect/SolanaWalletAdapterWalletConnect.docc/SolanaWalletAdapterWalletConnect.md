# SolanaWalletAdapterWalletConnect

Typed Solana WalletConnect/Reown request helpers for wallets that do not expose native iWA deeplink provider methods.

## Overview

Use this target when a wallet integration is documented through WalletConnect/Reown instead of Phantom-style `/ul/v1` deeplinks. Jupiter Mobile currently belongs on this track.

The target is transport-agnostic. Apps provide a concrete `WalletConnectSolanaTransport`, and the package provides typed request builders, response types, capability reporting, and a high-level client.

## Topics

### Client

- ``WalletConnectSolanaClient``
- ``WalletConnectSolanaTransport``

### Reown Configuration

- ``ReownProjectConfiguration``
- ``ReownAppMetadata``
- ``ReownRedirectMetadata``
- ``JupiterMobileWalletConnect``

### Namespace

- ``WalletConnectSolanaNamespace``
- ``WalletConnectSolanaChain``
- ``WalletConnectSolanaMethod``

### Requests And Results

- ``WalletConnectSolanaRequests``
- ``WalletConnectSolanaJSONRPCRequest``
- ``WalletConnectSolanaJSONRPCResponse``
- ``WalletConnectSolanaAccountsResult``
- ``WalletConnectSolanaSignMessageResult``
- ``WalletConnectSolanaSignTransactionResult``
- ``WalletConnectSolanaSignAllTransactionsResult``
- ``WalletConnectSolanaSignAndSendTransactionResult``
