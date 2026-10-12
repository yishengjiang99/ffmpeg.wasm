// Smoke checks for one core build via @ffmpeg/ffmpeg 0.12.15 (the API FinalCut uses).
import { FFmpeg } from '/node_modules/@ffmpeg/ffmpeg/dist/esm/index.js';

let LOG = [];
const withTimeout = (p, ms, what) => Promise.race([p, new Promise((_, rej) => setTimeout(() => rej(new Error(`${what}: timeout ${ms} ms; log tail: ${LOG.slice(-12).join(' | ')}`)), ms))]);

window.smoke = async (mode) => {
  const base = `${location.origin}/core/`;
  const checks = [];
  const check = (name, ok, detail) => checks.push({ name, ok: !!ok, detail });
  const ff = new FFmpeg();
  const log = [];
  LOG = log;
  let progress = 0;
  ff.on('log', ({ message }) => log.push(message));
  ff.on('progress', ({ progress: p }) => { progress = Math.max(progress, p); });
  const t0 = performance.now();
  await ff.load({ coreURL: `${base}ffmpeg-core.js`, wasmURL: `${base}ffmpeg-core.wasm` });
  const loadMs = Math.round(performance.now() - t0);
  check('load', true, { loadMs, crossOriginIsolated });

  log.length = 0;
  const v = await withTimeout(ff.exec(['-version']), 30e3, '-version');
  const version = (log.find(l => /^ffmpeg version/.test(l)) || '').trim();
  check('-version exits 0', v === 0, { exit: v, version });

  const enc = async (out, extra = [], T = mode === 'mt' && out !== 'auto.mp4' ? ['-threads', '4'] : []) => {
    log.length = 0;
    const t = performance.now();
    const code = await withTimeout(ff.exec(['-f', 'lavfi', '-i', 'testsrc2=size=640x360:rate=30:duration=2', '-f', 'lavfi', '-i', 'sine=f=440:d=2', '-c:v', 'libx264', '-preset', 'veryfast', ...T, ...extra, '-c:a', 'aac', '-shortest', out]), 60e3, out);
    let bytes = 0; try { bytes = (await ff.readFile(out)).length; } catch {}
    return { code, bytes, ms: Math.round(performance.now() - t), tail: code === 0 ? undefined : log.slice(-5) };
  };
  const e1 = await enc('a.mp4');
  check('libx264 encode exits 0', e1.code === 0 && e1.bytes > 0, e1);
  check('progress reaches 1', progress >= 0.99, { progress });

  const p1 = await withTimeout(ff.ffprobe(['-v', 'error', '-show_format', '-show_streams', '-of', 'json', 'a.mp4', '-o', 'p.json']), 30e3, 'ffprobe');
  let streams = 0; try { streams = JSON.parse(await ff.readFile('p.json', 'utf8')).streams.length; } catch {}
  check('ffprobe exits 0 on success', p1 === 0 && streams === 2, { exit: p1, streams });
  const p2 = await withTimeout(ff.ffprobe(['-v', 'error', 'missing.mp4']), 30e3, 'ffprobe missing');
  check('ffprobe exits non-zero on a missing file', p2 !== 0 && p2 !== -1, { exit: p2 });

  const bad = await withTimeout(ff.exec(['-i', 'missing.mp4', 'x.mp4']), 30e3, 'bad input');
  check('ffmpeg exits non-zero on a missing input', bad !== 0, { exit: bad });

  // Re-entry: the exit/re-entry patches must let one instance run many jobs.
  const runs = [];
  for (let i = 0; i < 15; i++) { const r = await enc(`r${i}.mp4`); runs.push(r.code); await ff.deleteFile(`r${i}.mp4`).catch(() => {}); if (r.code !== 0) break; }
  check('15 encodes in one instance', runs.length === 15 && runs.every(c => c === 0), { runs });

  // x264 choosing its own thread count: hung on core-mt 0.12.10; trapped with 6+ threads until
  // slicetype_slice_cost got the thread pool's signature (build/x264.sh).
  if (mode === 'mt') {
    const a = await enc('auto.mp4').catch(e => ({ code: -1, error: String(e && e.message || e) }));
    const many = await withTimeout(ff.exec(['-f', 'lavfi', '-i', 'testsrc2=size=640x360:rate=30:duration=2', '-c:v', 'libx264', '-preset', 'veryfast', '-threads', '16', 't16.mp4']), 60e3, 'threads 16').catch(e => String(e && e.message || e));
    check('x264 with automatic threads and with -threads 16', a.code === 0 && many === 0, { auto: a, threads16: many });
  }
  ff.terminate();
  return { mode, version, loadMs, encodeMs: e1.ms, checks };
};
window.smokeReady = true;
