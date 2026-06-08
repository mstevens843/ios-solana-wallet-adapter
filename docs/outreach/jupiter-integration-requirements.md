# What Jupiter needs to do to support jWA (iOS native, Reown-free)

For: Jupiter mobile engineering. From: the maintainers of the open-source iOS Solana wallet adapter ([github.com/mstevens843/ios-solana-wallet-adapter](https://github.com/mstevens843/ios-solana-wallet-adapter)). The tone here is "we're handing you a fix," not a complaint.

## 1. Short version

The one thing that's actually needed: adopt the open-source jWA wallet-side handler so a native iOS dApp can connect and sign against Jupiter Mobile, and the user gets sent straight back to the dApp after they approve. That's about 40 lines plus one Info.plist entry, with no Reown, relay, or projectId.

Why it can't be done any other way: on iOS, only the foreground app can fire the return. A backgrounded dApp can't bring itself to the front, so after the user approves in Jupiter, only Jupiter can call UIApplication.open(...) to send them back. No dApp-side SDK can stand in for that. It's exactly why the current WalletConnect path finishes the signature but leaves the user stuck in your app (your own jup-mobile-adapter issue #1).

Honest status: we have not run this against the real Jupiter app yet. Connect currently opens Jupiter, but signing deeplinks aren't handled and nothing returns. We've proven the full encrypted round trip and the auto-return in an automated loopback test (JupiterJWARoundTripTests). The last piece can only live inside your binary.

## 2. The one thing only you can do

Integrate the handler. Everything below is already implemented for you in the open-source SolanaWalletAdapterJupiterHandler target.

1. Register your custom URL scheme. Add one dict under CFBundleURLTypes whose CFBundleURLSchemes contains your canonical scheme (we assumed jupiter). That's the only Info.plist change.

2. Add the SPM package: https://github.com/mstevens843/ios-solana-wallet-adapter, and link the product SolanaWalletAdapterJupiterHandler (it pulls SolanaWalletAdapter and core transitively). No Reown dependency.

3. Conform three small adapters over your existing internals:
   - JWASigner: wrap your keystore. userPublicKey (base58), plus signMessage / signTransaction / signAllTransactions / signAndSendTransaction.
   - JWAApprovalUI: present your existing approval sheet and return approve or reject. The handler gives you a decoded JWAIncomingRequest (method, SigningRequest, cluster, appURL, redirectLink) so the sheet can show exactly what's being signed.
   - JWAReturnOpening: use the provided default UIApplicationReturnOpener(). Only override it if you need a custom open path.

4. Forward incoming URLs to the handler. Construct it once:
   ```swift
   let handler = JupiterWalletHandler(
       signer: MyKeystoreSigner(),
       approvalUI: MyApprovalSheet(),
       returnOpener: UIApplicationReturnOpener()
   )
   // SwiftUI:
   .onOpenURL { url in Task { await handler.handleIncomingURL(url) } }
   // UIKit, in scene(_:openURLContexts:), per context:
   Task { await handler.handleIncomingURL(ctx.url) }
   ```
   handleIncomingURL returns Bool. true means it was a jWA request and the callback already fired; false means it isn't jWA, so fall through to your existing routing (in-app browser, feature links, WalletConnect, all untouched).

The handler does all the parsing, x25519, NaCl decrypt and encrypt, base58, callback construction, and the return. You supply the keystore and the approval sheet, and that's it. It's wallet-agnostic, so the same work makes any iOS Solana wallet jWA-conformant.

## 3. What we need from you to finalize

A. Canonical URL scheme (the key blocker). Your actual registered CFBundleURLSchemes value, and confirmation that it routes to a scene or onOpenURL handler rather than the in-app WebView. We assumed jupiter://. On a device, some scheme just opens jup.ag in your in-app browser, and your live AASA only exposes feature links (/swap, /portfolio, /gift, and so on), no /connect or /sign. The whole adapter is parameterized on your scheme and dead-ends without the real value.

B. Connect key name (please confirm). Will you emit the wallet's session pubkey as jupiter_encryption_public_key? Our decoder already accepts that name and a wallet_* fallback. Confirming just removes the guesswork.

C. Universal-link host (optional but preferred). If you publish a signing host, add /ul/v1/* to your existing jup.ag AASA (covered by app ID 9X52DTVD8Z.ag.jup.jupiter.ios). Custom schemes are the weak link on iOS: any app can register jupiter:// and the OS resolves collisions with no chooser. A universal-link host (what Phantom, Solflare, and Backpack use) hardens this. The same params ride https://<host>/ul/v1/<method> with no other changes, and the custom scheme stays as the fallback.

D. A test path (region). A TestFlight or staging build we can call from a US dev device, a devnet or staging endpoint, or a co-test session with someone outside the US. Jupiter Mobile isn't available in the US or sanctioned regions, which blocks our on-device smoke test from here. In the meantime our loopback validates the full encrypted round trip and the return on real wire bytes.

## 4. From-scratch contract (only if you don't use our handler)

If you reimplement instead of adopting the handler, this has to match byte for byte. It's iWA v0.1 over your custom scheme, and any field-name or encoding drift breaks the round trip with the shipped dApp decoder.

Transport. `<scheme>://v1/<method>?<query>`. v1 is the URL authority/host, and the method is the single trailing path component. Methods: connect, disconnect, signMessage, signTransaction, signAllTransactions, signAndSendTransaction. Every request carries a URL-encoded redirect_link; if it's missing, drop the request (there's no response channel).

Crypto. X25519 (CryptoKit), then NaCl box (XSalsa20-Poly1305, TweetNaCl-compatible). Nonce 24 bytes, keys 32 bytes, base58 (Bitcoin alphabet) for all keys, nonces, and ciphertexts. The wallet generates a per-session ephemeral X25519 keypair at connect. Inner JSON is serialized with sorted keys.

Field asymmetry, please don't "fix" it: the inbound encrypted blob is in the field payload, and the outbound response blob is in the field data. (Verified in the shipped code: requests read payload, responses read data.)

Request payloads.
- connect (unencrypted query): app_url, dapp_encryption_public_key (b58, 32B), redirect_link, optional cluster in {mainnet-beta (default), devnet, testnet}.
- Encrypted methods carry dapp_encryption_public_key (selects the session before decrypt), nonce (b58, 24B), and the blob in payload (b58). The decrypted inner JSON echoes session every time; a mismatch returns INVALID_SESSION.
  - signMessage: {message:<b58>, session, display:"utf8"|"hex"}
  - signTransaction: {transaction:<b58>, session}
  - signAllTransactions: {transactions:[<b58>...], session}
  - signAndSendTransaction: {transaction:<b58>, session, sendOptions:{skipPreflight, preflightCommitment?, maxRetries?}}
  - disconnect: {session} (encrypted, to prove ownership)

Connect response (appended to redirect_link): jupiter_encryption_public_key (b58, the per-session wallet pubkey, confirm this name; the decoder also accepts wallet_*); nonce (b58, 24B); data (b58) which is the box over {"public_key":"<user account b58>","session":"<opaque token>"}.

Signing and disconnect response (appended to redirect_link): on success, nonce plus data (b58 encrypted JSON). signMessage {signature:<b58 64-byte sig>}; signTransaction {transaction:<b58 signed wire tx>}; signAllTransactions {transactions:[<b58>...]}; signAndSendTransaction {signature:<b58 txid>}. disconnect returns a bare redirect_link with no payload.

The seven (and only seven) error codes, sent as errorCode plus errorMessage query params on redirect_link: USER_REJECTED, INVALID_SESSION, UNSUPPORTED_METHOD, MALFORMED_PAYLOAD, WALLET_UNREACHABLE, DECRYPTION_FAILED, CLUSTER_MISMATCH. Map any wallet-specific failure cleanly onto one of these.

The return contract, which is the heart of jWA: on every terminal outcome (approve, reject, error), while in the foreground, the wallet must call UIApplication.open(redirect_link + params). It must not rely on the user switching back. This is the exact gap on your live Reown path today.

## 5. Short-term alternative (optional, smaller)

If adopting jWA takes a release cycle, you can return users today on the path you already ship. The Reown path completes connect and sign on iOS; the only missing piece is the wallet-side return for native callers. Two bounded changes:

1. Honor peer.metadata.redirect for native callers. After every result, read the dApp's redirect off the proposer/peer metadata (proposal.proposer.redirect?.native for custom schemes, .universal for universal links) and call UIApplication.open(...). Pre iOS 17 that was WalletConnectRouter.goBack(uri:), still the current reown-swift API. The "iOS 17 can't auto-redirect" caveat only applies to browser dApps; native callers return fine. Phantom and MetaMask both do this already.
2. Register Jupiter Mobile in the Reown Explorer with a working mobile.universal link. (Indirect evidence suggests none is registered right now.)

This is just the Reown fix from issue #1, extended to native callers. It improves the existing path now; jWA is the long-term, Reown-free path.

## 6. What we've already done for you

- Spec: [spec/jwa-protocol.md](https://github.com/mstevens843/ios-solana-wallet-adapter/blob/master/spec/jwa-protocol.md). It's a profile of iWA v0.1, and the crypto, methods, sessions, and errors are identical to the shipping Phantom/Solflare/Backpack path.
- dApp SDK: JupiterAdapter ships on the dApp side, and selecting Jupiter no longer dead-ends. It already consumes the return contract via WalletAdapterClient.handleOpenURL and matchesRedirectLink, so a conformant wallet gets clean auto-return for free.
- Reference wallet handler: [SolanaWalletAdapterJupiterHandler](https://github.com/mstevens843/ios-solana-wallet-adapter/tree/master/Sources/SolanaWalletAdapterJupiterHandler), open source, does all the crypto, parsing, callback, and return, surfaces a decoded SigningRequest to your approval UI, and has structured logging.
- Loopback proof: JupiterJWARoundTripTests and JupiterWalletAdapterClientTests validate the full encrypted round trip and the auto-return on real wire bytes (green).

Your part is the keystore and approval wiring. We carried the protocol.

## 7. Logistics

- Where to engage: we'll post a native-caller follow-up on TeamRaccoons/jup-mobile-adapter issue #1 (the right home for now, since it's the same root cause), plus a note in your dev Discord. Point us at whoever owns the mobile binary and we'll route directly.
- We'll open the PR. Say the word and we'll submit the handler integration against your iOS app, including the Info.plist entry, the three adapter conformances stubbed to your keystore and approval-sheet APIs, and tests, and we'll support it through review.
- First, the scheme (3-A). That single value unblocks both the PR and any on-device test.
- On-device and region (3-D). Given the US lock, we'll work with whatever you can provide: a TestFlight or staging build for a US dev device, a staging or devnet endpoint, or a co-test session with someone outside the US. Happy to get on a call.

Either path fixes the UX. jWA also makes Jupiter a first-class, Reown-free wallet in the iOS adapter ecosystem, and the same handler does that for every iOS Solana wallet, not just yours.
