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
#include <sys/time.h>
#include <unistd.h>

#include "easy_timer.h"
#include "image_utils.h"
#include "rknn3_ini.h"
#include "rknn3_vlm.h"

TIMER vision_cost;
TIMER llm_perfill, llm_decode;
int32_t gen_tokens = 0;
int32_t first_tokens = 1;
float tps = 0.f;
TIMER vl_cost;
TIMER infer_cost_time;
int32_t infer_loop_cnt;
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

// const char* system_prompt  = "<|im_start|>system\nYou are a helpful assistant.<|im_end|>\n";
// const char* prompt_prefix  = "<|im_start|>user\n";
// const char* prompt_postfix = "<|im_end|>\n<|im_start|>assistant\n";
// '<|im_start|>system\nYou are a helpful assistant.<|im_end|>\n<|im_start|>user\n<|vision_start|><|image_pad|>*x<|vision_end|>这张图片是关于什么的<|im_end|>\n<|im_start|>assistant\n'
/*-------------------------------------------
                Callback Function
-------------------------------------------*/
int result_callback(void *userdata, RKLLMResult *result, LLMCallState state) {
    Tokenizer *tokenizer = (Tokenizer *)userdata;

    if (state == RKLLM_RUN_ERROR) {
        printf("\n\nError occurred during inference\n");
        return 0;
    } else if (state == RKLLM_RUN_FINISH) {
        llm_decode.tok();
        first_tokens = 1;
        tps = gen_tokens / llm_decode.get_time() * 1000.f;
        
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
            llm_decode.tik();
            llm_perfill.tok();
            vl_cost.tok();
            first_tokens = 0;
            gen_tokens = 1;
            
        }
        else {
            gen_tokens += 1;
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

void print_usage(char *argv[]) {
    printf("Usage:\n");
    printf("%s [options]\n\n", argv[0]);
    printf("Options:\n");
    printf("  -vm, --vision_model   \n");
    printf("  -vw, --vision_weight  \n");
    printf("  -lm, --llm_model      \n");
    printf("  -lw, --llm_weight     \n");
    printf("  -tk, --tokenizer      \n");
    printf("  -em, --embedding      \n");
    printf("  -vc, --vision_core_mask \n");
    printf("  -lc, --llm_core_mask   \n");
    printf("  -im, --image_path      \n");
    printf("  -pi, --prompt_ini     \n");
    printf("  -vl, --vision_loop   default:1  \n");
    printf("  -ll, --llm_loop  default:1       \n");
    printf("  -tl, --time_loop(hours) \n");
    printf("\nUse '%s --help' to display this message.\n", argv[0]);

    return;
}
/*-------------------------------------------
                  Main Function
-------------------------------------------*/
int main(int argc, char **argv) {

    // 定义变量
    char *vision_model_path = NULL, *vision_weight_path = NULL;
    char *llm_model_path = NULL, *llm_weight_path = NULL;
    char *tokenizer_path = NULL, *embedding_path = NULL;
    uint32_t vision_core_mask = 0, llm_core_mask = 0;
    char *img_path = NULL, *prompt_path = NULL;
    uint32_t vision_loop = 1, llm_loop = 1;
    float time_loop = 0.f;
    uint32_t device_id = 0;

    for (int i = 1; i < argc; i += 2) {
        if (strcmp(argv[i], "-vm") == 0 || strcmp(argv[i], "--vision_model") == 0) {
            vision_model_path = argv[i + 1];
        } else if (strcmp(argv[i], "-vw") == 0 || strcmp(argv[i], "--vision_weight") == 0) {
            vision_weight_path = argv[i + 1];
        } else if (strcmp(argv[i], "-lm") == 0 || strcmp(argv[i], "--llm_model") == 0) {
            llm_model_path = argv[i + 1];
        } else if (strcmp(argv[i], "-lw") == 0 || strcmp(argv[i], "--llm_weight") == 0) {
            llm_weight_path = argv[i + 1];
        } else if (strcmp(argv[i], "-tk") == 0 || strcmp(argv[i], "--tokenizer") == 0) {
            tokenizer_path = argv[i + 1];
        } else if (strcmp(argv[i], "-em") == 0 || strcmp(argv[i], "--embedding") == 0) {
            embedding_path = argv[i + 1];
        } else if (strcmp(argv[i], "-vc") == 0 || strcmp(argv[i], "--vision_core_mask") == 0) {
            vision_core_mask = strtoul(argv[i + 1],nullptr, 16);
        } else if (strcmp(argv[i], "-lc") == 0 || strcmp(argv[i], "--llm_core_mask") == 0) {
            llm_core_mask = strtoul(argv[i + 1],nullptr, 16);
        } else if (strcmp(argv[i], "-im") == 0 || strcmp(argv[i], "--image_path") == 0) {
            img_path = argv[i + 1];
        } else if (strcmp(argv[i], "-pi") == 0 || strcmp(argv[i], "--prompt_ini") == 0) {
            prompt_path = argv[i + 1];
        } else if (strcmp(argv[i], "-vl") == 0 || strcmp(argv[i], "--vision_loop") == 0) {
            vision_loop = atoi(argv[i + 1]);
        } else if (strcmp(argv[i], "-ll") == 0 || strcmp(argv[i], "--llm_loop") == 0) {
            llm_loop = atoi(argv[i + 1]);
        } else if(strcmp(argv[i], "-tl") == 0 || strcmp(argv[i], "--time_loop") == 0) {
            time_loop = atof(argv[i + 1]);
        } else if (strcmp(argv[i], "-id") == 0 || strcmp(argv[i], "--device_id") == 0) {
            device_id = atoi(argv[i + 1]);
        }  else if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0) {
            print_usage(argv);
            return 0;
        }else {
            printf("[rknn3_model_stress_test_error] Unknown option: %s\n", argv[i]);
            return -1;
        }
    }

    // 打印解析结果
    printf("vision_model: %s\n", vision_model_path);
    printf("vision_weight: %s\n", vision_weight_path);
    printf("llm_model: %s\n", llm_model_path);
    printf("llm_weight: %s\n", llm_weight_path);
    printf("tokenizer: %s\n", tokenizer_path);
    printf("embedding: %s\n", embedding_path);
    printf("vision_core_mask: %p\n", vision_core_mask);
    printf("llm_core_mask: %p\n", llm_core_mask);
    printf("image_path: %s\n", img_path);
    printf("prompt.ini: %s\n", prompt_path);
    printf("vision_loop: %d\n", vision_loop);
    printf("llm_loop: %d\n", llm_loop);
    printf("device_id : %d\n", device_id);

    // 检查必要参数
    if (!vision_model_path || !vision_weight_path || !llm_model_path || !llm_weight_path || vision_core_mask == 0 || llm_core_mask == 0) {
        printf("[rknn3_model_stress_test_error]: Missing required arguments.\n");
        return -1;
    }

    // if(vision_loop == 0  && llm_loop == 0 && time_loop == 0) {
    //     printf("[rknn3_model_stress_test_error]: Please set vision_loop&llm_loop or time_loop.\n");
    //     return -1;
    // }

    if(time_loop != 0.f) {
        vision_loop = 1;
        llm_loop = 1;
    }

    int ret;

    if (ini_load(prompt_path) != 0) {
        fprintf(stderr, "cannot load ini\n");
        return 1;
    }

    float perfill_time = 0.f;

    const char *prompt = ini_get("prompt", "prompt", "");
    const char *system_prompt = ini_get("prompt", "system_prompt", "");
    const char *prompt_prefix = ini_get("prompt", "prompt_prefix", "");
    const char *prompt_postfix = ini_get("prompt", "prompt_postfix", "");
    int32_t print_result = ini_get_int("results", "print_result", 1);
    int32_t pruned_model_width = ini_get_int("tensor", "pruned_model_width", 0);
    int32_t pruned_model_height = ini_get_int("tensor", "pruned_model_height", 0);

    is_print_result = print_result;

    // const char *prompt = "what is in the image?";
    // RKNN Context
    rknn_app_context_t rknn_app_ctx;
    memset(&rknn_app_ctx, 0, sizeof(rknn_app_context_t));

    // Tokenizer
    Tokenizer *tokenizer;
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
    float16 *img_embeds;

    // LLM Multi Model Tensor
    // int n_inputs = 1;
    rknn3_llm_multimodal_tensor tensor;
    memset(&tensor, 0, sizeof(rknn3_llm_multimodal_tensor));

    // Callback
    RKLLMCallback callback;
    memset(&callback, 0, sizeof(RKLLMCallback));

    // Load Toenizer
    tokenizer = new Tokenizer(TOKENIZER_BACKEND_LLAMA, tokenizer_path);
    if (!tokenizer) {
        printf("[rknn3_model_stress_test_error] load tokenizer failed! tokenizer_path=%s\n", tokenizer_path);
        goto out;
    }

    tokenizer->GetVocabInfo(&(vocab_info));
    printf("vocab_info: vocab_size=%d special_bos_id=%d special_eos_id=%d\n", vocab_info.vocab_size,
           vocab_info.special_bos_id, vocab_info.special_eos_id);

    // Read Embedding
    embedding_info.fd = open(embedding_path, O_RDONLY);
    if (embedding_info.fd == -1) {
        printf("[rknn3_model_stress_test_error] Failed to open embedding file: %s\n", embedding_path);
        goto out;
    }

    if (fstat(embedding_info.fd, &emb_st) == -1) {
        printf("[rknn3_model_stress_test_error] Failed to get embedding file size\n");
        goto out;
    }

    embedding_info.embedding_data = (float16 *)mmap(NULL, emb_st.st_size, PROT_READ, MAP_PRIVATE, embedding_info.fd, 0);
    if (embedding_info.embedding_data == MAP_FAILED) {
        printf("[rknn3_model_stress_test_error] Failed to mmap embedding file\n");
        goto out;
    }

    embedding_info.vocab_size = vocab_info.vocab_size;
    embedding_info.embedding_dim = (emb_st.st_size / vocab_info.vocab_size) / sizeof(float16);

#if 0
    // Set LLM parameters
    params.logits_name               = "logits";
    params.max_context_len           = MAX_CONTEXT_LEN;
    // params.max_new_tokens            = MAX_NEW_TOKENS;
    params.sampling_param            = SAMPLE_PARAMS;
    params.vocab_info.vocab_size     = vocab_info.vocab_size;
    params.vocab_info.special_eos_id = vocab_info.special_eos_id;
    params.vocab_info.linefeed_id    = vocab_info.linefeed_id;

    // LLM Callback
    callback.result_callback    = result_callback;
    callback.result_userdata    = tokenizer;
    callback.tokenizer_callback = tokenizer_callback;
    callback.tokenizer_userdata = tokenizer;
    callback.embed_callback     = embed_callback;
    callback.embed_userdata     = &embedding_info;
#else
    // Set LLM parameters
    params.logits_name = "logits";
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

#endif
    strncpy(rknn_app_ctx.llm.system_prompt, system_prompt, strlen(system_prompt) - 1);
    strncpy(rknn_app_ctx.llm.prefix_prompt, prompt_prefix, strlen(prompt_prefix) - 1);
    strncpy(rknn_app_ctx.llm.postfix_prompt, prompt_postfix, strlen(prompt_postfix) - 1);

    rknn_app_ctx.vision.model_width = pruned_model_width;
    rknn_app_ctx.vision.model_height = pruned_model_height;
    rknn_app_ctx.vision.device_id = device_id;
    rknn_app_ctx.llm.device_id = device_id;
    
    // printf("rknn_app_ctx.vision.model_width:%d\n",rknn_app_ctx.vision.model_width);
    // printf("==================================rknn_app_ctx.llm.system_prompt: %s,system_prompt:%s\n",rknn_app_ctx.llm.system_prompt,system_prompt);
    // printf("==================================rknn_app_ctx.llm.prefix_prompt: %s\n",rknn_app_ctx.llm.prefix_prompt);
    ret = init_rknn3_vlm_model(&rknn_app_ctx, llm_model_path, llm_weight_path, vision_model_path, vision_weight_path, &params, n_params, callback, vision_core_mask, llm_core_mask);
    if (ret != 0) {
        printf("[rknn3_model_stress_test_error] init_rknn3_vlm_model fail! ret=%d llm_model_path=%s vision_model_path=%s\n", ret, llm_model_path, vision_model_path);
        goto out;
    }
    
    // Image Embed
    for (size_t i = 0; i < rknn_app_ctx.vision.embeds_ndims; i++) {
        embed_elems *= rknn_app_ctx.vision.embeds_shape[i];
    }
    img_embeds = (float16 *)malloc((embed_elems) * sizeof(float16));

    // Read Image
    ret = read_image(img_path, &src_image);
    if (ret != 0) {
        printf("[rknn3_model_stress_test_error] read image fail! ret=%d image_path=%s\n", ret, img_path);
        goto out;
    }

    // LLM Input
    // tensor.name           = "input_embeds";
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

    // strncpy((char *)tensor.img_start,(char *)img_start,strlen(img_start) - 1);
    tensor.image.image_start = ini_get("tensor", "img_start", "");
    tensor.image.image_end = ini_get("tensor", "img_end", "");
    tensor.image.image_content = ini_get("tensor", "img_content", "");

    // llm_perfill.tik();
    vl_cost.tik();
    ret = inference_rknn3_vlm_model(&rknn_app_ctx, &src_image, tensor, vision_loop, llm_loop,time_loop);
    if (ret != 0) {
        printf("[rknn3_model_stress_test_error] inference rknn3_vlm model fail! ret=%d\n", ret);
        goto out;
    }

    {
        const char *last_slash = strrchr(llm_model_path, '/');
        const char *filename;

        if (last_slash != NULL) {
            filename = last_slash + 1;
        } else {
            filename = llm_model_path;     
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
        printf("\n===== RKNN3_VLM_TEST 结果汇总 =====\n\n");
        printf("RK1820 deviceID: %s\n",rknn_app_ctx.llm.device_mac);
        printf("RKNN3模型: %s\n",model_name);
        printf("%s 总耗时：%12.3f (ms)\n",model_name,infer_cost_time.get_time());
        printf("%s 总推理次数: %d\n",model_name,infer_loop_cnt);
        printf("\n=================================\n");


    }
    


out:
    ret = release_rknn3_vlm_model(&rknn_app_ctx);

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

    return ret;
}