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

#include "rknn3_vlm.h"
#include "common.h"
#include "image_utils.h"
// #include "rknn_api.h"
#include <math.h>


int init_internal_share(rknn_app_context_t* app_ctx, uint32_t core_mask_vision, uint32_t core_mask_llm)
{
    int ret = -1;

    uint32_t core_num_vision = 0;
    uint32_t core_num_llm = 0;
    ret = rknn3_query(app_ctx->vision.rknn_ctx, RKNN3_QUERY_CORE_NUMBER, &core_num_vision, sizeof(core_num_vision));
    if (ret < 0) {
        printf("rknn3_query failed! ret=%d\n", ret);
        return ret;
    }
    ret = rknn3_query(app_ctx->llm.rknn_ctx, RKNN3_QUERY_CORE_NUMBER, &core_num_llm, sizeof(core_num_llm));
    if (ret < 0) {
        printf("rknn3_query failed! ret=%d\n", ret);
        return ret;
    }

    uint32_t core_num_vision_ = 0;
    uint32_t core_num_llm_ = 0;
    for (int i = 0; i < 32; i++) {
        if (core_mask_vision & (1 << i))    core_num_vision_++;
    }
    for (int i = 0; i < 32; i++) {
        if (core_mask_llm & (1 << i))    core_num_llm_++;
    }
    if (core_num_vision_ != core_num_vision) {
        printf("the core_mask_vision = %x is not match the core_num_vision = %d!\n", core_mask_vision, core_num_vision);
        return -1;
    }
    if (core_num_llm_ != core_num_llm) {
        printf("the core_mask_llm = %x is not match the core_num_llm = %d!\n", core_mask_llm, core_num_llm);
        return -1;
    }

    rknn3_core_mem_size* core_mem_sizes_vision = (rknn3_core_mem_size*)malloc(sizeof(rknn3_core_mem_size) * core_num_vision);
    if (!core_mem_sizes_vision) {
        printf("Failed to allocate memory for core_mem_sizes_vision\n");
        return ret;
    }
    rknn3_core_mem_size* core_mem_sizes_llm = (rknn3_core_mem_size*)malloc(sizeof(rknn3_core_mem_size) * core_num_llm);
    if (!core_mem_sizes_llm) {
        printf("Failed to allocate memory for core_mem_sizes_llm\n");
        return ret;
    }
    ret = rknn3_query(app_ctx->vision.rknn_ctx, RKNN3_QUERY_CORE_MEM_SIZE, core_mem_sizes_vision, sizeof(rknn3_core_mem_size) * core_num_vision);
    if (ret < 0) {
        printf("rknn3_query core memory size failed! ret=%d\n", ret);
        return ret;
    }
    ret = rknn3_query(app_ctx->llm.rknn_ctx, RKNN3_QUERY_CORE_MEM_SIZE, core_mem_sizes_llm, sizeof(rknn3_core_mem_size) * core_num_llm);
    if (ret < 0) {
        printf("rknn3_query core memory size failed! ret=%d\n", ret);
        return ret;
    }

    int llm_to_vision[core_num_llm];
    for (int i = 0; i < core_num_llm; i++)  { llm_to_vision[i] = -1; }

    int core_num_same = 0;
    for (int i = 0; i < core_num_vision; i++) {
        for (int j = 0; j < core_num_llm; j++) {
            if (core_mem_sizes_vision[i].core_id == core_mem_sizes_llm[j].core_id) {
                uint64_t internal_size = std::max(core_mem_sizes_vision[i].internal_size, core_mem_sizes_llm[j].internal_size);
                core_mem_sizes_vision[i].internal_size = internal_size;
                core_mem_sizes_llm[j].internal_size = internal_size;
                core_num_same ++;
                llm_to_vision[j] = i;
                break;
            }
        }
    }

    app_ctx->n_internal_mems = core_num_vision + core_num_llm - core_num_same;
    app_ctx->internal_mems = (rknn3_tensor_mem**)calloc(app_ctx->n_internal_mems, sizeof(rknn3_tensor_mem*));
    if (!app_ctx->internal_mems) {
        printf("Failed to allocate memory for app_ctx->internal_mems array\n");
        return -1;
    }
    rknn3_tensor_mem** internal_mems_vision = (rknn3_tensor_mem**)calloc(core_num_vision, sizeof(rknn3_tensor_mem*));
    if (!internal_mems_vision) {
        printf("Failed to allocate memory for internal_mems_vision array\n");
        return -1;
    }
    rknn3_tensor_mem** internal_mems_llm = (rknn3_tensor_mem**)calloc(core_num_llm, sizeof(rknn3_tensor_mem*));
    if (!internal_mems_llm) {
        printf("Failed to allocate memory for internal_mems_llm array\n");
        return -1;
    }

    int idx = 0;
    for (uint32_t i = 0; i < core_num_vision; i++) {
        internal_mems_vision[i] = rknn3_create_mem(app_ctx->vision.rknn_ctx, core_mem_sizes_vision[i].internal_size, core_mem_sizes_vision[i].core_id, RKNN3_FLAG_MEMORY_CACHEABLE);
        if (!internal_mems_vision[i]) {
            return -1;
        }
        printf("Created user internal memory for core %d: size=%lu, virt_addr=%p, phys_addr=0x%lx\n", core_mem_sizes_vision[i].core_id,
                internal_mems_vision[i]->size, internal_mems_vision[i]->virt_addr, internal_mems_vision[i]->phys_addr);
        app_ctx->internal_mems[idx++] = internal_mems_vision[i];
    }
    for (uint32_t i = 0; i < core_num_llm; i++) {
        if (llm_to_vision[i] != -1) {
            internal_mems_llm[i] = internal_mems_vision[llm_to_vision[i]];
            continue;
        }
        internal_mems_llm[i] = rknn3_create_mem(app_ctx->vision.rknn_ctx, core_mem_sizes_llm[i].internal_size, core_mem_sizes_llm[i].core_id, RKNN3_FLAG_MEMORY_CACHEABLE); 
        if (!internal_mems_llm[i]) {    // 都使用vision.rknn_ctx分配, 方便后面释放
            return -1;
        }
        printf("Created user internal memory for core %d: size=%lu, virt_addr=%p, phys_addr=0x%lx\n", core_mem_sizes_llm[i].core_id,
                internal_mems_llm[i]->size, internal_mems_llm[i]->virt_addr, internal_mems_llm[i]->phys_addr);
        app_ctx->internal_mems[idx++] = internal_mems_vision[i];
    }

    ret = rknn3_set_internal_mem(app_ctx->vision.rknn_ctx, internal_mems_vision, core_num_vision);
    if (ret < 0) {
        printf("rknn3_set_internal_mem failed! ret=%d\n", ret);
        return ret;
    }
    ret = rknn3_set_internal_mem(app_ctx->llm.rknn_ctx, internal_mems_llm, core_num_llm);
    if (ret < 0) {
        printf("rknn3_set_internal_mem failed! ret=%d\n", ret);
        return ret;
    }

    free(internal_mems_vision);
    free(internal_mems_llm);
    free(core_mem_sizes_vision);
    free(core_mem_sizes_llm);

    return ret;
}

