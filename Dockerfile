# syntax=docker/dockerfile:1.10
# ffmpeg.wasm core build (FinalCut fork). Every input is pinned by commit/tarball + sha256 in
# build/sources.lock.json; `node scripts/check-sources-lock.mjs` verifies this file matches it.
#
#   docker buildx build --build-arg FFMPEG_MT=yes -o packages/core-mt .   # FFmpeg 8.0.1, pthreads
#   docker buildx build --build-arg FFMPEG_ST=yes -o packages/core .      # FFmpeg 5.1.10, no threads
#
# Why two FFmpeg versions: since FFmpeg 6.1 the ffmpeg CLI itself is multithreaded
# (configure: ffmpeg_deps="... threads"), so a no-pthreads (non-crossOriginIsolated) core can
# only carry the 5.1 CLI. See docs/DECISIONS-finalcut.md.

# Global build args (used in FROM below to pick the FFmpeg version).
ARG FFMPEG_ST
ARG FFMPEG_MT

# Base emsdk image with environment variables.
FROM emscripten/emsdk:4.0.23@sha256:86537645c51e44899812d29820ee3b64b96c321ebb2aba4416a04ceeb1bcde62 AS emsdk-base
ARG EXTRA_CFLAGS
ARG EXTRA_LDFLAGS
ARG FFMPEG_ST
ARG FFMPEG_MT
ENV INSTALL_DIR=/opt
ENV CFLAGS="-I$INSTALL_DIR/include $CFLAGS $EXTRA_CFLAGS"
ENV CXXFLAGS="$CFLAGS"
ENV LDFLAGS="-L$INSTALL_DIR/lib $LDFLAGS $CFLAGS $EXTRA_LDFLAGS"
ENV EM_PKG_CONFIG_PATH=$EM_PKG_CONFIG_PATH:$INSTALL_DIR/lib/pkgconfig:/emsdk/upstream/emscripten/system/lib/pkgconfig
ENV EM_TOOLCHAIN_FILE=$EMSDK/upstream/emscripten/cmake/Modules/Platform/Emscripten.cmake
ENV PKG_CONFIG_PATH=$PKG_CONFIG_PATH:$EM_PKG_CONFIG_PATH
ENV FFMPEG_ST=$FFMPEG_ST
ENV FFMPEG_MT=$FFMPEG_MT
RUN apt-get update && \
      apt-get install -y pkg-config autoconf automake libtool ragel xz-utils

# x264: https://code.videolan.org/videolan/x264 @ stable (b35605ace3ddf7c1a5d67a2eb553f034aef41d55), upstream (was ffmpegwasm/x264 4-cores)
FROM emsdk-base AS x264-builder
ADD --checksum=sha256:cd71a7515b0e9a012e1ac9b1f8415bebcaf6fc97d4db32286642ac4c0fbe24f9 https://code.videolan.org/videolan/x264/-/archive/b35605ace3ddf7c1a5d67a2eb553f034aef41d55/x264-b35605ace3ddf7c1a5d67a2eb553f034aef41d55.tar.gz /tmp/src.tar.gz
RUN mkdir -p /src && tar xzf /tmp/src.tar.gz -C /src --strip-components=1 && rm /tmp/src.tar.gz
COPY build/x264.sh /src/build.sh
RUN bash -x /src/build.sh

# x265: https://github.com/ffmpegwasm/x265 @ 3.4 (2bb5520e9596f361bf0ed81b3b8da0d7fd999069)
FROM emsdk-base AS x265-builder
ADD --checksum=sha256:e5254828f5db7bc375d385e31247861d25facee87b43fa2d08ea3ab5569672ab https://codeload.github.com/ffmpegwasm/x265/tar.gz/2bb5520e9596f361bf0ed81b3b8da0d7fd999069 /tmp/src.tar.gz
RUN mkdir -p /src && tar xzf /tmp/src.tar.gz -C /src --strip-components=1 && rm /tmp/src.tar.gz
COPY build/x265.sh /src/build.sh
RUN bash -x /src/build.sh

# libvpx: https://github.com/ffmpegwasm/libvpx @ v1.13.1 (10b9492dcf05b652e2e4b370e205bd605d421972)
FROM emsdk-base AS libvpx-builder
ADD --checksum=sha256:12181ed27342415e8b01bf09abfbf1dfa27a6a32f302fb78b48bd70efe50f702 https://codeload.github.com/ffmpegwasm/libvpx/tar.gz/10b9492dcf05b652e2e4b370e205bd605d421972 /tmp/src.tar.gz
RUN mkdir -p /src && tar xzf /tmp/src.tar.gz -C /src --strip-components=1 && rm /tmp/src.tar.gz
COPY build/libvpx.sh /src/build.sh
RUN bash -x /src/build.sh

