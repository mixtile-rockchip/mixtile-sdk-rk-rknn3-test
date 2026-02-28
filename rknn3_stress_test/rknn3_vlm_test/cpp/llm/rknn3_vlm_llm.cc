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

#include <string>
// #include "easy_timer.h"

#include "rknn3_vlm_llm.h"
#include "rknn3_vlm.h"

int init_rknn3_vlm_llm(rknn3_vlm_llm_context *llm_ctx, const char *model_path, const char *weight_path, rknn3_llm_param *params, int n_params, RKLLMCallback callback, uint32_t core_mask) {
    int ret;
    rknn3_context ctx = 0;
    rknn3_session *session = NULL;

    rknn3_config config;
    memset(&config, 0, sizeof(config));
    
    config.user_mem_internal = 1;  // 使用用户管理的internal内存

    // 获取目前连接的RK182X信息
    rknn3_devices rknn3_devices;
    memset(&rknn3_devices, 0, sizeof(rknn3_devices));
    ret = rknn3_find_devices(&rknn3_devices);
    if (ret != RKNN3_SUCCESS || rknn3_devices.n_devices <= 0) {
        printf("find devices failed, or data is invalid: %d\n", ret);
        return ret;
    }

    if (llm_ctx->device_id >= rknn3_devices.n_devices) {
        printf("warning!!! device_id = %d is not allow ,use default:%d, %s, %d\n", llm_ctx->device_id, RKNN3_DEFAULT_DEVICE_ID, __FUNCTION__, __LINE__);
        llm_ctx->device_id = RKNN3_DEFAULT_DEVICE_ID;
    }

    printf("[rknn3_stress_test_log] device[%d].id=%s\n", llm_ctx->device_id, rknn3_devices.devices[llm_ctx->device_id].id);

    rknn3_init_extend init_extend = { 0 };
    init_extend.device_id = rknn3_devices.devices[llm_ctx->device_id].id;
    memcpy(llm_ctx->device_mac, rknn3_devices.devices[llm_ctx->device_id].id, sizeof(rknn3_devices.devices[llm_ctx->device_id].id));
    // llm_ctx->device_mac = rknn3_devices.devices[llm_ctx->device_id].id;
    // RKNN Init
    ret = rknn3_init(&ctx, &init_extend);
    if (ret < 0) {
        printf("[rknn3_model_stress_test_error] rknn_init fail ret=%d\n", ret);
        return ret;
    }

    // Load RKNN Model
    ret = rknn3_load_model_from_path(ctx, model_path, weight_path);
    if (ret < 0) {
        printf("[rknn3_model_stress_test_error] rknn_load_model failed! ret=%d\n", ret);
        return ret;
    }

    // Query and validate llm core_mask before model init
    uint32_t model_core_num = 0;
    ret = rknn3_query(ctx, RKNN3_QUERY_CORE_NUMBER, &model_core_num, sizeof(model_core_num));
    if (ret < 0) {
        printf("[rknn3_model_stress_test_error] rknn3_query llm core number failed! ret=%d\n", ret);
        rknn3_destroy(ctx);
        return ret;
    }

    if (core_mask == 0) {
        if (model_core_num > 32U) {
            printf("[rknn3_model_stress_test_error] model_core_num=%u exceeds max supported 32\n", model_core_num);
            rknn3_destroy(ctx);
            return -1;
        }
        // Auto-generate core_mask: starting from bit 0 for each core_number cores
        for (uint32_t i = 0; i < model_core_num; i++) {
            core_mask |= (1U << i);
        }
        printf("Auto-generated core_mask: 0x%x for %u cores\n", core_mask, model_core_num);
    } else {
        uint32_t core_num_from_mask = 0;
        for (int i = 0; i < 32; i++) {
            if (core_mask & (1U << i)) core_num_from_mask++;
        }

        if (core_num_from_mask != model_core_num) {
            printf("[rknn3_model_stress_test_error] LLM core_mask 0x%x has %u cores, but model requires %u cores\n",
                   core_mask, core_num_from_mask, model_core_num);
            printf("[rknn3_model_stress_test_error] Please specify exactly %u cores for llm model\n", model_core_num);
            rknn3_destroy(ctx);
            return -1;
        }
    }
    printf("[rknn3_stress_test_log] LLM model requires %u NPU cores\n", model_core_num);
    printf("[rknn3_stress_test_log] User specified llm_core_mask: 0x%x\n", core_mask);
    // printf("[rknn3_stress_test_log] LLM core mask validation passed (%u cores)\n", core_num_from_mask);
    config.run_core_mask = core_mask;
    // Init RKNN Model
    ret = rknn3_model_init(ctx, &config);
    if (ret < 0) {
        printf("[rknn3_model_stress_test_error] rknn_model_init failed! ret=%d\n", ret);
        return ret;
    }

    // RKNN Session Init
    session = rknn3_session_init(ctx, params, n_params);
    if (!session) {
        printf("[rknn3_model_stress_test_error] Failed to initialize test session\n");
        return -1;
    }

    ret = rknn3_session_set_chat_template(session, llm_ctx->system_prompt, llm_ctx->prefix_prompt, llm_ctx->postfix_prompt);
    if (ret < 0) {
        printf("[rknn3_model_stress_test_error] Failed to set chat template\n");
        return -1;
    }

    // Set Callback
    ret = rknn3_session_set_callback(session, &(callback));
    if (ret < 0) {
        printf("[rknn3_model_stress_test_error] Failed to set callback\n");
        return -1;
    }

    // Set to context
    llm_ctx->rknn_ctx = ctx;
    llm_ctx->rknn_sess = session;

    return ret;
}

