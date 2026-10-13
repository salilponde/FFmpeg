/* Fails unless all FFmpeg libraries report LGPLv2.1+ and every codec named
 * on the command line is available. Codecs are given as "enc:<name>" or
 * "dec:<name>". Used by lgpl-shared-libs.yml. */

#include <stdio.h>
#include <string.h>
#include <libavutil/avutil.h>
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavfilter/avfilter.h>
#include <libavdevice/avdevice.h>
#include <libswscale/swscale.h>
#include <libswresample/swresample.h>

int main(int argc, char **argv)
{
    for (int i = 1; i < argc; i++) {
        const char *arg = argv[i];
        const AVCodec *c = NULL;
        if (!strncmp(arg, "enc:", 4))
            c = avcodec_find_encoder_by_name(arg + 4);
        else if (!strncmp(arg, "dec:", 4))
            c = avcodec_find_decoder_by_name(arg + 4);
        if (!c) {
            fprintf(stderr, "missing codec: %s\n", arg);
            return 1;
        }
        printf("codec ok: %s\n", arg);
    }

    const char *lic[] = {
        avutil_license(), avcodec_license(), avformat_license(),
        avfilter_license(), avdevice_license(), swscale_license(),
        swresample_license(),
    };
    for (size_t i = 0; i < sizeof(lic) / sizeof(*lic); i++) {
        printf("%s\n", lic[i]);
        if (strcmp(lic[i], "LGPL version 2.1 or later"))
            return 1;
    }
    printf("configuration: %s\n", avutil_configuration());
    return 0;
}