# lame: https://github.com/ffmpegwasm/lame @ master (2badea1974ae36cb8312afe99cff1e6b3b5decee)
FROM emsdk-base AS lame-builder
ADD --checksum=sha256:0d97ba0776988f5730e0ce1fa936e7c5d6836c757993ba55073513fe89cf410a https://codeload.github.com/ffmpegwasm/lame/tar.gz/2badea1974ae36cb8312afe99cff1e6b3b5decee /tmp/src.tar.gz
RUN mkdir -p /src && tar xzf /tmp/src.tar.gz -C /src --strip-components=1 && rm /tmp/src.tar.gz
COPY build/lame.sh /src/build.sh
RUN bash -x /src/build.sh

# ogg: https://github.com/ffmpegwasm/Ogg @ v1.3.4 (bada45718453ac27b56773ae663f7e65112f6a6e)
FROM emsdk-base AS ogg-builder
ADD --checksum=sha256:4d61f8dfa248276c42bd5404b1a87ae9d8a0d58791f55e20018c7b39b38d8823 https://codeload.github.com/ffmpegwasm/Ogg/tar.gz/bada45718453ac27b56773ae663f7e65112f6a6e /tmp/src.tar.gz
RUN mkdir -p /src && tar xzf /tmp/src.tar.gz -C /src --strip-components=1 && rm /tmp/src.tar.gz
COPY build/ogg.sh /src/build.sh
RUN bash -x /src/build.sh

# theora: https://github.com/ffmpegwasm/theora @ v1.1.1 (7ffd8b2ecfc2d93ae5e16028e7528e609266bfbf)
FROM emsdk-base AS theora-builder
COPY --from=ogg-builder $INSTALL_DIR $INSTALL_DIR
ADD --checksum=sha256:c38e6a3fb19566a44dcb283323c48311dd484f1416f3f34676d3e7fd252dfbc5 https://codeload.github.com/ffmpegwasm/theora/tar.gz/7ffd8b2ecfc2d93ae5e16028e7528e609266bfbf /tmp/src.tar.gz
RUN mkdir -p /src && tar xzf /tmp/src.tar.gz -C /src --strip-components=1 && rm /tmp/src.tar.gz
COPY build/theora.sh /src/build.sh
RUN bash -x /src/build.sh

# opus: https://github.com/ffmpegwasm/opus @ v1.3.1 (e85ed7726db5d677c9c0677298ea0cb9c65bdd23)
FROM emsdk-base AS opus-builder
ADD --checksum=sha256:c6d574b17d70b8c289d997a8ac81314cf1fd8c52237c421b2ee34e69cea85bf8 https://codeload.github.com/ffmpegwasm/opus/tar.gz/e85ed7726db5d677c9c0677298ea0cb9c65bdd23 /tmp/src.tar.gz
RUN mkdir -p /src && tar xzf /tmp/src.tar.gz -C /src --strip-components=1 && rm /tmp/src.tar.gz
COPY build/opus.sh /src/build.sh
RUN bash -x /src/build.sh

# vorbis: https://github.com/ffmpegwasm/vorbis @ v1.3.3 (7798164043197d7e33f02de4353ce2aa5b248225)
FROM emsdk-base AS vorbis-builder
COPY --from=ogg-builder $INSTALL_DIR $INSTALL_DIR
ADD --checksum=sha256:69b87cafe2815d02609886a63b9d4c0b7461e1e2f6ecf3960ede04053da6e96a https://codeload.github.com/ffmpegwasm/vorbis/tar.gz/7798164043197d7e33f02de4353ce2aa5b248225 /tmp/src.tar.gz
RUN mkdir -p /src && tar xzf /tmp/src.tar.gz -C /src --strip-components=1 && rm /tmp/src.tar.gz
COPY build/vorbis.sh /src/build.sh
RUN bash -x /src/build.sh

# zlib: https://github.com/ffmpegwasm/zlib @ v1.2.11 (cacf7f1d4e3d44d871b605da3b647f07d718623f)
FROM emsdk-base AS zlib-builder
ADD --checksum=sha256:6d4d6640ca3121620995ee255945161821218752b551a1a180f4215f7d124d45 https://codeload.github.com/ffmpegwasm/zlib/tar.gz/cacf7f1d4e3d44d871b605da3b647f07d718623f /tmp/src.tar.gz
RUN mkdir -p /src && tar xzf /tmp/src.tar.gz -C /src --strip-components=1 && rm /tmp/src.tar.gz
COPY build/zlib.sh /src/build.sh
RUN bash -x /src/build.sh

