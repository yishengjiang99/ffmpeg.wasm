#!/bin/bash
# Local equivalent of .github/workflows/core-build.yml: lock check, Docker build, manifest and
# the Chromium smoke test, with no GitHub involved. Needs Docker (buildx) and Node.
#   scripts/ci-local.sh [st|mt ...]        # default: mt st
#   SKIP_BUILD=1 scripts/ci-local.sh mt    # manifest + smoke on the existing packages/core-mt/dist
# Logs go to .ci-local/build-<mode>.log; BuildKit's own layer cache makes rebuilds incremental.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
MODES=${*:-mt st}
LOGS=$ROOT/.ci-local
mkdir -p "$LOGS"

node scripts/check-sources-lock.mjs

# The smoke test drives the cores through this repo's @ffmpeg/ffmpeg (its worker awaits the mt
# core's async exec), so build it first. Needs `npm ci` at the repo root once.
(cd packages/ffmpeg && npm run build >/dev/null) || { echo "packages/ffmpeg build failed (run npm ci at the repo root)" >&2; exit 1; }

for mode in $MODES; do
  case $mode in
    mt) ARGS="--build-arg FFMPEG_MT=yes"; OUT=packages/core-mt; CF="-O3 -msimd128 -pthread" ;;
    st) ARGS="--build-arg FFMPEG_ST=yes"; OUT=packages/core; CF="-O3 -msimd128" ;;
    *) echo "unknown mode: $mode (st|mt)" >&2; exit 2 ;;
  esac
  if [ -z "${SKIP_BUILD:-}" ]; then
    echo "== build $mode -> $OUT ($LOGS/build-$mode.log)"
    start=$(date +%s)
    rm -rf "$OUT/dist"
    # shellcheck disable=SC2086
    docker buildx build --progress=plain $ARGS --build-arg EXTRA_CFLAGS="$CF" -o "$OUT" . > "$LOGS/build-$mode.log" 2>&1 \
      || { tail -n 80 "$LOGS/build-$mode.log"; exit 1; }
    export BUILD_SECONDS=$(( $(date +%s) - start ))
    echo "   built in ${BUILD_SECONDS}s"
  fi
  test -f "$OUT/dist/esm/ffmpeg-core.wasm" || { echo "$OUT/dist/esm/ffmpeg-core.wasm missing" >&2; exit 1; }
  node scripts/build-manifest.mjs "$mode" "$OUT/dist"
  echo "== smoke $mode"
  (cd tests/finalcut-smoke \
    && { [ -d node_modules ] || npm ci --no-audit --no-fund; } \
    && npx playwright install chromium >/dev/null \
    && node smoke.mjs "$mode" "$ROOT/$OUT/dist/esm")
done
