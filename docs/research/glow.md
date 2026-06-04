# Glow - research notes (2026-05-03)

## Status: held out of v0.1 wallet set pending verification.

## What we know

Source: Solana Mobile's "Wallet Signing on iOS" blog post (<https://docs.solanamobile.com/blog/ios-wallet-signing>).

Solana Mobile cites Glow as an exemplar for **Safari Web Extensions** for wallet signing - not as a deeplink-protocol implementer. Quote from the blog:

> The Glow app is a native iOS wallet that also provides a Safari Web Extension for wallet signing while browsing Safari.

## Open question

Does Glow expose a deeplink/universal-link protocol *in addition to* the Safari Web Extension? If yes, conformance to iWA v0.1 is plausible. If no, Glow is in a different category (Safari extension hosts the signer, not a separate URL bounce) and shouldn't be marketed as part of iWA.

## Action

- Ping the Glow team on Twitter/Discord before adding provider support.
- Until we have a published deeplink spec from Glow, do **not** list Glow as supported.
- Do not include Glow in `Package.swift` targets until deeplink support is verified.

## Why this matters

The gap-doc framing originally listed Glow alongside Phantom + Solflare + Backpack as a deeplink target. Verifying first prevents a credibility hit if a wallet team publicly notes the spec mischaracterizes their integration model.