# libwebp: https://github.com/ffmpegwasm/libwebp @ v1.3.2 (ca332209cb5567c9b249c86788cb2dbf8847e760)
FROM emsdk-base AS libwebp-builder
COPY --from=zlib-builder $INSTALL_DIR $INSTALL_DIR
ADD --checksum=sha256:1676107dc385f9bf6cb4c2b94d4a9359d1fd95ab6309cb587191a742df292fe2 https://codeload.github.com/ffmpegwasm/libwebp/tar.gz/ca332209cb5567c9b249c86788cb2dbf8847e760 /tmp/src.tar.gz
RUN mkdir -p /src && tar xzf /tmp/src.tar.gz -C /src --strip-components=1 && rm /tmp/src.tar.gz
COPY build/libwebp.sh /src/build.sh
RUN bash -x /src/build.sh

# freetype2: https://github.com/ffmpegwasm/freetype2 @ VER-2-10-4 (6a2b3e4007e794bfc6c91030d0ed987f925164a8)
FROM emsdk-base AS freetype2-builder
ADD --checksum=sha256:09acceb42508c65b7b744cc2ad01d7548868ca57babc39f7683ec3c0f7541e8c https://codeload.github.com/ffmpegwasm/freetype2/tar.gz/6a2b3e4007e794bfc6c91030d0ed987f925164a8 /tmp/src.tar.gz
RUN mkdir -p /src && tar xzf /tmp/src.tar.gz -C /src --strip-components=1 && rm /tmp/src.tar.gz
COPY build/freetype2.sh /src/build.sh
RUN bash -x /src/build.sh

# fribidi: https://github.com/fribidi/fribidi @ v1.0.9 (f9e8e71a6fbf4a4619481284c9f484d10e559995)
FROM emsdk-base AS fribidi-builder
ADD --checksum=sha256:65ff6fb1a478c4d90ae16825da8c97b8a63e2674f8a2d6dae8800f89089640ba https://codeload.github.com/fribidi/fribidi/tar.gz/f9e8e71a6fbf4a4619481284c9f484d10e559995 /tmp/src.tar.gz
RUN mkdir -p /src && tar xzf /tmp/src.tar.gz -C /src --strip-components=1 && rm /tmp/src.tar.gz
COPY build/fribidi.sh /src/build.sh
RUN bash -x /src/build.sh

# harfbuzz: https://github.com/harfbuzz/harfbuzz @ 5.2.0 (4a1d891c6317d2c83e5f3c2607ec5f5ccedffcde)
FROM emsdk-base AS harfbuzz-builder
ADD --checksum=sha256:69ba7c7a42643a3654781242016dd09245cab7353fc2a02cecb710e479c9a881 https://codeload.github.com/harfbuzz/harfbuzz/tar.gz/4a1d891c6317d2c83e5f3c2607ec5f5ccedffcde /tmp/src.tar.gz
RUN mkdir -p /src && tar xzf /tmp/src.tar.gz -C /src --strip-components=1 && rm /tmp/src.tar.gz
COPY build/harfbuzz.sh /src/build.sh
RUN bash -x /src/build.sh

# libass: https://github.com/libass/libass @ 0.15.0 (d149636f502f5774ae1a8fb4c554b122674393b2)
FROM emsdk-base AS libass-builder
COPY --from=freetype2-builder $INSTALL_DIR $INSTALL_DIR
COPY --from=fribidi-builder $INSTALL_DIR $INSTALL_DIR
COPY --from=harfbuzz-builder $INSTALL_DIR $INSTALL_DIR
ADD --checksum=sha256:5cfe23562fa623a3b209d156ad469aeb2e31f69bf6b256ea737d87d9ed89301d https://codeload.github.com/libass/libass/tar.gz/d149636f502f5774ae1a8fb4c554b122674393b2 /tmp/src.tar.gz
RUN mkdir -p /src && tar xzf /tmp/src.tar.gz -C /src --strip-components=1 && rm /tmp/src.tar.gz
COPY build/libass.sh /src/build.sh
RUN bash -x /src/build.sh

# zimg: https://github.com/sekrit-twc/zimg @ release-3.0.5 (e5b0de6bebbcbc66732ed5afaafef6b2c7dfef87)
FROM emsdk-base AS zimg-builder
ADD --checksum=sha256:3ab062eff30067799997bc3e911c0108a5b8cbcd6e0ef14053f17ff0ecd0add8 https://codeload.github.com/sekrit-twc/zimg/tar.gz/e5b0de6bebbcbc66732ed5afaafef6b2c7dfef87 /tmp/src.tar.gz
RUN mkdir -p /src && tar xzf /tmp/src.tar.gz -C /src --strip-components=1 && rm /tmp/src.tar.gz
COPY build/zimg.sh /src/build.sh
RUN bash -x /src/build.sh

