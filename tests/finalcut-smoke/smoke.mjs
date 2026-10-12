#!/usr/bin/env node
// node smoke.mjs <st|mt> <dist/esm dir>  -> prints JSON, exits 1 if a check fails.
import { createServer } from 'node:http';
import { createReadStream, existsSync, statSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const [mode, coreDir] = process.argv.slice(2);
const TYPES = { '.js': 'text/javascript', '.wasm': 'application/wasm', '.html': 'text/html' };
const server = createServer((req, res) => {
  const p = new URL(req.url, 'http://x').pathname;
  const file = p === '/' ? path.join(HERE, 'index.html') : p === '/page.js' ? path.join(HERE, 'page.js')
    : p.startsWith('/core/') ? path.join(path.resolve(coreDir), path.basename(p))
    : p.startsWith('/node_modules/@ffmpeg/') ? path.join(HERE, p) : null;
  const h = { 'Cross-Origin-Opener-Policy': 'same-origin', 'Cross-Origin-Embedder-Policy': 'require-corp', 'Cross-Origin-Resource-Policy': 'same-origin' };
  if (!file || !existsSync(file) || !statSync(file).isFile()) { res.writeHead(404, h); return res.end(); }
  res.writeHead(200, { ...h, 'Content-Type': TYPES[path.extname(file)] || 'application/octet-stream' });
  createReadStream(file).pipe(res);
});
await new Promise(r => server.listen(0, '127.0.0.1', r));
writeFileSync(path.join(HERE, 'index.html'), '<!doctype html><script type="module" src="/page.js"></script>');
const browser = await chromium.launch();
const page = await browser.newPage();
page.on('console', m => { if (m.type() === 'error') console.error('[console]', m.text()); });
await page.goto(`http://127.0.0.1:${server.address().port}/`);
await page.waitForFunction(() => window.smokeReady);
let result;
try { result = await page.evaluate((m) => window.smoke(m), mode); }
catch (e) { result = { mode, checks: [{ name: 'smoke ran', ok: false, detail: String(e.message).split('\n')[0] }] }; }
await browser.close(); server.close();
console.log(JSON.stringify(result, null, 2));
writeFileSync(path.join(HERE, `smoke-${mode}.json`), JSON.stringify(result, null, 2));
const failed = result.checks.filter(c => !c.ok);
for (const c of result.checks) console.error(`${c.ok ? 'PASS' : 'FAIL'} ${c.name}`);
process.exit(failed.length ? 1 : 0);
