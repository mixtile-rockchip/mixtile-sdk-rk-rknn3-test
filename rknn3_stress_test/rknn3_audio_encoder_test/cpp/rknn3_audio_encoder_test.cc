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

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <algorithm>
#include <vector>
#include <string>

#include "rknn3_audio_encoder_test.h"
#include "common.h"
#include "rknn3_api.h"
#include "audio_utils.h"
#include <math.h>

// Performance jitter check function
// Monitors if audio encoding latency is stable across runs
void check_performance(float last_latency, float cur_latency, int iter) {
    if (last_latency <= 0) {
        return; // Skip first run
    }

    float diff = fabsf(cur_latency - last_latency);
    float ratio = diff / last_latency;  // Jitter percentage

    // Critical: >50% jitter
    if (ratio > 0.5f) {
        printf("\n+------------------+--------------------+\n");
        printf("| Stage            | Perf               |\n");
        printf("+------------------+--------------------+\n");
        printf("| %-16s | %-14.2f(ms) |\n", "Last Latency", last_latency);
        printf("| %-16s | %-14.2f(ms) |\n", "Curr Latency", cur_latency);
        printf("| %-16s | %-14.2f(%%) |\n", "Jitter", ratio * 100);
        printf("+------------------+--------------------+\n");

        fprintf(stderr, RKNN3_AUDIO_ENC_ERR "Perf jitter %.2f%% exceeds 50%% threshold (last=%.2f, cur=%.2f)\n",
                ratio * 100, last_latency, cur_latency);
        fprintf(stderr, RKNN3_AUDIO_ENC_ERR "Performance is unstable! Exiting...\n");
        exit(EXIT_FAILURE);
    }
    // Warning: >20% jitter
    else if (ratio > 0.2f) {
        fprintf(stderr, RKNN3_AUDIO_ENC_WRN "Perf jitter %.2f%% exceeds 20%% at iteration %d (last=%.2f, cur=%.2f)\n",
                ratio * 100, iter, last_latency, cur_latency);
    }
}

int init_audio_encoder_test(rknn_audio_encoder_context_t* app_ctx,
                             const char* audio_model_path, const char* audio_weight_path,
                             uint32_t audio_core_mask,
                             uint32_t device_id)
{
    int ret = 0;

    // Set device_id in context before init
    app_ctx->audio.device_id = device_id;

    printf(RKNN3_AUDIO_ENC_LOG "--> Initializing audio encoder model\n");
    ret = init_audio_encoder(&(app_ctx->audio), audio_model_path, audio_weight_path, audio_core_mask);
    if (ret < 0) {
        printf(RKNN3_AUDIO_ENC_ERR "Failed to init audio model! ret=%d\n", ret);
        return ret;
    }

    // ========================================================================
    // Manual Internal Memory Allocation (Required for user_mem_internal = 1)
    // ========================================================================

    // Step 1: Query how many NPU cores this model uses
    uint32_t core_num_audio = 0;
    ret = rknn3_query(app_ctx->audio.rknn_ctx, RKNN3_QUERY_CORE_NUMBER, &core_num_audio, sizeof(core_num_audio));
    if (ret < 0) {
        printf(RKNN3_AUDIO_ENC_ERR "rknn3_query audio core number failed! ret=%d\n", ret);
        return ret;
    }
    printf(RKNN3_AUDIO_ENC_LOG "Model uses %u NPU cores\n", core_num_audio);

    // Step 2: Query internal memory size required for each core
    rknn3_core_mem_size* core_mem_sizes = (rknn3_core_mem_size*)malloc(sizeof(rknn3_core_mem_size) * core_num_audio);
    if (!core_mem_sizes) {
        printf(RKNN3_AUDIO_ENC_ERR "Failed to allocate memory for core_mem_sizes\n");
        return -1;
    }

    ret = rknn3_query(app_ctx->audio.rknn_ctx, RKNN3_QUERY_CORE_MEM_SIZE, core_mem_sizes, sizeof(rknn3_core_mem_size) * core_num_audio);
    if (ret < 0) {
        printf(RKNN3_AUDIO_ENC_ERR "rknn3_query core memory size failed! ret=%d\n", ret);
        free(core_mem_sizes);
        return ret;
    }

    // Step 3: Allocate internal memory pointer array
    rknn3_tensor_mem** internal_mems = (rknn3_tensor_mem**)malloc(sizeof(rknn3_tensor_mem*) * core_num_audio);
    if (!internal_mems) {
        printf(RKNN3_AUDIO_ENC_ERR "Failed to allocate internal_mems array\n");
        free(core_mem_sizes);
        return -1;
    }

    // Step 4: Create internal memory for each NPU core
    for (uint32_t i = 0; i < core_num_audio; i++) {
        if (core_mem_sizes[i].internal_size > 0) {
            internal_mems[i] = rknn3_create_mem(app_ctx->audio.rknn_ctx,
                                                core_mem_sizes[i].internal_size,
                                                core_mem_sizes[i].core_id,
                                                RKNN3_FLAG_MEMORY_CACHEABLE);
            if (!internal_mems[i]) {
                printf(RKNN3_AUDIO_ENC_ERR "Failed to create internal memory for core %d\n", core_mem_sizes[i].core_id);
                free(core_mem_sizes);
                free(internal_mems);
                return -1;
            }
            printf(RKNN3_AUDIO_ENC_LOG "Created internal memory for core %d: size=%lu bytes\n",
                   core_mem_sizes[i].core_id, core_mem_sizes[i].internal_size);
        }
    }

    free(core_mem_sizes);

    // Step 5: Bind internal memory to RKNN context
    ret = rknn3_set_internal_mem(app_ctx->audio.rknn_ctx, internal_mems, core_num_audio);
    if (ret < 0) {
        printf(RKNN3_AUDIO_ENC_ERR "rknn3_set_internal_mem failed! ret=%d\n", ret);
        for (uint32_t i = 0; i < core_num_audio; i++) {
            if (internal_mems[i]) {
                rknn3_destroy_mem(app_ctx->audio.rknn_ctx, internal_mems[i]);
            }
        }
        free(internal_mems);
        return ret;
    }

    // Step 6: Store for later cleanup
    app_ctx->internal_mems = internal_mems;
    app_ctx->n_internal_mems = core_num_audio;

    // Set device ID string for reporting
    snprintf(app_ctx->device_id_mac, sizeof(app_ctx->device_id_mac), "device_%d", device_id);

    return ret;
}

