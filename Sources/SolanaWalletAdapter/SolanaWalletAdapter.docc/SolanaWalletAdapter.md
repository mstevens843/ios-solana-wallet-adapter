# SolanaWalletAdapter

Build encrypted iOS wallet deeplink requests for Solana wallets and decode wallet callbacks.

## Overview

Use `WalletAdapter` when your app wants full control over URL opening and callback routing.

Use `WalletAdapterClient` from `SolanaWalletAdapterUI` when your app wants async connect/sign/disconnect methods that bridge SwiftUI or UIKit URL opening with `.onOpenURL`, `SceneDelegate`, or `AppDelegate` callbacks.

## Topics

### Core

- ``WalletAdapter``
- ``WalletProvider``
- ``Session``
- ``WalletAdapterError``

### State

- ``WalletAdapterState``
- ``WalletAdapterStateStore``

### Configuration

- ``WalletAdapterServiceConfiguration``
- ``JupiterAPIConfiguration``

### Sign In With Solana

- ``SignInWithSolanaInput``
- ``SignInWithSolanaResult``
- ``SignInWithSolanaMessage``

### Logging

- ``WalletAdapterLogger``
- ``WalletAdapterLogEvent``
- ``WalletAdapterLogLevel``

### Simulator Testing

- ``SimulatorMockWalletProvider``
- ``SimulatorMockWalletResponder``
