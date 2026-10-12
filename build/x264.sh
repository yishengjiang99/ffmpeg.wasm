#!/bin/bash

set -euo pipefail

CONF_FLAGS=(
  --prefix=$INSTALL_DIR           # lib installation dir
  --host=x86-gnu                  # use x86 linux host
  --enable-static                 # build static library
  --disable-cli                   # disable cli build
  --disable-asm                   # disable assembly
  --extra-cflags="$CFLAGS"        # add extra cflags
  ${FFMPEG_ST:+ --disable-thread} # disable thread when FFMPEG_ST is defined
)

# The lookahead thread pool calls slicetype_slice_cost through a void *(*)(void *) pointer,
# but it is declared void. Native ABIs tolerate that; WebAssembly traps ("function signature
# mismatch") as soon as there is more than one lookahead thread, i.e. with about 6+ encoder
# threads. Give it the pool's signature.
python3 - <<'PY'
import re
p = 'encoder/slicetype.c'; s = open(p).read()
s, n = re.subn(r'static void (slicetype_slice_cost\( x264_slicetype_slice_t \*s \)\n\{.*?\n)\}', r'static void *\1    return NULL;\n}', s, count=1, flags=re.S)
assert n == 1, 'slicetype_slice_cost not found'
open(p, 'w').write(s)
PY

emconfigure ./configure "${CONF_FLAGS[@]}"
emmake make install-lib-static -j
