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
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <unistd.h>

#include "rknn3_cnn_test.h"
#include "image_utils.h"

/*-------------------------------------------
                  Main Function
-------------------------------------------*/


void print_usage(char *argv[]) {
    printf("Usage:\n");
    printf("%s [options]\n\n", argv[0]);
    printf("Options:\n");
    printf("  -m, --model_path  .rknn model path  \n");
    printf("  -w, --weight_path .weight model path  \n");
    printf("  -c, --core_mask  core mask  \n");
    printf("  -i, --image_path  core mask  \n");
    printf("  -cl, --cnt_loop  default:1      \n");
    printf("  -tl, --time_loop(hours) \n");
    printf("\nUse '%s --help' to display this message.\n", argv[0]);

    return;

}

int main(int argc, char **argv)
{
    char *common_model_path;
    char *common_weight_path;
    char *img_path;
    uint32_t  core_mask = 0x01;
    uint32_t cnt_loop = 1 ;
    float time_loop = 0.f;
    uint32_t device_id = RKNN3_DEFAULT_DEVICE_ID;
    for (int i = 1; i < argc; i += 2) {
        if (strcmp(argv[i], "-m") == 0 || strcmp(argv[i], "--model_path") == 0) {
            common_model_path = argv[i + 1];
        } else if(strcmp(argv[i], "-w") == 0 || strcmp(argv[i], "--weight_path") == 0) {
            common_weight_path = argv[i + 1];
        } else if(strcmp(argv[i], "-c") == 0 || strcmp(argv[i], "--core_mask") == 0) {
             core_mask  = strtoul(argv[i + 1], nullptr, 16);
        } else if(strcmp(argv[i], "-cl") == 0 || strcmp(argv[i], "--cnt_loop") == 0) {
             cnt_loop  =atoi(argv[i+1]);
        } else if(strcmp(argv[i], "-tl") == 0 || strcmp(argv[i], "--time_loop") == 0) {
            time_loop = atof(argv[i+1]);
        } else if(strcmp(argv[i], "-i") == 0 || strcmp(argv[i], "--image_path") == 0) {
            img_path = argv[i + 1];
        } else if (strcmp(argv[i], "-id") == 0 || strcmp(argv[i], "--device_id") == 0) {
            device_id = atoi(argv[i + 1]);
        } else if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0) {
            print_usage(argv);
            return 0;
        } else {
            printf("[rknn3_model_stress_test_error] Unknown option: %s\n", argv[i]);
            print_usage(argv);
            return -1;
        }
    }

    int ret;
    // printf()

    // RKNN Context
    rknn_common_img_ctx rknn_app_ctx;
    memset(&rknn_app_ctx, 0, sizeof(rknn_common_img_ctx));

    // Input Image
    image_buffer_t src_image;
    memset(&src_image, 0, sizeof(image_buffer_t));

    // // Image Embed
    size_t embed_elems = 1;
    float16* img_embeds;

    // printf("core_mask :%d\n",core_mask);
    ret = init_common_img(&rknn_app_ctx, common_model_path, common_weight_path, core_mask, device_id);
    if (ret != 0)
    {
        printf("[rknn3_model_stress_test_error] init_common_img fail! ret=%d llm_model_path=%s vision_model_path=%s\n", ret, common_model_path, common_weight_path);
        return -1;
        // goto out;
    }

    // Image Embed
    for (size_t i = 0; i < rknn_app_ctx.embeds_ndims; i++)
    {
      embed_elems *= rknn_app_ctx.embeds_shape[i];
    //   printf("i:%d rknn_app_ctx.embeds_shape:%d\n",i,rknn_app_ctx.embeds_shape[i]);
    }
    // img_embeds = (float16*)malloc((embed_elems) * sizeof(float16));
    // memset(img_embeds,0,(embed_elems) * sizeof(float16));

    // Read Image
    ret = read_image(img_path, &src_image);
    if (ret != 0)
    {
        printf("[rknn3_model_stress_test_error] read image fail! ret=%d image_path=%s\n", ret, img_path);
        return -1;
        // goto out;
    }

    ret = inference_common_img(&rknn_app_ctx, &src_image, cnt_loop,time_loop);
    if (ret != 0)
    {
        printf("[rknn3_model_stress_test_error] inference model fail! ret=%d\n", ret);
        return -1;
        // goto out;
    }
    
out:
    ret = release_common_img(&rknn_app_ctx);
    if (ret != 0)
    {
        printf("[rknn3_model_stress_test_error] release model fail! ret=%d\n", ret);
        return -1;
    }

    if (src_image.virt_addr != NULL)
    {
        free(src_image.virt_addr);
    }
    printf("[rknn3_model_stress_test_done]\n");

    // if (img_embeds != NULL)
    // {
    //     free(img_embeds);
    // }

    // if(ret == 0) {
        
    // } else {
    //     printf("[rknn3_model_stress_test_error] \n");
    // }

    return ret;
}