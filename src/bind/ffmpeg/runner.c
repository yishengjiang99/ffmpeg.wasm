/*
 * mt core: run a tool (ffmpeg / ffprobe) on its own pthread.
 *
 * Called on the module's main thread (the @ffmpeg/ffmpeg worker), which returns to its event
 * loop right away. That matters because a pthread_create that finds the pool empty needs the
 * main thread to create the Worker: when the tool itself ran on the main thread and blocked
 * there, any job needing more than PTHREAD_POOL_SIZE threads deadlocked (8+ core machines,
 * multi-input filter graphs). The exit code is delivered to Module.toolExit on the main thread.
 */
#include <errno.h>
#include <pthread.h>
#include <stdlib.h>
#include <emscripten.h>
#include <emscripten/threading.h>

int ffmpeg(int argc, char **argv);
int ffprobe(int argc, char **argv);
int run_tool_async(int tool, int argc, char **argv);
void send_progress(double progress, double time);
int is_timeout(double diff);

/* Called by fftools/ffmpeg.c on the tool thread; the handlers are on the main thread. */
void send_progress(double progress, double time)
{
    MAIN_THREAD_ASYNC_EM_ASM({ Module["receiveProgress"]($0, $1); }, progress, time);
}

int is_timeout(double diff)
{
    return MAIN_THREAD_EM_ASM_INT({
        if (Module["timeout"] === -1) return 0;
        return Module["timeout"] <= $0 ? 1 : 0;
    }, diff);
}

typedef struct Job {
    int (*fn)(int, char **);
    int argc;
    char **argv;
} Job;

static void *tool_thread(void *arg)
{
    Job job = *(Job *)arg;
    int ret;

    free(arg);
    ret = job.fn(job.argc, job.argv);
    MAIN_THREAD_ASYNC_EM_ASM({ Module["toolExit"]($0); }, ret);
    return NULL;
}

/* tool: 0 = ffmpeg, 1 = ffprobe. Returns 0, or an errno if the thread could not be started. */
EMSCRIPTEN_KEEPALIVE
int run_tool_async(int tool, int argc, char **argv)
{
    pthread_attr_t attr;
    pthread_t thread;
    Job *job = malloc(sizeof(*job));
    int err;

    if (!job)
        return ENOMEM;
    job->fn   = tool ? ffprobe : ffmpeg;
    job->argc = argc;
    job->argv = argv;

    pthread_attr_init(&attr);
    pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
    pthread_attr_setstacksize(&attr, 5 * 1024 * 1024); /* as the main thread's STACK_SIZE */
    err = pthread_create(&thread, &attr, tool_thread, job);
    pthread_attr_destroy(&attr);
    if (err)
        free(job);
    return err;
}
