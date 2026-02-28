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

#include "rknn3_vlm_vision.h"
#include "rknn3_vlm.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <string>

#include "common.h"
#include "file_utils.h"
#include "image_utils.h"

static void dump_tensor_attr(rknn3_tensor_attr *attrs) {
    std::string shape_str = "";
    for (int j = 0; j < attrs->n_dims; j++) {
        shape_str += std::to_string(attrs->shape[j]);
        if (j < attrs->n_dims - 1) {
            shape_str += ", ";
        }
    }

    std::string stride_str = "";
    for (int j = 0; j < attrs->n_stride; j++) {
        stride_str += std::to_string(attrs->stride[j]);
        if (j < attrs->n_stride - 1) {
            stride_str += ", ";
        }
    }

    printf(
        "Tensor: name=%s, n_dims=%d, shape=[%s], stride=[%s], aligned_size=%ld, layout=%s, dtype=%s, core_id=%d, "
        "qnt_type=%s\n",
        attrs->name, attrs->n_dims, shape_str.c_str(), stride_str.c_str(), attrs->aligned_size, rknn3_get_layout_string(attrs->layout),
        rknn3_get_type_string(attrs->dtype), attrs->core_id, rknn3_get_qnt_type_string(attrs->qnt_type));
}

int init_rknn3_vlm_vision(rknn3_vlm_vision_context *vision_ctx, const char *model_path, const char *weight_path, uint32_t core_mask) {
    int ret;
    rknn3_context ctx = 0;
    rknn3_config config;
    memset(&config, 0, sizeof(config));
    
    config.user_mem_internal = 1;  // 使用用户管理的internal内存
    uint32_t device_id = vision_ctx->device_id;
    // 获取目前连接的RK182X信息
    rknn3_devices rknn3_devices;
    memset(&rknn3_devices, 0, sizeof(rknn3_devices));
    ret = rknn3_find_devices(&rknn3_devices);
    if (ret != RKNN3_SUCCESS || rknn3_devices.n_devices <= 0) {
        printf("find devices failed, or data is invalid: %d\n", ret);
        return ret;
    }

    if (device_id >= rknn3_devices.n_devices) {
        printf("warning!!! device_id = %d is not allow ,use default:%d, %s, %d\n", device_id, RKNN3_DEFAULT_DEVICE_ID, __FUNCTION__, __LINE__);
        device_id = RKNN3_DEFAULT_DEVICE_ID;
    }

    printf("[rknn3_stress_test_log] device[%d].id=%s\n", device_id, rknn3_devices.devices[device_id].id);

    rknn3_init_extend init_extend = { 0 };
    init_extend.device_id = rknn3_devices.devices[device_id].id;

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

    // Query and validate vision core_mask before model init
    uint32_t model_core_num = 0;
    ret = rknn3_query(ctx, RKNN3_QUERY_CORE_NUMBER, &model_core_num, sizeof(model_core_num));
    if (ret < 0) {
        printf("[rknn3_model_stress_test_error] rknn3_query vision core number failed! ret=%d\n", ret);
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
            printf("[rknn3_model_stress_test_error] Vision core_mask 0x%x has %u cores, but model requires %u cores\n",
                   core_mask, core_num_from_mask, model_core_num);
            printf("[rknn3_model_stress_test_error] Please specify exactly %u cores for vision model\n", model_core_num);
            rknn3_destroy(ctx);
            return -1;
        }
    }
    printf("[rknn3_stress_test_log] Vision model requires %u NPU cores\n", model_core_num);
    printf("[rknn3_stress_test_log] User specified vision_core_mask: 0x%x\n", core_mask);
    // printf("[rknn3_stress_test_log] Vision core mask validation passed (%u cores)\n", core_num_from_mask);
    config.run_core_mask = core_mask;
    // Init RKNN Model
    ret = rknn3_model_init(ctx, &config);
    if (ret < 0) {
        printf("[rknn3_model_stress_test_error] rknn_model_init failed! ret=%d\n", ret);
        return ret;
    }

    // Get Model Input Output Number
    rknn3_input_output_num io_num;
    ret = rknn3_query(ctx, RKNN3_QUERY_IN_OUT_NUM, &io_num, sizeof(io_num));
    if (ret < 0) {
        printf("[rknn3_model_stress_test_error] rknn_query fail! ret=%d\n", ret);
        return ret;
    }
    printf("model input num: %d, output num: %d\n", io_num.n_input, io_num.n_output);

    // Get Model Input Info
    printf("input tensors:\n");
    rknn3_tensor_attr input_attrs[io_num.n_input];
    for (int i = 0; i < io_num.n_input; i++) {
        input_attrs[i].index = i;
        ret = rknn3_query(ctx, RKNN3_QUERY_INPUT_ATTR, &(input_attrs[i]), sizeof(rknn3_tensor_attr));
        if (ret < 0) {
            printf("[rknn3_model_stress_test_error] rknn_query fail! ret=%d\n", ret);
            return ret;
        }
        dump_tensor_attr(&(input_attrs[i]));
    }

    // Get Model Output Info
    printf("output tensors:\n");
    rknn3_tensor_attr output_attrs[io_num.n_output];
    for (int i = 0; i < io_num.n_output; i++) {
        output_attrs[i].index = i;
        ret = rknn3_query(ctx, RKNN3_QUERY_OUTPUT_ATTR, &(output_attrs[i]), sizeof(rknn3_tensor_attr));
        if (ret < 0) {
            printf("[rknn3_model_stress_test_error] rknn_query fail! ret=%d\n", ret);
            return ret;
        }
        dump_tensor_attr(&(output_attrs[i]));
    }

    // Set to context
    vision_ctx->pruned_version_flag = 0;
    vision_ctx->inputs = (rknn3_tensor *)malloc(io_num.n_input * sizeof(rknn3_tensor));
    vision_ctx->outputs = (rknn3_tensor *)malloc(io_num.n_output * sizeof(rknn3_tensor));
    vision_ctx->rknn_ctx = ctx;
    vision_ctx->io_num = io_num;
    for (int i = 0; i < vision_ctx->io_num.n_input; i++) {
        vision_ctx->inputs[i].mem = rknn3_create_mem(ctx, input_attrs[i].aligned_size, input_attrs[i].core_id, RKNN3_FLAG_MEMORY_CACHEABLE);
        vision_ctx->inputs[i].attr = (rknn3_tensor_attr *)malloc(sizeof(rknn3_tensor_attr));
        memcpy(vision_ctx->inputs[i].attr, &(input_attrs[i]), sizeof(rknn3_tensor_attr));
    }
    for (int i = 0; i < vision_ctx->io_num.n_output; i++) {
        vision_ctx->outputs[i].mem = rknn3_create_mem(ctx, output_attrs[i].aligned_size, output_attrs[i].core_id, RKNN3_FLAG_MEMORY_CACHEABLE);
        vision_ctx->outputs[i].attr = (rknn3_tensor_attr *)malloc(sizeof(rknn3_tensor_attr));
        memcpy(vision_ctx->outputs[i].attr, &(output_attrs[i]), sizeof(rknn3_tensor_attr));
    }

    if (input_attrs[0].layout == RKNN3_TENSOR_NCHW) {
        printf("model is NCHW input layout\n");
        vision_ctx->model_channel = input_attrs[0].shape[1];
        vision_ctx->model_height = input_attrs[0].shape[2];
        vision_ctx->model_width = input_attrs[0].shape[3];
        printf("input image height=%d, input image width=%d, input image channel=%d\n",
               vision_ctx->model_height, vision_ctx->model_width, vision_ctx->model_channel);
    } else if (input_attrs[0].layout == RKNN3_TENSOR_NHWC) {
        printf("model is NHWC input layout\n");
        vision_ctx->model_channel = input_attrs[0].shape[3];
        vision_ctx->model_height = input_attrs[0].shape[1];
        vision_ctx->model_width = input_attrs[0].shape[2];
        printf("input image height=%d, input image width=%d, input image channel=%d\n",
               vision_ctx->model_height, vision_ctx->model_width, vision_ctx->model_channel);

    } else {
        vision_ctx->pruned_version_flag = 1;
        vision_ctx->model_channel = 3;
        // vision_ctx->model_width = MODEL_WIDTH;
        // vision_ctx->model_height = MODEL_HEIGHT;
        // 由于vision模型被裁剪了，需要手动添加这些参数配置
        printf("model is UNDEFINED!\n");
        printf("model_width=%d model_height=%d \n", vision_ctx->model_width, vision_ctx->model_height);
    }

    if (output_attrs[0].layout == RKNN3_TENSOR_UNDEFINED) {
        printf("model is UNDEFINED output layout\n");
        vision_ctx->embeds_shape = vision_ctx->outputs[0].attr->shape;
        vision_ctx->embeds_ndims = vision_ctx->outputs[0].attr->n_dims;
    } else {
        printf("[rknn3_model_stress_test_error] model is not UNDEFINED output layout, model output error!\n");
        return -1;
    }

    return ret;
}

