// Copyright (c) 2025 by Rockchip Electronics Co., Ltd. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

/*-------------------------------------------
                Includes
-------------------------------------------*/
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>
#include <vector>
#include <string>

#include "easy_timer.h"
#include "audio_utils.h"
#include "rknn3_audio_encoder_test.h"
#include "cmdline_parser.h"

TIMER audio_encode_timer;
TIMER total_infer_timer;
int32_t infer_loop_cnt;

/*-------------------------------------------
                Print Usage
-------------------------------------------*/
void print_usage(char *argv[]) {
    printf("Usage:\n");
    printf("%s [options]\n\n", argv[0]);
    printf("Options:\n");
    printf("  -am, --audio_model     Audio model path (.rknn)\n");
    printf("  -aw, --audio_weight    Audio weight path (.weight)\n");
    printf("  -ac, --audio_core      Audio core mask (hex, e.g. 0x7)\n");
    printf("  -a,  --audio_path      Audio file path (.wav)\n");
    printf("  -al, --audio_loop      Audio loop count (default: 1)\n");
    printf("  -tl, --time_loop       Time loop in hours (overrides loop count)\n");
    printf("  -id, --device_id       Device ID (default: 0)\n");
    printf("  -h,  --help            Display this help message\n");
    printf("\nExample:\n");
    printf("  %s -am audio.rknn -aw audio.weight -ac 0x7 -a test.wav -al 100\n", argv[0]);
}

/*-------------------------------------------
                  Main Function
-------------------------------------------*/
int main(int argc, char **argv) {
    int ret = 0;

    // Parse command line arguments using common parser
    cmdline_args_t args;
    ret = parse_cmdline_args(argc, argv, &args);
    if (ret != 0 || args.show_help) {
        print_usage(argv[0], PROGRAM_TYPE_AUDIO, NULL, 0);  // Use AUDIO type for audio-specific usage
        free_cmdline_args(&args);
        return args.show_help ? 0 : -1;
    }

    if (args.model_folder) {
        (void)populate_args_from_model_folder(&args, PROGRAM_TYPE_AUDIO);
    }

    // Validate required arguments for audio encoder using common function
    ret = validate_required_params(&args, PROGRAM_TYPE_AUDIO);
    if (ret != 0) {
        print_usage(argv[0], PROGRAM_TYPE_AUDIO, NULL, 0);
        free_cmdline_args(&args);
        return -1;
    }

    // Handle time_loop override
    handle_time_loop_override(&args, PROGRAM_TYPE_AUDIO);

    // Print configuration using common function
    print_configuration(&args, PROGRAM_TYPE_AUDIO);

    // Define program type for audio (using custom approach since not directly supported)
    // Map audio-specific parameters from common args
    char *audio_model_path = args.model_path;
    char *audio_weight_path = args.weight_path;
    uint32_t audio_core_mask = args.core_mask;
    char *audio_path = args.audio_path;  // Reuse audio_path field for audio_path
    int audio_loop = args.cnt_loop;
    float time_loop = args.time_loop;
    uint32_t device_id = args.device_id;

    // RKNN Context
    rknn_audio_encoder_context_t rknn_app_ctx;
    memset(&rknn_app_ctx, 0, sizeof(rknn_audio_encoder_context_t));

    // Input Audio
    audio_buffer_t src_audio;
    memset(&src_audio, 0, sizeof(audio_buffer_t));

    // Extract model name (before any goto to avoid initialization errors)
    const char *last_slash = strrchr(audio_model_path, '/');
    const char *filename = (last_slash != NULL) ? (last_slash + 1) : audio_model_path;
    char model_name[256];
    strncpy(model_name, filename, sizeof(model_name) - 1);
    model_name[sizeof(model_name) - 1] = '\0';
    char *last_dot = strrchr(model_name, '.');
    if (last_dot != NULL && strcmp(last_dot, ".rknn") == 0) {
        *last_dot = '\0';
    }

    // Init audio encoder model
    ret = init_audio_encoder_test(&rknn_app_ctx, audio_model_path, audio_weight_path,
                                   audio_core_mask, device_id);
    if (ret != 0) {
        printf(RKNN3_AUDIO_ENC_ERR "init_audio_encoder_test failed! ret=%d\n", ret);
        goto out;
    }

    // Read Audio file
    ret = read_audio(audio_path, &src_audio);
    if (ret != 0) {
        printf(RKNN3_AUDIO_ENC_ERR "read audio failed! ret=%d audio_path=%s\n", ret, audio_path);
        goto out;
    }
    printf(RKNN3_AUDIO_ENC_LOG "Audio loaded: %d frames, %d channels, %d Hz\n",
           src_audio.num_frames, src_audio.num_channels, src_audio.sample_rate);

    // Run inference test
    printf("\n" RKNN3_AUDIO_ENC_LOG "Starting audio encoding stress test...\n");
    ret = inference_audio_encoder_test(&rknn_app_ctx, &src_audio, model_name, audio_loop, time_loop);
    if (ret != 0) {
        printf(RKNN3_AUDIO_ENC_ERR "Inference test failed! ret=%d\n", ret);
        goto out;
    }

out:
    ret = release_audio_encoder_test(&rknn_app_ctx);
    if (ret != 0) {
        printf(RKNN3_AUDIO_ENC_ERR "Release model failed! ret=%d\n", ret);
    }

    if (src_audio.data != NULL) {
        free(src_audio.data);
    }

    // Output format matches other stress tests for consistency
    if (ret == 0) {
        printf(RKNN3_AUDIO_ENC_DONE);
    }

    free_cmdline_args(&args);

    return ret;
}
