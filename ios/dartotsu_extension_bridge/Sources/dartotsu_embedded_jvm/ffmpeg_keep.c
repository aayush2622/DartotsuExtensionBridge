extern int dartotsu_ffmpeg_run(int argc, char **argv) __attribute__((weak_import));
extern void dartotsu_ffmpeg_cancel(void) __attribute__((weak_import));

__attribute__((used)) void *const dartotsu_ffmpeg_keep[] = {
    (void *)dartotsu_ffmpeg_run,
    (void *)dartotsu_ffmpeg_cancel,
};
