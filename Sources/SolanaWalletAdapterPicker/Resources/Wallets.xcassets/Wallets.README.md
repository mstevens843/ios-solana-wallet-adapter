# Wallet logo assets

Each imageset in this catalog is the slot the picker looks up for a wallet's
brand mark:

- `wallet-phantom.imageset` — Phantom (ghost mark or "P" logo)
- `wallet-solflare.imageset` — Solflare (yellow flare logo)
- `wallet-backpack.imageset` — Backpack (red square logo)
- `wallet-jupiter.imageset` — Jupiter Mobile (green ring logo)

Drop @1x / @2x / @3x PNGs into each imageset and update its `Contents.json`
to list the filenames. The picker calls `UIImage(named:in:with:)` against
`Bundle.module`; if the asset is missing, it renders a colored tile with a
monogram fallback (no crash, just less polish).

Each wallet's brand assets are governed by its own usage policy. Before
shipping bundled logos, follow the source links in `THIRD_PARTY_NOTICES.md`
to confirm allowed usage (most wallets explicitly permit logos inside
connect modals, but always re-check the current guidelines).
