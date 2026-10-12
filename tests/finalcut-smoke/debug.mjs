#!/usr/bin/env node
// node debug.mjs <dist/esm dir> <timeoutMs> <hardwareConcurrency|0> -- <ffmpeg args...>
// Runs one ffmpeg command in Chromium against a core build and prints exit code + full log.
// hardwareConcurrency > 0 overrides navigator.hardwareConcurrency in every worker (to
// reproduce another machine's core count).
import { createServer } from 'node:http';
import { createReadStream, existsSync, statSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const sep = process.argv.indexOf('--');
const [coreDir, timeoutMs = '60000', cores = '0'] = process.argv.slice(2, sep);
const args = process.argv.slice(sep + 1);
const TYPES = { '.js': 'text/javascript', '.wasm': 'application/wasm' };
const PAGE = `<!doctype html><script type="module">
import { FFmpeg } from '/node_modules/@ffmpeg/ffmpeg/dist/esm/index.js';
window.run = async (args, timeoutMs) => {
  const ff = new FFmpeg(); const log = [];
  ff.on('log', ({ message }) => log.push(message));
  await ff.load({ coreURL: location.origin + '/core/ffmpeg-core.js', wasmURL: location.origin + '/core/ffmpeg-core.wasm' });
  const t0 = performance.now();
  const exit = await Promise.race([ff.exec(args), new Promise(r => setTimeout(() => r('TIMEOUT'), timeoutMs))]);
  ff.terminate();
  return { exit, ms: Math.round(performance.now() - t0), cores: navigator.hardwareConcurrency, log };
};
window.ready = true;
</script>`;
const server = createServer((req, res) => {
  const p = new URL(req.url, 'http://x').pathname;
  const h = { 'Cross-Origin-Opener-Policy': 'same-origin', 'Cross-Origin-Embedder-Policy': 'require-corp', 'Cross-Origin-Resource-Policy': 'same-origin' };
  if (p === '/') { res.writeHead(200, { ...h, 'Content-Type': 'text/html' }); return res.end(PAGE); }
  const file = p.startsWith('/core/') ? path.join(path.resolve(coreDir), path.basename(p)) : p.startsWith('/node_modules/@ffmpeg/') ? path.join(HERE, p) : null;
  if (!file || !existsSync(file) || !statSync(file).isFile()) { res.writeHead(404, h); return res.end(); }
  res.writeHead(200, { ...h, 'Content-Type': TYPES[path.extname(file)] || 'application/octet-stream' });
  if (Number(cores) > 0 && file.endsWith('.js')) {
    // Prepend the override to every script so module workers and pthread workers see it too.
    res.write(`Object.defineProperty(navigator,'hardwareConcurrency',{get:()=>${Number(cores)},configurable:true});\n`);
  }
  createReadStream(file).pipe(res);
});
await new Promise(r => server.listen(0, '127.0.0.1', r));
const browser = await chromium.launch();
const page = await browser.newPage();
page.on('console', m => console.error('[console]', m.text()));
page.on('pageerror', e => console.error('[pageerror]', e.message));
await page.goto(`http://127.0.0.1:${server.address().port}/`);
await page.waitForFunction(() => window.ready);
const r = await page.evaluate(([a, t]) => window.run(a, t), [args, Number(timeoutMs)]);
await browser.close(); server.close();
console.log(r.log.join('\n'));
console.log(`\nexit=${r.exit} ms=${r.ms} cores=${r.cores}`);
