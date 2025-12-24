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

#include "rknn3_cnn_test.h"
#include "common.h"
#include "file_utils.h"
#include "image_utils.h"
#include "easy_timer.h"
#include <math.h>
#include "cnpy.h"
#include "float16.h"


static void dump_tensor_attr(rknn3_tensor_attr* attrs)
{
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
  
    printf("Tensor: name=%s, n_dims=%d, shape=[%s], stride=[%s], aligned_size=%ld, layout=%s, dtype=%s, core_id=%d, "
           "qnt_type=%s\n",
           attrs->name, attrs->n_dims, shape_str.c_str(), stride_str.c_str(), attrs->aligned_size, rknn3_get_layout_string(attrs->layout),
           rknn3_get_type_string(attrs->dtype), attrs->core_id, rknn3_get_qnt_type_string(attrs->qnt_type));
}

int init_common_img(rknn_common_img_ctx* vision_ctx, const char* model_path, const char* weight_path, uint32_t core_mask, uint32_t device_id)
{
    int ret;
    rknn3_context ctx = 0;
    rknn3_config config;
    memset(&config, 0, sizeof(config));
    config.run_core_mask = core_mask;
    config.user_mem_internal = 0;

    // 获取目前连接的RK182X信息
    rknn3_devices rknn3_devices;
    memset(&rknn3_devices, 0 ,sizeof(rknn3_devices));
    ret = rknn3_find_devices(&rknn3_devices);
    if (ret != RKNN3_SUCCESS || rknn3_devices.n_devices <= 0) {
        printf("find devices failed, or data is invalid: %d\n", ret);
        return ret;
    }

    if (device_id >= rknn3_devices.n_devices) {
        printf("warning!!! device_id = %d is not allow ,use default:%d, %s, %d\n", device_id, RKNN3_DEFAULT_DEVICE_ID, __FUNCTION__, __LINE__);
        device_id = RKNN3_DEFAULT_DEVICE_ID;
    }
    memcpy(vision_ctx->device_id_mac,rknn3_devices.devices[device_id].id,sizeof(rknn3_devices.devices[device_id].id));
    printf("[rknn3_stress_test_log] device[%d].id=%s\n", device_id, rknn3_devices.devices[device_id].id);

    rknn3_init_extend init_extend = {0};
    init_extend.device_id = rknn3_devices.devices[device_id].id;

    // RKNN Init
    ret = rknn3_init(&ctx, &init_extend);
    if (ret < 0)
    {
        printf("[rknn3_model_stress_test_error] rknn_init fail ret=%d\n", ret);
        return ret;
    }

    // Load RKNN Model
    ret = rknn3_load_model_from_path(ctx, model_path, weight_path);
    if (ret < 0) {
        printf("[rknn3_model_stress_test_error] rknn_load_model failed! ret=%d\n", ret);
        return ret;
    }

    //Init RKNN Model
    ret = rknn3_model_init(ctx, &config);
    if (ret < 0) {
        printf("[rknn3_model_stress_test_error] rknn_model_init failed! ret=%d\n", ret);
        return ret;
    }

    // Get Model Input Output Number
    rknn3_input_output_num io_num;
    ret = rknn3_query(ctx, RKNN3_QUERY_IN_OUT_NUM, &io_num, sizeof(io_num));
    if (ret < 0)
    {
        printf("[rknn3_model_stress_test_error] rknn_query fail! ret=%d\n", ret);
        return ret;
    }
    printf("model input num: %d, output num: %d\n", io_num.n_input, io_num.n_output);

    // Get Model Input Info
    printf("input tensors:\n");
    rknn3_tensor_attr input_attrs[io_num.n_input];
    for (int i = 0; i < io_num.n_input; i++)
    {
        input_attrs[i].index = i;
        ret = rknn3_query(ctx, RKNN3_QUERY_INPUT_ATTR, &(input_attrs[i]), sizeof(rknn3_tensor_attr));
        if (ret < 0)
        {
            printf("[rknn3_model_stress_test_error] rknn_query fail! ret=%d\n", ret);
            return ret;
        }
        dump_tensor_attr(&(input_attrs[i]));
    }

    // Get Model Output Info
    printf("output tensors:\n");
    rknn3_tensor_attr output_attrs[io_num.n_output];
    for (int i = 0; i < io_num.n_output; i++)
    {
        output_attrs[i].index = i;
        ret = rknn3_query(ctx, RKNN3_QUERY_OUTPUT_ATTR, &(output_attrs[i]), sizeof(rknn3_tensor_attr));
        if (ret < 0)
        {
            printf("[rknn3_model_stress_test_error] rknn_query fail! ret=%d\n", ret);
            return ret;
        }
        dump_tensor_attr(&(output_attrs[i]));
    }

    // Set to context
    vision_ctx->inputs = (rknn3_tensor*)malloc(io_num.n_input * sizeof(rknn3_tensor));
    vision_ctx->outputs = (rknn3_tensor*)malloc(io_num.n_output * sizeof(rknn3_tensor));
    vision_ctx->rknn_ctx = ctx;
    vision_ctx->io_num = io_num;
    for (int i = 0; i < vision_ctx->io_num.n_input; i++) {
        vision_ctx->inputs[i].mem  = rknn3_create_mem(ctx, input_attrs[i].aligned_size, input_attrs[i].core_id, RKNN3_FLAG_MEMORY_CACHEABLE);
        
        vision_ctx->inputs[i].attr = (rknn3_tensor_attr*)malloc(sizeof(rknn3_tensor_attr));
        memcpy(vision_ctx->inputs[i].attr, &(input_attrs[i]), sizeof(rknn3_tensor_attr));
    }
    for (int i = 0; i < vision_ctx->io_num.n_output; i++) {
        vision_ctx->outputs[i].mem  = rknn3_create_mem(ctx, output_attrs[i].aligned_size, output_attrs[i].core_id, RKNN3_FLAG_MEMORY_CACHEABLE);
        vision_ctx->outputs[i].attr = (rknn3_tensor_attr*)malloc(sizeof(rknn3_tensor_attr));
        memcpy(vision_ctx->outputs[i].attr, &(output_attrs[i]), sizeof(rknn3_tensor_attr));
        // printf("output_attrs[i].aligned_size:%d\n",output_attrs[i].aligned_size);
    }

    if (input_attrs[0].layout == RKNN3_TENSOR_NCHW)
    {
        printf("model is NCHW input layout\n");
        vision_ctx->model_channel = input_attrs[0].shape[1];
        vision_ctx->model_height = input_attrs[0].shape[2];
        vision_ctx->model_width = input_attrs[0].shape[3];
        printf("input image height=%d, input image width=%d, input image channel=%d\n",
                vision_ctx->model_height, vision_ctx->model_width, vision_ctx->model_channel);
    }
    else if (input_attrs[0].layout == RKNN3_TENSOR_NHWC)
    {
        printf("model is NHWC input layout\n");
        vision_ctx->model_channel = input_attrs[0].shape[3];
        vision_ctx->model_height = input_attrs[0].shape[1];
        vision_ctx->model_width = input_attrs[0].shape[2];
        printf("input image height=%d, input image width=%d, input image channel=%d\n",
                vision_ctx->model_height, vision_ctx->model_width, vision_ctx->model_channel);

    }
    else 
    {
        printf("[rknn3_model_stress_test_error] model is not NHWC/NCHW input layout, model input error!\n");
        return -1;
    }

    // if (output_attrs[0].layout == RKNN3_TENSOR_UNDEFINED)
    // {
    //     printf("model is UNDEFINED output layout\n");
    //     vision_ctx->embeds_shape = vision_ctx->outputs[0].attr->shape;
    //     vision_ctx->embeds_ndims = vision_ctx->outputs[0].attr->n_dims;
    // }
    // else
    // {
    //     printf("[rknn3_model_stress_test_error] model is not UNDEFINED output layout, model output error!\n");
    //     return -1;
    // }

    return ret;
}

