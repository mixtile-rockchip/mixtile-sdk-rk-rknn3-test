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
#include <dirent.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>

#include "cmdline_parser.h"
#include "easy_timer.h"
#include "image_utils.h"
#include "audio_utils.h"
#include "rknn3_ini.h"
#include "rknn3_vlm.h"

rknn3_vlm_perf_t g_vlm_perf;
int32_t first_tokens = 1;
int is_print_result = 1;
struct embedding_info {
    int fd;
    float16 *embedding_data;
    int embedding_dim;
    int vocab_size;
};

const rknn3_sampling_params SAMPLE_PARAMS = {
    .top_k = 1,
    .top_p = 0.9,
    .temperature = 1.0f,
    .repeat_penalty = 1.2f,
    .frequency_penalty = 0.0f,
    .presence_penalty = 0.0f
};

/*-------------------------------------------
                Callback Function
-------------------------------------------*/
int result_callback(void *userdata, RKLLMResult *result, LLMCallState state) {
    Tokenizer *tokenizer = (Tokenizer *)userdata;

    if (state == RKLLM_RUN_ERROR) {
        printf("\n\nError occurred during inference\n");
        return 0;
    } else if (state == RKLLM_RUN_FINISH) {
        g_vlm_perf.llm_decode.tok();
        first_tokens = 1;
        g_vlm_perf.tps = g_vlm_perf.gen_tokens / g_vlm_perf.llm_decode.get_time() * 1000.f;

        // printf("\n\n--------------------Finished-------------------- \n");
        return 0;
    } else if (state == RKLLM_RUN_WAITING) {
        printf("\n\nWaiting for UTF-8 encoded character\n");
        return 0;
    } else if (state == RKLLM_RUN_MAX_NEW_TOKEN_REACHED) {
        printf("\n\n--------------Max new token reached------------- \n");
        return 0;
    } else if (state == RKLLM_RUN_STOP) {
        printf("\n\n-----------------------Stop--------------------- \n");
        return 0;
    } else if (state == RKLLM_RUN_NORMAL) {
        if (first_tokens) {
            g_vlm_perf.llm_decode.tik();
            g_vlm_perf.llm_perfill.tok();
            g_vlm_perf.vl_cost.tok();
            first_tokens = 0;
            g_vlm_perf.gen_tokens = 1;

        } else {
            g_vlm_perf.gen_tokens += 1;
        }
        if (is_print_result) {
            if (result->num_tokens > 1) {
                for (int i = 0; i < result->num_tokens; i++) {
                    std::string piece = tokenizer->Decode(result->token_ids, result->num_tokens);
                    printf("%s", piece.c_str());
                }
            } else {
                std::string piece = tokenizer->TokenToPiece(result->token_ids[0]);
                printf("%s", piece.c_str());
            }
        }

        fflush(stdout);
    }
    return 0;
}

int tokenizer_callback(void *userdata, const char *text, int32_t text_len, int32_t *tokens, int32_t n_tokens_max) {
    int n_tokens = 0;
    Tokenizer *tokenizer = (Tokenizer *)userdata;
    n_tokens = tokenizer->Tokenize(text, text_len, tokens, n_tokens_max);

    if (n_tokens <= 0) {
        printf("tokenizer failed for %s\n", text);
        return n_tokens;
    }

    return n_tokens;
}

int embed_callback(void *userdata, int32_t *tokens, uint64_t num_tokens, void *embded, uint64_t len) {
    struct embedding_info *embded_info = (struct embedding_info *)userdata;

    if (len != num_tokens * embded_info->embedding_dim * sizeof(float16)) {
        printf("invalid embded buffer\n");
        return -1;
    }

    for (int n = 0; n < num_tokens; n++) {
        memcpy((unsigned char *)embded + n * embded_info->embedding_dim * sizeof(float16), embded_info->embedding_data + tokens[n] * embded_info->embedding_dim,
               embded_info->embedding_dim * sizeof(float16));
    }

    return 0;
}

