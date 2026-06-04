# Third-Party Notices

## TweetNaCl

`Sources/SolanaWalletAdapterCore/TweetNaCl.swift` contains a minimal Swift implementation of TweetNaCl-compatible XSalsa20-Poly1305 routines.

It is based on TweetNaCl.js / nacl-fast.js by Dmitry Chestnykh and Devi Mandiri.

TweetNaCl.js is public domain. See:

https://tweetnacl.js.org/

## Wallet brand assets

`Sources/SolanaWalletAdapterPicker/Resources/Wallets.xcassets/` ships SVG
brand marks for the four bundled wallets. The marks themselves are owned by
their respective publishers; consult each wallet's brand-usage policy before
modifying or redistributing the assets outside this SDK.

| Wallet | Asset slot | Brand-usage source |
| --- | --- | --- |
| Phantom | `wallet-phantom.imageset/phantom.svg` | https://phantom.com/brand |
| Solflare | `wallet-solflare.imageset/solflare.svg` | https://solflare.com/ (about/press) |
| Backpack | `wallet-backpack.imageset/backpack.svg` | https://backpack.app/ (press kit) |
| Jupiter Mobile | `wallet-jupiter.imageset/jupiter.svg` | https://docs.jup.ag/ (brand assets) |

If an asset is missing at runtime the picker renders a colored tile with
the wallet's initial — no crash, no broken layout.
