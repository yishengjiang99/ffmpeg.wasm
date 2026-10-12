#!/bin/bash
# Packs the three packages FinalCut consumes into installable tarballs (no npm publish):
#   scripts/pack-local.sh            # -> .ci-local/packs/*.tgz + SHA256SUMS
# Run scripts/ci-local.sh first: the cores must be built and smoke-tested, and each dist/
# carries its manifest.json (inputs pinned in build/sources.lock.json + output hashes).
# Attach the tarballs to a GitHub release and depend on them by URL, e.g.
#   "@ffmpeg/core-mt": "https://github.com/<owner>/ffmpeg.wasm/releases/download/<tag>/ffmpeg-core-mt-<version>.tgz"
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=$ROOT/.ci-local/packs
rm -rf "$OUT"; mkdir -p "$OUT"
for p in core core-mt; do
  for f in esm/ffmpeg-core.js esm/ffmpeg-core.wasm umd/ffmpeg-core.js manifest.json; do
    test -f "$ROOT/packages/$p/dist/$f" || { echo "packages/$p/dist/$f missing: run scripts/ci-local.sh" >&2; exit 1; }
  done
done
(cd "$ROOT/packages/ffmpeg" && npm run build >/dev/null)
for p in core core-mt ffmpeg; do
  (cd "$ROOT/packages/$p" && npm pack --ignore-scripts --pack-destination "$OUT" >/dev/null)
done
(cd "$OUT" && shasum -a 256 *.tgz | tee SHA256SUMS && ls -la *.tgz)
