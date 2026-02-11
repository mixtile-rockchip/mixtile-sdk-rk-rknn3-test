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
#include <time.h>
#include <unistd.h>

#include "cmdline_parser.h"
#include "image_utils.h"
#include "rknn3_cnn_test.h"

/*-------------------------------------------
                  Main Function
-------------------------------------------*/
rknn3_cnn_perf_t g_perf;
static int64_t get_model_memory(rknn3_context ctx) {
    int ret;
    // Query model required core number
    uint32_t model_core_num = 0;
    int64_t tot_memory = 0;
    ret = rknn3_query(ctx, RKNN3_QUERY_CORE_NUMBER, &model_core_num, sizeof(model_core_num));
    if (ret < 0) {
        printf("[rknn3_model_stress_test_error] rknn3_query core number failed! ret=%d\n", ret);
        rknn3_destroy(ctx);
        return -1;
    }
    rknn3_core_mem_size *core_mem_sizes = (rknn3_core_mem_size *)malloc(sizeof(rknn3_core_mem_size) * model_core_num);

    if (!core_mem_sizes) {
        printf("Failed to allocate memory for core_mem_sizes\n");
        return ret;
    }

    ret = rknn3_query(ctx, RKNN3_QUERY_CORE_MEM_SIZE, core_mem_sizes, sizeof(rknn3_core_mem_size) * model_core_num);
    if (ret < 0) {
        printf("rknn3_query core memory size failed! ret=%d\n", ret);
        return ret;
    }
    for (int i = 0; i < model_core_num; i++) {
        tot_memory += core_mem_sizes[i].weight_size;
        tot_memory += core_mem_sizes[i].internal_size;
        printf("core %d: weight_size=%ld, internal_size=%ld\n", i, core_mem_sizes[i].weight_size, core_mem_sizes[i].internal_size);
    }
    if (core_mem_sizes) {
        free(core_mem_sizes);
    }
    return tot_memory;
}
int main(int argc, char **argv) {
    cmdline_args_t args;
    int ret;

    // Parse command line arguments
    ret = parse_cmdline_args(argc, argv, &args);
    if (ret != 0 || args.show_help) {
        print_usage(argv[0], PROGRAM_TYPE_CNN, NULL, 0);
        free_cmdline_args(&args);
        return args.show_help ? 0 : -1;
    }

    // Validate required arguments using common function
    ret = validate_required_params(&args, PROGRAM_TYPE_CNN);
    if (ret != 0) {
        print_usage(argv[0], PROGRAM_TYPE_CNN, NULL, 0);
        free_cmdline_args(&args);
        return -1;
    }

    // Handle time_loop override
    handle_time_loop_override(&args, PROGRAM_TYPE_CNN);

    // Print configuration using common function
    print_configuration(&args, PROGRAM_TYPE_CNN);

    srand((unsigned int)time(NULL));

    // RKNN Context
    rknn_common_img_ctx rknn_app_ctx;
    memset(&rknn_app_ctx, 0, sizeof(rknn_common_img_ctx));

    // Input Image
    image_buffer_t src_image;
    memset(&src_image, 0, sizeof(image_buffer_t));

    // Set image format based on yuv flag
    src_image.format = args.yuv_input ? IMAGE_FORMAT_YUV420SP_NV12 : IMAGE_FORMAT_RGB888;

    // 若未提供图片路径，则使用随机输入
    if (args.image_path == NULL || strlen(args.image_path) == 0) {
        src_image.width = 640;
        src_image.height = 640;
        src_image.size = args.yuv_input ? (src_image.width * src_image.height * 3) / 2
                                        : (src_image.width * src_image.height * 3);
        src_image.virt_addr = (uint8_t *)malloc(src_image.size);
        if (!src_image.virt_addr) {
            printf("[rknn3_model_stress_test_error] malloc random input buffer fail!\n");
            free_cmdline_args(&args);
            return -1;
        }
        // 填充随机数据
        for (int i = 0; i < src_image.size; ++i) {
            src_image.virt_addr[i] = rand() & 0xFF;
        }
    } else {
        // 正常读取图片
        ret = read_image(args.image_path, &src_image);
        if (ret != 0) {
            printf("[rknn3_model_stress_test_error] read image fail! ret=%d image_path=%s\n", ret, args.image_path);
            free_cmdline_args(&args);
            return -1;
        }
    }
    // Initialize model
    ret = init_common_img(&rknn_app_ctx, args.model_path, args.weight_path,
                          args.core_mask, args.device_id, src_image.format);
    if (ret != 0) {
        printf("[rknn3_model_stress_test_error] init_common_img fail! ret=%d model_path=%s weight_path=%s\n",
               ret, args.model_path, args.weight_path);
        free(src_image.virt_addr);
        free_cmdline_args(&args);
        return -1;
    }

    g_perf.infer_cnt = 0;
    g_perf.total_time = 0.0f;
    g_perf.avg_cost = 0.0f;
    g_perf.avg_FPS = 0.0f;
    g_perf.tot_memory = 0;
    int64_t tot_memory = 0;
    // printf("------------\n");
    g_perf.tot_memory = get_model_memory(rknn_app_ctx.rknn_ctx);
    if (g_perf.tot_memory < 0) {
        printf("[rknn3_model_stress_test_error] get_model_memory fail! ret=%ld\n", g_perf.tot_memory);
        goto cleanup;
    }
    // g_perf.tot_memory = tot_memory;
    // Run inference
    ret = inference_common_img(&rknn_app_ctx, &src_image, args.cnt_loop,
                               args.time_loop);
    if (ret != 0) {
        printf("[rknn3_model_stress_test_error] inference model fail! ret=%d\n", ret);
        goto cleanup;
    }

cleanup:
    ret = release_common_img(&rknn_app_ctx);
    if (ret != 0) {
        printf("[rknn3_model_stress_test_error] release model fail! ret=%d\n", ret);
    }

    if (src_image.virt_addr != NULL) {
        free(src_image.virt_addr);
    }

    const char *last_slash = strrchr(args.model_path, '/');
    const char *filename;

    if (last_slash != NULL) {
        filename = last_slash + 1;
    } else {
        filename = args.model_path;
    }

    char model_name[256];
    strncpy(model_name, filename, sizeof(model_name) - 1);
    model_name[sizeof(model_name) - 1] = '\0';
    char *last_dot = strrchr(model_name, '.');
    if (last_dot != NULL) {
        if (strcmp(last_dot, ".rknn") == 0) {
            *last_dot = '\0';
        }
    }

    printf("\n===== RKNN3_CNN_TEST Results Summary =====\n\n");
    printf("Model: %s\n", model_name);
    printf("DeviceId: %s\n", g_perf.device_id_mac);
    printf("ModelMemory: %.3f MB\n", (float)g_perf.tot_memory / (1024.0 * 1024.0));
    printf("InputFormat: %s\n", g_perf.input_format);
    printf("InferCnt: %d\n", g_perf.infer_cnt);
    printf("TotalTime: %.6f ms\n", g_perf.total_time);
    printf("AvgCost: %.6f ms\n", g_perf.avg_cost);
    printf("AvgFPS: %.2f\n", g_perf.avg_FPS);
    printf("\n=================================\n");
    printf("[rknn3_model_stress_test_done]\n");

    free_cmdline_args(&args);

    return ret;
}