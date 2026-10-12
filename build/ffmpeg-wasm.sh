#!/bin/bash
# `-o <OUTPUT_FILE_NAME>` must be provided when using this build script.
# ex:
#     bash ffmpeg-wasm.sh -o ffmpeg.js

set -euo pipefail

EXPORT_NAME="createFFmpegCore"

CONF_FLAGS=(
  -I. 
  -I./fftools 
  -I$INSTALL_DIR/include 
  -L$INSTALL_DIR/lib 
  -Llibavcodec 
  -Llibavdevice 
  -Llibavfilter 
  -Llibavformat 
  -Llibavutil 
  -Llibswresample 
  -Llibswscale 
  -lavcodec 
  -lavdevice 
  -lavfilter 
  -lavformat 
  -lavutil 
  $([ -f libpostproc/libpostproc.a ] && echo -Llibpostproc -lpostproc || true)  # FFmpeg <= 7.1 only (removed in 8.0)
  -lswresample 
  -lswscale 
  -Wno-deprecated-declarations 
  $LDFLAGS 
  -sENVIRONMENT=worker
  -sWASM_BIGINT                            # enable big int support (default since emsdk 4)
  -sSTACK_SIZE=5MB                         # increase stack size to support libopus
  -sMODULARIZE                             # modularized to use as a library
  ${FFMPEG_MT:+ -sINITIAL_MEMORY=1024MB}   # ALLOW_MEMORY_GROWTH is not recommended when using threads, thus we use a large initial memory
  ${FFMPEG_MT:+ -sPTHREAD_POOL_SIZE=32}    # use 32 threads
  ${FFMPEG_MT:+ -sPTHREAD_POOL_SIZE_STRICT=0} # more threads than the pool are fine: the tool runs on a pthread (runner.c), so the main thread can start them
  ${FFMPEG_ST:+ -sINITIAL_MEMORY=32MB -sALLOW_MEMORY_GROWTH} # Use just enough memory as memory usage can grow
  -sEXPORT_NAME="$EXPORT_NAME"             # required in browser env, so that user can access this module from window object
  -sEXPORTED_FUNCTIONS=$(node src/bind/ffmpeg/export.js) # exported functions
  -sEXPORTED_RUNTIME_METHODS=$(node src/bind/ffmpeg/export-runtime.js) # exported built-in functions
  -lworkerfs.js
  --pre-js src/bind/ffmpeg/bind.js        # extra bindings, contains most of the ffmpeg.wasm javascript code
  # patched fftools (src/fftools-5.1 or src/fftools-8.0), compiled by FFmpeg's build (fftools.mk)
  $(make -s -f fftools.mk print-fftools-objs)
  ${FFMPEG_MT:+ src/bind/ffmpeg/runner.c}
)

emcc "${CONF_FLAGS[@]}" $@
