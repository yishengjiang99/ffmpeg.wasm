#!/usr/bin/env node
// Writes <dist>/manifest.json for one core build: inputs (from build/sources.lock.json),
// output files with bytes / gzip / brotli / sha256, and the configure + emcc info captured by
// the Dockerfile (dist/build-info.txt).
//   node scripts/build-manifest.mjs <st|mt> <dist dir>
import { createHash } from 'node:crypto';
import { readFileSync, readdirSync, statSync, writeFileSync, existsSync } from 'node:fs';
import { gzipSync, brotliCompressSync, constants } from 'node:zlib';
import { execSync } from 'node:child_process';
import path from 'node:path';

const [mode, dist] = process.argv.slice(2);
if (!['st', 'mt'].includes(mode) || !dist) { console.error('usage: build-manifest.mjs <st|mt> <dist>'); process.exit(2); }
const lock = JSON.parse(readFileSync(new URL('../build/sources.lock.json', import.meta.url)));
const walk = (d) => readdirSync(d).flatMap(n => { const p = path.join(d, n); return statSync(p).isDirectory() ? walk(p) : [p]; });
const files = {};
for (const f of walk(dist).sort()) {
  const rel = path.relative(dist, f);
  if (rel === 'manifest.json') continue;
  const buf = readFileSync(f);
  files[rel] = {
    bytes: buf.length,
    gzipBytes: gzipSync(buf, { level: 9 }).length,
    brotliBytes: brotliCompressSync(buf, { params: { [constants.BROTLI_PARAM_QUALITY]: 11 } }).length,
    sha256: createHash('sha256').update(buf).digest('hex'),
  };
}
const git = (c) => { try { return execSync(`git ${c}`, { encoding: 'utf8' }).trim(); } catch { return null; } };
const info = existsSync(path.join(dist, 'build-info.txt')) ? readFileSync(path.join(dist, 'build-info.txt'), 'utf8') : '';
const manifest = {
  schemaVersion: 1,
  mode,
  package: mode === 'mt' ? '@ffmpeg/core-mt (FinalCut fork build)' : '@ffmpeg/core (FinalCut fork build)',
  recipe: { repository: process.env.GITHUB_SERVER_URL ? `${process.env.GITHUB_SERVER_URL}/${process.env.GITHUB_REPOSITORY}` : null, commit: process.env.GITHUB_SHA || git('rev-parse HEAD'), runId: process.env.GITHUB_RUN_ID || null },
  builtAt: new Date().toISOString(),
  toolchain: lock.toolchain,
  ffmpeg: lock.ffmpeg[mode],
  components: lock.components,
  buildInfo: info,
  files,
};
writeFileSync(path.join(dist, 'manifest.json'), JSON.stringify(manifest, null, 2) + '\n');
for (const [f, v] of Object.entries(files)) console.log(`${f.padEnd(28)} ${String(v.bytes).padStart(10)} B  gz ${String(v.gzipBytes).padStart(9)}  br ${String(v.brotliBytes).padStart(9)}  ${v.sha256.slice(0, 12)}`);