int release_common_img(rknn_common_img_ctx* vision_ctx)
{
    for (int i = 0; i < vision_ctx->io_num.n_input; i++) {
        if (vision_ctx->inputs[i].mem) {
            rknn3_destroy_mem(vision_ctx->rknn_ctx, vision_ctx->inputs[i].mem);
        }
        if (vision_ctx->inputs[i].attr != NULL) {
            free(vision_ctx->inputs[i].attr);
            vision_ctx->inputs[i].attr = NULL;
        }
    }
    if(vision_ctx->inputs) {
        free(vision_ctx->inputs);
        vision_ctx->inputs = NULL;
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
    if(vision_ctx->outputs) {
        free(vision_ctx->outputs);
        vision_ctx->outputs = NULL;
    }

    if (vision_ctx->rknn_ctx != 0)
    {
        rknn3_destroy(vision_ctx->rknn_ctx);
        vision_ctx->rknn_ctx = 0;
    }

    return 0;
}

// static void check_perfance(float last_perf, float cur_perf) {
//     if (last_perf <= 0) {
//         fprintf(stderr, "Error: last_perf must be positive.\n");
//         return;
//     }

//     float diff = fabsf(cur_perf - last_perf);
//     float ratio = diff / last_perf;  // 抖动比例

//     if (ratio > 0.5f) {
//         fprintf(stderr, "[rknn3_model_stress_test_error] perf jitter %.2f%% exceeds 20%% (last=%.3f, cur=%.3f)\n",
//                 ratio * 100, last_perf, cur_perf);
//         exit(EXIT_FAILURE);  // 异常退出
//     } else if (ratio > 0.2f) {
//         fprintf(stderr, "[rknn3_model_stress_test_warnning] perf jitter %.2f%% exceeds 10%% (last=%.3f, cur=%.3f)\n",
//                 ratio * 100, last_perf, cur_perf);
//     }
// }
static int NC1HWC2_fp16_to_NCHW_fp32(const float16 *src, float *dst, int batch, int C1, int C2, int hw_src, int channel, int h, int w) {
    printf("NC1HWC2_fp16_to_NCHW_fp32\n");
    printf("batch=%d, C1=%d, C2=%d, hw_src=%d, channel=%d, h=%d, w=%d\n", batch, C1, C2, hw_src, channel, h, w);
    int hw_dst = h * w;
    for (int i = 0; i < batch; i++) {
        const float16 *src_b = src + i * C1 * hw_src * C2;
        float *dst_b = dst + i * channel * hw_dst;
        for (int c = 0; c < channel; ++c) {
            int plane = c / C2;
            const float16 *src_bc = plane * hw_src * C2 + src_b;
            int offset = c % C2;
            for (int cur_h = 0; cur_h < h; ++cur_h)
                for (int cur_w = 0; cur_w < w; ++cur_w) {
                    int cur_hw = cur_h * w + cur_w;
                    dst_b[c * hw_dst + cur_hw] = fp16_to_fp32(src_bc[C2 * cur_hw + offset]);  // float16-->float
                }
        }
    }

    return 0;
}

static int NC1HWC2_int8_to_NCHW_fp32(const int8_t *src, float *dst, int batch, int C1, int C2, int hw_src, int channel, int h, int w,
                                     rknn3_tensor_attr *attr) {
    printf("NC1HWC2_int8_to_NCHW_fp32\n");
    printf("batch=%d, C1=%d, C2=%d, hw_src=%d, channel=%d, h=%d, w=%d\n", batch, C1, C2, hw_src, channel, h, w);

    // 获取量化参数
    float scale = 1.0f;
    int32_t zero_point = 0;

    if (attr->qnt_type != RKNN3_TENSOR_QNT_NONE) {
        scale = attr->qnt_info.scale;
        zero_point = attr->qnt_info.zero_point;
        printf("Quantization params: scale=%f, zero_point=%d\n", scale, zero_point);
    } else {
        printf("No quantization parameters found, using default values\n");
    }

    int hw_dst = h * w;
    for (int i = 0; i < batch; i++) {
        const int8_t *src_b = src + i * C1 * hw_src * C2;
        float *dst_b = dst + i * channel * hw_dst;
        for (int c = 0; c < channel; ++c) {
            int plane = c / C2;
            const int8_t *src_bc = plane * hw_src * C2 + src_b;
            int offset = c % C2;
            for (int cur_h = 0; cur_h < h; ++cur_h)
                for (int cur_w = 0; cur_w < w; ++cur_w) {
                    int cur_hw = cur_h * w + cur_w;
                    int8_t quantized_value = src_bc[C2 * cur_hw + offset];
                    // 反量化：float_value = (int8_value - zero_point) * scale
                    dst_b[c * hw_dst + cur_hw] = (float)(quantized_value - zero_point) * scale;
                }
        }
    }

    return 0;
}

static int convert_int8_to_fp32(const void *src, float *dst, int n_elems, rknn3_tensor_type type, float scale, int32_t zero_point) {
    printf("convert_int8_to_fp32\n");
    printf("n_elems=%d, type=%s\n", n_elems, rknn3_get_type_string(type));
    printf("scale=%f, zero_point=%d\n", scale, zero_point);

    for (int i = 0; i < n_elems; i++) {
        dst[i] = ((float)((int8_t *)src)[i] - zero_point) * scale;
    }

    return 0;
}

static int convert_fp16_to_fp32(const float16 *src, float *dst, int n_elems) {
    for (int i = 0; i < n_elems; i++) {
        dst[i] = fp16_to_fp32(src[i]);
    }
    return 0;
}

static int convert_any_type_to_fp32(const void *src, float *dst, int n_elems, rknn3_tensor_type type) {
    printf("convert_any_type_to_fp32\n");
    printf("n_elems=%d, type=%s\n", n_elems, rknn3_get_type_string(type));

    switch (type) {
        case RKNN3_TENSOR_FLOAT16:
            convert_fp16_to_fp32((const float16 *)src, dst, n_elems);
            break;
        case RKNN3_TENSOR_FLOAT32:
            memcpy(dst, src, n_elems * sizeof(float));
            break;
        case RKNN3_TENSOR_INT64:
            for (int i = 0; i < n_elems; i++) {
                dst[i] = (float)((int64_t *)src)[i];
            }
            break;
        case RKNN3_TENSOR_INT32:
            for (int i = 0; i < n_elems; i++) {
                dst[i] = (float)((int32_t *)src)[i];
            }
            break;
        case RKNN3_TENSOR_INT16:
            for (int i = 0; i < n_elems; i++) {
                dst[i] = (float)((int16_t *)src)[i];
            }
            break;
        case RKNN3_TENSOR_INT8:
            for (int i = 0; i < n_elems; i++) {
                dst[i] = (float)((int8_t *)src)[i];
            }
            break;
        case RKNN3_TENSOR_UINT8:
            for (int i = 0; i < n_elems; i++) {
                dst[i] = (float)((uint8_t *)src)[i];
            }
            break;
        default:
            printf("Unsupported tensor type: %d\n", type);
            return -1;
    }
    return 0;
}


int inference_common_img(rknn_common_img_ctx* vision_ctx, image_buffer_t* img,uint32_t cnt_loop,float time_loop)
{
    TIMER cost;
    if ((!vision_ctx) || (!img))
    {
        printf("[rknn3_model_stress_test_error] vision_ctx or img is NULL");
        return -1;
    }

    int ret;
    image_buffer_t dst_img;
    memset(&dst_img, 0, sizeof(image_buffer_t));

    int infer_cnt = 1;
    TIMER tot_cost;
    static float last_print_time = 0.0f;
    float print_interval = 1*1000*60 ; //1ms
    float time_loop_ms = (float)time_loop *60.f*60.f*1000.f;

    // Pre Process
    dst_img.width     = vision_ctx->model_width;
    dst_img.height    = vision_ctx->model_height;
    dst_img.format    = IMAGE_FORMAT_RGB888;
    dst_img.size      = get_image_size(&dst_img);
    dst_img.virt_addr = (unsigned char *)malloc(dst_img.size);
    if (dst_img.virt_addr == NULL)
    {
        printf("[rknn3_model_stress_test_error] malloc buffer size:%d fail!\n", dst_img.size);
        goto out;
    }

    ret = convert_image(img, &dst_img, NULL, NULL, 0);
    if (ret < 0)
    {
        printf("[rknn3_model_stress_test_error] convert_image fail! ret=%d\n", ret);
        goto out;
    }

    // Set Input Data
    memcpy(vision_ctx->inputs[0].mem->virt_addr, (uint8_t*)dst_img.virt_addr, dst_img.size);
    #if 0
    if(time_loop != 0.f) {
        float time_loop_ms = (float)time_loop *60.f*60.f*1000.f;
        // printf("time_loop_ms: %f\n",time_loop_ms);
        int model_run_cnt = 0;
        // float tot_fps = 0.;
        TIMER tot_cost;
        // float tot_cost = 0.f;
        int infer_cnt = 1;
        tot_cost.tik();
        static float last_print_time = 0.0f;
        float print_interval = 1*1000*60 ; //1ms
        
        while(1) {
            // printf("---------------------test_by_cdd\n");
            for (int i = 0; i < vision_ctx->io_num.n_input; i++)
            {
                // printf("Syncing input[%d] to device...\n", i);
                ret = rknn3_mem_sync(vision_ctx->rknn_ctx, vision_ctx->inputs[i].mem, RKNN3_MEMORY_SYNC_TO_DEVICE);
                if (ret != RKNN3_SUCCESS)
                {
                    printf("rknn3_mem_sync input[%d] failed! ret=%d\n", i, ret);
                    break;
                }
            }
            // cost.tik();
            ret = rknn3_run(vision_ctx->rknn_ctx, vision_ctx->inputs, vision_ctx->io_num.n_input, vision_ctx->outputs, vision_ctx->io_num.n_output);
            if (ret < 0)
            {
                printf("[rknn3_model_stress_test_error] rknn_run fail! ret=%d\n", ret);
                goto out;
            }

            for (int i = 0; i < vision_ctx->io_num.n_output; i++)
            {
                // printf("Syncing output[%d] from device...\n", i);
                rknn3_mem_sync(vision_ctx->rknn_ctx, vision_ctx->outputs[i].mem, RKNN3_MEMORY_SYNC_FROM_DEVICE);
                if (ret != RKNN3_SUCCESS)
                {
                    printf("rknn3_mem_sync output[%d] failed! ret=%d\n", i, ret);
                    break;
                }
            }

            // cost.tok();
            tot_cost.tok();
            float tmp_time = tot_cost.get_time();
            // float print_time_delta = 20 *1000*60*60; // 20min
            if(tmp_time - last_print_time >= print_interval) {
                // printf("FPS: %8.2f\n",infer_cnt/tot_cost.get_time()*1000.f);
                tot_cost.print_time("rknn3_cnn_demo cost now: ");
                last_print_time = tmp_time;         // 更新上次打印时间
            }
            if(tmp_time >= time_loop_ms) {
                float avgCost = tmp_time / infer_cnt;
                float avgFPS = 1000. / avgCost;
                printf("device_id: %s\n",vision_ctx->device_id_mac);
                printf("run %d ,tot_time:%8.2f,avgFPS: %.2f ,avgCost = %8.2f ms\n",infer_cnt,tmp_time,avgFPS,avgCost);
                break;
            }
            // printf("FPS: %8.2f\n",infer_cnt/tot_cost.get_time()*1000.f);
            infer_cnt ++;
            // cost.print_time("rknn_vision_test");
            // printf("rknn_cnn_test time_loop: %d / %d ,cost_time: %8.2f\n",i+1,cnt_loop,cost.get_time());
            
        }
    } else{
        float tot_cost = 0.f;
        TIMER sync_cost;
        
        for(int i = 0;i < cnt_loop;i ++) {
            cost.tik();
            sync_cost.tik();
            for (int i = 0; i < vision_ctx->io_num.n_input; i++)
            {
                // printf("Syncing input[%d] to device...\n", i);
                ret = rknn3_mem_sync(vision_ctx->rknn_ctx, vision_ctx->inputs[i].mem, RKNN3_MEMORY_SYNC_TO_DEVICE);
                if (ret != RKNN3_SUCCESS)
                {
                    printf("rknn3_mem_sync input[%d] failed! ret=%d\n", i, ret);
                    break;
                }
            }
            sync_cost.tok();
            sync_cost.print_time("Syncing input cost: ");

            ret = rknn3_run(vision_ctx->rknn_ctx, vision_ctx->inputs, vision_ctx->io_num.n_input, vision_ctx->outputs, vision_ctx->io_num.n_output);
            if (ret < 0)
            {
                printf("[rknn3_model_stress_test_error] rknn_run fail! ret=%d\n", ret);
                goto out;
            }
            sync_cost.tik();
            for (int i = 0; i < vision_ctx->io_num.n_output; i++)
            {
                // printf("Syncing output[%d] from device...\n", i);
                rknn3_mem_sync(vision_ctx->rknn_ctx, vision_ctx->outputs[i].mem, RKNN3_MEMORY_SYNC_FROM_DEVICE);
                if (ret != RKNN3_SUCCESS)
                {
                    printf("rknn3_mem_sync output[%d] failed! ret=%d\n", i, ret);
                    break;
                }
            }
            
            cost.tok();
            tot_cost += cost.get_time();
            sync_cost.tok();
            sync_cost.print_time("Syncing outputs cost: ");

            // cost.print_time("rknn_vision_test");
            printf("rknn_cnn_test cnt_loop: %d / %d ,cost time : %8.2f ms\n",i, cnt_loop,cost.get_time());
        }
        
        float avgCost = tot_cost / (cnt_loop);
        float avgFPS = 1000. / avgCost;
        printf("run %d ,tot_time:%8.2f,avgFPS: %.2f ,avgCost = %8.2f ms\n",cnt_loop,tot_cost,avgFPS,avgCost);
        
    }
        #endif

    tot_cost.tik();
    while (1) {
        if (time_loop == 0.f && infer_cnt >= cnt_loop) {
            break;
        }

        // --- Sync Input ---
        for (int i = 0; i < vision_ctx->io_num.n_input; i++) {
            ret = rknn3_mem_sync(vision_ctx->rknn_ctx, vision_ctx->inputs[i].mem, RKNN3_MEMORY_SYNC_TO_DEVICE);
            if (ret != RKNN3_SUCCESS) {
                printf("rknn3_mem_sync input[%d] failed! ret=%d\n", i, ret);
                goto out;
            }
        }

        // --- Run Model ---
        ret = rknn3_run(vision_ctx->rknn_ctx, vision_ctx->inputs, vision_ctx->io_num.n_input, vision_ctx->outputs, vision_ctx->io_num.n_output);
        if (ret < 0) {
            printf("[rknn3_model_stress_test_error] rknn_run fail! ret=%d\n", ret);
            goto out;
        }

        // --- Sync Output ---
        for (int i = 0; i < vision_ctx->io_num.n_output; i++) {
            rknn3_mem_sync(vision_ctx->rknn_ctx, vision_ctx->outputs[i].mem, RKNN3_MEMORY_SYNC_FROM_DEVICE);
        }

        infer_cnt++;
        tot_cost.tok();
        float tmp_time = tot_cost.get_time();

        if (tmp_time - last_print_time >= print_interval) {
            tot_cost.print_time("rknn3_cnn_demo running cost: ");
            last_print_time = tmp_time;
        }
        if (time_loop != 0.f) {
            // 时间模式退出检查
            if (tmp_time >= time_loop_ms) {
                break;
            }
        }
    }
    // 4. 统一最终统计输出
    {
        float total_time = tot_cost.get_time();
        float avgCost = total_time / infer_cnt;
        float avgFPS = 1000.f / avgCost;

        // printf("\n---------------- Final Result ----------------\n");
        if (vision_ctx->device_id_mac) {
            printf("device_id: %s\n", vision_ctx->device_id_mac);
        }
        printf("run %d ,tot_time:%8.2f,avgFPS: %.3f ,avgCost: %8.2f ms\n",infer_cnt,total_time,avgFPS,avgCost);

        // printf("Run Count: %d, Tot Time: %8.2f ms\n", infer_cnt, total_time);
        // printf("Avg FPS  : %.2f, Avg Cost : %8.2f ms\n", avgFPS, avgCost);

    }
    

#if 0
    for (uint32_t i = 0; i < vision_ctx->io_num.n_output; i++) {
        rknn3_tensor_attr *output_attr = vision_ctx->outputs[i].attr;
        rknn3_tensor_mem *output_mem = vision_ctx->outputs[i].mem;
        int batch = 1;
        
        // rt_hw_cpu_dcache_ops(RT_HW_CACHE_INVALIDATE, (void*)output_mem->virt_addr, output_mem->size);
        // int  dst_elems = 
        int aligned_size = output_attr->aligned_size;
        int aligned_type_size = 0;
        if(output_attr->dtype == RKNN3_TENSOR_FLOAT16) {
            aligned_type_size = sizeof(float16);
        }
        else if(output_attr->dtype == RKNN3_TENSOR_INT8) {
            aligned_type_size = sizeof(int8_t);
        }
        else {
            printf("not support output_attr->dtype:%d save\n",output_attr->dtype);
            return -1;
        }
        int dst_elems = aligned_size / aligned_type_size;
        printf("......vision_ctx->outputs[0].mem->size:%d,dst_elems:%d\n",aligned_size,dst_elems);
        float *output_data = (float *)malloc(dst_elems *sizeof(float));
        if (output_data == NULL) {
            printf("Failed to allocate memory for output_data\n");
        }
        printf("output_attr->layout: %d\n",output_attr->layout);
        // int channel = 3;
        // int h = output_attr->n_dims,w = 624;
        // int h =0,w = 0;
        // for(int dim = 0;dim < output_attr->n_dims;dim ++) {
        //     h = output_attr->shape;
        // }

        int channel = output_attr[i].n_dims > 1 ? output_attr[i].shape[1] : 1;
        int h = output_attr[i].n_dims > 2 ? output_attr[i].shape[2] : 1;
        int w = output_attr[i].n_dims > 3 ? output_attr[i].shape[3] : 1;
        if (output_attr->layout == RKNN3_TENSOR_NC1HWC2) {
            if (output_attr->dtype == RKNN3_TENSOR_FLOAT16) {
                int C1 = output_attr->shape[1];
                int C2 = output_attr->shape[4];
                int hw = output_attr->shape[2] * output_attr->shape[3]; 
                // int channel = 
                NC1HWC2_fp16_to_NCHW_fp32((float16 *)output_mem->virt_addr, output_data, batch, C1, C2, hw, channel, h, w);
            } else if (output_attr->dtype == RKNN3_TENSOR_INT8) {
                int C1 = output_attr->shape[1];
                int C2 = output_attr->shape[4];
                int hw = output_attr->shape[2] * output_attr->shape[3];
                NC1HWC2_int8_to_NCHW_fp32((int8_t *)output_mem->virt_addr, output_data, batch, C1, C2, hw, channel, h, w, output_attr);
            } else {
                printf("Unsupported type for NC1HWC2 format: %s\n", rknn3_get_type_string(output_attr->dtype));
                return -1;
            }
        } else if (output_attr->layout == RKNN3_TENSOR_NCHW || output_attr->layout == RKNN3_TENSOR_UNDEFINED) {
            if (output_attr->dtype == RKNN3_TENSOR_INT8) {
                float scale = output_attr->qnt_info.scale;
                int32_t zero_point = output_attr->qnt_info.zero_point;
                convert_int8_to_fp32(output_mem->virt_addr, output_data, dst_elems, output_attr->dtype, scale, zero_point);
            } else {
                convert_any_type_to_fp32(output_mem->virt_addr, output_data, dst_elems, output_attr->dtype);
            }
        } else {
            printf("Unsupported output format: %s\n", rknn3_get_layout_string(output_attr->layout));
        }

        size_t *shape = (size_t *)malloc(output_attr->n_dims * sizeof(size_t));
        memset(shape, 0, output_attr->n_dims * sizeof(size_t));
        for (uint32_t j = 0; j < output_attr->n_dims; j++) {
            shape[j] = output_attr->shape[j];
        }
        char filename[256];
        snprintf(filename, sizeof(filename), "output_data_%d.npy", i);
        npy_save_float_buffer_to_file(filename, output_data, output_attr->n_elems, shape, output_attr->n_dims);
        if (shape) {
            free(shape);
            shape = NULL;
        }
        if(output_data) {
            free(output_data);
            output_data = NULL;
        }
    }

#endif 
    // Get Output
    // printf("......vision_ctx->outputs[0].mem->size:%d\n",vision_ctx->outputs[0].mem->size);

    // memcpy(img_embeds, (float16*)vision_ctx->outputs[0].mem->virt_addr,vision_ctx->outputs[0].mem->size);

out:
    if (dst_img.virt_addr != NULL)
    {
        free(dst_img.virt_addr);
    }

    return ret;
}