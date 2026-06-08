<!-- Channel: GitHub NEW issue in TeamRaccoons/jup-mobile-adapter -->
<!-- Open at: https://github.com/TeamRaccoons/jup-mobile-adapter/issues/new -->

# Title
Proposal: native, Reown-free auto-return for Jupiter Mobile (jWA), with a reference handler and an offer to PR

# Body

Hey, I maintain an open-source iOS Solana wallet adapter (Phantom, Solflare, Backpack today) and I'd like to add Jupiter Mobile. Short proposal below, and I'm offering to do the work.

The problem

Native iOS dApps can connect and sign with Jupiter Mobile through Reown, but the user never gets sent back to the dApp after they approve (same root cause as #1). On iOS only the foreground wallet can fire the return, so the fix has to live inside the Jupiter app.

What I'm proposing

I built jWA, a Reown-free custom-scheme profile of the iOS wallet adapter standard (iWA v0.1, the same crypto Phantom, Solflare, and Backpack use). I've done everything except the part that has to live in your binary:

- dApp SDK (JupiterAdapter): done
- Open-source wallet-side reference handler (SolanaWalletAdapterJupiterHandler): parses the request, does the x25519/NaCl decrypt, shows your approval sheet (with the decoded request so you can display what's being signed), signs with your keystore, and fires the return
- Loopback and full client tests: passing

What it costs you

About 40 lines plus one Info.plist entry. You conform three small adapters (keystore, approval sheet, UIApplication.open) and forward incoming URLs to handler.handleIncomingURL(url). No relay, no projectId. Optional but nice for robustness against scheme collisions: add /ul/v1/* to your jup.ag AASA so it can ride universal links too.

What I need from you

Your actual iOS URL scheme (the one real blocker), and confirmation of the connect key name (jupiter_encryption_public_key).

The offer

I'll open the PR (Info.plist, adapter stubs, tests) and stay with it through review.
Spec: https://github.com/mstevens843/ios-solana-wallet-adapter/blob/master/spec/jwa-protocol.md
Handler: https://github.com/mstevens843/ios-solana-wallet-adapter/tree/master/Sources/SolanaWalletAdapterJupiterHandler
Requirements: https://github.com/mstevens843/ios-solana-wallet-adapter/blob/master/docs/outreach/jupiter-integration-requirements.md

Either path fixes the UX. jWA does it with no Reown dependency, and since the handler is wallet-agnostic, the same work lets any iOS Solana wallet support it.

mstevens843
