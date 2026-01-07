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

#ifndef _RKNN3_AUDIO_ENCODER_TEST_H_
#define _RKNN3_AUDIO_ENCODER_TEST_H_

#include "rknn3_api.h"
#include "common.h"
#include "rknn3_audio_encoder.h"
#include "easy_timer.h"

// Unified log prefix macros (project-specific to avoid namespace pollution)
#define RKNN3_AUDIO_ENC_LOG "[rknn3_model_stress_test_log] "
#define RKNN3_AUDIO_ENC_ERR "[rknn3_model_stress_test_error] "
#define RKNN3_AUDIO_ENC_WRN "[rknn3_model_stress_test_warning] "
#define RKNN3_AUDIO_ENC_DONE "[rknn3_model_stress_test_done]\n"

// External variables
extern TIMER audio_encode_timer;
extern TIMER total_infer_timer;
extern int32_t infer_loop_cnt;

typedef struct {
    rknn_audio_encoder_context audio;
    char device_id_mac[128];

    // Internal memory management (for user_mem_internal = 1)
    int n_internal_mems;              // Number of NPU cores (each core needs internal memory)
    rknn3_tensor_mem** internal_mems; // Array of internal memory for each NPU core
} rknn_audio_encoder_context_t;

int init_audio_encoder_test(rknn_audio_encoder_context_t* app_ctx,
                             const char* audio_model_path, const char* audio_weight_path,
                             uint32_t audio_core_mask,
                             uint32_t device_id);

int release_audio_encoder_test(rknn_audio_encoder_context_t* app_ctx);

int inference_audio_encoder_test(rknn_audio_encoder_context_t* app_ctx,
                                  audio_buffer_t* audio,
                                  const char* model_name,
                                  int audio_loop, float time_loop);

#endif //_RKNN3_AUDIO_ENCODER_TEST_H_
