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


#ifndef _RKNN_DEMO_COMMON_VISION_UTILS_H_
#define _RKNN_DEMO_COMMON_VISION_UTILS_H_

#include "rknn3_api.h"
#include "common.h"

#define RKNN3_DEFAULT_DEVICE_ID 0
typedef struct {
    rknn3_context rknn_ctx;
    rknn3_input_output_num io_num;
    rknn3_tensor* inputs;
    rknn3_tensor* outputs;

    int model_channel;
    int model_height;
    int model_width;

    uint32_t* embeds_shape;
    uint32_t embeds_ndims;

    rknn3_im_mem src_mem;
    rknn3_im_mem dst_mem;

    char device_id_mac[128];
    uint32_t device_id;  // Device ID for memory monitoring
} rknn_common_img_ctx;

typedef struct {
    int infer_cnt;
    float total_time;
    float avg_cost;
    float avg_FPS;
    int64_t tot_memory;
    char device_id_mac[128];
    char input_format[128];
} rknn3_cnn_perf_t;

int init_common_img(rknn_common_img_ctx* vision_ctx, const char* model_path, const char* weight_path, uint32_t core_mask,uint32_t device_id, image_format_t src_fmt);
int release_common_img(rknn_common_img_ctx* vision_ctx);
int inference_common_img(rknn_common_img_ctx* vision_ctx, image_buffer_t* img,uint32_t loop,float time_loop);

#endif