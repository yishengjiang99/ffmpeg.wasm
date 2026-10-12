# Builds the fftools objects that ffmpeg-wasm.sh links (ffmpeg + ffprobe in one module),
# using FFmpeg's own rules so generated sources (e.g. 8.0's fftools/resources) just work.
#   make -f fftools.mk -j all-yes fftools-objs   # libraries + fftools objects
#   make -s -f fftools.mk print-fftools-objs      # object list for the link
include Makefile

FFTOOLS_OBJS := $(sort fftools/cmdutils.o fftools/opt_common.o fftools/ffmpeg.o fftools/ffprobe.o $(OBJS-ffmpeg) $(OBJS-ffprobe))

fftools-objs: $(FFTOOLS_OBJS)
print-fftools-objs:
	@echo $(FFTOOLS_OBJS)
.PHONY: fftools-objs print-fftools-objs
