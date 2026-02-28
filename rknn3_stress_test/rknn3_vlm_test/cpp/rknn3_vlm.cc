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

#include "rknn3_vlm.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "common.h"
#include "image_utils.h"

// External variables from main.cc
// extern int32_t gen_tokens;
// internal memory is not counted
static int64_t get_model_memory(rknn_app_context_t *app_ctx) {
    // internal memory is not counted
    int64_t tot_memory = 0;
    // Query model required core number
    uint32_t model_core_num = 0;
    int ret = 0;
    ret = rknn3_query(app_ctx->vision.rknn_ctx, RKNN3_QUERY_CORE_NUMBER, &model_core_num, sizeof(model_core_num));
    if (ret < 0) {
        printf("[rknn3_model_stress_test_error] rknn3_query core number failed! ret=%d\n", ret);
        rknn3_destroy(app_ctx->vision.rknn_ctx);
        return -1;
    }

    rknn3_allocation_info *allocation_info = (rknn3_allocation_info *)malloc(sizeof(rknn3_allocation_info) * model_core_num);
    ret = rknn3_query(app_ctx->vision.rknn_ctx, RKNN3_QUERY_ALLOCATION_INFO, allocation_info, sizeof(rknn3_allocation_info) * model_core_num);
    if (ret < 0) {
        printf("rknn3_query allocation info failed! ret=%d\n", ret);
        return ret;
    }
    printf("vision model mem.\n");
    // printf("allocation_info[i].weight_mem.size: %d\n",allocation_info[0].weight_mem.size);
    for (int i = 0; i < model_core_num; i++) {
        // printf("id:%d,allocation_info.weights_size=%d, allocation_info.internal_size=%d, allocation_info.weights_mem_size=%d, allocation_info.internal_mem_size=%d\n",
        //     i,allocation_info[i].weight_mem.size / 1024/1024, allocation_info[i].internal_mem.size/1024/1024,
        //     allocation_info[i].command_mem.size/1024/1024, allocation_info[i].kvcache_mem.size/1024/1024);
        tot_memory += allocation_info[i].weight_mem.size;
        // tot_memory += allocation_info[i].internal_mem.size;
        tot_memory += allocation_info[i].command_mem.size;
        tot_memory += allocation_info[i].kvcache_mem.size;
    }
    if (allocation_info) {
        free(allocation_info);
        allocation_info = NULL;
    }

    ret = rknn3_query(app_ctx->llm.rknn_ctx, RKNN3_QUERY_CORE_NUMBER, &model_core_num, sizeof(model_core_num));
    if (ret < 0) {
        printf("[rknn3_model_stress_test_error] rknn3_query core number failed! ret=%d\n", ret);
        rknn3_destroy(app_ctx->llm.rknn_ctx);
        return -1;
    }

    allocation_info = (rknn3_allocation_info *)malloc(sizeof(rknn3_allocation_info) * model_core_num);
    ret = rknn3_query(app_ctx->llm.rknn_ctx, RKNN3_QUERY_ALLOCATION_INFO, allocation_info, sizeof(rknn3_allocation_info) * model_core_num);
    if (ret < 0) {
        printf("rknn3_query allocation info failed! ret=%d\n", ret);
        return ret;
    }
    printf("llm model mem.\n");
    // printf("allocation_info[i].weight_mem.size: %d\n",allocation_info[0].weight_mem.size);
    for (int i = 0; i < model_core_num; i++) {
        // printf("id:%d,allocation_info.weights_size=%d, allocation_info.internal_size=%d, allocation_info.weights_mem_size=%d, allocation_info.internal_mem_size=%d\n",
        //     i,allocation_info[i].weight_mem.size / 1024/1024, allocation_info[i].internal_mem.size/1024/1024,
        //     allocation_info[i].command_mem.size/1024/1024, allocation_info[i].kvcache_mem.size/1024/1024);
        tot_memory += allocation_info[i].weight_mem.size;
        // tot_memory += allocation_info[i].internal_mem.size;
        tot_memory += allocation_info[i].command_mem.size;
        tot_memory += allocation_info[i].kvcache_mem.size;
    }
    if (allocation_info) {
        free(allocation_info);
        allocation_info = NULL;
    }

    return tot_memory;
}