int release_internal_share(rknn_app_context_t* app_ctx)
{

    if (app_ctx->internal_mems) {
        for (int i = 0; i < app_ctx->n_internal_mems; i++) {
            if (app_ctx->internal_mems[i]) {
                rknn3_destroy_mem(app_ctx->llm.rknn_ctx, app_ctx->internal_mems[i]);
                app_ctx->internal_mems[i] = NULL;
            }
        }
        free(app_ctx->internal_mems);
        app_ctx->internal_mems = NULL;
        app_ctx->n_internal_mems = 0;
    }
    return 0;
}


int init_rknn3_vlm_model(rknn_app_context_t* app_ctx, const char* llm_model_path, const char* llm_weight_path, const char* vision_model_path, const char* vision_weight_path, rknn3_llm_param* params, int n_params, RKLLMCallback callback, uint32_t vision_core_mask, uint32_t llm_core_mask, uint32_t device_id)
{
    int ret = 0;

    printf("--> init rknn3_vlm vision model\n");
    ret = init_rknn3_vlm_vision(&(app_ctx->vision), vision_model_path, vision_weight_path, vision_core_mask, device_id);
    if (ret < 0)
    {
        printf("rknn_init rknn3_vlm vision model fail! ret=%d\n", ret);
        return ret;
    }

    printf("--> init rknn3_vlm llm model\n");
    ret = init_rknn3_vlm_llm(&(app_ctx->llm), llm_model_path, llm_weight_path, params, n_params, callback, llm_core_mask, device_id);
    if (ret < 0)
    {
        printf("rknn_init rknn3_vlm llm model fail! ret=%d\n", ret);
        return ret;
    }

    printf("--> init internal share\n");
    ret = init_internal_share(app_ctx, vision_core_mask, llm_core_mask);
    if (ret < 0)
    {
        printf("fastvlm llm/vision internal memeory share fail! ret=%d\n", ret);
        return ret;
    }

    return ret;
}

