# jWA — Jupiter / custom-scheme profile of iWA v0.1 (draft)

> **Status:** draft. A *profile* of [iWA v0.1](./protocol.md), not a new protocol.
> Implemented dApp-side by `SolanaWalletAdapterJupiter` and wallet-side by the
> reference `SolanaWalletAdapterJupiterHandler`. Round-trip proven by
> `JupiterJWARoundTripTests`. Subject to change until v1.0.

## Why this profile exists

iWA v0.1 (Phantom/Solflare/Backpack) addresses wallets over a **universal-link**
host (`https://<host>/ul/v1/<method>`). Jupiter Mobile publishes **no signing
universal-link host** — its live `apple-app-site-association` exposes only feature
links (`/swap`, `/portfolio`, `/gift`, …), and its only documented cross-app
connection path is WalletConnect/Reown (see [`docs/research/jupiter.md`](../docs/research/jupiter.md)).

jWA is the **Reown-free** path: it reaches the wallet over its **custom URL
scheme** instead of a universal link, and pins down the one thing that makes the
experience good on iOS — a **mandatory return contract** so the user is bounced
back automatically after approving.

Everything else (cryptography, payloads, session model, error codes) is
**byte-identical to iWA v0.1**, so a jWA wallet is "just another `WalletProvider`."

## What is and isn't possible on iOS (read this first)

- **In-app sheets (Android-MWA style) are not possible on iOS** for two
  independent apps. Do not expect them.
- **Auto-return must be fired by the wallet.** A backgrounded dApp cannot
  foreground itself; only the foreground wallet can call `UIApplication.open` on
  the dApp's `redirect_link`. jWA therefore makes this a normative MUST (below).
  No dApp-side SDK can substitute for it.
- Consequently, jWA delivers clean auto-return **only when the wallet ships a
  conformant handler.** Against today's Jupiter app, `connect` opens Jupiter but
  signing requests are not honored ("invalid uri path") and nothing returns — see
  Status.

## Transport

```
<customScheme>://<version>/<method>?<query>
```

For Jupiter: `jupiter://v1/connect`, `jupiter://v1/signMessage`, etc. The version
is the URL authority so the method stays the single trailing path component
(keeping wallet-side method parsing identical to the universal-link shape).

If Jupiter later publishes a signing universal-link host, the same parameters ride
`https://<host>/ul/v1/<method>` with no other change to this profile.

`LSApplicationQueriesSchemes` must list `jupiter` for the dApp to probe/open it.
iOS provides no app-chooser for shared schemes; jWA dApps select a specific wallet
explicitly (see iWA §App-chooser).

## Cryptography, methods, sessions, errors

Identical to [iWA v0.1](./protocol.md):

- X25519 (CryptoKit) → NaCl `box` (XSalsa20-Poly1305, vendored TweetNaCl), base58 wire.
- Methods: `connect`, `disconnect`, `signMessage`, `signTransaction`,
  `signAllTransactions`, `signAndSendTransaction` — same request/response JSON.
- Session token echoed in every encrypted payload; `INVALID_SESSION` ⇒ reconnect.
- Same seven error codes; surfaced as `errorCode` / `errorMessage` on `redirect_link`.

**Connect response key:** the wallet returns its X25519 public key as
`jupiter_encryption_public_key` (added to the decoder's alias list alongside
`phantom_`/`solflare_`/`wallet_*`).

## The return contract (normative — the heart of jWA)

> On **every** terminal outcome of a jWA request — user approval, user rejection,
> or internal error — the wallet **MUST**, while in the foreground, call
> `UIApplication.open(redirect_link + response)`. The wallet **MUST NOT** rely on
> the user manually switching back. `redirect_link` is supplied on every request
> and is the sole response channel.

Outcome encodings appended to `redirect_link`:

- **Success:** `nonce` + `data` (encrypted response payload), and for `connect`
  also `jupiter_encryption_public_key`.
- **Rejection:** `errorCode=USER_REJECTED&errorMessage=…`.
- **Error:** `errorCode=<one of the seven codes>&errorMessage=…`.
- **disconnect:** bare `redirect_link` (no payload) is sufficient.

This contract is already consumed on the dApp side by
`WalletAdapterClient.handleOpenURL` / `matchesRedirectLink`, so a conformant
wallet gets clean auto-return for free.

## Adopting jWA in a wallet (the ~40-line lift)

The open-source `SolanaWalletAdapterJupiterHandler` target implements all parsing,
decryption, callback construction, and the return call. A wallet adopts jWA by:

1. Registering its custom scheme (e.g. `jupiter`) under `CFBundleURLTypes`.
2. Conforming three thin adapters:
   - `JWASigner` — wrap the existing keystore (`signMessage` / `signTransaction` /
     `signAllTransactions` / `signAndSendTransaction`, `userPublicKey`).
   - `JWAApprovalUI` — present the existing approval sheet, return approve/reject.
   - `JWAReturnOpening` — `UIApplicationReturnOpener()` is provided by default.
3. Forwarding inbound URLs to the handler:

```swift
let handler = JupiterWalletHandler(
    signer: MyKeystoreSigner(),
    approvalUI: MyApprovalSheet(),
    returnOpener: UIApplicationReturnOpener()
)
// In SceneDelegate.scene(_:openURLContexts:) or SwiftUI .onOpenURL:
Task { await handler.handleIncomingURL(url) }
```

Because the handler is wallet-agnostic, the same integration makes jWA an
ecosystem standard any iOS Solana wallet can adopt — not a Jupiter-only path.

## Status

| Piece | Status |
|-------|--------|
| dApp provider (`JupiterAdapter`) | shipped; resolvable via `WalletProviderRegistry.previewProviders` (selecting it no longer dead-ends), kept out of the verified `supportedProviders` until on-device confirmation |
| Reference wallet handler (`JupiterWalletHandler`) | shipped, open source; exposes the decoded `SigningRequest` to the approval UI and supports structured `WalletAdapterLogger` tracing |
| Loopback + full `WalletAdapterClient` round-trip + auto-return proof | passing (`JupiterJWARoundTripTests`, `JupiterWalletAdapterClientTests`) |
| Real Jupiter Mobile end-to-end | **gated on Jupiter shipping the handler** (tracking issue + dev ask in flight) |

Until Jupiter (or another wallet) adopts the handler, dApps targeting the **real**
Jupiter app should use the WalletConnect/Reown companion track for connect+sign and
present an explicit return affordance (jWA's auto-return needs the wallet-side fix).

## References

- iWA v0.1 spec: [`spec/protocol.md`](./protocol.md)
- Jupiter research + Reown track: [`docs/research/jupiter.md`](../docs/research/jupiter.md)
- Jupiter Mobile Adapter (Reown/WalletConnect): <https://developers.jup.ag/docs/tool-kits/wallet-kit/jupiter-mobile-adapter>
- Auto-return / iOS app-switch limits: <https://docs.solanamobile.com/blog/ios-wallet-signing>
- WalletConnect iOS mobile linking / redirect: <https://docs.reown.com/walletkit/ios/mobile-linking>