int init_internal_share(rknn_app_context_t *app_ctx, uint32_t core_mask_vision, uint32_t core_mask_llm) {
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
    rknn3_core_mem_size *core_mem_sizes_vision = (rknn3_core_mem_size *)malloc(sizeof(rknn3_core_mem_size) * core_num_vision);
    if (!core_mem_sizes_vision) {
        printf("Failed to allocate memory for core_mem_sizes_vision\n");
        return ret;
    }
    rknn3_core_mem_size *core_mem_sizes_llm = (rknn3_core_mem_size *)malloc(sizeof(rknn3_core_mem_size) * core_num_llm);
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
    for (int i = 0; i < core_num_llm; i++) {
        llm_to_vision[i] = -1;
    }
    g_vlm_perf.tot_memory += get_model_memory(app_ctx);
    int core_num_same = 0;
    for (int i = 0; i < core_num_vision; i++) {
        for (int j = 0; j < core_num_llm; j++) {
            if (core_mem_sizes_vision[i].core_id == core_mem_sizes_llm[j].core_id) {
                uint64_t internal_size = std::max(core_mem_sizes_vision[i].internal_size, core_mem_sizes_llm[j].internal_size);
                core_mem_sizes_vision[i].internal_size = internal_size;
                core_mem_sizes_llm[j].internal_size = internal_size;
                core_num_same++;
                llm_to_vision[j] = i;
                break;
            }
        }
    }

    app_ctx->n_internal_mems = core_num_vision + core_num_llm - core_num_same;
    app_ctx->internal_mems = (rknn3_tensor_mem **)calloc(app_ctx->n_internal_mems, sizeof(rknn3_tensor_mem *));
    if (!app_ctx->internal_mems) {
        printf("Failed to allocate memory for app_ctx->internal_mems array\n");
        return -1;
    }
    rknn3_tensor_mem **internal_mems_vision = (rknn3_tensor_mem **)calloc(core_num_vision, sizeof(rknn3_tensor_mem *));
    if (!internal_mems_vision) {
        printf("Failed to allocate memory for internal_mems_vision array\n");
        return -1;
    }
    rknn3_tensor_mem **internal_mems_llm = (rknn3_tensor_mem **)calloc(core_num_llm, sizeof(rknn3_tensor_mem *));
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
        // printf("Created user internal memory for core %d: size=%lu, virt_addr=%p, phys_addr=0x%lx\n", core_mem_sizes_vision[i].core_id,
        //         internal_mems_vision[i]->size, internal_mems_vision[i]->virt_addr, internal_mems_vision[i]->phys_addr);
        g_vlm_perf.tot_memory += internal_mems_vision[i]->size;
        app_ctx->internal_mems[idx++] = internal_mems_vision[i];
    }
    for (uint32_t i = 0; i < core_num_llm; i++) {
        if (llm_to_vision[i] != -1) {
            internal_mems_llm[i] = internal_mems_vision[llm_to_vision[i]];
            continue;
        }
        internal_mems_llm[i] = rknn3_create_mem(app_ctx->vision.rknn_ctx, core_mem_sizes_llm[i].internal_size, core_mem_sizes_llm[i].core_id, RKNN3_FLAG_MEMORY_CACHEABLE);
        if (!internal_mems_llm[i]) {  // 都使用vision.rknn_ctx分配, 方便后面释放
            return -1;
        }
        // printf("Created user internal memory for core %d: size=%lu, virt_addr=%p, phys_addr=0x%lx\n", core_mem_sizes_llm[i].core_id,
        //         internal_mems_llm[i]->size, internal_mems_llm[i]->virt_addr, internal_mems_llm[i]->phys_addr);
        g_vlm_perf.tot_memory += internal_mems_llm[i]->size;
        app_ctx->internal_mems[idx++] = internal_mems_llm[i];
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

int release_internal_share(rknn_app_context_t *app_ctx) {
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

int init_rknn3_vlm_model(rknn_app_context_t *app_ctx,
                         const char *llm_model_path,
                         const char *llm_weight_path,
                         const char *vision_model_path,
                         const char *vision_weight_path,
                         rknn3_llm_param *params, int n_params,
                         RKLLMCallback callback,
                         uint32_t vision_core_mask,
                         uint32_t llm_core_mask) {
    int ret = 0;
    if (vision_core_mask == 0 || llm_core_mask == 0) {
        printf("[rknn3_stress_test_log] core_mask=0, auto-generate mask from model core number\n");
    }

    printf("--> init rknn3_vlm vision model\n");
    g_vlm_perf.load_vision_model.tik();
    ret = init_rknn3_vlm_vision(&(app_ctx->vision), vision_model_path, vision_weight_path, vision_core_mask);
    if (ret < 0) {
        printf("rknn_init rknn3_vlm vision model fail! ret=%d\n", ret);
        return ret;
    }
    g_vlm_perf.load_vision_model.tok();
    printf("--> init rknn3_vlm llm model\n");
    g_vlm_perf.load_llm_model.tik();
    ret = init_rknn3_vlm_llm(&(app_ctx->llm), llm_model_path, llm_weight_path, params, n_params, callback, llm_core_mask);
    if (ret < 0) {
        printf("rknn_init rknn3_vlm llm model fail! ret=%d\n", ret);
        return ret;
    }
    g_vlm_perf.load_llm_model.tok();
    if (app_ctx->vision.io_num.n_output > 1) {
        rknn3_tensor_attr deepstack_attrs[3];
        for (int i = 0; i < 3; i++) {
            int32_t deepstack_aligned_size = app_ctx->vision.outputs[i].attr->aligned_size;
            printf("deepstack_aligned_size = %d \n", deepstack_aligned_size);

            deepstack_attrs[i].index = 2 + i;  // deepstack的index为2、3、 4,可以通过rknn3_query查询所有input_attrs定位到deepstack的index
            ret = rknn3_query(app_ctx->llm.rknn_ctx, RKNN3_QUERY_INPUT_ATTR, &(deepstack_attrs[i]), sizeof(rknn3_tensor_attr));
            if (ret < 0) {
                printf("[rknn3_model_stress_test_error] rknn_query fail! ret=%d\n", ret);
                return -1;
            }

            app_ctx->llm.deepstack_tensor[i].mem = rknn3_create_mem(app_ctx->llm.rknn_ctx, deepstack_aligned_size, deepstack_attrs[i].core_id, RKNN3_FLAG_MEMORY_CACHEABLE);
            if (!app_ctx->llm.deepstack_tensor[i].mem) {
                printf("[rknn3_model_stress_test_error] fail to create aux_input_tensor.mem!\n");
                return -1;
            }
        }
    }

    printf("--> init internal share\n");
    ret = init_internal_share(app_ctx, vision_core_mask, llm_core_mask);
    if (ret < 0) {
        printf("[rknn3_model_stress_test_error] llm/vision internal memeory share fail! ret=%d\n", ret);
        return ret;
    }

    return ret;
}

int release_rknn3_vlm_model(rknn_app_context_t *app_ctx) {
    release_internal_share(app_ctx);
    if (app_ctx->vision.io_num.n_output > 1) {
        for (int i = 0; i < 3; i++) {
            if (app_ctx->llm.deepstack_tensor[i].mem) {
                rknn3_destroy_mem(app_ctx->llm.rknn_ctx, app_ctx->llm.deepstack_tensor[i].mem);
                // rknn3_destroy_mem(llm_ctx->rknn_ctx, llm_ctx->deepstack_tensor[i].mem);
                app_ctx->llm.deepstack_tensor[i].mem = nullptr;
            }
        }
    }
    release_rknn3_vlm_vision(&(app_ctx->vision));
    release_rknn3_vlm_llm(&(app_ctx->llm));

    return 0;
}

void check_perfance(float last_perf, float cur_perf, int32_t last_gen_tokens, int32_t cur_gen_tokens) {
    if (last_perf <= 0) {
        fprintf(stderr, "Error: last_perf must be positive.\n");
        return;
    }

    // 检测 gen_tokens 是否一致
    if (last_gen_tokens != cur_gen_tokens) {
        printf("\n+------------------+--------------------+\n");
        printf("| Stage            | Perf               |\n");
        printf("+------------------+--------------------+\n");
        printf("| %-16s | %-14.f(ms) |\n", "Vision", g_vlm_perf.vision_cost.get_time());
        // printf("| %-16s | %-10.d(tokens) |\n", "SeqLen",result->perf.prefill_tokens);
        // printf("| %-16s | %-10.d(tokens) |\n", "GenLen",result->perf.generate_tokens);
        // printf("| %-16s | %-8.3f(tokens/s) |\n", "Pefill",result->perf.prefill_tokens/result->perf.prefill_time_ms*1000.);
        printf("| %-16s | %-14.3f(ms) |\n", "TTFT", g_vlm_perf.llm_perfill.get_time());
        printf("| %-16s | %-8.3f(tokens/s) |\n", "TPS", g_vlm_perf.tps);
        printf("| %-16s | %-10d        |\n", "GenTokens", cur_gen_tokens);
        printf("+------------------+--------------------+\n");

        fprintf(stderr, "[rknn3_model_stress_test_error] gen_tokens inconsistency! (last=%d, cur=%d)\n",
                last_gen_tokens, cur_gen_tokens);
        exit(EXIT_FAILURE);  // 异常退出
    }

    float diff = fabsf(cur_perf - last_perf);
    float ratio = diff / last_perf;  // 抖动比例

    if (ratio > 0.5f) {
        printf("\n+------------------+--------------------+\n");
        printf("| Stage            | Perf               |\n");
        printf("+------------------+--------------------+\n");
        printf("| %-16s | %-14.f(ms) |\n", "Vision", g_vlm_perf.vision_cost.get_time());
        // printf("| %-16s | %-10.d(tokens) |\n", "SeqLen",result->perf.prefill_tokens);
        // printf("| %-16s | %-10.d(tokens) |\n", "GenLen",result->perf.generate_tokens);
        // printf("| %-16s | %-8.3f(tokens/s) |\n", "Pefill",result->perf.prefill_tokens/result->perf.prefill_time_ms*1000.);
        printf("| %-16s | %-14.3f(ms) |\n", "TTFT", g_vlm_perf.llm_perfill.get_time());
        printf("| %-16s | %-8.3f(tokens/s) |\n", "TPS", g_vlm_perf.tps);
        printf("| %-16s | %-10d        |\n", "GenTokens", cur_gen_tokens);
        printf("+------------------+--------------------+\n");

        fprintf(stderr, "[rknn3_model_stress_test_error] perf jitter %.2f%% exceeds 20%% (last=%.3f, cur=%.3f)\n",
                ratio * 100, last_perf, cur_perf);
        exit(EXIT_FAILURE);  // 异常退出
    } else if (ratio > 0.2f) {
        fprintf(stderr, "[rknn3_model_stress_test_warnning] perf jitter %.2f%% exceeds 10%% (last=%.3f, cur=%.3f)\n",
                ratio * 100, last_perf, cur_perf);
    }
}

int inference_rknn3_vlm_model(rknn_app_context_t *app_ctx,
                              image_buffer_t *img,
                              rknn3_llm_multimodal_tensor tensor,
                              int vision_loop,
                              int llm_loop,
                              float time_loop) {
    int ret;

    if ((!app_ctx) || (!img)) {
        printf("[rknn3_model_stress_test_error] app_ctx or img is NULL");
        return -1;
    }

    static float last_vision_cost = 0.f;
    static float last_ttft = 0.f;
    static float last_tps = 0.f;
    static int32_t last_gen_tokens = 0;

    int acc_cnt = 0;
    float acc_ms = 0.f;
    TIMER one_infer_time;
    float print_interval = 1 * 1000 * 40;  // 40s

    bool is_time_mode = (time_loop != 0);
    bool is_equal_loop = (vision_loop == llm_loop);
    float time_limit_ms = is_time_mode ? (float)time_loop * 3600.0f * 1000.0f : 0;
    int max_iters = (!is_time_mode && is_equal_loop) ? vision_loop : 1;
    uint32_t n_inputs = app_ctx->vision.io_num.n_output;

    if (!is_time_mode && !is_equal_loop) {
        ret = inference_rknn3_vlm_vision(&(app_ctx->vision), img, vision_loop);
        if (ret == 0) {
            ret = inference_rknn3_vlm_llm(&(app_ctx->llm), tensor, n_inputs, llm_loop);
        }
        if (ret != 0) {
            printf("[rknn3_model_stress_test_error] inference fail! ret=%d\n", ret);
            return ret;
        }
    } else {
        g_vlm_perf.infer_cost_time.tik();
        int iter = 0;

        while (true) {
            one_infer_time.tik();
            ret = inference_rknn3_vlm_vision(&(app_ctx->vision), img, 1);
            if (ret == 0) {
                memcpy(tensor.image.image_embed, (float16 *)app_ctx->vision.outputs[0].mem->virt_addr, app_ctx->vision.outputs[0].mem->size);

                if (app_ctx->vision.io_num.n_output > 1) {
                    memcpy((uint8_t *)app_ctx->llm.deepstack_tensor[0].mem->virt_addr, (uint8_t *)app_ctx->vision.outputs[1].mem->virt_addr, app_ctx->vision.outputs[1].mem->size);
                    memcpy((uint8_t *)app_ctx->llm.deepstack_tensor[1].mem->virt_addr, (uint8_t *)app_ctx->vision.outputs[2].mem->virt_addr, app_ctx->vision.outputs[2].mem->size);
                    memcpy((uint8_t *)app_ctx->llm.deepstack_tensor[2].mem->virt_addr, (uint8_t *)app_ctx->vision.outputs[3].mem->virt_addr, app_ctx->vision.outputs[3].mem->size);
                }
                // memcpy(img_embeds, (float16*)vision_ctx->outputs[0].mem->virt_addr, vision_ctx->outputs[0].mem->size);

                ret = inference_rknn3_vlm_llm(&(app_ctx->llm), tensor, n_inputs, 1);
            }

            if (ret != 0) {
                printf("[rknn3_model_stress_test_error] inference fail! ret=%d\n", ret);
                return ret;
            }

            iter++;
            g_vlm_perf.infer_loop_cnt = iter;
            g_vlm_perf.infer_cost_time.tok();
            float current_total_ms = g_vlm_perf.infer_cost_time.get_time();
            one_infer_time.tok();
            acc_cnt += 1;
            acc_ms += one_infer_time.get_time();
            // if (acc_cnt >= 100) {
            //     printf("run_cnt diff: %d, run cost: %8.2f ms \n", acc_cnt, acc_ms);
            //     acc_cnt = 0;
            //     acc_ms = 0.0f;
            // }
            if(acc_ms >= print_interval) {
                printf("run_cnt : %d, run cost: %8.2f ms \n", iter, current_total_ms);
                acc_cnt = 0;
                acc_ms = 0.0f;
            }

            if (last_vision_cost != 0.f && iter > 10) {
                check_perfance(last_vision_cost, g_vlm_perf.vision_cost.get_time(), last_gen_tokens, g_vlm_perf.gen_tokens);
                check_perfance(last_ttft, g_vlm_perf.llm_perfill.get_time(), last_gen_tokens, g_vlm_perf.gen_tokens);
                check_perfance(last_tps, g_vlm_perf.tps, last_gen_tokens, g_vlm_perf.gen_tokens);

                last_vision_cost = g_vlm_perf.vision_cost.get_time();
                last_ttft = g_vlm_perf.llm_perfill.get_time();
                last_tps = g_vlm_perf.tps;
                last_gen_tokens = g_vlm_perf.gen_tokens;
            }
            if (is_time_mode) {
                if (current_total_ms >= time_limit_ms)
                    break;
            } else {
                if (iter >= max_iters)
                    break;
            }
        }
    }

    // if(ret == 0) {
    //     printf("[rknn3_model_stress_test_done] rknn3_vlm_demo run done\n");
    //     printf("\n===== RKNN3_VLM_TEST Results =====\n");
    //     printf("Vision: %.f ms\n", g_vlm_perf.vision_cost.get_time());
    //     printf("GenLen: %d tokens\n", g_vlm_perf.gen_tokens);
    //     printf("TTFT: %.3f ms\n", g_vlm_perf.llm_perfill.get_time());
    //     printf("TPS: %.3f tokens/s\n", g_vlm_perf.tps);

    // }

    return ret;
}