int release_rknn3_vlm_vision(rknn3_vlm_vision_context *vision_ctx) {
    for (int i = 0; i < vision_ctx->io_num.n_input; i++) {
        if (vision_ctx->inputs[i].mem) {
            rknn3_destroy_mem(vision_ctx->rknn_ctx, vision_ctx->inputs[i].mem);
        }
        if (vision_ctx->inputs[i].attr != NULL) {
            free(vision_ctx->inputs[i].attr);
            vision_ctx->inputs[i].attr = NULL;
        }
    }
    for (int i = 0; i < vision_ctx->io_num.n_output; i++) {
        if (vision_ctx->outputs[i].mem) {
            rknn3_destroy_mem(vision_ctx->rknn_ctx, vision_ctx->outputs[i].mem);
        }
        if (vision_ctx->outputs[i].attr != NULL) {
            free(vision_ctx->outputs[i].attr);
            vision_ctx->outputs[i].attr = NULL;
        }
    }
    if (vision_ctx->rknn_ctx != 0) {
        rknn3_destroy(vision_ctx->rknn_ctx);
        vision_ctx->rknn_ctx = 0;
    }
    return 0;
}

void normalize_and_to_nchw(const unsigned char *src, float16 *dst, int width, int height) {
    float mean[3] = { 122.7f, 116.74f, 104.09f };
    float std[3] = { 68.5f, 66.6f, 70.3f };
    int num_pixels = width * height;

    // 分配临时NHWC缓冲区
    float16 *temp_nhwc = (float16 *)malloc(num_pixels * 3 * sizeof(float16));
    if (!temp_nhwc) {
        printf("[rknn3_model_stress_test_error] Memory allocation failed for temp_nhwc\n");
        return;
    }

    // 1. 归一化到临时NHWC缓冲区
    for (int i = 0; i < num_pixels; ++i) {
        int idx = i * 3;
        temp_nhwc[idx + 0] = fp32_to_fp16(((float)src[idx + 0] - mean[0]) / std[0]);  // R通道
        temp_nhwc[idx + 1] = fp32_to_fp16(((float)src[idx + 1] - mean[1]) / std[1]);  // G通道
        temp_nhwc[idx + 2] = fp32_to_fp16(((float)src[idx + 2] - mean[2]) / std[2]);  // B通道
    }

    // 2. 转换到NCHW
    for (int c = 0; c < 3; ++c) {  // 遍历R,G,B通道
        for (int h = 0; h < height; ++h) {
            for (int w = 0; w < width; ++w) {
                int nhwc_idx = (h * width + w) * 3 + c;         // NHWC索引
                int nchw_idx = c * num_pixels + h * width + w;  // NCHW索引
                dst[nchw_idx] = temp_nhwc[nhwc_idx];
            }
        }
    }

    // 释放临时缓冲区
    free(temp_nhwc);
}

