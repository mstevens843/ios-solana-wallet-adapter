# Return UX — Live Activity "tap-to-return" (`SolanaWalletAdapterReturnUX`)

## Why this exists

On iOS there is **no silent auto-return** for a separate native wallet that does
not cooperate: only the foreground wallet can re-open the calling dApp (a
backgrounded app cannot foreground itself). For wallets that don't fire the
return — Jupiter Mobile over WalletConnect today — the best iOS allows is to make
the manual return **one obvious tap** and confirm success. A Live Activity does
exactly that: a glanceable Dynamic Island / lock-screen pill that returns the user
in one tap and updates to "Signed ✓".

This is transport-agnostic: use it with the WalletConnect/Reown stopgap now, and
with the native iWA/jWA path once a wallet adopts the handler (where it becomes a
backup to true auto-return).

## What the package provides (verified, iOS 16.2+)

- `WalletHandoffStatus` — `waiting` / `signed` / `failed`.
- `WalletHandoffAttributes: ActivityAttributes` — shared between app and widget.
- `WalletHandoffActivityController` — `start` / `update` / `end` around a hand-off.

## What the app (e.g. Agentic) must add

Live Activities require an app + a Widget Extension; the rendering UI cannot live
in an SPM library. App-side steps:

1. **Info.plist:** set `NSSupportsLiveActivities = YES`.
2. **Widget Extension:** add a `WidgetKit` extension that imports
   `SolanaWalletAdapterReturnUX` and renders an `ActivityConfiguration<WalletHandoffAttributes>`
   (lock screen + Dynamic Island). Set the view's `widgetURL(attributes.returnURL)`
   so a tap deep-links back to the dApp.
3. **Register a return scheme/universal link** (e.g. `agentic://wallet/return`) in
   `CFBundleURLTypes` and handle it in `onOpenURL` to reconcile state and `end()`
   the activity.

## Wiring around a wallet hand-off

```swift
import SolanaWalletAdapterReturnUX

let activity = WalletHandoffActivityController()

// 1. Immediately BEFORE opening the wallet (synchronously, in the user gesture):
activity.start(
    walletName: "Jupiter Mobile",
    dappName: "Agentic",
    returnURL: URL(string: "agentic://wallet/return")!
)
openWallet() // WalletConnect deep link today, or jWA jupiter:// once adopted

// 2. When the result arrives (on foreground reconcile, or an ActivityKit push
//    when the tx confirms on-chain):
await activity.update(.signed, detail: "Transaction signed")

// 3. Dismiss:
await activity.end(finalStatus: .signed)
```

Notes:
- The basic "tap-to-return" affordance works for **all** actions with no backend.
- Updating to `.signed` automatically (vs. on foreground) requires an ActivityKit
  **push** driven by a backend that observes on-chain confirmation — only
  available for on-chain actions (send/signAndSend), not connect/off-chain sign.
- This does **not** claim silent auto-return. When/if the wallet adopts jWA (or
  honors the WalletConnect redirect), true auto-return supersedes the tap and the
  Live Activity becomes a confirmation/backup.
