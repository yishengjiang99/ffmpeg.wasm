# FinalCut fork: decisions and adoption notes

This fork builds the ffmpeg.wasm cores that FinalCut's browser editor runs. It keeps the
`@ffmpeg/ffmpeg` 0.12 message API and changes the cores underneath. Releases are tarballs on
GitHub releases; nothing is published to npm.

## Build and test (all local, no GitHub Actions)

```sh
npm ci                      # once, for packages/ffmpeg
scripts/ci-local.sh         # lock check, Docker build of mt + st, manifest, Chromium smoke test
scripts/pack-local.sh       # .ci-local/packs/*.tgz for a GitHub release
node tests/finalcut-smoke/debug.mjs packages/core-mt/dist/esm 30000 8 -- -i ...   # one command, emulating 8 cores
```

`core-build.yml` is manual-only. Run the smoke test on a machine with 8 or more cores: the
thread bugs below never showed on 4-vCPU runners. The full browser bench (Chromium, WebKit,
Firefox) lives in the FinalCut repo: `tests/bench/run-local.sh <label> --core-root packages`.

## Decisions

1. **Two FFmpeg versions.** mt is FFmpeg 8.0.1. st stays on 5.1.10, because since FFmpeg 6.1
   the `ffmpeg` CLI itself needs threads, so a core for non-isolated pages can only carry the
   5.1 CLI. The st core was not dropped. Consequence: the two cores have different filter and
   codec catalogs, so FinalCut needs one capability catalog per core.
2. **The tool runs on its own pthread (mt).** `exec`/`ffprobe` return a Promise inside the core,
   so the module's main thread stays free to start Workers. Before, any job needing more
   threads than the pool deadlocked (8+ core machines, multi-input graphs). FinalCut must use
   this repo's `@ffmpeg/ffmpeg` with the mt core; the npm 0.12.15 wrapper would return before
   the job ends.
3. **Mailbox wakeups use postMessage outside Chromium.** With `Atomics.waitAsync`, Playwright
   WebKit hung intermittently mid-job once the tool ran on a pthread.
4. **Growable mt heap**: 256 MB initial, 4 GB max, pool of 4 pre-spawned Workers. No measurable
   cost against the fixed 1 GB heap and 32 Workers.
5. **Upstream x264** (videolan stable) replaces ffmpegwasm's `4-cores` fork, with one patch:
   `slicetype_slice_cost` gets the thread pool's signature. Without it WebAssembly traps as soon
   as x264 uses more than one lookahead thread (about 6+ encoder threads).
6. **`-cpucount 4` default on mt.** FFmpeg sizes decoder and filter thread pools from the CPU
   count and more of them did not make the bench faster, only bigger (3-clip 720p join: 0.9 GB
   heap at 4, 1.3 GB at 14). It does not limit x264: pass `-threads N` (or nothing, for
   x264's own choice) and the encoder scales. A caller's own `-cpucount` wins.
7. **Source patches are in the build scripts**, so the recipe plus `build/sources.lock.json`
   is the complete corresponding source: `build/ffmpeg.sh` zeroes `af_vibrato`'s delay line
   (upstream reads it uninitialised), `build/x264.sh` carries the signature fix, and
   `src/fftools-*` are the patched tools.
8. **Not adopted, measured no gain**: `-mrelaxed-simd`; `-fwasm-exceptions` with
   `-sSUPPORT_LONGJMP=wasm`. FFmpeg's own WebAssembly SIMD is enabled (`--arch=wasm32`), but in
   8.0 it only covers HEVC idct and SAO: about 3% on 1080p HEVC decode.
9. **No slimmed core yet.** Dropping x265 alone saves 4.4 MB raw (0.5 MB brotli). A real cut
   needs `--disable-everything` plus a list of what FinalCut keeps, which changes what its
   free-form `run_ffmpeg` tool can do. That is a product decision and is left open. Download
   size is on par with 0.12.10 (mt: 31.9 MB raw, 8.9 MB brotli; 0.12.10: 32.7 / 8.4).

## What FinalCut gets, and what it has to change

API additions in `@ffmpeg/ffmpeg` (everything else is unchanged):

- `ffmpeg.cancel()`: mt only. Stops the running `exec` like one Ctrl-C; `exec` resolves 255 and
  the instance stays loaded. Resolves `false` if nothing was cancelled (idle, ffprobe, st);
  fall back to `terminate()` then.
- `ffmpeg.mount('OPFS', { dir, files }, '/out')`: outputs written to `/out/<file>` go to OPFS
  on disk instead of memory. After `unmount`, read the `File` from
  `navigator.storage.getDirectory()` → `dir` → `file`. Only the listed names can be created.
- A crash on any thread (for example out of memory) now rejects `exec` at once with
  `ffmpeg core crashed: …`. The instance is unusable after that; terminate and reload.
- `ffprobe` returns 0 on success and a real error code on failure.
- No `ffmpeg-core.worker.js`: with emsdk 4 the core script is its own worker. `workerURL` is
  ignored.

Adoption checklist for `src/wasm/ffmpegHost.js` and friends:

1. Depend on the three release tarballs by URL (`@ffmpeg/ffmpeg`, `@ffmpeg/core`,
   `@ffmpeg/core-mt`), update `scripts/copy-ffmpeg-core.mjs` (no worker file) and the version
   constants.
2. Regenerate the capability catalog per core (mt = FFmpeg 8.0.1, st = 5.1.10) and check
   `src/wasm/ops/*` for options renamed since 5.1 on the mt path (`-vsync` → `-fps_mode`,
   channel layout options).
3. Regenerate `vendor/ffmpeg-source.lock.json` and the served source tarballs from
   `build/sources.lock.json` (each core's `dist/manifest.json` lists its exact inputs).
4. Workarounds, each to be removed only with a test that would have caught the original
   failure:
   - `MAX_MT_THREADS = 4`: the smoke test runs x264 with automatic threads and with 16.
   - `RECYCLE_AFTER_RUNS = 12`: the 60-run soak passes on both cores in three browsers.
   - ffprobe exit-code workaround: no longer needed.
   - terminate-on-cancel: use `cancel()` on mt, keep `terminate()` as the last resort and for st.
   - Wall-clock watchdog: keep it. `exec`'s own timeout now works on mt, but a watchdog is
     still the only defence against a hang nobody has found yet.
   - mt → st fallback: keep it.
5. Test on real Safari and on an iPhone. Everything here was measured on Playwright's desktop
   WebKit; whether iOS now loads the mt core with the growable heap is not verified.
