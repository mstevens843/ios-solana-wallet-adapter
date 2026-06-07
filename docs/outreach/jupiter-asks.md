# Jupiter outreach — drafts (2026-06-07)

Two asks. We build jWA regardless; these run in parallel to unblock the **real**
Jupiter Mobile app. The real fix can only live inside Jupiter's binary (only the
foreground wallet can fire the iOS return), so the goal is to make that fix as
cheap as possible for them.

---

## 1. Escalation comment — `TeamRaccoons/jup-mobile-adapter` issue #1

> **Re: Jupiter Mobile doesn't auto-return after Approve — also affects native iOS callers**
>
> Confirming this reproduces beyond the Safari/web case, on a funded mainnet
> wallet (iOS, US): a **native** iOS dApp connecting Jupiter Mobile over
> WalletConnect completes connect/sign, but the user is **never** returned to the
> calling app — they must background Jupiter and reopen the dApp manually. Every
> wallet action is affected.
>
> Root cause is the standard WalletConnect iOS return contract: after approval the
> wallet must read the dApp's `redirect`/`peer.metadata.redirect` and call
> `UIApplication.open(dappLink)` (pre-iOS-17 `WalletConnectRouter.goBack(uri:)`).
> Phantom and MetaMask do this; Jupiter Mobile appears not to, and Jupiter does
> not appear to be registered with a mobile universal link in Reown's wallet
> registry. A backgrounded dApp cannot foreground itself, so this is only fixable
> wallet-side.
>
> Two concrete fixes that would resolve it:
> 1. Honor `peer.metadata.redirect` (`native`/`universal`) and fire the return
>    after every terminal outcome (approve/reject/error), for **native** callers
>    too — not just web.
> 2. Register Jupiter Mobile in the Reown Explorer with a working mobile
>    universal link.
>
> Separately, we've published an open, Reown-free native option (jWA) that gives
> clean auto-return by design and is a ~40-line drop-in on the wallet side — happy
> to open a PR. Details in the dev-support note / repo below.

Link to include: the iWA repo + `spec/jwa-protocol.md`.

---

## 2. Jupiter dev-support / Discord request

> **Subject: Making third-party iOS dApp → Jupiter Mobile connections return cleanly (with a turnkey option)**
>
> Hi Jupiter team — we maintain an open-source iOS Solana wallet-adapter
> (Phantom/Solflare/Backpack today) and want first-class Jupiter Mobile support.
>
> **What works today:** via WalletConnect/Reown, connect and signing complete on
> iOS. **The gap:** Jupiter Mobile never auto-returns the user to the calling
> native app after approval (device-confirmed, funded mainnet wallet, US). On iOS
> only the foreground wallet can send the user back, so this can only be fixed in
> the Jupiter app.
>
> **Short-term ask (small):**
> 1. After approval, honor the dApp's WalletConnect `redirect` (`native` +
>    `universal`) and fire `UIApplication.open(...)` for **native** callers, on
>    every outcome.
> 2. Register Jupiter Mobile in Reown's Explorer with a working mobile universal link.
>
> **The real ask (turnkey, Reown-free):** we've published **jWA**, a custom-scheme
> profile of our iOS wallet-adapter spec, with an **open-source drop-in handler**.
> Adopting it is roughly: add a `jupiter://` entry to `CFBundleURLTypes`, conform
> three thin adapters (your keystore → `JWASigner`, your approve sheet →
> `JWAApprovalUI`, default `UIApplicationReturnOpener`), and forward inbound URLs
> to `JupiterWalletHandler`. ~40 lines, no Reown/relay/projectId dependency, and
> the user gets clean auto-return by design. We've proven the full encrypted
> round-trip + return in an automated loopback and would gladly open the PR and
> support it.
>
> Spec: `spec/jwa-protocol.md`. Reference handler: `SolanaWalletAdapterJupiterHandler`.
> Repo: <https://github.com/mstevens843/ios-solana-wallet-adapter>
>
> Either path fixes the UX; (2) makes Jupiter a first-class, Reown-free citizen of
> the iOS wallet-adapter ecosystem. Happy to jump on a call.

---

### Notes for sending
- Keep the tone collaborative — we're handing them a fix, not filing a complaint.
- Do not claim the real Jupiter app works natively yet; lead with the loopback proof + the offer.
- Targets: GitHub issue #1 (above), Jupiter dev Discord, and any Raccoon Labs dev contact.
