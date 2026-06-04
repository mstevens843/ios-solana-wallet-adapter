import { writeFileSync } from "node:fs";

const solanaMarkPath =
  "M86.619 69.036 74.403 82.101a2.837 2.837 0 0 1-2.075.899h-57.91a1.421 1.421 0 0 1-1.3-.85 1.411 1.411 0 0 1 .263-1.53l12.225-13.064a2.837 2.837 0 0 1 2.07-.899h57.906a1.423 1.423 0 0 1 1.3.85 1.412 1.412 0 0 1-.263 1.53ZM74.403 42.727a2.837 2.837 0 0 0-2.075-.898h-57.91a1.421 1.421 0 0 0-1.3.85 1.412 1.412 0 0 0 .263 1.529l12.225 13.065a2.84 2.84 0 0 0 2.07.898h57.906a1.422 1.422 0 0 0 1.3-.85 1.412 1.412 0 0 0-.263-1.529L74.403 42.727Zm-59.985-9.384h57.91a2.844 2.844 0 0 0 2.075-.899l12.216-13.065A1.414 1.414 0 0 0 85.582 17H27.676a2.845 2.845 0 0 0-2.07.899L13.384 30.964a1.412 1.412 0 0 0 1.034 2.379Z";

const cards = [
  {
    name: "ios-solana-wallet-adapter-card",
    width: 1080,
    height: 1080,
    titleSize: 82,
    subtitleSize: 31,
  },
  {
    name: "ios-solana-wallet-adapter-wide",
    width: 1600,
    height: 900,
    titleSize: 86,
    subtitleSize: 32,
  },
  {
    name: "ios-solana-wallet-adapter-og",
    width: 1200,
    height: 630,
    titleSize: 68,
    subtitleSize: 25,
  },
];

const escapeXML = (value) =>
  value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");

const phone = (x, y, width, height) => `
<g filter="url(#shadow)">
  <rect x="${x}" y="${y}" width="${width}" height="${height}" rx="${width * 0.16}" fill="#071017" stroke="#dce7ef" stroke-width="${Math.max(4, width * 0.018)}"/>
  <rect x="${x + width * 0.09}" y="${y + height * 0.09}" width="${width * 0.82}" height="${height * 0.82}" rx="${width * 0.09}" fill="url(#screen)"/>
  <rect x="${x + width * 0.35}" y="${y + height * 0.035}" width="${width * 0.3}" height="${height * 0.018}" rx="${height * 0.009}" fill="#dce7ef" opacity=".9"/>
  <circle cx="${x + width * 0.5}" cy="${y + height * 0.945}" r="${width * 0.025}" fill="#dce7ef" opacity=".8"/>
  <path d="M${x + width * 0.25} ${y + height * 0.48}h${width * 0.5}v${height * 0.25}h-${width * 0.5}z" fill="#06121a" opacity=".5"/>
  <path d="M${x + width * 0.33} ${y + height * 0.48}v-${height * 0.08}c0-${height * 0.08} ${width * 0.07}-${height * 0.14} ${width * 0.17}-${height * 0.14}s${width * 0.17} ${height * 0.06} ${width * 0.17} ${height * 0.14}v${height * 0.08}" fill="none" stroke="#f6fbff" stroke-width="${Math.max(5, width * 0.025)}" stroke-linecap="round"/>
</g>`;

const solanaMark = (x, y, size) => {
  const scale = size / 100;
  return `<g transform="translate(${x} ${y}) scale(${scale})" filter="url(#shadow)"><path fill="url(#solana)" d="${solanaMarkPath}"/></g>`;
};