int release_rknn3_vlm_model(rknn_app_context_t* app_ctx)
{
    release_internal_share(app_ctx);
    release_rknn3_vlm_vision(&(app_ctx->vision));
    release_rknn3_vlm_llm(&(app_ctx->llm));
    return 0;
}

void check_perfance(float last_perf, float cur_perf) {
    if (last_perf <= 0) {
        fprintf(stderr, "Error: last_perf must be positive.\n");
        return;
    }

    float diff = fabsf(cur_perf - last_perf);
    float ratio = diff / last_perf;  // 抖动比例

    if (ratio > 0.5f) {
         printf("\n+------------------+--------------------+\n");
        printf("| Stage            | Perf               |\n");
        printf("+------------------+--------------------+\n");
        printf("| %-16s | %-14.f(ms) |\n", "Vision", vision_cost.get_time());
        // printf("| %-16s | %-10.d(tokens) |\n", "SeqLen",result->perf.prefill_tokens);
        // printf("| %-16s | %-10.d(tokens) |\n", "GenLen",result->perf.generate_tokens);
        // printf("| %-16s | %-8.3f(tokens/s) |\n", "Pefill",result->perf.prefill_tokens/result->perf.prefill_time_ms*1000.);
        printf("| %-16s | %-14.3f(ms) |\n", "TTFT", llm_perfill.get_time());
        printf("| %-16s | %-8.3f(tokens/s) |\n", "TPS", tps);
        printf("+------------------+--------------------+\n");

        fprintf(stderr, "[rknn3_model_stress_test_error] perf jitter %.2f%% exceeds 20%% (last=%.3f, cur=%.3f)\n",
                ratio * 100, last_perf, cur_perf);
        exit(EXIT_FAILURE);  // 异常退出
    } else if (ratio > 0.2f) {
        fprintf(stderr, "[rknn3_model_stress_test_warnning] perf jitter %.2f%% exceeds 10%% (last=%.3f, cur=%.3f)\n",
                ratio * 100, last_perf, cur_perf);
    }
}

