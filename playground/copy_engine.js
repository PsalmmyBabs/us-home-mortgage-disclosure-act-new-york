// Copy the DuckDB WebAssembly runtime out of node_modules into vendor/.
//
// This is a Node script rather than a `cp` in the npm script because npm runs
// scripts through the platform shell, and cmd.exe has no `cp`. On Windows the
// copy silently did nothing while the bundle step succeeded, leaving a vendor/
// folder with one file out of three and a page that could not start.
//
// The two files are shipped as-is; only duckdb-browser.mjs is bundled, because
// it is the only one with a bare import a browser cannot resolve.
const fs = require('fs');
const path = require('path');

const SRC = path.join('node_modules', '@duckdb', 'duckdb-wasm', 'dist');
const DEST = 'vendor';
const FILES = ['duckdb-eh.wasm', 'duckdb-browser-eh.worker.js'];

fs.mkdirSync(DEST, { recursive: true });

for (const name of FILES) {
  const from = path.join(SRC, name);
  if (!fs.existsSync(from)) {
    console.error(`missing ${from}\nRun npm install first.`);
    process.exit(1);
  }
  fs.copyFileSync(from, path.join(DEST, name));
}

const version = require(path.join(process.cwd(), SRC, '..', 'package.json')).version;
console.log(`vendor/ ready, duckdb-wasm ${version}`);
for (const name of fs.readdirSync(DEST).sort()) {
  const kb = fs.statSync(path.join(DEST, name)).size / 1024;
  console.log(`  ${name.padEnd(32)} ${kb.toFixed(0).padStart(7)} kB`);
}
