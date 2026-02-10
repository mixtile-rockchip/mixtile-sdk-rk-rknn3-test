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
#include <unistd.h>

#include "image_utils.h"
#include "rknn3_cnn_test.h"
#include "cmdline_parser.h"

/*-------------------------------------------
                  Main Function
-------------------------------------------*/

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

    if (args.model_folder) {
        (void)populate_args_from_model_folder(&args, PROGRAM_TYPE_CNN);
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

    // RKNN Context
    rknn_common_img_ctx rknn_app_ctx;
    memset(&rknn_app_ctx, 0, sizeof(rknn_common_img_ctx));

    // Input Image
    image_buffer_t src_image;
    memset(&src_image, 0, sizeof(image_buffer_t));

    // Set image format based on yuv flag
    src_image.format = args.yuv_input ? IMAGE_FORMAT_YUV420SP_NV12 : IMAGE_FORMAT_RGB888;

    
    // Read Image
    ret = read_image(args.image_path, &src_image);
    if (ret != 0) {
        printf("[rknn3_model_stress_test_error] read image fail! ret=%d image_path=%s\n", ret, args.image_path);
        free_cmdline_args(&args);
        return -1;
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

    printf("[rknn3_model_stress_test_done]\n");
    free_cmdline_args(&args);

    return ret;
}