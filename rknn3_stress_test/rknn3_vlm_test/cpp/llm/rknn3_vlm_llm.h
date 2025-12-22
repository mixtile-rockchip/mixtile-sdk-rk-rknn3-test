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


#ifndef _RKNN_DEMO_RKNN3_VLM_LLM_UTILS_H_
#define _RKNN_DEMO_RKNN3_VLM_LLM_UTILS_H_

#include "rknn3_api.h"
#include "Tokenizer.h"
#include "common.h"
#include "easy_timer.h"
// extern const char* system_prompt;
// extern const char* prompt_prefix;
// extern const char* prompt_postfix;


#define MAX_NEW_TOKENS 1024
#define MAX_CONTEXT_LEN 1024
#define RKNN3_DEFAULT_DEVICE_ID 0

typedef struct {
    rknn3_context   rknn_ctx;
    rknn3_session* rknn_sess;
    uint32_t device_id;
    char device_mac[128];
    rknn3_aux_tensor deepstack_tensor[3];
    char system_prompt[128];
    char prefix_prompt[128];
    char postfix_prompt[128];
} rknn3_vlm_llm_context;

int init_rknn3_vlm_llm(rknn3_vlm_llm_context* llm_ctx, const char* model_path, const char* weight_path, rknn3_llm_param* params, int n_params, RKLLMCallback callback, uint32_t core_mask);

int release_rknn3_vlm_llm(rknn3_vlm_llm_context* llm_ctx);

int inference_rknn3_vlm_llm(rknn3_vlm_llm_context* llm_ctx, rknn3_llm_multimodal_tensor tensor, int n_inputs,int loop);

#endif //_RKNN_DEMO_RKNN3_VLM_LLM_UTILS_H_