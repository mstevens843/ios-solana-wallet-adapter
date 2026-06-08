<!-- Channel: Email to mobile-support@jup.ag -->

Subject: Open-source fix for Jupiter Mobile's iOS dApp auto-return (about a 40-line change)

Hi Jupiter Mobile team,

I maintain an open-source iOS Solana wallet adapter (Phantom, Solflare, Backpack) and I'd love to add Jupiter Mobile so native iOS dApps can use it properly.

Right now native iOS dApps can connect and sign with Jupiter Mobile through Reown, but the user never gets sent back to the dApp after they approve (it's your jup-mobile-adapter issue #1). On iOS only the foreground app can fire that return, so it can only be fixed inside the Jupiter app. The good news is I've already built everything around it and tried to make it a tiny lift for you:

- jWA, a Reown-free custom-scheme profile of the iOS wallet adapter standard (same crypto your peers use)
- An open-source wallet-side handler that does all the crypto and parsing and fires the return. Your part is about 40 lines plus one Info.plist entry: wrap your keystore and approval sheet, and forward incoming URLs to it. No relay, no projectId.
- It already passes an automated end-to-end test, the full encrypted round trip plus the return

The one thing I need to make it work against the real app is your actual iOS URL scheme. I assumed jupiter://, but that just opens jup.ag in your in-app browser right now. I'm glad to open the PR and support it through review.

Repo: https://github.com/mstevens843/ios-solana-wallet-adapter
Spec: https://github.com/mstevens843/ios-solana-wallet-adapter/blob/master/spec/jwa-protocol.md
What integrating it looks like: https://github.com/mstevens843/ios-solana-wallet-adapter/blob/master/docs/outreach/jupiter-integration-requirements.md

If there's a faster way to reach whoever owns the iOS app, please point me there. Thanks,
Mathew (mstevens843)
