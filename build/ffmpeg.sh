#!/bin/bash

set -euo pipefail

# FFmpeg >= 7.1 knows the wasm arch and carries WebAssembly SIMD128 code (8.0: HEVC idct and
# SAO), which --disable-asm would switch off. Older trees (the st core's 5.1) have neither.
if [ -d libavutil/wasm ]; then
  ARCH_FLAGS=(--arch=wasm32 --disable-inline-asm --disable-x86asm)
else
  ARCH_FLAGS=(--arch=x86_32 --disable-asm)
fi

CONF_FLAGS=(
  --target-os=none              # disable target specific configs
  "${ARCH_FLAGS[@]}"
  --enable-cross-compile        # use cross compile configs
  --disable-stripping           # disable stripping as it won't work
  --enable-ffmpeg --enable-ffprobe --disable-ffplay  # fftools objects are built (fftools.mk), not linked
  --disable-doc                 # disable doc build
  --disable-debug               # disable debug mode
  --disable-runtime-cpudetect   # disable cpu detection
  --disable-autodetect          # disable env auto detect

  # assign toolchains and extra flags
  --nm=emnm
  --ar=emar
  --ranlib=emranlib
  --cc=emcc
  --cxx=em++
  --objcc=emcc
  --dep-cc=emcc
  --extra-cflags="$CFLAGS"
  --extra-cxxflags="$CXXFLAGS"

  # disable thread when FFMPEG_ST is NOT defined
  ${FFMPEG_ST:+ --disable-pthreads --disable-w32threads --disable-os2threads}
)

# af_vibrato allocates its delay line with av_malloc_array and reads it before writing
# (upstream bug, 5.1 through 8.0). Native malloc usually hands back zero pages; in a reused
# wasm heap it is stale data, which turned into NaN samples ("Input contains (near)
# NaN/+-Inf" from the aac encoder) after a few jobs in one instance.
grep -q 's->buf\[c\] = av_malloc_array(s->buf_size, sizeof(\*s->buf\[c\]));' libavfilter/af_vibrato.c
sed -i 's/s->buf\[c\] = av_malloc_array(s->buf_size, sizeof(\*s->buf\[c\]));/s->buf[c] = av_calloc(s->buf_size, sizeof(*s->buf[c]));/' libavfilter/af_vibrato.c

emconfigure ./configure "${CONF_FLAGS[@]}" $@
emmake make -f fftools.mk -j"$(nproc)" all-yes fftools-objs
