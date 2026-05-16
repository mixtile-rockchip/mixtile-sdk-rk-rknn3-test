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


#ifndef _RKNN_DEMO_QWEN2_5_OMNI_AUDIO_UTILS_H_
#define _RKNN_DEMO_QWEN2_5_OMNI_AUDIO_UTILS_H_

#include "rknn3_api.h"
#include "common.h"

// Generic audio encoder context that can support different audio encoder models
typedef struct {
    rknn3_context rknn_ctx;
    rknn3_input_output_num io_num;
    rknn3_tensor* inputs;
    rknn3_tensor* outputs;

    int batch_size;
    int window_size;
    int n_mels;

    uint32_t* embeds_shape;
    uint32_t embeds_ndims;

    char mel_filters_path[512];

    uint32_t device_id;
} rknn_audio_encoder_context;

// Initialize audio encoder model
int init_audio_encoder(rknn_audio_encoder_context* audio_ctx, const char* model_path, const char* weight_path, uint32_t core_mask);

// Release audio encoder model resources
int release_audio_encoder(rknn_audio_encoder_context* audio_ctx);

// Calculate number of audio tokens/embeddings from audio length
int get_n_audio_tokens(rknn_audio_encoder_context* audio_ctx, int audio_len);

// Run chunked audio encoder inference (preprocess + NCHW chunked loop + embeds output)
// audio_embeds must be pre-allocated with enough space for get_n_audio_tokens() * embeds_dim
int inference_audio_encoder(rknn_audio_encoder_context* audio_ctx, audio_buffer_t* audio, float16* audio_embeds);

#endif //_RKNN_DEMO_QWEN2_5_OMNI_AUDIO_UTILS_H_
