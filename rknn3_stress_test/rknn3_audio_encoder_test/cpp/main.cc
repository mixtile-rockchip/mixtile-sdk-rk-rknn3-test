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
    printf("  -mm, --enable_memory_monitor  Enable memory monitoring (default: disabled)\n");
    printf("  -h,  --help            Display this help message\n");
    printf("\nExample:\n");
    printf("  %s -am audio.rknn -aw audio.weight -ac 0x7 -a test.wav -al 100\n", argv[0]);
}

/*-------------------------------------------
                  Main Function
-------------------------------------------*/
int main(int argc, char **argv) {
    char *audio_model_path = NULL;
    char *audio_weight_path = NULL;
    void *audio_core_mask = NULL;
    char *audio_path = NULL;
    int audio_loop = 1;
    float time_loop = 0.f;
    uint32_t device_id = 0;
    bool enable_memory_monitor = false;

    // Parse command line arguments
    for (int i = 1; i < argc; i += 2) {
        if (strcmp(argv[i], "-am") == 0 || strcmp(argv[i], "--audio_model") == 0) {
            audio_model_path = argv[i + 1];
        } else if (strcmp(argv[i], "-aw") == 0 || strcmp(argv[i], "--audio_weight") == 0) {
            audio_weight_path = argv[i + 1];
        } else if (strcmp(argv[i], "-ac") == 0 || strcmp(argv[i], "--audio_core") == 0) {
            audio_core_mask = (void *)(uintptr_t)strtoul(argv[i + 1], NULL, 16);
        } else if (strcmp(argv[i], "-a") == 0 || strcmp(argv[i], "--audio_path") == 0) {
            audio_path = argv[i + 1];
        } else if (strcmp(argv[i], "-al") == 0 || strcmp(argv[i], "--audio_loop") == 0) {
            audio_loop = atoi(argv[i + 1]);
        } else if (strcmp(argv[i], "-tl") == 0 || strcmp(argv[i], "--time_loop") == 0) {
            time_loop = atof(argv[i + 1]);
        } else if (strcmp(argv[i], "-id") == 0 || strcmp(argv[i], "--device_id") == 0) {
            device_id = atoi(argv[i + 1]);
        } else if (strcmp(argv[i], "-mm") == 0 || strcmp(argv[i], "--enable_memory_monitor") == 0) {
            enable_memory_monitor = true;
            i--;  // This flag doesn't have a value, so decrement i to compensate for i += 2
        } else if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0) {
            print_usage(argv);
            return 0;
        } else {
            printf(RKNN3_AUDIO_ENC_ERR "Unknown option: %s\n", argv[i]);
            return -1;
        }
    }

    printf("\n===== RKNN3 Audio Encoder Stress Test =====\n");
    printf("audio_model: %s\n", audio_model_path);
    printf("audio_weight: %s\n", audio_weight_path);
    printf("audio_core_mask: %p\n", audio_core_mask);
    printf("audio_path: %s\n", audio_path);
    printf("audio_loop: %d\n", audio_loop);
    printf("device_id: %d\n", device_id);
    printf("time_loop: %.2f hours\n", time_loop);
    printf("==========================================\n\n");

    // Check required arguments
    if (!audio_model_path) {
        printf(RKNN3_AUDIO_ENC_ERR "Missing audio_model_path\n");
        print_usage(argv);
        return -1;
    }
    if (!audio_weight_path) {
        printf(RKNN3_AUDIO_ENC_ERR "Missing audio_weight_path\n");
        print_usage(argv);
        return -1;
    }
    if (!audio_path) {
        printf(RKNN3_AUDIO_ENC_ERR "Missing audio_path\n");
        print_usage(argv);
        return -1;
    }
    if (audio_core_mask == 0) {
        printf(RKNN3_AUDIO_ENC_ERR "Invalid audio_core_mask (must not be 0)\n");
        print_usage(argv);
        return -1;
    }

    // Validate device_id
    if (device_id < 0) {
        printf(RKNN3_AUDIO_ENC_WRN "device_id = %d is invalid, using default: 0\n", device_id);
        device_id = 0;
    }

    // Validate loop parameters
    if (time_loop == 0.f && audio_loop <= 0) {
        printf(RKNN3_AUDIO_ENC_ERR "Invalid loop configuration: audio_loop=%d, time_loop=%.2f\n", audio_loop, time_loop);
        printf(RKNN3_AUDIO_ENC_ERR "Please set audio_loop > 0 or time_loop > 0\n");
        return -1;
    }

    if (time_loop != 0.f) {
        audio_loop = 1; // Time mode overrides count mode
    }

    int ret;

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
                                   (uint32_t)(uintptr_t)audio_core_mask, device_id);
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
    ret = inference_audio_encoder_test(&rknn_app_ctx, &src_audio, model_name, audio_loop, time_loop, enable_memory_monitor);
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

    return ret;
}
