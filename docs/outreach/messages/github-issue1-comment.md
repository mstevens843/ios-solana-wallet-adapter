<!-- Channel: GitHub comment on TeamRaccoons/jup-mobile-adapter#1 -->
<!-- Post at: https://github.com/TeamRaccoons/jup-mobile-adapter/issues/1 -->

Following up on this from the native app side, not just Safari. I think I have a clean fix for it.

I can reproduce the same thing on a funded mainnet wallet with a native iOS dApp: connect and signing actually go through, but the user just gets left in Jupiter. The reason is that on iOS only the foreground app can trigger the return. Once the user approves, only Jupiter can call UIApplication.open(redirectLink) to send them back, and a backgrounded dApp can't bring itself to the front. So there's nothing a dApp-side SDK (Reown or anything else) can do about it. It has to happen inside the Jupiter app.

There are two ways to handle it.

1. Quick fix on your current Reown path: after each result, read the dApp's redirect off peer.metadata.redirect (.native for a custom scheme, .universal for a universal link) and call UIApplication.open(...) for native callers. Pre iOS 17 that was WalletConnectRouter.goBack(uri:). The "iOS 17 can't auto-redirect" thing only applies to browser dApps; native returns work fine. Phantom and MetaMask already do this. Getting Jupiter Mobile listed in the Reown Explorer with a mobile.universal link would help too.

2. The proper fix, with no Reown at all: I put together jWA, a custom-scheme profile of the iOS wallet adapter standard, plus an open-source wallet-side handler that does all the crypto, parsing, and the return for you. Integrating it is about 40 lines plus one Info.plist entry, no relay and no projectId. The full encrypted round trip and the auto-return already pass in an automated loopback test.
   Spec: https://github.com/mstevens843/ios-solana-wallet-adapter/blob/master/spec/jwa-protocol.md
   Handler: https://github.com/mstevens843/ios-solana-wallet-adapter/tree/master/Sources/SolanaWalletAdapterJupiterHandler
   What integrating it looks like: https://github.com/mstevens843/ios-solana-wallet-adapter/blob/master/docs/outreach/jupiter-integration-requirements.md

The one thing I need to make it work against the real app is your actual iOS URL scheme. I assumed jupiter:// but that just opens jup.ag in your in-app browser right now. Happy to open the PR with the Info.plist entry and the adapter stubs wired to your keystore and approval sheet. Who owns the mobile app these days, can someone point me their way?

Thanks,
mstevens843