/*-------------------------------------------
                  Main Function
-------------------------------------------*/
int main(int argc, char **argv) {
    int ret = 0;

    // Parse command line arguments
    cmdline_args_t args;
    ret = parse_cmdline_args(argc, argv, &args);
    if (ret != 0 || args.show_help) {
        print_usage(argv[0], PROGRAM_TYPE_VLM, NULL, 0);
        return args.show_help ? 0 : -1;
    }

    // Validate required arguments for VLM using common function
    ret = validate_required_params(&args, PROGRAM_TYPE_VLM);
    if (ret != 0) {
        print_usage(argv[0], PROGRAM_TYPE_VLM, NULL, 0);
        return -1;
    }

    // Handle time_loop override
    handle_time_loop_override(&args, PROGRAM_TYPE_VLM);

    // Print configuration using common function
    print_configuration(&args, PROGRAM_TYPE_VLM);

    srand((unsigned int)time(NULL));

    // Determine mode by vision/encoder model filename:
    //   - vision model name contains "asr" or "encoder" → ASR mode
    //   - otherwise → VLM mode
    bool is_asr_mode = false;
    if (args.vision_model_path) {
        const char *vm = args.vision_model_path;
        if (strcasestr(vm, "asr") || strcasestr(vm, "encoder")) {
            is_asr_mode = true;
        }
    }

    if (ini_load(args.prompt_ini_path) != 0) {
        if (!is_asr_mode) {
            fprintf(stderr, "cannot load ini\n");
            free_cmdline_args(&args);
            return 1;
        }
        // ASR mode: ini file is optional, use defaults
    }

    float perfill_time = 0.f;

    const char *prompt = nullptr;
    const char *system_prompt = nullptr;
    const char *prompt_prefix = nullptr;
    const char *prompt_postfix = nullptr;
    int32_t print_result = 1;
    int32_t pruned_model_width = 0;
    int32_t pruned_model_height = 0;

    if (!is_asr_mode) {
        prompt = ini_get("prompt", "prompt", "");
        system_prompt = ini_get("prompt", "system_prompt", "");
        prompt_prefix = ini_get("prompt", "prompt_prefix", "");
        prompt_postfix = ini_get("prompt", "prompt_postfix", "");
        pruned_model_width = ini_get_int("tensor", "pruned_model_width", 0);
        pruned_model_height = ini_get_int("tensor", "pruned_model_height", 0);
    }
    // ASR and VLM both read print_result from ini (ASR defaults to 0 if no ini)
    print_result = ini_get_int("results", "print_result", is_asr_mode ? 0 : 1);

    is_print_result = print_result;

    // init g_vlm_perf
    g_vlm_perf.tot_memory = 0;

    // RKNN Context
    rknn_app_context_t rknn_app_ctx;
    memset(&rknn_app_ctx, 0, sizeof(rknn_app_context_t));

    // Tokenizer
    Tokenizer *tokenizer = NULL;
    VocabInfo vocab_info;

    // Embedding
    struct embedding_info embedding_info;
    struct stat emb_st;
    memset(&embedding_info, 0x00, sizeof(embedding_info));

    // LLM Param
    int n_params = 1;
    rknn3_llm_param params;
    memset(&params, 0, sizeof(rknn3_llm_param));

    // Input Image
    image_buffer_t src_image;
    memset(&src_image, 0, sizeof(image_buffer_t));

    // Image Embed
    size_t embed_elems = 1;
    float16 *img_embeds = NULL;

    // LLM Multi Model Tensor
    // int n_inputs = 1;
    rknn3_llm_multimodal_tensor tensor;
    memset(&tensor, 0, sizeof(rknn3_llm_multimodal_tensor));

    // Callback
    RKLLMCallback callback;
    memset(&callback, 0, sizeof(RKLLMCallback));

    // Load Toenizer
    printf("Loading tokenizer from %s\n", args.tokenizer_path);
    tokenizer = new Tokenizer(TOKENIZER_BACKEND_LLAMA, args.tokenizer_path);
    if (!tokenizer) {
        printf("[rknn3_model_stress_test_error] load tokenizer failed! tokenizer_path=%s\n", args.tokenizer_path);
        goto out;
    }

    tokenizer->GetVocabInfo(&(vocab_info));
    printf("vocab_info: vocab_size=%d n_special_bos_id=%d n_special_eos_id=%d\n", vocab_info.vocab_size,
           vocab_info.n_special_bos_id, vocab_info.n_special_eos_id);

    // Read Embedding
    printf("Opening embedding file: %s\n", args.embedding_path);
    embedding_info.fd = open(args.embedding_path, O_RDONLY);
    if (embedding_info.fd == -1) {
        printf("[rknn3_model_stress_test_error] Failed to open embedding file: %s\n", args.embedding_path);
        goto out;
    }

    if (fstat(embedding_info.fd, &emb_st) == -1) {
        printf("[rknn3_model_stress_test_error] Failed to get embedding file size\n");
        goto out;
    }
    printf("Embedding file size: %ld bytes\n", emb_st.st_size);

    embedding_info.embedding_data = (float16 *)mmap(NULL, emb_st.st_size, PROT_READ, MAP_PRIVATE, embedding_info.fd, 0);
    if (embedding_info.embedding_data == MAP_FAILED) {
        printf("[rknn3_model_stress_test_error] Failed to mmap embedding file\n");
        goto out;
    }
    printf("Embedding mmap success, dim=%d\n", (int)((emb_st.st_size / vocab_info.vocab_size) / sizeof(float16)));

    embedding_info.vocab_size = vocab_info.vocab_size;
    embedding_info.embedding_dim = (emb_st.st_size / vocab_info.vocab_size) / sizeof(float16);

    // Set LLM parameters
    params.logits_name = (char *)"logits";
    params.max_context_len = MAX_CONTEXT_LEN;
    params.sampling_param = SAMPLE_PARAMS;
    params.vocab_info.vocab_size = vocab_info.vocab_size;
    memcpy(params.vocab_info.special_bos_id, vocab_info.special_bos_id, RKNN3_MAX_SPECIAL_BOS_ID_NUM * sizeof(int));
    memcpy(params.vocab_info.special_eos_id, vocab_info.special_eos_id, RKNN3_MAX_SPECIAL_EOS_ID_NUM * sizeof(int));
    params.vocab_info.n_special_bos_id = vocab_info.n_special_bos_id;
    params.vocab_info.n_special_eos_id = vocab_info.n_special_eos_id;
    params.vocab_info.linefeed_id = vocab_info.linefeed_id;

    // LLM Callback
    callback.result_callback = result_callback;
    callback.result_userdata = tokenizer;
    callback.tokenizer_callback = tokenizer_callback;
    callback.tokenizer_userdata = tokenizer;
    callback.embed_callback = embed_callback;
    callback.embed_userdata = &embedding_info;

    if (is_asr_mode) {
        // ===== ASR Mode =====
        printf("[rknn3_stress_test_log] ASR mode: initializing...\n");
        params.logits_name = (char *)"logits";
        params.max_context_len = ASR_MAX_CONTEXT_LEN;
        params.vocab_info.vocab_size = vocab_info.vocab_size;
        memcpy(params.vocab_info.special_bos_id, vocab_info.special_bos_id, RKNN3_MAX_SPECIAL_BOS_ID_NUM * sizeof(int));
        memcpy(params.vocab_info.special_eos_id, vocab_info.special_eos_id, RKNN3_MAX_SPECIAL_EOS_ID_NUM * sizeof(int));
        params.vocab_info.n_special_bos_id = vocab_info.n_special_bos_id;
        params.vocab_info.n_special_eos_id = vocab_info.n_special_eos_id;
        params.vocab_info.linefeed_id = vocab_info.linefeed_id;

        rknn_app_ctx.llm.device_id = args.device_id;
        rknn_app_ctx.device_id = args.device_id;

        printf("ASR: calling init_rknn3_asr_model\n");
        // vision_model_path → audio model, vision_weight_path → audio weight, vision_core_mask → audio core mask
        ret = init_rknn3_asr_model(&rknn_app_ctx,
                                    args.llm_model_path, args.llm_weight_path,
                                    args.vision_model_path, args.vision_weight_path,
                                    &params, n_params, callback,
                                    args.vision_core_mask, args.llm_core_mask,
                                    tokenizer, embedding_info.embedding_data, embedding_info.embedding_dim, vocab_info.vocab_size);
        if (ret != 0) {
            printf("[rknn3_model_stress_test_error] init_rknn3_asr_model fail! ret=%d\n", ret);
            free_cmdline_args(&args);
            goto out;
        }
        // Resolve audio path: use user-specified or find from model directory
        const char *audio_path = args.audio_path;
        char auto_audio_path[1024] = {0};
        if (!audio_path && args.model_folder) {
            DIR *dir = opendir(args.model_folder);
            if (dir) {
                struct dirent *ent;
                while ((ent = readdir(dir)) != NULL) {
                    if (strstr(ent->d_name, ".wav") || strstr(ent->d_name, ".mp3") ||
                        strstr(ent->d_name, ".flac") || strstr(ent->d_name, ".pcm")) {
                        snprintf(auto_audio_path, sizeof(auto_audio_path), "%s/%s", args.model_folder, ent->d_name);
                        audio_path = auto_audio_path;
                        printf("[rknn3_stress_test_log] Auto-detected audio file: %s\n", audio_path);
                        break;
                    }
                }
                closedir(dir);
            }
        }
        if (!audio_path) {
            printf("[rknn3_model_stress_test_error] No audio file specified (-a) and no audio file found in model directory\n");
            goto out;
        }

        // Read audio
        audio_buffer_t src_audio;
        memset(&src_audio, 0, sizeof(audio_buffer_t));
        ret = read_audio(audio_path, &src_audio);
        if (ret != 0) {
            printf("[rknn3_model_stress_test_error] read audio fail! ret=%d audio_path=%s\n", ret, audio_path);
            goto out;
        }

        g_vlm_perf.vl_cost.tik();
        ret = inference_rknn3_asr_model(&rknn_app_ctx, &src_audio, args.llm_loop, args.time_loop);
        if (ret != 0) {
            printf("[rknn3_model_stress_test_error] inference rknn3_asr model fail! ret=%d\n", ret);
        }

        {
            const char *last_slash = strrchr(args.llm_model_path, '/');
            const char *filename = last_slash ? last_slash + 1 : args.llm_model_path;

            char model_name[256];
            strncpy(model_name, filename, sizeof(model_name) - 1);
            model_name[sizeof(model_name) - 1] = '\0';
            char *last_dot = strrchr(model_name, '-');
            if (last_dot != NULL && strcmp(last_dot, "-llm.rknn") == 0) {
                *last_dot = '\0';
            }
            printf("\n===== RKNN3_ASR_TEST Results Summary =====\n\n");
            printf("Model: %s\n", model_name);
            printf("DeviceID: %s\n", rknn_app_ctx.llm.device_mac);
            printf("LoadAudioModelTime: %.3f ms\n", g_vlm_perf.load_vision_model.get_time());
            printf("LoadLLMModelTime: %.3f ms\n", g_vlm_perf.load_llm_model.get_time());
            printf("ModelMemory: %.3f MB\n", (float)g_vlm_perf.tot_memory / (1024. * 1024.));
            printf("Audio: %.f ms\n", g_vlm_perf.vision_cost.get_time());
            printf("GenLen: %d tokens\n", g_vlm_perf.gen_tokens);
            printf("TTFT: %.3f ms\n", g_vlm_perf.llm_perfill.get_time());
            printf("TPS: %.3f tokens/s\n", g_vlm_perf.tps);
            printf("TotalTime: %.3f ms\n", g_vlm_perf.infer_cost_time.get_time());
            printf("TotalRuns: %d\n", g_vlm_perf.infer_loop_cnt);
            printf("\n=================================\n");
            printf("[rknn3_model_stress_test_done]\n");
        }

        if (src_audio.data != NULL) {
            free(src_audio.data);
            src_audio.data = NULL;
        }

    } else {
        // ===== VLM Mode (original) =====
        strncpy(rknn_app_ctx.llm.system_prompt, system_prompt, sizeof(rknn_app_ctx.llm.system_prompt) - 1);
        rknn_app_ctx.llm.system_prompt[sizeof(rknn_app_ctx.llm.system_prompt) - 1] = '\0';
        strncpy(rknn_app_ctx.llm.prefix_prompt, prompt_prefix, sizeof(rknn_app_ctx.llm.prefix_prompt) - 1);
        rknn_app_ctx.llm.prefix_prompt[sizeof(rknn_app_ctx.llm.prefix_prompt) - 1] = '\0';
        strncpy(rknn_app_ctx.llm.postfix_prompt, prompt_postfix, sizeof(rknn_app_ctx.llm.postfix_prompt) - 1);
        rknn_app_ctx.llm.postfix_prompt[sizeof(rknn_app_ctx.llm.postfix_prompt) - 1] = '\0';

        rknn_app_ctx.vision.model_width = pruned_model_width;
        rknn_app_ctx.vision.model_height = pruned_model_height;
        rknn_app_ctx.vision.device_id = args.device_id;
        rknn_app_ctx.llm.device_id = args.device_id;
        rknn_app_ctx.device_id = args.device_id;

        ret = init_rknn3_vlm_model(&rknn_app_ctx, args.llm_model_path, args.llm_weight_path, args.vision_model_path, args.vision_weight_path, &params, n_params, callback, args.vision_core_mask, args.llm_core_mask);
        if (ret != 0) {
            printf("[rknn3_model_stress_test_error] init_rknn3_vlm_model fail! ret=%d llm_model_path=%s vision_model_path=%s\n", ret, args.llm_model_path, args.vision_model_path);
            free_cmdline_args(&args);
            goto out;
        }

        // Image Embed
        for (size_t i = 0; i < rknn_app_ctx.vision.embeds_ndims; i++) {
            embed_elems *= rknn_app_ctx.vision.embeds_shape[i];
        }
        img_embeds = (float16 *)malloc((embed_elems) * sizeof(float16));

        src_image.format = args.yuv_input ? IMAGE_FORMAT_YUV420SP_NV12 : IMAGE_FORMAT_RGB888;
        if (args.image_path == NULL || strlen(args.image_path) == 0) {
            const int kMaxRandomInputSize = 100 * 1024 * 1024;  // 100MB hard limit
            src_image.width = 640;
            src_image.height = 640;
            int64_t expected_size = args.yuv_input
                                        ? ((int64_t)src_image.width * src_image.height * 3) / 2
                                        : ((int64_t)src_image.width * src_image.height * 3);
            if (expected_size <= 0 || expected_size > INT_MAX || expected_size > kMaxRandomInputSize) {
                printf("[rknn3_model_stress_test_error] invalid random input size: %lld\n", (long long)expected_size);
                ret = -1;
                goto out;
            }
            src_image.size = (int)expected_size;
            src_image.virt_addr = (uint8_t *)malloc(src_image.size);
            if (!src_image.virt_addr) {
                printf("[rknn3_model_stress_test_error] malloc random input buffer fail!\n");
                ret = -1;
                goto out;
            }
            // 填充随机数据
            for (int i = 0; i < src_image.size; ++i) {
                src_image.virt_addr[i] = rand() & 0xFF;
            }
        } else {
            ret = read_image(args.image_path, &src_image);
            if (ret != 0) {
                printf("[rknn3_model_stress_test_error] read image fail! ret=%d image_path=%s\n", ret, args.image_path);
                goto out;
            }
        }

        tensor.name = ini_get("tensor", "input_embeds", "");
        tensor.prompt = prompt;
        tensor.image.image_embed = img_embeds;
        if (rknn_app_ctx.vision.embeds_ndims == 2) {
            tensor.image.n_image_tokens = rknn_app_ctx.vision.embeds_shape[0];
            tensor.image.n_image = 1;
        } else {
            tensor.image.n_image_tokens = rknn_app_ctx.vision.embeds_shape[1];
            tensor.image.n_image = rknn_app_ctx.vision.embeds_shape[0];
        }
        tensor.image.image_width = rknn_app_ctx.vision.model_width;
        tensor.image.image_height = rknn_app_ctx.vision.model_height;
        tensor.enable_thinking = false;

        tensor.image.image_start = ini_get("tensor", "img_start", "");
        tensor.image.image_end = ini_get("tensor", "img_end", "");
        tensor.image.image_content = ini_get("tensor", "img_content", "");

        g_vlm_perf.vl_cost.tik();
        ret = inference_rknn3_vlm_model(&rknn_app_ctx, &src_image, tensor, args.vision_loop, args.llm_loop, args.time_loop);
        if (ret != 0) {
            printf("[rknn3_model_stress_test_error] inference rknn3_vlm model fail! ret=%d\n", ret);
            goto out;
        }

        {
            const char *last_slash = strrchr(args.llm_model_path, '/');
            const char *filename;

            if (last_slash != NULL) {
                filename = last_slash + 1;
            } else {
                filename = args.llm_model_path;
            }

            char model_name[256];
            strncpy(model_name, filename, sizeof(model_name) - 1);
            model_name[sizeof(model_name) - 1] = '\0';
            char *last_dot = strrchr(model_name, '-');
            if (last_dot != NULL) {
                if (strcmp(last_dot, "-llm.rknn") == 0) {
                    *last_dot = '\0';
                }
            }
            printf("\n===== RKNN3_VLM_TEST Results Summary =====\n\n");
            printf("Model: %s\n", model_name);
            printf("DeviceID: %s\n", rknn_app_ctx.llm.device_mac);
            printf("LoadVisionModelTime: %.3f ms\n", g_vlm_perf.load_vision_model.get_time());
            printf("LoadLLMModelTime: %.3f ms\n", g_vlm_perf.load_llm_model.get_time());
            printf("ModelMemory: %.3f MB\n", (float)g_vlm_perf.tot_memory / (1024. * 1024.));
            printf("Vision: %.f ms\n", g_vlm_perf.vision_cost.get_time());
            printf("GenLen: %d tokens\n", g_vlm_perf.gen_tokens);
            printf("TTFT: %.3f ms\n", g_vlm_perf.llm_perfill.get_time());
            printf("TPS: %.3f tokens/s\n", g_vlm_perf.tps);
            printf("TotalTime: %.3f ms\n", g_vlm_perf.infer_cost_time.get_time());
            printf("TotalRuns: %d\n", g_vlm_perf.infer_loop_cnt);
            printf("\n=================================\n");
            printf("[rknn3_model_stress_test_done]\n");
        }
    }

out:
    if (is_asr_mode) {
        ret = release_rknn3_asr_model(&rknn_app_ctx);
    } else {
        ret = release_rknn3_vlm_model(&rknn_app_ctx);
    }

    if (ret != 0) {
        printf("[rknn3_model_stress_test_error] release rknn3_vlm model fail! ret=%d\n", ret);
    }

    if (embedding_info.fd != -1) {
        if (embedding_info.embedding_data != MAP_FAILED && embedding_info.embedding_data != NULL) {
            munmap((void *)embedding_info.embedding_data, emb_st.st_size);
            embedding_info.embedding_data = NULL;
        }
        close(embedding_info.fd);
        embedding_info.fd = -1;
    }

    if (src_image.virt_addr != NULL) {
        free(src_image.virt_addr);
    }

    if (tokenizer != NULL) {
        delete tokenizer;
        tokenizer = NULL;
    }

    if (img_embeds != NULL) {
        free(img_embeds);
    }

    free_cmdline_args(&args);
    return ret;
}