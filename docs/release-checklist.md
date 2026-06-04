# Release Checklist

## Public RC Gate

- `scripts/verify-local.sh` passes.
- `scripts/secret-scan.sh` passes.
- README, changelog, security notes, and docs describe the release as `0.2.0-rc.1`.
- No real API keys, keyed RPC URLs, raw wallet callbacks, session tokens, messages, transactions, or signatures are committed.
- Simulator mock wallet connect, sign message, and disconnect work in iWADemo.
- Launch copy says "public RC" or "release candidate", not "production-validated".

## Stable 0.2.0 Gate

- Physical iPhone smoke passes for Phantom connect, sign message, and disconnect.
- Physical iPhone smoke passes for Solflare connect, sign message, and disconnect.
- Physical iPhone smoke passes for Backpack connect, sign message, and disconnect.
- Smoke result files include device, iOS version, wallet app version, cluster, commit, screenshots, and redacted logs.
- README wallet table can be updated from "real-device smoke pending" to the exact tested status.
- Tag `0.2.0` only after the smoke result files are committed.

## Pre-Tweet Check

- Use the clean generated PNG in `assets/`.
- Do not show unsafe raw logs in screenshots or video.
- Do not claim Mobile Wallet Adapter support on iOS.
- Do not claim Jupiter Mobile native deeplink support.
- Do not claim stable production support until the stable gate is complete.