# FFmpeg sources: n5.1.10 for st, n8.0.1 for mt.
FROM emsdk-base AS ffmpeg-src-st
ADD --checksum=sha256:392306d6fc45dab0e9e0ea55381e071842e83a2fb31d320aeda40477a7766293 https://ffmpeg.org/releases/ffmpeg-5.1.10.tar.xz /tmp/ffmpeg.tar.xz
RUN mkdir -p /src && tar xJf /tmp/ffmpeg.tar.xz -C /src --strip-components=1 && rm /tmp/ffmpeg.tar.xz
COPY src/fftools-5.1 /src/fftools-wasm
ENV FFMPEG_EXTRA_CONF=""

FROM emsdk-base AS ffmpeg-src-mt
ADD --checksum=sha256:05ee0b03119b45c0bdb4df654b96802e909e0a752f72e4fe3794f487229e5a41 https://ffmpeg.org/releases/ffmpeg-8.0.1.tar.xz /tmp/ffmpeg.tar.xz
RUN mkdir -p /src && tar xJf /tmp/ffmpeg.tar.xz -C /src --strip-components=1 && rm /tmp/ffmpeg.tar.xz
COPY src/fftools-8.0 /src/fftools-wasm
# drawtext needs libharfbuzz since FFmpeg 6.1 (harfbuzz is already built for libass).
ENV FFMPEG_EXTRA_CONF="--disable-resource-compression --enable-libharfbuzz"

FROM ffmpeg-src-${FFMPEG_MT:+mt}${FFMPEG_ST:+st} AS ffmpeg-base
# The patched fftools replace FFmpeg's own (only the files we carry; the build system's
# Makefiles stay FFmpeg's).
RUN cp -a /src/fftools-wasm/. /src/fftools/ && rm -rf /src/fftools-wasm
COPY --from=x264-builder $INSTALL_DIR $INSTALL_DIR
COPY --from=x265-builder $INSTALL_DIR $INSTALL_DIR
COPY --from=libvpx-builder $INSTALL_DIR $INSTALL_DIR
COPY --from=lame-builder $INSTALL_DIR $INSTALL_DIR
COPY --from=ogg-builder $INSTALL_DIR $INSTALL_DIR
COPY --from=theora-builder $INSTALL_DIR $INSTALL_DIR
COPY --from=opus-builder $INSTALL_DIR $INSTALL_DIR
COPY --from=vorbis-builder $INSTALL_DIR $INSTALL_DIR
COPY --from=zlib-builder $INSTALL_DIR $INSTALL_DIR
COPY --from=libwebp-builder $INSTALL_DIR $INSTALL_DIR
COPY --from=freetype2-builder $INSTALL_DIR $INSTALL_DIR
COPY --from=fribidi-builder $INSTALL_DIR $INSTALL_DIR
COPY --from=harfbuzz-builder $INSTALL_DIR $INSTALL_DIR
COPY --from=libass-builder $INSTALL_DIR $INSTALL_DIR
COPY --from=zimg-builder $INSTALL_DIR $INSTALL_DIR

# Build ffmpeg libraries and the (patched) fftools objects
FROM ffmpeg-base AS ffmpeg-builder
COPY build/ffmpeg.sh /src/build.sh
COPY build/fftools.mk /src/fftools.mk
RUN bash -x /src/build.sh \
      --enable-gpl \
      --enable-libx264 \
      --enable-libx265 \
      --enable-libvpx \
      --enable-libmp3lame \
      --enable-libtheora \
      --enable-libvorbis \
      --enable-libopus \
      --enable-zlib \
      --enable-libwebp \
      --enable-libfreetype \
      --enable-libfribidi \
      --enable-libass \
      --enable-libzimg \
      $FFMPEG_EXTRA_CONF

# Build ffmpeg.wasm
FROM ffmpeg-builder AS ffmpeg-wasm-builder
COPY src/bind /src/src/bind
COPY build/ffmpeg-wasm.sh build.sh
# libraries to link
ENV FFMPEG_LIBS="-lx264 -lx265 -lvpx -lmp3lame -logg -ltheora -lvorbis -lvorbisenc -lvorbisfile -lopus -lz -lwebpmux -lwebp -lsharpyuv -lfreetype -lfribidi -lharfbuzz -lass -lzimg"
RUN mkdir -p /src/dist/umd && bash -x /src/build.sh \
      ${FFMPEG_LIBS} \
      -o dist/umd/ffmpeg-core.js
RUN mkdir -p /src/dist/esm && bash -x /src/build.sh \
      ${FFMPEG_LIBS} \
      -sEXPORT_ES6 \
      -o dist/esm/ffmpeg-core.js
RUN (emcc --version | head -1; echo; grep -m1 FFMPEG_CONFIGURATION config.h; echo; cat VERSION RELEASE 2>/dev/null) > dist/build-info.txt

# Export dist/, use `docker buildx build -o . .` to get assets
FROM scratch AS exportor
COPY --from=ffmpeg-wasm-builder /src/dist /dist