const svg = ({ width, height, titleSize, subtitleSize }) => {
  const isSquare = width === height;
  const deviceW = isSquare ? 260 : 220;
  const deviceH = deviceW * 1.92;
  const deviceX = isSquare ? width / 2 - deviceW / 2 : width * 0.14;
  const deviceY = isSquare ? height * 0.08 : height / 2 - deviceH / 2;
  const titleX = isSquare ? width / 2 : width * 0.47;
  const titleY = isSquare ? height * 0.67 : height * 0.37;
  const markSize = isSquare ? 168 : 140;
  const markX = isSquare ? width / 2 - markSize / 2 : width * 0.78;
  const markY = isSquare ? height * 0.42 : height * 0.24;
  const providerY = isSquare ? height * 0.89 : height * 0.78;
  const maxTextWidth = isSquare ? width * 0.78 : width * 0.52;

  return `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">
<defs>
  <radialGradient id="bg" cx="48%" cy="38%" r="75%"><stop offset="0%" stop-color="#15363a"/><stop offset="48%" stop-color="#071419"/><stop offset="100%" stop-color="#010408"/></radialGradient>
  <linearGradient id="screen" x1="0" x2="1" y1="1" y2="0"><stop offset="0" stop-color="#0f172a"/><stop offset=".45" stop-color="#165a67"/><stop offset="1" stop-color="#19f6b0"/></linearGradient>
  <linearGradient id="solana" x1="0" x2="1" y1="1" y2="0"><stop offset=".08" stop-color="#9945FF"/><stop offset=".42" stop-color="#5497D5"/><stop offset=".97" stop-color="#14F195"/></linearGradient>
  <filter id="shadow" x="-30%" y="-30%" width="160%" height="160%"><feDropShadow dx="0" dy="18" stdDeviation="20" flood-color="#000" flood-opacity=".36"/></filter>
  <style>
    .eyebrow{font-family:"Avenir Next","Helvetica Neue",Arial,sans-serif;font-weight:800;letter-spacing:7px;fill:#7fffe2}
    .title{font-family:"Avenir Next Condensed","Arial Narrow","Helvetica Neue",Arial,sans-serif;font-weight:900;letter-spacing:0;fill:#f8fbff}
    .sub{font-family:"Avenir Next","Helvetica Neue",Arial,sans-serif;font-weight:700;letter-spacing:5px;fill:#cdd7df}
    .foot{font-family:"Avenir Next","Helvetica Neue",Arial,sans-serif;font-weight:800;letter-spacing:8px;fill:#7c8791}
  </style>
</defs>
<rect width="${width}" height="${height}" fill="url(#bg)"/>
<g opacity=".34" fill="#d6f9ff">
  <circle cx="${width * 0.08}" cy="${height * 0.12}" r="2"/><circle cx="${width * 0.2}" cy="${height * 0.82}" r="1.5"/><circle cx="${width * 0.39}" cy="${height * 0.13}" r="1.8"/><circle cx="${width * 0.61}" cy="${height * 0.85}" r="1.8"/><circle cx="${width * 0.86}" cy="${height * 0.18}" r="2"/><circle cx="${width * 0.94}" cy="${height * 0.75}" r="1.5"/>
</g>
${phone(deviceX, deviceY, deviceW, deviceH)}
${solanaMark(markX, markY, markSize)}
<text class="eyebrow" x="${titleX}" y="${titleY - titleSize * 1.25}" text-anchor="${isSquare ? "middle" : "start"}" font-size="${Math.round(subtitleSize * 0.68)}">PUBLIC RC</text>
<text class="title" x="${titleX}" y="${titleY}" text-anchor="${isSquare ? "middle" : "start"}" font-size="${titleSize}" textLength="${maxTextWidth}" lengthAdjust="spacingAndGlyphs">${escapeXML("iOS Wallet Adapter")}</text>
<text class="sub" x="${titleX}" y="${titleY + titleSize * 0.85}" text-anchor="${isSquare ? "middle" : "start"}" font-size="${subtitleSize}">${escapeXML("NATIVE DEEPLINK SIGNING")}</text>
<text class="foot" x="${width / 2}" y="${providerY}" text-anchor="middle" font-size="${Math.round(subtitleSize * 0.62)}">${escapeXML("PHANTOM · SOLFLARE · BACKPACK")}</text>
<text class="foot" x="${width / 2}" y="${providerY + subtitleSize * 1.55}" text-anchor="middle" font-size="${Math.round(subtitleSize * 0.48)}">${escapeXML("0.2.0-rc.1 · SWIFT PACKAGE")}</text>
</svg>`;
};

for (const card of cards) {
  const out = new URL(`./${card.name}.svg`, import.meta.url);
  writeFileSync(out, svg(card));
}
