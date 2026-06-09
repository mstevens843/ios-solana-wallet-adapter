# jWA security model (for wallet integrators)

This is the security writeup for the open-source jWA wallet-side handler (`SolanaWalletAdapterJupiterHandler`). It is written for a wallet's security reviewers who are deciding whether to integrate it. Everything below is verifiable against the source in this repo.

## The one thing that matters

Adopting the handler does not widen your trust boundary. It never holds private keys and it never signs without your approval, so the worst case is bounded by the controls you already own: your keystore and your approval UI. The handler is an encrypted message router, not a key manager and not a signer.

No one can promise bug-free code, so this document does not claim that. It explains why the attack surface is small and what stays under your control.

## What the handler is

A small Swift package (a few hundred lines) that:
1. parses an inbound jWA URL,
2. does the x25519 ECDH and NaCl decrypt to read the request,
3. calls back into your code to approve and to sign,
4. encrypts the response and opens the dApp's `redirect_link` to return the user.

It depends only on `SolanaWalletAdapter` and `SolanaWalletAdapterCore` in this repo. It has no third-party dependencies, no relay, no projectId, and no network access.

## Verified properties

1. Keys never enter the handler. You implement `JWASigner`, which exposes only `userPublicKey` plus `signMessage` / `signTransaction` / `signAllTransactions` / `signAndSendTransaction`. Those methods sign inside your keystore and return signatures or signed bytes. The handler never receives, stores, or derives a private signing key. The only keypair it generates is a per-session x25519 encryption keypair used purely for the NaCl channel, which is unrelated to your Solana signing key.

2. Nothing is signed without your approval. For every signing request the handler decrypts, validates the session, then calls `JWAApprovalUI.requestApproval(...)`, and only calls your signer if it returns `.approve`. Connect is gated the same way. The approval request carries the decoded `SigningRequest`, so your sheet can show the exact message or transaction being signed. Your existing approval and security UI stays the gate, and the handler cannot bypass it.

3. Zero network I/O. The handler and both of its dependencies contain no `URLSession`, `URLRequest`, `Network` framework, or sockets. There is no telemetry and no analytics. The only outward call is `UIApplication.open(...)`, which is the app-switch that returns the user to the dApp. You can confirm this by grepping the three targets.

4. No secrets in the handler's logs. The handler logs only the method name, a step name, an error code, and the cluster. It does not log keys, signatures, decrypted payloads, or session tokens, and logging is off by default. One honest caveat: the supporting `EncryptedDeeplink` code has a debug mode that can print raw encrypted payloads and nonces for troubleshooting. It is off by default and is controlled by the integrating app. Use the defaults (logging off) and nothing sensitive is ever written.

5. Sessions are bound per dApp. Each session is keyed by the dApp's encryption public key, and every signing request must carry the matching session token or it is rejected with `INVALID_SESSION`. A request encrypted to the wrong key fails to decrypt first. One dApp's session cannot be used by another.

6. Standard, well-known crypto. x25519 ECDH via Apple CryptoKit, NaCl box (XSalsa20-Poly1305) via a vendored TweetNaCl implementation, base58 wire encoding. This is the same scheme used by the Phantom, Solflare, and Backpack deeplink flows that the ecosystem already relies on. Nothing here is novel or homegrown beyond the standard primitives.

## What it does not protect against, and the fixes

- A malicious dApp can request a bad transaction. This is true of any wallet connection method. The defense is the wallet showing the user what they are signing and the user approving, which jWA preserves and feeds with the decoded content. jWA does not weaken this.
- Custom URL schemes on iOS can be registered by more than one app, and the OS resolves collisions with no chooser. This is true for every deeplink wallet, not specific to jWA. The clean fix is to also serve the protocol over a universal link via your `apple-app-site-association`, which is cryptographically bound to your app and cannot be hijacked. jWA already supports the universal-link transport with no other changes; the custom scheme stays as a fallback.
- The debug logging mode noted in property 4. Keep it off in production (the default).

## How to verify and lock it down

- Read the source. The handler is `Sources/SolanaWalletAdapterJupiterHandler/` (interfaces, session store, the handler, and the UIKit return opener). It is small enough to review in one sitting.
- Confirm no network: grep the handler plus `SolanaWalletAdapter` and `SolanaWalletAdapterCore` for `URLSession`, `URLRequest`, `Network`, and sockets. You will find none.
- Pin or vendor it. Pin a specific commit, or copy the handler files directly into your own repo so there is no external dependency at all.
- Keep the defaults: logging off, the provided `UIApplicationReturnOpener`, your own keystore behind `JWASigner`, your own approval sheet behind `JWAApprovalUI`.
- Add the universal-link host to remove the custom-scheme collision vector.
- Run it through whatever you run on any dependency: your own security review, or your bug bounty.

## How the integration ships

The integration goes in through a normal pull request that your team reviews line by line before anything reaches users. It is roughly one `Info.plist` entry plus three small adapter conformances over your existing keystore, approval sheet, and `UIApplication.open`. Nothing is hidden, and nothing ships without your review and sign-off.