int release_audio_encoder_test(rknn_audio_encoder_context_t* app_ctx)
{
    // Release internal memory (for user_mem_internal = 1)
    if (app_ctx->internal_mems) {
        for (int i = 0; i < app_ctx->n_internal_mems; i++) {
            if (app_ctx->internal_mems[i]) {
                rknn3_destroy_mem(app_ctx->audio.rknn_ctx, app_ctx->internal_mems[i]);
                app_ctx->internal_mems[i] = NULL;
            }
        }
        free(app_ctx->internal_mems);
        app_ctx->internal_mems = NULL;
        app_ctx->n_internal_mems = 0;
    }

    // Release audio encoder resources
    release_audio_encoder(&(app_ctx->audio));
    return 0;
}

int inference_audio_encoder_test(rknn_audio_encoder_context_t* app_ctx,
                                  audio_buffer_t* audio,
                                  const char* model_name,
                                  int audio_loop, float time_loop)
{
    int ret;
    if (!app_ctx || !audio) {
        printf(RKNN3_AUDIO_ENC_ERR "app_ctx or audio is NULL\n");
        return -1;
    }

    // Allocate audio embeddings buffer
    int n_audio_tokens = get_n_audio_tokens(&(app_ctx->audio), audio->num_frames);
    int embedding_dim = app_ctx->audio.embeds_shape[1];
    size_t n_embed_audio = n_audio_tokens * embedding_dim;
    float16* audio_embeds = (float16*)malloc(n_embed_audio * sizeof(float16));
    if (!audio_embeds) {
        printf(RKNN3_AUDIO_ENC_ERR "Failed to allocate audio_embeds\n");
        return -1;
    }

    printf("Output: %d audio tokens x %d embedding dim\n", n_audio_tokens, embedding_dim);

    total_infer_timer.tik();
    int infer_cnt = 0;
    int stable_cnt = 0;
    float time_loop_ms = time_loop * 60.f * 60.f * 1000.f;
    float acc_audio_time = 0.0f;
    float stable_audio_time = 0.0f;
    float min_time = 1e9f;
    float max_time = 0.0f;

    // For performance jitter check
    float last_latency = 0.0f;

    while (1) {
        // Full inference: preprocess + chunked NCHW inference + embeds output
        audio_encode_timer.tik();
        ret = inference_audio_encoder(&(app_ctx->audio), audio, audio_embeds);
        audio_encode_timer.tok();

        if (ret != 0) {
            printf(RKNN3_AUDIO_ENC_ERR "Audio inference failed! ret=%d\n", ret);
            free(audio_embeds);
            return ret;
        }

        float this_time = audio_encode_timer.get_time();
        acc_audio_time += this_time;
        infer_cnt++;

        // Always update min/max
        if (this_time < min_time) min_time = this_time;
        if (this_time > max_time) max_time = this_time;

        // Phase management
        if (infer_cnt < 10) {
            // Warmup phase (1-9): just run
        } else if (infer_cnt == 10) {
            // End of warmup: reset min/max for production measurement
            min_time = this_time;
            max_time = this_time;
            last_latency = this_time;
        } else {
            // Production phase (11+): check performance jitter
            check_performance(last_latency, this_time, infer_cnt);
            last_latency = this_time;
        }

        // Exit condition check
        total_infer_timer.tok();
        if (time_loop != 0.f) {
            if (total_infer_timer.get_time() >= time_loop_ms) {
                break;
            }
        } else {
            if (infer_cnt >= audio_loop) {
                break;
            }
        }
    }

    total_infer_timer.tok();
    float total_time = total_infer_timer.get_time();
    float avgCost = acc_audio_time / infer_cnt;

    // Output format matches llm/vlm multi-line key-value format
    printf("\n===== Audio Encoder Test Results =====\n\n");
    printf("Model: %s\n", model_name);
    printf("DeviceID: %s\n", app_ctx->device_id_mac);
    printf("AvgLatency: %.2f ms\n", avgCost);
    printf("MinLatency: %.2f ms\n", min_time);
    printf("MaxLatency: %.2f ms\n", max_time);
    printf("TotalTime: %.2f ms\n", total_time);
    printf("TotalRuns: %d\n", infer_cnt);

    printf("\n=================================\n");
    free(audio_embeds);

    return 0;
}
