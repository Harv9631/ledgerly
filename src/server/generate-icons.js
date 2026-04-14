'use strict';
// Run: node server/generate-icons.js
// Generates green-themed Walify icons for PWA home screen

const fs   = require('fs');
const path = require('path');
const outDir = path.join(__dirname, '..', 'icons');
if (!fs.existsSync(outDir)) fs.mkdirSync(outDir);

// SVG template: green gradient background + bold W
function makeSVG(size) {
  const r = Math.round(size * 0.12); // corner radius
  const fontSize = Math.round(size * 0.52);
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 ${size} ${size}">
  <defs>
    <linearGradient id="bg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#1a4a2e"/>
      <stop offset="100%" stop-color="#0d1117"/>
    </linearGradient>
    <linearGradient id="letter" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#3fb950"/>
      <stop offset="100%" stop-color="#58d68d"/>
    </linearGradient>
  </defs>
  <rect width="${size}" height="${size}" rx="${r}" ry="${r}" fill="url(#bg)"/>
  <text
    x="${size / 2}"
    y="${Math.round(size * 0.72)}"
    font-family="-apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif"
    font-weight="800"
    font-size="${fontSize}"
    text-anchor="middle"
    fill="url(#letter)"
  >W</text>
</svg>`;
}

try {
  const sharp = require('sharp');
  [192, 512].forEach(size => {
    const svg = Buffer.from(makeSVG(size));
    sharp(svg)
      .png()
      .toFile(path.join(outDir, `icon-${size}.png`), (err) => {
        if (err) console.error(`icon-${size}: ${err.message}`);
        else console.log(`Generated icon-${size}.png (${size}x${size} green W)`);
      });
  });
} catch {
  // Fallback: write SVGs directly (browsers accept SVG icons too)
  [192, 512].forEach(size => {
    fs.writeFileSync(path.join(outDir, `icon-${size}.svg`), makeSVG(size));
    console.log(`Written icon-${size}.svg (install sharp for PNG)`);
  });
}
