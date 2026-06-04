# Device logging — tail [iWA] logs in the terminal (adb-logcat analog)

The iWADemo app logs deterministic, structured `[iWA]` lines at every step of every
wallet action (detect / connect / SIWS / signMessage / signTransaction /
signAllTransactions / signAndSend / disconnect) for all four wallets — Phantom, Solflare,
Backpack (native deeplink) and Jupiter (WalletConnect). Logging is **on by default at
`.debug`**, so no env var is required to see logs on device.

Every line is emitted via **`NSLog`** (by the demo's `DemoLogRecorder`), so it lands in the
device unified log — visible in `idevicesyslog`, Console.app, **and** the Xcode console,
even when the app is **not** attached to a debugger. The device is **auto-detected**; you
never type a UDID.

```
[iWA] [Component] method | STEP_TOKEN phase=INFO|FAIL message="…" key=value …
```

## One-time setup

```sh
brew install libimobiledevice        # provides idevicesyslog + idevice_id
```
Connect the iPhone over USB, unlock it, and tap **Trust** when prompted. Then put real
secrets in the gitignored root `.env` (see `.env.example`):
`SOLANA_RPC_URL=https://mainnet.helius-rpc.com/?api-key=…` (sign/send blockhash) and
`WALLETCONNECT_PROJECT_ID=…` (Jupiter path).

> Jupiter / Phantom / Solflare / Backpack are real App Store wallets — they can't be
> installed on the Simulator. **Use a physical device** for the full round-trip.

## The command set

> **Rebuild + reinstall after EVERY code change, then stream.** `idevicesyslog` only
> sees the *installed* build — the #1 reason "logs don't show" is streaming against a
> stale build. After launching, the very first `[iWA]` line is `STEP_0_BOOT` (it prints
> `build_config` + `log_level` + `payload_policy`). **If you don't see `STEP_0_BOOT`,
> you're on a stale build — reinstall.** Debug builds default to
> `payload_policy=unsafeRawPayloads`, so signatures / txids / decrypted JSON appear in full.

```sh
# Command 1 — build + (re)install on the iPhone (auto-detects the device, bakes .env)
scripts/iwademo-device.sh reinstall

# Command 2 — Tab 1: live filtered stream (the adb logcat | grep analog, no UDID typed)
./scripts/ios-logs.sh
#   equivalent to:
#   idevicesyslog -u "$(idevice_id -l | head -n1)" | grep --line-buffered -E '\[iWA'
#   per-wallet only (wallet id is tagged on every line — request AND callback):
#   ./scripts/ios-logs.sh | grep --line-buffered -E 'wallet=phantom'
#   narrower (WalletConnect/Jupiter path only):
#   IWA_LOG_FILTER='\[iWA\]|InstalledWalletDetector|WalletConnectSolanaClient|STEP_FAIL' ./scripts/ios-logs.sh

# Command 3 — Tab 2: full capture to a file, grep afterwards
idevicesyslog -u "$(idevice_id -l | head -n1)" > /tmp/iwa-ios.log
#   …reproduce the flow, Ctrl+C, then:
grep -E '\[iWA' /tmp/iwa-ios.log

# Launch the app: tap the icon, or
xcrun devicectl device process launch --device "$(idevice_id -l | head -n1)" com.mstevens843.iWADemo
```

`./scripts/ios-logs.sh` auto-detects the device (`idevice_id -l`), so you don't need a UDID;
pass one as `$1` or set `IWA_LOG_FILTER` to override the default `\[iWA` filter (which catches
both the `[iWA]` and `[iWA Demo]` prefixes).

### Fallbacks if `idevicesyslog` shows nothing
- **Console.app**: open it, pick your iPhone in the sidebar, set the search to
  `process:iWADemo` or message `[iWA]`, click **Start**. Zero install.
- **Attached (devicectl):** `scripts/iwademo-device.sh logs` launches the app and tails its
  stdout through the same filter — handy, but only while the launched process stays attached.

## Decoder ring — each step and what a failure means

Read top-to-bottom; a healthy detect → connect → sign produces this sequence. `phase=FAIL`
lines are named `STEP_FAIL*` and carry `error_code` / `wallet_error_code`.

| Log line (component · STEP) | Means | If missing / FAIL |
| --- | --- | --- |
| `InstalledWalletDetector isInstalled STEP_1_PROBE … declared_in_lsaqs=true` → `STEP_2_RESULT installed=true` | The app probed a wallet's scheme and iOS reports it installed | `STEP_FAIL_SCHEME_UNDECLARED reason=scheme_not_in_LSApplicationQueriesSchemes` → scheme missing from `Info.plist` `LSApplicationQueriesSchemes` (the classic false "not installed"). `installed=false` with `declared_in_lsaqs=true` → wallet genuinely not installed. Jupiter logs `STEP_0_NO_SCHEME reason=walletconnect_only` (always surfaces). |
| `WalletAdapterServiceConfiguration fromEnvironment STEP_1_READY` (`solana_rpc_source`, `walletconnect_project_id_present`) | Network config loaded; shows the RPC source (Helius when `SOLANA_RPC_URL` set) and whether the WC project id is present | `STEP_FAIL` → bad env value (RPC URL invalid, etc.); the client won't be built. Secrets are never printed (presence/length only). |
| `WalletAdapterClient <action> STEP_1_START` → `STEP_2_OPEN_URL` → `openOrFail STEP_3_OPEN_ACCEPTED` | Request built + the wallet deeplink was opened | `STEP_FAIL_OPEN_URL` (`error_code=WALLET_UNREACHABLE`) → iOS refused to open the wallet URL (not installed / scheme). `STEP_FAIL_PENDING_REQUEST` (`OPERATION_IN_PROGRESS`) → another request is already in flight. |
| `onOpenURL STEP_1_DELIVERED client_present=true` → `handleOpenURL STEP_1_CALLBACK_RECEIVED` | Wallet bounced back into the app via `iwademo://wallet/callback` | `onOpenURL STEP_FAIL_NO_CLIENT` → callback arrived before the client was configured (cold launch). `STEP_FAIL_NO_PENDING_REQUEST` → callback with nothing in flight. `STEP_IGNORE_UNRELATED_CALLBACK` → URL didn't match the redirect link (harmless). |
| `WalletResponseDecoder … STEP_4_PAYLOAD_DECRYPTED` → `STEP_5_RESULT_DECODED` | The encrypted callback was decrypted + parsed | decoder `STEP_FAIL` (`error_code=DECRYPTION_FAILED`) → wrong session/keypair (client recreated mid-flow); (`MALFORMED_PAYLOAD`) → response missing required fields. |
| `WalletAdapterClient handleOpenURL STEP_2_RESUME_SUCCESS` | The action completed and the async call resumed | `STEP_FAIL_WALLET_ERROR error_code=USER_REJECTED` → user declined; `INVALID_SESSION` → expired, reconnect; `CLUSTER_MISMATCH` (SIWS) → cluster/chainId mismatch. |
| `DemoTransactionBuilder STEP_1A_RPC_ENDPOINT rpc_source=SOLANA_RPC_URL` → `STEP_1_RPC_REQUEST` → `STEP_2_RPC_RESPONSE http_status=200` → `STEP_3_RESULT_DECODED` | Blockhash fetch for signTransaction / signAndSend, via your Helius RPC | `STEP_FAIL_HTTP http_status=401` → bad/expired Helius key; `STEP_FAIL_NETWORK` → no connectivity; `STEP_FAIL_DECODE` → unexpected RPC body; `STEP_FAIL_RPC_ERROR` → RPC returned a JSON-RPC error. The api-key value is redacted (`query_keys=api-key` only). |
| `WalletConnectSolanaClient connect STEP_1_START` (Jupiter) → `STEP_FAIL wallet_error_code=WALLETCONNECT_TRANSPORT_NOT_WIRED project_id_present=true` | Jupiter selected; the WalletConnect client started and failed deterministically | **Expected today** — there's no concrete Reown transport yet (a focused follow-up). The trace proves the project id loaded without leaking it. |
| `KeychainWalletAdapterStateStore … STEP_*` (load/save) | Session/keypair persistence | `STEP_FAIL_KEYCHAIN` / `STEP_FAIL_SAVE` → Keychain read/write failed (entitlements / device lock). |

Mental model: once the wallet returns over the deeplink callback, decode is local and
deterministic. A `STEP_2_OPEN_URL` with **no** later `handleOpenURL STEP_1_CALLBACK_RECEIVED`
means the wallet never bounced you back — start there.

## Raw payloads

**Debug builds enable full-payload logging by default** (`payload_policy=unsafeRawPayloads`
in the `STEP_0_BOOT` line), so raw URLs / payloads / signatures / txids / decrypted JSON
appear — that's what lets you diff exactly what each wallet sent back. Release builds stay
redacted. To force a mode regardless of build, set `SOLANA_WALLET_ADAPTER_UNSAFE_LOGS=true|false`
in `.env` and re-run `scripts/iwademo-device.sh reinstall`. Keep raw logs off for screenshots
and never paste raw-payload logs into public issues.
