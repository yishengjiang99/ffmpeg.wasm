const EXPORTED_FUNCTIONS = ["_ffmpeg", "_abort", "_malloc", "_ffprobe"];
// mt core: the tools run on a pthread (runner.c).
if (process.env.FFMPEG_MT) EXPORTED_FUNCTIONS.push("_run_tool_async", "_ffmpeg_cancel");

console.log(EXPORTED_FUNCTIONS.join(","));
