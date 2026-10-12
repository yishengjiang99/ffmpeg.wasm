#!/bin/bash
# Build a core without Docker, with an activated emsdk matching build/sources.lock.json
# (source /path/to/emsdk/emsdk_env.sh). Mirrors the Dockerfile; for iterating on the build
# scripts. CI (Docker) remains the reference build.
#   scripts/build-local.sh st|mt [workdir] [lib ...]   # default: all libs, then ffmpeg + link
set -euo pipefail
MODE=$1; WORK=${2:-$PWD/.build-local}/$MODE; shift $(( $# >= 2 ? 2 : 1 ))
ROOT=$(cd "$(dirname "$0")/.." && pwd)
LOCK=$ROOT/build/sources.lock.json
want=$(node -p "require('$LOCK').toolchain.tag"); have=$(emcc --version | head -1 | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' | head -1)
[ "$want" = "$have" ] || { echo "emsdk $have active, lock wants $want" >&2; exit 1; }
export INSTALL_DIR=$WORK/opt
if [ "$MODE" = mt ]; then export FFMPEG_MT=yes FFMPEG_ST=; EXTRA_CFLAGS=${EXTRA_CFLAGS:--O3 -msimd128 -pthread}; else export FFMPEG_ST=yes FFMPEG_MT=; EXTRA_CFLAGS=${EXTRA_CFLAGS:--O3 -msimd128}; fi
export CFLAGS="-I$INSTALL_DIR/include $EXTRA_CFLAGS" CXXFLAGS="-I$INSTALL_DIR/include $EXTRA_CFLAGS"
export LDFLAGS="-L$INSTALL_DIR/lib $CFLAGS ${EXTRA_LDFLAGS:-}"
export EM_PKG_CONFIG_PATH=$INSTALL_DIR/lib/pkgconfig:$EMSDK/upstream/emscripten/system/lib/pkgconfig
export EM_TOOLCHAIN_FILE=$EMSDK/upstream/emscripten/cmake/Modules/Platform/Emscripten.cmake
export PKG_CONFIG_PATH=$EM_PKG_CONFIG_PATH
mkdir -p "$WORK/dl" "$INSTALL_DIR"
fetch() { # url sha256 dest
  local f=$WORK/dl/$2; [ -f "$f" ] || curl -sSfL -o "$f" "$1"
  echo "$2  $f" | sha256sum -c --quiet - || { rm -f "$f"; echo "checksum mismatch: $1" >&2; exit 1; }
  rm -rf "$3"; mkdir -p "$3"; tar xf "$f" -C "$3" --strip-components=1
}
LIBS=${*:-x264 x265 libvpx lame ogg theora opus vorbis zlib libwebp freetype2 fribidi harfbuzz libass zimg ffmpeg}
for lib in $LIBS; do
  log=$WORK/$lib.log; echo "== $lib ($log)"
  if [ "$lib" = ffmpeg ]; then
    read -r url sha tools < <(node -p "const f=require('$LOCK').ffmpeg['$MODE']; [f.url,f.sha256,f.fftools].join(' ')")
    fetch "$url" "$sha" "$WORK/src/ffmpeg"
    cp -a "$ROOT/$tools/." "$WORK/src/ffmpeg/fftools/"
    cp "$ROOT/build/ffmpeg.sh" "$WORK/src/ffmpeg/build.sh"; cp "$ROOT/build/fftools.mk" "$WORK/src/ffmpeg/"
    extra=; [ "$MODE" = mt ] && extra=--disable-resource-compression
    (cd "$WORK/src/ffmpeg" && bash -x ./build.sh --enable-gpl --enable-libx264 --enable-libx265 --enable-libvpx --enable-libmp3lame \
      --enable-libtheora --enable-libvorbis --enable-libopus --enable-zlib --enable-libwebp --enable-libfreetype --enable-libfribidi \
      --enable-libass --enable-libzimg $extra) > "$log" 2>&1 || { tail -40 "$log"; exit 1; }
    D=$WORK/src/ffmpeg; rm -rf "$D/src" "$D/dist"; mkdir -p "$D/src" "$D/dist/umd" "$D/dist/esm"; cp -a "$ROOT/src/bind" "$D/src/"
    LIBSF="-lx264 -lx265 -lvpx -lmp3lame -logg -ltheora -lvorbis -lvorbisenc -lvorbisfile -lopus -lz -lwebpmux -lwebp -lsharpyuv -lfreetype -lfribidi -lharfbuzz -lass -lzimg"
    (cd "$D" && bash -x "$ROOT/build/ffmpeg-wasm.sh" $LIBSF -o dist/umd/ffmpeg-core.js && bash -x "$ROOT/build/ffmpeg-wasm.sh" $LIBSF -sEXPORT_ES6 -o dist/esm/ffmpeg-core.js) >> "$log" 2>&1 || { tail -40 "$log"; exit 1; }
    ls -la "$D/dist/esm"
  else
    read -r url sha < <(node -p "const c=require('$LOCK').components.find(c=>c.id==='$lib'); [c.url,c.sha256].join(' ')")
    fetch "$url" "$sha" "$WORK/src/$lib"
    cp "$ROOT/build/$lib.sh" "$WORK/src/$lib/build.sh"
    (cd "$WORK/src/$lib" && bash -x ./build.sh) > "$log" 2>&1 || { tail -40 "$log"; exit 1; }
  fi
done