void transpose_qwen3(float16 *in, float16 *out, int model_width, int model_height) {
    int64_t dims[8] = { 2, 3, int(model_height / 32), 2, 16, int(model_width / 32), 2, 16 };
    //[temporal_patch_size,channel, grid_h // merge_size,  merge_size, patch_size,
    // grid_w // merge_size, merge_size, patch_size]
    int perm[8] = { 2, 5, 3, 6, 1, 0, 4, 7 };
    int64_t new_dims[8];
    for (int k = 0; k < 8; k++) {
        new_dims[k] = dims[perm[k]];
    }
    int64_t total = 1;
    for (int k = 0; k < 8; k++) {
        total *= dims[k];
    }
    // 计算原始strides
    int64_t strides[8];
    strides[7] = 1;
    for (int d = 6; d >= 0; d--) {
        strides[d] = strides[d + 1] * dims[d + 1];
    }

    // 使用嵌套循环遍历输出索引，避免内循环计算
    int64_t out_idx = 0;
    for (int64_t o0 = 0; o0 < new_dims[0]; o0++) {
        for (int64_t o1 = 0; o1 < new_dims[1]; o1++) {
            for (int64_t o2 = 0; o2 < new_dims[2]; o2++) {
                for (int64_t o3 = 0; o3 < new_dims[3]; o3++) {
                    for (int64_t o4 = 0; o4 < new_dims[4]; o4++) {
                        for (int64_t o5 = 0; o5 < new_dims[5]; o5++) {
                            for (int64_t o6 = 0; o6 < new_dims[6]; o6++) {
                                for (int64_t o7 = 0; o7 < new_dims[7]; o7++) {
                                    int64_t i[8];
                                    i[perm[0]] = o0;
                                    i[perm[1]] = o1;
                                    i[perm[2]] = o2;
                                    i[perm[3]] = o3;
                                    i[perm[4]] = o4;
                                    i[perm[5]] = o5;
                                    i[perm[6]] = o6;
                                    i[perm[7]] = o7;
                                    int64_t flat_in = i[0] * strides[0] + i[1] * strides[1] + i[2] * strides[2] +
                                                      i[3] * strides[3] + i[4] * strides[4] + i[5] * strides[5] +
                                                      i[6] * strides[6] + i[7] * strides[7];
                                    out[out_idx++] = in[flat_in];
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

void transpose(float16 *in, float16 *out) {
    int64_t dims[8] = { 2, 3, 14, 2, 14, 14, 2, 14 };
    int perm[8] = { 2, 5, 3, 6, 1, 0, 4, 7 };
    int64_t new_dims[8];
    for (int k = 0; k < 8; k++) {
        new_dims[k] = dims[perm[k]];
    }
    int64_t total = 1;
    for (int k = 0; k < 8; k++) {
        total *= dims[k];
    }
    // 计算原始strides
    int64_t strides[8];
    strides[7] = 1;
    for (int d = 6; d >= 0; d--) {
        strides[d] = strides[d + 1] * dims[d + 1];
    }

    // 使用嵌套循环遍历输出索引，避免内循环计算
    int64_t out_idx = 0;
    for (int64_t o0 = 0; o0 < new_dims[0]; o0++) {
        for (int64_t o1 = 0; o1 < new_dims[1]; o1++) {
            for (int64_t o2 = 0; o2 < new_dims[2]; o2++) {
                for (int64_t o3 = 0; o3 < new_dims[3]; o3++) {
                    for (int64_t o4 = 0; o4 < new_dims[4]; o4++) {
                        for (int64_t o5 = 0; o5 < new_dims[5]; o5++) {
                            for (int64_t o6 = 0; o6 < new_dims[6]; o6++) {
                                for (int64_t o7 = 0; o7 < new_dims[7]; o7++) {
                                    int64_t i[8];
                                    i[perm[0]] = o0;
                                    i[perm[1]] = o1;
                                    i[perm[2]] = o2;
                                    i[perm[3]] = o3;
                                    i[perm[4]] = o4;
                                    i[perm[5]] = o5;
                                    i[perm[6]] = o6;
                                    i[perm[7]] = o7;
                                    int64_t flat_in = i[0] * strides[0] + i[1] * strides[1] + i[2] * strides[2] +
                                                      i[3] * strides[3] + i[4] * strides[4] + i[5] * strides[5] +
                                                      i[6] * strides[6] + i[7] * strides[7];
                                    out[out_idx++] = in[flat_in];
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

int inference_rknn3_vlm_vision(rknn3_vlm_vision_context *vision_ctx, image_buffer_t *img, int loop) {
    if ((!vision_ctx) || (!img)) {
        printf("[rknn3_model_stress_test_error] vision_ctx or img is NULL");
        return -1;
    }
    int ret;
    image_buffer_t dst_img;
    float16 *expand_data;
    memset(&dst_img, 0, sizeof(image_buffer_t));
    float tot_cost = 0.f;
    // Pre Process
    dst_img.width = vision_ctx->model_width;
    dst_img.height = vision_ctx->model_height;
    dst_img.format = IMAGE_FORMAT_RGB888;
    dst_img.size = get_image_size(&dst_img);
    dst_img.virt_addr = (unsigned char *)malloc(dst_img.size);
    TIMER sync_in_time, sync_out_time;

    if (dst_img.virt_addr == NULL) {
        printf("[rknn3_model_stress_test_error] malloc buffer size:%d fail!\n", dst_img.size);
        goto out;
    }

    ret = convert_image(img, &dst_img, NULL, NULL, 0);
    if (ret < 0) {
        printf("[rknn3_model_stress_test_error] convert_image fail! ret=%d\n", ret);
        goto out;
    }

    if (vision_ctx->pruned_version_flag == 1) {
        expand_data = (float16 *)malloc(dst_img.size * 2 * sizeof(float16));  // expand
        normalize_and_to_nchw(dst_img.virt_addr, expand_data, vision_ctx->model_width, vision_ctx->model_height);
        memcpy((char *)expand_data + dst_img.size * 2, expand_data, dst_img.size * 2);  // expand
        if (vision_ctx->io_num.n_output > 1) {
            transpose_qwen3((float16 *)expand_data, (float16 *)(vision_ctx->inputs[0].mem->virt_addr), vision_ctx->model_width, vision_ctx->model_height);
        } else {
            transpose((float16 *)expand_data, (float16 *)(vision_ctx->inputs[0].mem->virt_addr));
        }
        free(expand_data);
        // printf("vision_ctx->pruned_version_flag\n");
    } else {
        // Set Input Data
        memcpy(vision_ctx->inputs[0].mem->virt_addr, (uint8_t *)dst_img.virt_addr, dst_img.size);
    }

    // Run
    // printf("rknn_run\n");

    for (int i = 0; i < loop; i++) {
        g_vlm_perf.vision_cost.tik();
        // printf("vision_ctx->io_num.n_input:%d\n",vision_ctx->io_num.n_input);
        sync_in_time.tik();
        for (int j = 0; j < vision_ctx->io_num.n_input; j++) {
            // printf("Syncing input[%d] to device...\n", i);
            ret = rknn3_mem_sync(vision_ctx->rknn_ctx, vision_ctx->inputs[j].mem, RKNN3_MEMORY_SYNC_TO_DEVICE);
            if (ret != RKNN3_SUCCESS) {
                printf("rknn3_mem_sync input[%d] failed! ret=%d\n", i, ret);
                break;
            }
        }
        sync_in_time.tok();
        ret = rknn3_run(vision_ctx->rknn_ctx, vision_ctx->inputs, vision_ctx->io_num.n_input, vision_ctx->outputs, vision_ctx->io_num.n_output);
        if (ret < 0) {
            printf("[rknn3_model_stress_test_error] rknn_run fail! ret=%d\n", ret);
            goto out;
        }
        sync_out_time.tik();
        for (int j = 0; j < vision_ctx->io_num.n_output; j++) {
            // printf("Syncing output[%d] from device...\n", i);
            rknn3_mem_sync(vision_ctx->rknn_ctx, vision_ctx->outputs[j].mem, RKNN3_MEMORY_SYNC_FROM_DEVICE);
            if (ret != RKNN3_SUCCESS) {
                printf("rknn3_mem_sync output[%d] failed! ret=%d\n", i, ret);
                break;
            }
        }
        sync_out_time.tok();
        g_vlm_perf.vision_cost.tok();
        tot_cost += g_vlm_perf.vision_cost.get_time();
        if (loop != 1) {
            if (i % 100 == 0) {
                printf("run: %d, cost: %f,sync_in: %f,sync_out: %f\n", i + 1, tot_cost, sync_in_time.get_time(), sync_out_time.get_time());
                tot_cost = 0.f;
            }
            // printf("[rknn3_model_stress_test_log] vision run: %d/ %d\n",i+1,loop);
        }
    }

    // Get Output
    // memcpy(img_embeds, (float16*)vision_ctx->outputs[0].mem->virt_addr, vision_ctx->outputs[0].mem->size);
    // memcpy(img_embeds, (float16*)vision_ctx->outputs[0].mem->virt_addr, vision_ctx->outputs[0].mem->size);
    // memcpy(img_embeds, (float16*)vision_ctx->outputs[0].mem->virt_addr, vision_ctx->outputs[0].mem->size);
    // memcpy(img_embeds, (float16*)vision_ctx->outputs[0].mem->virt_addr, vision_ctx->outputs[0].mem->size);

out:
    if (dst_img.virt_addr != NULL) {
        free(dst_img.virt_addr);
    }

    return ret;
}