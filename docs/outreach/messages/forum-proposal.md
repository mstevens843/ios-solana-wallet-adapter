<!-- Channel: Forum, discuss.jup.ag (Proposals). New Topic. -->

# Title
Proposal: native, Reown-free Jupiter Mobile support for iOS dApps (with an open-source reference handler)

# Body

Short version: we can make Jupiter Mobile a first-class wallet for native iOS Solana apps by adopting an open-source, Reown-free wallet-side handler that sends the user back to the app after they approve. It's about a 40-line integration, and I've already built and tested everything except the part that has to live in the Jupiter app.

The problem: native iOS dApps connect and sign with Jupiter Mobile through Reown, but users never get returned after approving (jup-mobile-adapter issue #1). On iOS only the foreground wallet can fire the return, so it can only be fixed inside the Jupiter app.

The proposal: jWA, a custom-scheme profile of the iOS wallet adapter standard (iWA v0.1), with an open-source reference handler (SolanaWalletAdapterJupiterHandler). Jupiter conforms three small adapters (keystore, approval sheet, UIApplication.open) and forwards incoming URLs to it. No relay, no projectId. Already tested end to end.

Why it's worth doing: it fixes the number one complaint about integrating Jupiter Mobile on iOS, it makes Jupiter the easiest Solana wallet to build against on iOS, and because the handler is wallet-agnostic it sets a standard any iOS Solana wallet can adopt, with Jupiter as the first.

What we'd need from Jupiter: your actual iOS URL scheme (the real blocker), confirmation of the connect key name, and a way to test given the US region lock. I'll open the PR and support it.

Already done and public: the spec, the dApp SDK, the reference handler, and the loopback proof.
Repo: https://github.com/mstevens843/ios-solana-wallet-adapter
Spec: https://github.com/mstevens843/ios-solana-wallet-adapter/blob/master/spec/jwa-protocol.md
Requirements: https://github.com/mstevens843/ios-solana-wallet-adapter/blob/master/docs/outreach/jupiter-integration-requirements.md

mstevens843
