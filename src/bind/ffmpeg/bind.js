/**
 * Constants
 */

const NULL = 0;
const SIZE_I32 = Uint32Array.BYTES_PER_ELEMENT;
const DEFAULT_ARGS = ["./ffmpeg", "-nostdin", "-y"];
const DEFAULT_ARGS_FFPROBE = ["./ffprobe"];

Module["NULL"] = NULL;
Module["SIZE_I32"] = SIZE_I32;
Module["DEFAULT_ARGS"] = DEFAULT_ARGS;
Module["DEFAULT_ARGS_FFPROBE"] = DEFAULT_ARGS_FFPROBE;

/**
 * Variables
 */

Module["ret"] = -1;
Module["timeout"] = -1;
Module["logger"] = () => {};
Module["progress"] = () => {};

/**
 * Functions
 */

function stringToPtr(str) {
  const len = Module["lengthBytesUTF8"](str) + 1;
  const ptr = Module["_malloc"](len);
  Module["stringToUTF8"](str, ptr, len);

  return ptr;
}

function stringsToPtr(strs) {
  const len = strs.length;
  const ptr = Module["_malloc"](len * SIZE_I32);
  for (let i = 0; i < len; i++) {
    Module["setValue"](ptr + SIZE_I32 * i, stringToPtr(strs[i]), "i32");
  }

  return ptr;
}

function print(message) {
  Module["logger"]({ type: "stdout", message });
}

function printErr(message) {
  if (!message.startsWith("Aborted(native code called abort())"))
    Module["logger"]({ type: "stderr", message });
}

/**
 * Runs `_ffmpeg`/`_ffprobe` and records the exit code in Module["ret"].
 *
 * - FFmpeg 5.1's ffmpeg always ends in exit_program() -> abort() after storing the code in
 *   Module.ret (see src/fftools-5.1/cmdutils.c), so the "Aborted" exception is expected.
 * - A normal return (ffprobe, and every FFmpeg 8.0 tool) carries the exit code. Before this
 *   fork ffprobe's return value was dropped and Module.ret stayed -1 on success.
 * - exit() from C throws ExitStatus; its status is the exit code.
 */
function runTool(fn, args) {
  const argv = stringsToPtr(args);
  try {
    Module["ret"] = fn(args.length, argv);
  } catch (e) {
    if (e && e.name === "ExitStatus") {
      Module["ret"] = e.status;
    } else if (!(e && typeof e.message === "string" && e.message.startsWith("Aborted"))) {
      throw e;
    }
  }
  return Module["ret"];
}

/**
 * mt core only: cap the CPU count FFmpeg sizes its automatic thread pools from (decoder frame
 * threads, every filter graph, lavfi inputs). The tools run on the module's main thread, which
 * blocks while a job runs, so a pthread_create beyond PTHREAD_POOL_SIZE can never get its
 * Worker and the job deadlocks. Measured with one x264 encode from two lavfi inputs: passes
 * with 4 cores, hangs with 8, 12 and 14 (tests/finalcut-smoke/debug.mjs emulates core counts).
 * A caller's own -cpucount / -threads comes later on the command line and still wins.
 */
const MT_CPU_COUNT = 4;
function threadArgs() {
  return typeof PThread === "undefined" ? [] : ["-cpucount", String(Math.min(MT_CPU_COUNT, navigator.hardwareConcurrency || MT_CPU_COUNT))];
}

function exec(..._args) {
  const [prog, ...rest] = Module["DEFAULT_ARGS"];
  return runTool(Module["_ffmpeg"], [prog, ...threadArgs(), ...rest, ..._args]);
}

function ffprobe(..._args) {
  const [prog, ...rest] = Module["DEFAULT_ARGS_FFPROBE"];
  return runTool(Module["_ffprobe"], [prog, ...threadArgs(), ...rest, ..._args]);
}

function setLogger(logger) {
  Module["logger"] = logger;
}

function setTimeout(timeout) {
  Module["timeout"] = timeout;
}

function setProgress(handler) {
  Module["progress"] = handler;
}

function receiveProgress(progress, time) {
  Module["progress"]({ progress, time });
}

function reset() {
  Module["ret"] = -1;
  Module["timeout"] = -1;
}

/**
 * In multithread version of ffmpeg.wasm, the bootstrap process is like:
 * 1. Execute ffmpeg-core.js
 * 2. ffmpeg-core.js spawns workers by calling `new Worker("ffmpeg-core.worker.js")`
 * 3. ffmpeg-core.worker.js imports ffmpeg-core.js
 * 4. ffmpeg-core.js imports ffmpeg-core.wasm
 *
 * It is a straightforward process when all files are in the same location.
 * But when files are in different location (or Blob URL), #4 fails because
 * there is no way to pass custom ffmpeg-core.wasm URL to ffmpeg-core.worker.js
 * when it imports ffmpeg-core.js in #3.
 *
 * To fix this issue, a hack here is leveraging mainScriptUrlOrBlob variable by
 * adding wasmURL and workerURL in base64 format as query string. ex:
 *
 *   http://example.com/ffmpeg-core.js#{btoa(JSON.stringify({"wasmURL": "...", "workerURL": "..."}))}
 *
 * Thus, we can successfully extract custom URLs using _locateFile funciton.
 */
function _locateFile(path, prefix) {
  const mainScriptUrlOrBlob = Module["mainScriptUrlOrBlob"];
  if (mainScriptUrlOrBlob) {
    const { wasmURL, workerURL } = JSON.parse(
      atob(mainScriptUrlOrBlob.slice(mainScriptUrlOrBlob.lastIndexOf("#") + 1))
    );
    if (path.endsWith(".wasm")) return wasmURL;
    if (path.endsWith(".worker.js")) return workerURL;
  }
  return prefix + path;
}

Module["stringToPtr"] = stringToPtr;
Module["stringsToPtr"] = stringsToPtr;
Module["print"] = print;
Module["printErr"] = printErr;
Module["locateFile"] = _locateFile;

Module["exec"] = exec;
Module["ffprobe"] = ffprobe;
Module["setLogger"] = setLogger;
Module["setTimeout"] = setTimeout;
Module["setProgress"] = setProgress;
Module["reset"] = reset;
Module["receiveProgress"] = receiveProgress;