int release_rknn3_vlm_llm(rknn3_vlm_llm_context *llm_ctx) {
    if (llm_ctx->rknn_sess) {
        rknn3_session_destroy(llm_ctx->rknn_sess);
        llm_ctx->rknn_sess = NULL;
    }

    if (llm_ctx->rknn_ctx != 0) {
        rknn3_destroy(llm_ctx->rknn_ctx);
        llm_ctx->rknn_ctx = 0;
    }
    return 0;
}

int inference_rknn3_vlm_llm(rknn3_vlm_llm_context *llm_ctx, rknn3_llm_multimodal_tensor tensor, int n_inputs, int loop) {
    if ((!llm_ctx) || !(llm_ctx->rknn_sess)) {
        printf("[rknn3_model_stress_test_error] llm_ctx or rknn_session is NULL");
        return -1;
    }

    int ret;
    rknn3_llm_input inputs[n_inputs];
    rknn3_llm_infer_param llm_infer_param;

    memset(inputs, 0, sizeof(inputs));
    memset(&(llm_infer_param), 0, sizeof(llm_infer_param));

    llm_infer_param.keep_history = 0;
    llm_infer_param.max_new_tokens = MAX_NEW_TOKENS;

    // Set Input Data
    inputs[0].input_type = RKNN3_LLM_INPUT_MULTIMODAL;
    inputs[0].multimodal_input = tensor;

    // int prefill_n_tokens = 0;
    // int32_t need_tokens_len = 256;
    for (int i = 0; i < loop; i++) {
        g_vlm_perf.llm_perfill.tik();
        if (n_inputs > 1) {
            for (int i = 1; i < n_inputs; ++i) {
                inputs[i].input_type = RKNN3_LLM_INPUT_AUX;
                inputs[i].aux_input = llm_ctx->deepstack_tensor[i - 1];
            }
        }
        ret = rknn3_session_run(llm_ctx->rknn_sess, inputs, n_inputs, &llm_infer_param);
        if (ret < 0) {
            printf("[rknn3_model_stress_test_error] rknn_session_run fail! ret=%d\n", ret);
            return ret;
        }
        RKLLMRunState state = { 0 };

        if (ret != RKNN3_SUCCESS) {
            printf("[rknn3_model_stress_test_error] rknn3_session_query_state failed, ret=%d\n", ret);
            return ret;
        }

        if (loop != 1) {
            printf("llm run: %d / %d\n end\n", (i + 1), loop);
        }
    }

    return ret;
}