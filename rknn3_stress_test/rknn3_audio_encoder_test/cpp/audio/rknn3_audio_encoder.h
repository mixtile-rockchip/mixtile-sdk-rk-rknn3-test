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

#define MAX_SHAPE_ID        10

// Generic audio encoder context that can support different audio encoder models
typedef struct {
    rknn3_context rknn_ctx;
    rknn3_input_output_num io_num;
    int n_shapes;
    rknn3_shape_info *shape_infos;
    rknn3_tensor* inputs;
    rknn3_tensor* outputs;

    int n_mels;
    int n_frame[MAX_SHAPE_ID];
    int padded_mask_size[MAX_SHAPE_ID];
    int attn_mask_size[MAX_SHAPE_ID];
    int embeds_dim0[MAX_SHAPE_ID];
    int embeds_dim1;

    uint32_t device_id;
} rknn_audio_encoder_context;

// Initialize audio encoder model
int init_audio_encoder(rknn_audio_encoder_context* audio_ctx, const char* model_path, const char* weight_path, uint32_t core_mask);

// Release audio encoder model resources
int release_audio_encoder(rknn_audio_encoder_context* audio_ctx);

// Calculate number of audio tokens/embeddings from audio length
int get_n_audio_tokens(rknn_audio_encoder_context* audio_ctx, int audio_len);

// Prepare audio input (preprocessing, should be called once before inference loop)
// This function does: mel filter extraction, audio preprocessing, mask creation, fp16 conversion
int prepare_audio_input(rknn_audio_encoder_context* audio_ctx, audio_buffer_t* audio);

// Run audio encoder model inference (only mem_sync + rknn3_run, for performance testing in loop)
int inference_audio_encoder(rknn_audio_encoder_context* audio_ctx);

// Run audio encoder model inference without mem_sync (only rknn3_run, for hiding transfer latency)
int inference_audio_encoder_no_sync(rknn_audio_encoder_context* audio_ctx);

// Sync audio input to device (call once before inference_audio_encoder_no_sync loop)
int sync_audio_input(rknn_audio_encoder_context* audio_ctx);

// Sync audio output from device (call once after inference_audio_encoder_no_sync loop)
int sync_audio_output(rknn_audio_encoder_context* audio_ctx);

// Get audio embeddings from output buffer (call once after inference loop)
int get_audio_embeds(rknn_audio_encoder_context* audio_ctx, audio_buffer_t* audio, float16* audio_embeds);

#endif //_RKNN_DEMO_QWEN2_5_OMNI_AUDIO_UTILS_H_