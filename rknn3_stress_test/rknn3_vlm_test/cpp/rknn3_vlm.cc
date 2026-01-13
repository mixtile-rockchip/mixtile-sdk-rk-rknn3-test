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
#include "MemoryMonitor.h"
// #include "rknn_api.h"
#include <math.h>

// External variables from main.cc
extern int32_t gen_tokens;

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


int init_rknn3_vlm_model(rknn_app_context_t* app_ctx,
                        const char* llm_model_path,
                        const char* llm_weight_path,
                        const char* vision_model_path,
                        const char* vision_weight_path,
                        rknn3_llm_param* params, int n_params,
                        RKLLMCallback callback,
                        uint32_t vision_core_mask,
                        uint32_t llm_core_mask)
{
    int ret = 0;

    printf("--> init rknn3_vlm vision model\n");
    ret = init_rknn3_vlm_vision(&(app_ctx->vision), vision_model_path, vision_weight_path, vision_core_mask);
    if (ret < 0)
    {
        printf("rknn_init rknn3_vlm vision model fail! ret=%d\n", ret);
        return ret;
    }

    printf("--> init rknn3_vlm llm model\n");
    ret = init_rknn3_vlm_llm(&(app_ctx->llm), llm_model_path, llm_weight_path, params, n_params, callback, llm_core_mask);
    if (ret < 0)
    {
        printf("rknn_init rknn3_vlm llm model fail! ret=%d\n", ret);
        return ret;
    }

    if(app_ctx->vision.io_num.n_output > 1) {
        rknn3_tensor_attr deepstack_attrs[3];
        for(int i = 0; i < 3; i++) {
            int32_t deepstack_aligned_size = app_ctx->vision.outputs[i].attr->aligned_size;
            printf("deepstack_aligned_size = %d \n", deepstack_aligned_size);

            deepstack_attrs[i].index = 2 + i; //deepstack的index为2、3、 4,可以通过rknn3_query查询所有input_attrs定位到deepstack的index
            ret = rknn3_query(app_ctx->llm.rknn_ctx, RKNN3_QUERY_INPUT_ATTR, &(deepstack_attrs[i]), sizeof(rknn3_tensor_attr));
            if (ret < 0) {
            printf("rknn_query fail! ret=%d\n", ret);
            return -1;
            }

            app_ctx->llm.deepstack_tensor[i].mem = rknn3_create_mem(app_ctx->llm.rknn_ctx, deepstack_aligned_size, deepstack_attrs[i].core_id, RKNN3_FLAG_MEMORY_CACHEABLE);
            if (!app_ctx->llm.deepstack_tensor[i].mem) {
            printf("fail to create aux_input_tensor.mem!\n");
            return -1;
            }
        }
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
    if(app_ctx->vision.io_num.n_output > 1) {
        for(int i = 0; i < 3; i++) {
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
        printf("| %-16s | %-14.f(ms) |\n", "Vision", vision_cost.get_time());
        // printf("| %-16s | %-10.d(tokens) |\n", "SeqLen",result->perf.prefill_tokens);
        // printf("| %-16s | %-10.d(tokens) |\n", "GenLen",result->perf.generate_tokens);
        // printf("| %-16s | %-8.3f(tokens/s) |\n", "Pefill",result->perf.prefill_tokens/result->perf.prefill_time_ms*1000.);
        printf("| %-16s | %-14.3f(ms) |\n", "TTFT", llm_perfill.get_time());
        printf("| %-16s | %-8.3f(tokens/s) |\n", "TPS", tps);
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
        printf("| %-16s | %-14.f(ms) |\n", "Vision", vision_cost.get_time());
        // printf("| %-16s | %-10.d(tokens) |\n", "SeqLen",result->perf.prefill_tokens);
        // printf("| %-16s | %-10.d(tokens) |\n", "GenLen",result->perf.generate_tokens);
        // printf("| %-16s | %-8.3f(tokens/s) |\n", "Pefill",result->perf.prefill_tokens/result->perf.prefill_time_ms*1000.);
        printf("| %-16s | %-14.3f(ms) |\n", "TTFT", llm_perfill.get_time());
        printf("| %-16s | %-8.3f(tokens/s) |\n", "TPS", tps);
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

int inference_rknn3_vlm_model(rknn_app_context_t* app_ctx,
                                image_buffer_t* img,
                                rknn3_llm_multimodal_tensor tensor,
                                int vision_loop,
                                int llm_loop,
                                float time_loop)
{
    int ret;

    if ((!app_ctx) || (!img))
    {
        printf("[rknn3_model_stress_test_error] app_ctx or img is NULL");
        return -1;
    }

    // Initialize memory monitor
    MemoryMonitor* memory_monitor = new MemoryMonitor(100000); // 100ms interval

    // 设置目标设备（只监控推理使用的设备）
    std::vector<uint16_t> target_devices = {(uint16_t)app_ctx->device_id};
    memory_monitor->set_target_devices(target_devices);

    if (!memory_monitor->initialize()) {
        printf("[rknn3_model_stress_test_warning] Memory monitor initialization failed, memory monitoring will be disabled\n");
        delete memory_monitor;
        memory_monitor = nullptr;
    } else {
        memory_monitor->set_realtime_print(false);
        printf("[rknn3_model_stress_test] Memory monitor initialized successfully\n");
    }
    static float last_vision_cost = 0.f;
    static float last_ttft = 0.f;
    static float last_tps = 0.f;
    static int32_t last_gen_tokens = 0;

    int acc_cnt = 0;
    float acc_ms = 0.f;
    TIMER one_infer_time;
    #if 0
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
                    check_perfance(last_vision_cost,vision_cost.get_time(), last_gen_tokens, gen_tokens);
                    check_perfance(last_ttft,llm_perfill.get_time(), last_gen_tokens, gen_tokens);
                    check_perfance(last_tps,tps, last_gen_tokens, gen_tokens);
                    last_vision_cost = vision_cost.get_time();
                    last_ttft = llm_perfill.get_time();
                    last_tps = tps;
                    last_gen_tokens = gen_tokens;
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
    #else

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
        infer_cost_time.tik();
        int iter = 0;
        // Start memory monitoring
        if (memory_monitor) {
            memory_monitor->start_monitoring();
        }
        while (true) {

            one_infer_time.tik();
            ret = inference_rknn3_vlm_vision(&(app_ctx->vision), img, 1);
            if (ret == 0) {
                memcpy(tensor.image.image_embed, (float16*)app_ctx->vision.outputs[0].mem->virt_addr, app_ctx->vision.outputs[0].mem->size);

                if(app_ctx->vision.io_num.n_output > 1) {
                    memcpy((uint8_t*)app_ctx->llm.deepstack_tensor[0].mem->virt_addr, (uint8_t*)app_ctx->vision.outputs[1].mem->virt_addr, app_ctx->vision.outputs[1].mem->size);
                    memcpy((uint8_t*)app_ctx->llm.deepstack_tensor[1].mem->virt_addr, (uint8_t*)app_ctx->vision.outputs[2].mem->virt_addr, app_ctx->vision.outputs[2].mem->size);
                    memcpy((uint8_t*)app_ctx->llm.deepstack_tensor[2].mem->virt_addr, (uint8_t*)app_ctx->vision.outputs[3].mem->virt_addr, app_ctx->vision.outputs[3].mem->size);
                }
            // memcpy(img_embeds, (float16*)vision_ctx->outputs[0].mem->virt_addr, vision_ctx->outputs[0].mem->size);

                ret = inference_rknn3_vlm_llm(&(app_ctx->llm), tensor, n_inputs, 1);
            }



            if (ret != 0) {
                printf("[rknn3_model_stress_test_error] inference fail! ret=%d\n", ret);
                return ret;
            }

            iter++;
            infer_loop_cnt = iter;
            infer_cost_time.tok();
            float current_total_ms = infer_cost_time.get_time();
            one_infer_time.tok();
            // if (!is_time_mode) {
            //     printf("\n vlm run: %d/%d\n", iter, vision_loop);
            // }
            // else {
            //     infer_cost_time.print_time("cost_time:");
            // }
            acc_cnt += 1;
            acc_ms += one_infer_time.get_time();
            if(acc_cnt >= 100) {
                printf("run_cnt diff: %d, run cost: %8.2f ms \n",acc_cnt,acc_ms);
                acc_cnt = 0;
                acc_ms = 0.0f;
            }


            if (last_vision_cost != 0.f && iter > 10) {
                check_perfance(last_vision_cost, vision_cost.get_time(), last_gen_tokens, gen_tokens);
                check_perfance(last_ttft, llm_perfill.get_time(), last_gen_tokens, gen_tokens);
                check_perfance(last_tps, tps, last_gen_tokens, gen_tokens);

                last_vision_cost = vision_cost.get_time();
                last_ttft = llm_perfill.get_time();
                last_tps = tps;
                last_gen_tokens = gen_tokens;
            }
            if (is_time_mode) {
                if (current_total_ms >= time_limit_ms)
                    break;
            } else {
                if (iter >= max_iters)
                    break;
            }
        }
        // Stop memory monitoring
        if (memory_monitor) {
            memory_monitor->stop_monitoring();
        }
    }

    #endif

    if(ret == 0) {
        printf("[rknn3_model_stress_test_done] rknn3_vlm_demo run done\n");
        printf("\n===== RKNN3_VLM_TEST Results =====\n");
        printf("Vision: %.f ms\n", vision_cost.get_time());
        printf("GenLen: %d tokens\n", gen_tokens);
        printf("TTFT: %.3f ms\n", llm_perfill.get_time());
        printf("TPS: %.3f tokens/s\n", tps);

        // Print memory statistics
        if (memory_monitor) {
            MemoryStatistics mem_stats = memory_monitor->get_statistics();
            if (mem_stats.is_valid && !mem_stats.devices.empty()) {
                const DeviceMemoryStats& dev = mem_stats.devices[0];
                printf("AvgMemoryUsage: %.2f MB (%.1f%%)\n",
                       dev.avg_used_memory / 1024.0f / 1024.0f, dev.avg_usage_percent);
                printf("AvgNpuUtilization: %u%%\n", dev.avg_npu_util);
            } else {
                printf("AvgMemoryUsage: \n");
                printf("AvgNpuUtilization: error\n");
            }
        } else {
            printf("AvgMemoryUsage: unavailable\n");
            printf("AvgNpuUtilization: unavailable\n");
        }

    }

    // Cleanup memory monitor
    if (memory_monitor) {
        delete memory_monitor;
        memory_monitor = nullptr;
    }

    return ret;
}