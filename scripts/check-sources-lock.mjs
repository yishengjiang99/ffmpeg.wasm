#!/usr/bin/env node
// Fails if the Dockerfile and build/sources.lock.json disagree: every locked url must be ADDed
// with its sha256, the emsdk image must be pinned by digest, and no unpinned git ADD remains.
import { readFileSync } from 'node:fs';

const lock = JSON.parse(readFileSync(new URL('../build/sources.lock.json', import.meta.url)));
const df = readFileSync(new URL('../Dockerfile', import.meta.url), 'utf8');
const problems = [];
const tc = lock.toolchain;
if (!df.includes(`FROM ${tc.image}:${tc.tag}@${tc.digest}`)) problems.push(`toolchain ${tc.image}:${tc.tag}@${tc.digest} not in Dockerfile`);
const entries = [...lock.components, ...Object.values(lock.ffmpeg)];
for (const c of entries) {
  if (!/^[0-9a-f]{64}$/.test(c.sha256)) problems.push(`${c.id || c.tag}: bad sha256`);
  if (!df.includes(`ADD --checksum=sha256:${c.sha256} ${c.url} `)) problems.push(`${c.id || c.tag}: ADD --checksum line missing for ${c.url}`);
  if (c.commit && !/^[0-9a-f]{40}$/.test(c.commit)) problems.push(`${c.id || c.tag}: commit not a full sha`);
}
const adds = [...df.matchAll(/^ADD (.*)$/gm)].map(m => m[1]);
for (const a of adds) if (!a.startsWith('--checksum=sha256:')) problems.push(`unpinned ADD: ${a}`);
if (/git clone/.test(df)) problems.push('git clone in Dockerfile (unpinned)');
if (adds.length !== entries.length) problems.push(`Dockerfile has ${adds.length} ADDs, lock has ${entries.length} entries`);
if (problems.length) { console.error(problems.join('\n')); process.exit(1); }
console.log(`sources lock OK: ${entries.length} inputs pinned, toolchain ${tc.tag}@${tc.digest.slice(0, 19)}…`);
