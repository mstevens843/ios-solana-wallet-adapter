# Jupiter - research notes (2026-05-07)

## Status: WalletConnect/Reown track; do not list as a native iWA provider.

## What we know

Jupiter Mobile is a self-custodial, Solana-native wallet. Jupiter's user docs describe it as available on iOS, Android, Solana Seeker, Solana Saga, and Play Solana, with Solana-only chain support.

Source: <https://docs.jup.ag/user-docs/manage/mobile>

Jupiter's developer docs currently expose a "Jupiter Mobile Adapter" path through Jupiter Wallet Kit. That integration is described as QR-code login powered by `@jup-ag/jup-mobile-adapter`, Reown AppKit, and WalletConnect.

Source: <https://developers.jup.ag/docs/tool-kits/wallet-kit/jupiter-mobile-adapter>

The published `@jup-ag/jup-mobile-adapter` npm package confirms that shape:

- package description: wraps around Reown/WalletConnect AppKit
- peer dependencies: `@reown/appkit`, `@reown/appkit-adapter-solana`, `@reown/appkit-wallet-button`, `@solana/wallet-adapter-base`, and `@solana/web3.js`
- exported surface: `useWrappedReownAdapter`
- Jupiter Mobile selection: proxies a Reown adapter and targets Reown wallet button id `jupiter`

Source: <https://www.npmjs.com/package/@jup-ag/jup-mobile-adapter>

Jupiter's user docs also state that Jupiter Mobile is not available in the United States, China, or other sanctioned regions. That can block ordinary US real-device smoke testing even if protocol support is later confirmed.

## Compatibility read

The current iWA package supports native iOS URL-bounce providers that publish Phantom/Solflare/Backpack-style endpoints:

- `https://<wallet-host>/ul/v1/connect`
- encrypted callback query params containing wallet encryption public key, `nonce`, and `data`
- post-connect signing methods such as `signMessage`, `signTransaction`, `signAllTransactions`, `signAndSendTransaction`, and `disconnect`

The public Jupiter docs and published package reviewed so far do not document that protocol shape for Jupiter Mobile. They document WalletConnect/Reown QR login instead, which is a different integration class from this package's native deeplink provider interface.

That makes Jupiter Mobile a strong candidate for `SolanaWalletAdapterWalletConnect`, not for a `SolanaWalletAdapterJupiter` native deeplink target.

## Remaining open question

Does Jupiter Mobile expose an unpublished native iOS deeplink signing protocol in addition to its WalletConnect/Reown adapter? If yes, Jupiter could still become a direct iWA provider later. If no, the WalletConnect/Reown track is the correct production path.

## Action

- Do not add a `SolanaWalletAdapterJupiter` target from guessed URL shapes.
- Do not add Jupiter to `WalletProviderRegistry.supportedProviders` until connect and at least one signing method are confirmed on a real device.
- Use `SolanaWalletAdapterWalletConnect` for Jupiter Mobile's documented Reown/WalletConnect path.
- Keep any Reown Project ID in local app configuration, build settings, or environment-specific configuration.
- If Jupiter confirms native deeplinks later, capture the exact host, scheme, request params, response encryption key alias, supported methods, error codes, and regional test constraints before implementing a direct provider.

## Why this matters

Jupiter Mobile is strategically interesting because it is a growing Solana wallet, but advertising unverified native iWA compatibility would weaken the adapter's credibility. The credible path is to support Jupiter through WalletConnect/Reown and keep the native provider registry limited to wallets with published `/ul/v1` deeplink support.
