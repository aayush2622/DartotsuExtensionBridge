
#include <pthread.h>

static pthread_mutex_t dartotsu_run_lock = PTHREAD_MUTEX_INITIALIZER;

int dartotsu_ffmpeg_run(int argc, char **argv)
{
    int ret;
    pthread_mutex_lock(&dartotsu_run_lock);
    received_sigterm = 0;
    received_nb_signals = 0;
    atomic_store(&transcode_init_done, 0);
    ffmpeg_exited = 0;
    copy_ts_first_pts = AV_NOPTS_VALUE;
    atomic_store(&nb_output_dumped, 0);
    nb_input_files = 0;
    nb_output_files = 0;
    nb_filtergraphs = 0;
    nb_decoders = 0;
    ret = dartotsu_ffmpeg_main(argc, argv);
    pthread_mutex_unlock(&dartotsu_run_lock);
    return ret;
}

void dartotsu_ffmpeg_cancel(void)
{
    received_nb_signals++;
    received_sigterm = 15;
}
