<!-- Channel: Email to partnerships@jup.ag -->

Subject: Making Jupiter Mobile a first-class wallet for native iOS Solana apps (open-source, Reown-free)

Hello Jupiter Partnerships team,

I maintain an open-source iOS Solana wallet adapter that native iOS apps use to connect to Phantom, Solflare, and Backpack. I'd like to add Jupiter Mobile, and I've already built the open-source pieces to make it a small, well-supported change on your side.

The opportunity: native iOS is a fast-growing surface for Solana apps, from agent apps to trading apps. Jupiter Mobile already connects through Reown, but it never sends the user back to the calling app after they approve, which is the biggest friction point for third-party iOS integrations today (your own jup-mobile-adapter issue #1). Fixing it makes Jupiter Mobile the easiest wallet to integrate on iOS.

Why it's low cost for you: I built jWA, a Reown-free profile of the iOS wallet adapter standard, plus an open-source wallet-side handler. Your engineering work is about 40 lines plus one Info.plist entry, with no relay or projectId dependency. I've proven the full round trip and the return in an automated test, and I'm offering to open the PR and support it.

What I'm asking for: a quick intro to whoever owns the Jupiter Mobile iOS app, and your actual iOS URL scheme so I can finalize and open the PR. If possible, a TestFlight or staging build, or a co-test session with someone outside the US, since Jupiter Mobile isn't available here.

Repo: https://github.com/mstevens843/ios-solana-wallet-adapter
Spec: https://github.com/mstevens843/ios-solana-wallet-adapter/blob/master/spec/jwa-protocol.md
What integrating it looks like: https://github.com/mstevens843/ios-solana-wallet-adapter/blob/master/docs/outreach/jupiter-integration-requirements.md

Happy to hop on a call. Best,
Mathew Stevens (mstevens843)
https://github.com/mstevens843/ios-solana-wallet-adapter