int inference_rknn3_vlm_model(rknn_app_context_t* app_ctx, 
                                image_buffer_t* img,
                                float16* img_embeds,
                                rknn3_llm_multimodal_tensor tensor,
                                int n_inputs,
                                int vision_loop,
                                int llm_loop,
                                int time_loop)
{
    int ret;

    if ((!app_ctx) || (!img))
    {
        printf("[rknn3_model_stress_test_error] app_ctx or img is NULL");
        return -1;
    }
    static float last_vision_cost = 0.f;
    static float last_ttft = 0.f;
    static float last_tps = 0.f;

    // int32_t is_time_loop_mode = 0;
    if(time_loop != 0) {
        float time_loop_ms = (float)time_loop *60.*60.*1000.;
        TIMER infer_cost_time;
        infer_cost_time.tik();
        int32_t model_loop = 0;
        while(1) {
            ret = inference_rknn3_vlm_vision(&(app_ctx->vision), img, img_embeds,1);
            if (ret != 0)
            {
                printf("[rknn3_model_stress_test_error] inference rknn3_vlm vision model fail! ret=%d\n", ret);
                return ret;
            }
              
            ret = inference_rknn3_vlm_llm(&(app_ctx->llm), tensor, n_inputs,1);
            if (ret != 0)
            {
                printf("[rknn3_model_stress_test_error] inference rknn3_vlm llm model fail! ret=%d\n", ret);
                return ret;
            };
            infer_cost_time.tok();
            float tmp_time = infer_cost_time.get_time();

            model_loop ++;
            if(tmp_time >time_loop_ms) {
                break;
            }
            // printf("vlm run: %d/%d\n",model_loop);
            infer_cost_time.print_time("cost_time");
            if(last_vision_cost != 0.f && (model_loop > 10)) { // 为了防止不稳定，10次以后才开始性能测试
                check_perfance(last_vision_cost,vision_cost.get_time());
                check_perfance(last_ttft,llm_perfill.get_time());
                check_perfance(last_tps,tps);
                last_vision_cost = vision_cost.get_time();
                last_ttft = llm_perfill.get_time();
                last_tps = tps;
            }
            // printf("\n+------------------+--------------------+\n");
            // printf("| Stage            | Perf               |\n");
            // printf("+------------------+--------------------+\n");
            // printf("| %-16s | %-14.f(ms) |\n", "Vision", vision_cost.get_time());
            // // printf("| %-16s | %-10.d(tokens) |\n", "SeqLen",result->perf.prefill_tokens);
            // // printf("| %-16s | %-10.d(tokens) |\n", "GenLen",result->perf.generate_tokens);
            // // printf("| %-16s | %-8.3f(tokens/s) |\n", "Pefill",result->perf.prefill_tokens/result->perf.prefill_time_ms*1000.);
            // printf("| %-16s | %-14.3f(ms) |\n", "TTFT", llm_perfill.get_time());
            // printf("| %-16s | %-8.3f(tokens/s) |\n", "TPS", tps);
            // printf("+------------------+--------------------+\n");
            
        }
    } else  {
        // printf("--> inference rknn3_vlm vision model\n");
        if(vision_loop == llm_loop) {
            for(int i = 0;i < vision_loop;i ++) {
                ret = inference_rknn3_vlm_vision(&(app_ctx->vision), img, img_embeds,1);
                if (ret != 0)
                {
                    printf("[rknn3_model_stress_test_error] inference rknn3_vlm vision model fail! ret=%d\n", ret);
                    return ret;
                }
                
                ret = inference_rknn3_vlm_llm(&(app_ctx->llm), tensor, n_inputs,1);
                if (ret != 0)
                {
                    printf("[rknn3_model_stress_test_error] inference rknn3_vlm llm model fail! ret=%d\n", ret);
                    return ret;
                };
                printf("vlm run: %d/%d\n",i+1,vision_loop);
                if(last_vision_cost != 0.f && (i > 10)) { // 为了防止不稳定，10次以后才开始性能测试
                    check_perfance(last_vision_cost,vision_cost.get_time());
                    check_perfance(last_ttft,llm_perfill.get_time());
                    check_perfance(last_tps,tps);
                    last_vision_cost = vision_cost.get_time();
                    last_ttft = llm_perfill.get_time();
                    last_tps = tps;
                }

            }
        }else {
            ret = inference_rknn3_vlm_vision(&(app_ctx->vision), img, img_embeds,vision_loop);
            if (ret != 0)
            {
                printf("[rknn3_model_stress_test_error] inference rknn3_vlm vision model fail! ret=%d\n", ret);
                return ret;
            }

            ret = inference_rknn3_vlm_llm(&(app_ctx->llm), tensor, n_inputs,llm_loop);

            if (ret != 0)
            {
                printf("[rknn3_model_stress_test_error] inference rknn3_vlm llm model fail! ret=%d\n", ret);
                return ret;
            }
            // printf("vlm run %d end\n",i);
        }


    }
    
    if(ret == 0) {
        printf("[rknn3_model_stress_test_done] rknn3_vlm_demo run done\n");
    }
    
    return ret;
}