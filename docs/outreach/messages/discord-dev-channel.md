<!-- Channel: Discord dev-support channel -->
<!-- discord.gg/jup, then the dev channel: https://discord.com/channels/897540204506775583/910250162402779146 -->

hey Jupiter devs, I maintain an open-source iOS Solana wallet adapter (Phantom, Solflare, Backpack right now). I built a Reown-free way for native iOS dApps to connect and sign with Jupiter Mobile that actually returns the user to the app afterward, which is the thing that's broken today (people approve and then get stuck in Jupiter, it's your jup-mobile-adapter issue #1).

the catch is the last piece has to live in the Jupiter app, since on iOS only the foreground wallet can fire the return. so I shipped an open-source wallet-side handler that does it. integrating it is about 40 lines plus one Info.plist entry, no relay or projectId, and it already passes an end-to-end loopback test.

repo: https://github.com/mstevens843/ios-solana-wallet-adapter
spec: https://github.com/mstevens843/ios-solana-wallet-adapter/blob/master/spec/jwa-protocol.md
what integrating it looks like: https://github.com/mstevens843/ios-solana-wallet-adapter/blob/master/docs/outreach/jupiter-integration-requirements.md

two things I'm hoping for: (1) who owns the Jupiter Mobile iOS app so I can get this in front of them, and (2) what's your actual URL scheme? happy to open the PR 🙏
