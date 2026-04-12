'use strict';
// Run once: node server/generate-icons.js
// Generates /icons/icon-192.png and /icons/icon-512.png from ledgerly-logo-1024.png

const fs   = require('fs');
const path = require('path');

const srcLogo = path.join(__dirname, '..', 'ledgerly-logo-1024.png');
const outDir  = path.join(__dirname, '..', 'icons');
if (!fs.existsSync(outDir)) fs.mkdirSync(outDir);

// Try to use sharp if available, otherwise copy and note manual step
try {
  const sharp = require('sharp');
  [192, 512].forEach(size => {
    sharp(srcLogo)
      .resize(size, size)
      .toFile(path.join(outDir, `icon-${size}.png`), (err) => {
        if (err) console.error(`icon-${size}: ${err.message}`);
        else console.log(`Generated icon-${size}.png`);
      });
  });
} catch {
  // sharp not available — copy the 1024 as placeholder
  [192, 512].forEach(size => {
    fs.copyFileSync(srcLogo, path.join(outDir, `icon-${size}.png`));
    console.log(`Copied ledgerly-logo-1024.png as icon-${size}.png (install sharp for proper resize)`);
  });
}
