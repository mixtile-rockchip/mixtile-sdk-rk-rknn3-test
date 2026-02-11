#include <fcntl.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

#include "Tokenizer.h"
#include "cmdline_parser.h"
#include "easy_timer.h"
#include "float16.h"
#include "rknn3_api.h"

#define LOGW(fmt, ...) printf("\033[33m" fmt "\033[0m", ##__VA_ARGS__)

rknn3_session *session = nullptr;

// struct timeval start, first_token, end;
TIMER first_token, decode_time_ms;

static bool first_decode = true;
struct embedding_info {
    int fd;
    float16 *embedding_data;
    int embedding_dim;
    int vocab_size;
};

int argmax(const float16 *data, int size) {
    if (size <= 0 || !data)
        return -1;

    int max_id = 0;
    for (int i = 1; i < size; i++) {
        if (fp16_to_fp32(data[i]) > fp16_to_fp32(data[max_id])) {
            max_id = i;
        }
    }
    return max_id;
}

int sampling_callback(void *userdata, float16 *logits, char *logits_name) {
    struct embedding_info *embded_info = (struct embedding_info *)userdata;
    int size = embded_info->vocab_size;
    int max_id = argmax(logits, size);

    return max_id;
}

int result_callback(void *userdata, RKLLMResult *result, LLMCallState state) {
    Tokenizer *tokenizer = (Tokenizer *)userdata;

    if (state == RKLLM_RUN_ERROR) {
        printf("\n\nError occurred during inference\n");
        fflush(stdout);
        return 0;
    } else if (state == RKLLM_RUN_FINISH) {
        // printf("\n\n--------------------Finished-------------------- \n");
        fflush(stdout);
        return 0;
    } else if (state == RKLLM_RUN_WAITING) {
        printf("\n\nWaiting for UTF-8 encoded character\n");
        fflush(stdout);
        return 0;
    } else if (state == RKLLM_RUN_MAX_NEW_TOKEN_REACHED) {
        // printf("\n\n--------------Max new token reached------------- \n");
        fflush(stdout);
        return 0;
    } else if (state == RKLLM_RUN_STOP) {
        printf("\n\n-----------------------Stop--------------------- \n");
        fflush(stdout);
        return 0;
    } else if (state == RKLLM_RUN_NORMAL) {
        // Get token text
        std::string piece;
        if (result->num_tokens == 1) {
            piece = tokenizer->TokenToPiece(result->token_ids[0]);
        } else {
            piece = tokenizer->Decode(result->token_ids, result->num_tokens);
        }

        if (first_decode) {
            // gettimeofday(&first_token, NULL);
            first_token.tok();
            first_decode = false;
            decode_time_ms.tik();
        }
        fflush(stdout);
    }
    return 0;
}

int tokenizer_callback(void *userdata, const char *text, int32_t text_len, int32_t *tokens, int32_t n_tokens_max) {
    Tokenizer *tokenizer = (Tokenizer *)userdata;

    int n_tokens = tokenizer->Tokenize(text, text_len, tokens, n_tokens_max);

    if (n_tokens <= 0) {
        printf("[rknn3_model_stress_test_error] tokenizer failed for %s\n", text);
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
        memcpy((unsigned char *)embded + n * embded_info->embedding_dim * sizeof(float16),
               embded_info->embedding_data + tokens[n] * embded_info->embedding_dim, embded_info->embedding_dim * sizeof(float16));
    }

    return 0;
}

uint64_t read_tokens_from_bin(const char *binPath, int32_t *tokens) {
    FILE *fp = fopen(binPath, "rb");
    if (!fp) {
        printf("[rknn3_model_stress_test_error] Failed to open file: %s\n", binPath);
        return 0;
    }

    fseek(fp, 0, SEEK_END);
    long fileSize = ftell(fp);
    fseek(fp, 0, SEEK_SET);

    uint64_t n_tokens = fileSize / sizeof(int32_t);
    size_t readSize = fread(tokens, sizeof(int32_t), n_tokens, fp);

    if (readSize != n_tokens) {
        printf("[rknn3_model_stress_test_error] Failed to read file, only read %zu elements\n", readSize);
        fclose(fp);
        return 0;
    }

    fclose(fp);
    return n_tokens;
}

rknn3_context init_context_and_model(const char *model_path, const char *weight_path, uint32_t core_mask, const char *device_id) {
    int ret = 0;
    rknn3_config config;
    rknn3_context ctx = 0;
    // find devices
    rknn3_devices devs;
    memset(&devs, 0, sizeof(devs));
    ret = rknn3_find_devices(&devs);
    if (ret != RKNN3_SUCCESS || devs.n_devices == 0) {
        printf("[rknn3_stress_test_error] rknn3_find_devices fail! ret=%d, devs.n_devices = %d\n", ret, devs.n_devices);
        return -1;
    }

    // 检查devices指针是否有效
    if (devs.devices == NULL) {
        printf("[rknn3_stress_test_error] rknn3_find_devices returned n_devices > 0 but devices is NULL!\n");
        return -1;
    }

    // 检查第一个设备的ID是否有效
    if (devs.devices[0].id == NULL) {
        printf("[rknn3_stress_test_error] device[0].id is NULL!\n");
        return -1;
    }

    printf("[rknn3_stress_test_log] device[0].id=%s\n", devs.devices[0].id);

    // init context
    rknn3_init_extend extend;
    memset(&extend, 0, sizeof(extend));

    // 根据是否指定了设备ID来设置
    if (device_id != nullptr) {
        // 使用指定的设备ID
        extend.device_id = (char *)device_id;
        printf("[rknn3_stress_test_log] Using specified device ID: %s\n", device_id);
    } else {
        // 多个设备时，使用第一个设备的ID
        extend.device_id = devs.devices[0].id;
        printf("[rknn3_stress_test_log] Using first device ID: %s\n", extend.device_id);
    }
    // memcpy(device_id_mac,)
    ret = rknn3_init(&ctx, &extend);
    if (ret < 0) {
        printf("[rknn3_model_stress_test_error] rknn3_init fail! ret=%d\n", ret);
        return -1;
    }

    // load model
    ret = rknn3_load_model_from_path(ctx, model_path, weight_path);
    if (ret != RKNN3_SUCCESS) {
        printf("[rknn3_model_stress_test_error] rknn3_load_model_from_data failed! ret=%d\n", ret);
        rknn3_destroy(ctx);
        return -1;
    }

    // Query model required core number
    uint32_t model_core_num = 0;
    ret = rknn3_query(ctx, RKNN3_QUERY_CORE_NUMBER, &model_core_num, sizeof(model_core_num));
    if (ret < 0) {
        printf("[rknn3_model_stress_test_error] rknn3_query core number failed! ret=%d\n", ret);
        rknn3_destroy(ctx);
        return -1;
    }

    if (core_mask == 0) {
        if (model_core_num > 32U) {
            printf("[rknn3_model_stress_test_error] model_core_num=%u exceeds max supported 32\n", model_core_num);
            rknn3_destroy(ctx);
            return -1;
        }
        // 自动生成core_mask：从0位开始对应core_number个核心
        for (uint32_t i = 0; i < model_core_num; i++) {
            core_mask |= (1U << i);
        }
        printf("Auto-generated core_mask: 0x%x for %u cores\n", core_mask, model_core_num);
    }
    printf("[rknn3_stress_test_log] Model requires %u NPU cores\n", model_core_num);
    printf("[rknn3_stress_test_log] User specified core_mask: 0x%x\n", core_mask);
    // set config
    memset(&config, 0, sizeof(config));
    config.run_core_mask = core_mask;

    // init model
    ret = rknn3_model_init(ctx, &config);
    if (ret != RKNN3_SUCCESS) {
        printf("[rknn3_model_stress_test_error] rknn3_model_init failed! ret=%d\n", ret);
        rknn3_destroy(ctx);
        return -1;
    }

    return ctx;
}

int get_tokenizer_and_embedding(const char *tokenizer_path, VocabInfo *vocab_info, Tokenizer **tokenizer,
                                struct embedding_info *embedding_info, const char *embedding_path, struct stat *emb_st) {
    *tokenizer = new Tokenizer(TOKENIZER_BACKEND_LLAMA, tokenizer_path);
    (*tokenizer)->GetVocabInfo(vocab_info);

    memset(embedding_info, 0x00, sizeof(struct embedding_info));
    embedding_info->fd = open(embedding_path, O_RDONLY);
    if (embedding_info->fd == -1) {
        printf("[rknn3_model_stress_test_error] Failed to open embedding file: %s\n", embedding_path);
        delete *tokenizer;
        *tokenizer = nullptr;
        return -1;
    }

    if (fstat(embedding_info->fd, emb_st) == -1) {
        printf("[rknn3_model_stress_test_error] Failed to get file size\n");
        close(embedding_info->fd);
        delete *tokenizer;
        *tokenizer = nullptr;
        return -1;
    }

    embedding_info->embedding_data = (float16 *)mmap(NULL, emb_st->st_size, PROT_READ, MAP_PRIVATE, embedding_info->fd, 0);
    if (embedding_info->embedding_data == MAP_FAILED) {
        printf("[rknn3_model_stress_test_error] Failed to mmap file\n");
        close(embedding_info->fd);
        delete *tokenizer;
        *tokenizer = nullptr;
        return -1;
    }

    embedding_info->vocab_size = vocab_info->vocab_size;
    embedding_info->embedding_dim = (emb_st->st_size / vocab_info->vocab_size) / sizeof(float16);

    return 0;
}

// Use common print_usage from cmdline_parser
// void print_usage(char *argv[]) { ... }

static void check_perfance(float last_perf, float cur_perf, int32_t last_decode_tokens, int32_t cur_decode_tokens) {
    if (last_perf <= 0) {
        fprintf(stderr, "Error: last_perf must be positive.\n");
        return;
    }

    // check decode_tokens consistency
    if (last_decode_tokens != cur_decode_tokens) {
        fprintf(stderr, "[rknn3_model_stress_test_error] decode_tokens inconsistency! (last=%d, cur=%d)\n",
                last_decode_tokens, cur_decode_tokens);
        exit(EXIT_FAILURE);  // terminate test
    }

    float diff = fabsf(cur_perf - last_perf);
    float ratio = diff / last_perf;  //    test jitter ratio

    if (ratio > 0.5f) {
        fprintf(stderr, "[rknn3_model_stress_test_error] perf jitter %.2f%% exceeds 20%% (last=%.3f, cur=%.3f)\n",
                ratio * 100, last_perf, cur_perf);
        exit(EXIT_FAILURE);  // terminate test
    } else if (ratio > 0.2f) {
        fprintf(stderr, "[rknn3_model_stress_test_warnning] perf jitter %.2f%% exceeds 10%% (last=%.3f, cur=%.3f)\n",
                ratio * 100, last_perf, cur_perf);
    }
}

#define RKNN3_DEFAULT_DEVICE_ID 0
int main(int argc, char **argv) {
    int ret = 0;

    // Parse command line arguments
    cmdline_args_t args;
    ret = parse_cmdline_args(argc, argv, &args);
    if (ret != 0 || args.show_help) {
        print_usage(argv[0], PROGRAM_TYPE_LLM, NULL, 0);
        free_cmdline_args(&args);
        return args.show_help ? 0 : -1;
    }

    // Validate required arguments using common function
    ret = validate_required_params(&args, PROGRAM_TYPE_LLM);
    if (ret != 0) {
        print_usage(argv[0], PROGRAM_TYPE_LLM, NULL, 0);
        free_cmdline_args(&args);
        return -1;
    }

    // Handle time_loop override
    handle_time_loop_override(&args, PROGRAM_TYPE_LLM);

    // Print configuration using common function
    print_configuration(&args, PROGRAM_TYPE_LLM);

    rknn3_devices devs;
    rknn3_context ctx = 0;

    VocabInfo vocab_info;
    Tokenizer *tokenizer = nullptr;
    struct stat emb_st;
    struct embedding_info embedding_info;
    RKLLMCallback callback = { 0 };
    rknn3_llm_param params = { 0 };
    RKLLMRunState state = { 0 };
    rknn3_lora loras_enabled[RKNN3_MAX_LORA_NUM];
    state.loras_enabled = loras_enabled;

    float last_ttft = 0.0f;
    float last_tps = 0.0f;

    int i = 0;
    int llm_n_inputs = 1;
    int64_t tot_memory = 0;
    int prefill_n_tokens = 0;
    float prefill_per_second = 0.f;

    float tpot = 0.f;
    float tps = 0.f;
    float total_time = 0.f;
    float infer_total_time = 0.f;
    float print_interval = 1 * 1000 * 40;  // 40s
    float last_time = 0.0f;
    int32_t last_decode_tokens = 0;
    TIMER cost_time;
    TIMER cur_time;
    float acc_ms = 0.f;
    int acc_cnt = 0;

    int iter = 0;
    float time_limit_ms = (args.time_loop != 0) ? (args.time_loop * 3600.0f * 1000.0f) : -1.0f;

    rknn3_llm_infer_param llm_infer_param = { .keep_history = 0, .max_new_tokens = args.max_new_tokens };
    rknn3_llm_input llm_inputs[llm_n_inputs];
    std::vector<int32_t> tokens(args.n_input_tokens);

    rknn3_llm_tensor input_tensor = { .name = NULL, .prompt = NULL, .embed = NULL, .tokens = tokens.data(), .n_tokens = args.n_input_tokens };
    rknn3_llm_input input;

    printf("*******************************RKNN3_LLM_TEST**********************************\n");

    // 获取目前连接的RK182X信息
    rknn3_devices rknn3_devices;
    memset(&rknn3_devices, 0, sizeof(rknn3_devices));
    ret = rknn3_find_devices(&rknn3_devices);
    if (ret != RKNN3_SUCCESS || rknn3_devices.n_devices <= 0) {
        printf("find devices failed, or data is invalid: %d\n", ret);
        free_cmdline_args(&args);
        return ret;
    }

    uint32_t device_id = args.device_id;
    if (device_id >= rknn3_devices.n_devices) {
        printf("warning!!! device_id = %d is not allow ,use default:%d, %s, %d\n", device_id, RKNN3_DEFAULT_DEVICE_ID, __FUNCTION__, __LINE__);
        device_id = RKNN3_DEFAULT_DEVICE_ID;
    }

    printf("[rknn3_stress_test_log] device[%d].id=%s\n", device_id, rknn3_devices.devices[device_id].id);

    rknn3_init_extend init_extend = { 0 };
    init_extend.device_id = rknn3_devices.devices[device_id].id;
    char device_id_mac[128];
    memcpy(device_id_mac, rknn3_devices.devices[device_id].id, sizeof(rknn3_devices.devices[device_id].id));

    TIMER init_timer;
    init_timer.tik();
    // init context and model
    ctx = init_context_and_model(args.model_path, args.weight_path, args.core_mask, device_id_mac);
    if (ctx < 0) {
        printf("[rknn3_model_stress_test_error] rknn3_session_init_model fail! ctx=%lu\n", ctx);
        free_cmdline_args(&args);
        goto exit;
    }
    init_timer.tok();

    {
        // Query model required core number
        uint32_t model_core_num = 0;
        ret = rknn3_query(ctx, RKNN3_QUERY_CORE_NUMBER, &model_core_num, sizeof(model_core_num));
        if (ret < 0) {
            printf("[rknn3_model_stress_test_error] rknn3_query core number failed! ret=%d\n", ret);
            goto exit;
        }
        rknn3_core_mem_size *core_mem_sizes_llm = (rknn3_core_mem_size *)malloc(sizeof(rknn3_core_mem_size) * model_core_num);

        if (!core_mem_sizes_llm) {
            printf("Failed to allocate memory for core_mem_sizes_llm\n");
            ret = -1;
            goto exit;
        }
        free(core_mem_sizes_llm);

        rknn3_allocation_info *allocation_info = (rknn3_allocation_info *)malloc(sizeof(rknn3_allocation_info) * model_core_num);
        if (!allocation_info) {
            printf("Failed to allocate memory for allocation_info\n");
            ret = -1;
            goto exit;
        }
        ret = rknn3_query(ctx, RKNN3_QUERY_ALLOCATION_INFO, allocation_info, sizeof(rknn3_allocation_info) * model_core_num);
        if (ret < 0) {
            printf("rknn3_query allocation info failed! ret=%d\n", ret);
            free(allocation_info);
            allocation_info = NULL;
            goto exit;
        }
        // printf("allocation_info[i].weight_mem.size: %d\n",allocation_info[0].weight_mem.size);
        for (int i = 0; i < model_core_num; i++) {
            // printf("id:%d,allocation_info.weights_size=%d, allocation_info.internal_size=%d, allocation_info.weights_mem_size=%d, allocation_info.internal_mem_size=%d\n",
            //     i,allocation_info[i].weight_mem.size, allocation_info[i].internal_mem.size,
            //     allocation_info[i].command_mem.size, allocation_info[i].kvcache_mem.size);
            tot_memory += allocation_info[i].weight_mem.size;
            tot_memory += allocation_info[i].internal_mem.size;
            tot_memory += allocation_info[i].command_mem.size;
            tot_memory += allocation_info[i].kvcache_mem.size;
        }
        if (allocation_info) {
            free(allocation_info);
            allocation_info = NULL;
        }
    }
    // printf("----------tot_memory:%ld\n",tot_memory);
    // get_tokenizer_and_embedding
    ret = get_tokenizer_and_embedding(args.tokenizer_path, &vocab_info, &tokenizer, &embedding_info, args.embedding_path, &emb_st);
    if (ret < 0) {
        printf("[rknn3_model_stress_test_error] get_tokenizer_and_embedding fail! ret=%d\n", ret);
        free_cmdline_args(&args);
        goto exit;
    }

    // set session params
    params.logits_name = (char *)"output";
    params.max_context_len = args.max_context_len;
    params.sampling_param.temperature = 1.0f;
    params.sampling_param.top_k = 1;
    params.sampling_param.top_p = 0.9f;
    params.sampling_param.repeat_penalty = 1.0f;
    params.sampling_param.frequency_penalty = 0.0f;
    params.sampling_param.presence_penalty = 0.0f;
    params.vocab_info.vocab_size = vocab_info.vocab_size;
    params.vocab_info.n_special_eos_id = vocab_info.n_special_eos_id;
    params.vocab_info.n_special_bos_id = vocab_info.n_special_bos_id;
    memcpy(params.vocab_info.special_eos_id, vocab_info.special_eos_id, sizeof(vocab_info.special_eos_id));
    memcpy(params.vocab_info.special_bos_id, vocab_info.special_bos_id, sizeof(vocab_info.special_bos_id));
    params.vocab_info.linefeed_id = vocab_info.linefeed_id;
    params.vocab_info.ignore_eos_token = 1;

    // init session
    session = rknn3_session_init(ctx, &params, 1);
    if (!session) {
        printf("[rknn3_model_stress_test_error] Failed to initialize test session, ret=%d\n", ret);
        goto exit;
    }

    // set callback
    callback.result_callback = result_callback;
    callback.result_userdata = tokenizer;
    callback.embed_callback = embed_callback;
    callback.embed_userdata = &embedding_info;
    callback.tokenizer_callback = tokenizer_callback;
    callback.tokenizer_userdata = tokenizer;
    // callback.sampling_callback  = sampling_callback;
    // callback.sampling_userdata  = &embedding_info;

    // set session callback
    ret = rknn3_session_set_callback(session, &callback);
    if (ret != RKNN3_SUCCESS) {
        printf("[rknn3_model_stress_test_error] rknn3_session_set_callback failed, ret=%d\n", ret);
        goto exit;
    }

    // printf("max_context_len %d\n", params.max_context_len);
    // printf("max_new_tokens %d\n", max_new_tokens);

    srand(42);  // Use fixed seed
    for (i = 0; i < args.n_input_tokens; i++) {
        tokens[i] = rand() % 1024;
    }

    input.input_type = RKNN3_LLM_INPUT_TOKEN;
    input.llm_input = input_tensor;
    llm_inputs[0] = input;

    cost_time.tik();

    while (true) {
        // 1. 记录单次推理开始时间 (用于 TTFT 和基础计时)
        // gettimeofday(&start, NULL);

        cur_time.tik();
        first_token.tik();
        first_decode = true;

        ret = rknn3_session_run(session, llm_inputs, llm_n_inputs, &llm_infer_param);
        if (ret != RKNN3_SUCCESS) {
            printf("[rknn3_model_stress_test_error] rknn3_session_run failed, ret=%d\n", ret);
            goto exit;
        }
        ret = rknn3_session_clear_kvcache(session, RKNN3_KVCACHE_CLEAR_ALL);
        if (ret != RKNN3_SUCCESS) {
            printf("[rknn3_model_stress_test_error] rknn3_session_clear_kvcache failed, ret=%d\n", ret);
            goto exit;
        }

        decode_time_ms.tok();
        // 3. 结束计时
        cur_time.tok();
        cost_time.tok();
        // gettimeofday(&end, NULL);

        total_time = cur_time.get_time();         // 当前单次耗时
        infer_total_time = cost_time.get_time();  // 累计运行耗时

        // 查询当前 state 以获取 decode_tokens
        ret = rknn3_session_query_state(session, &state);
        if (ret != RKNN3_SUCCESS) {
            printf("[rknn3_model_stress_test_error] rknn3_session_query_state failed during loop, ret=%d\n", ret);
            goto exit;
        }

        // 4. 性能波动检查
        if (last_time != 0.0f || (args.time_loop != 0 ? infer_total_time > 5000.0f : iter > 10)) {
            check_perfance(last_time, total_time, last_decode_tokens, state.n_decode_tokens);
        }
        last_time = total_time;
        last_decode_tokens = state.n_decode_tokens;

        // 5. 迭代计数更新
        iter++;
        acc_cnt++;
        acc_ms += total_time;

        // if (acc_cnt >= 100) {
        //     printf("[rknn3_model_stress_test_log] run_cnt diff: %d, run cost: %8.2f ms \n", acc_cnt, acc_ms);
        //     acc_cnt = 0;
        //     acc_ms = 0.0f;
        // }
        if (acc_ms >= print_interval) {
            printf("run_cnt : %d, run cost: %8.2f ms \n", iter, infer_total_time);
            acc_cnt = 0;
            acc_ms = 0.0f;
        }

        // 6. 统一退出条件判断
        if (args.time_loop != 0.f) {
            // 时间模式：达到指定小时数退出
            if (infer_total_time >= time_limit_ms) {
                printf("[rknn3_model_stress_test_log] Time limit reached. cost_time: %8.3f h\n", infer_total_time / 1000.f / 60.f / 60.f);
                break;
            }
        } else {
            // 次数模式：达到指定次数退出
            if (iter >= args.cnt_loop) {
                break;
            }
        }
    }

    ret = rknn3_session_query_state(session, &state);
    // if (ret == RKNN3_SUCCESS) {

    // }

    ret = rknn3_session_query_state(session, &state);
    if (ret != RKNN3_SUCCESS) {
        printf("[rknn3_model_stress_test_error] rknn3_session_query_state failed, ret=%d\n", ret);
        goto exit;
    }

exit:
    // Save memory statistics before cleanup

    if (session) {
        rknn3_session_destroy(session);
    }

    if (ctx) {
        rknn3_destroy(ctx);
    }

    if (embedding_info.embedding_data) {
        munmap(embedding_info.embedding_data, emb_st.st_size);
    }

    if (embedding_info.fd != -1) {
        close(embedding_info.fd);
    }

    if (tokenizer) {
        delete tokenizer;
    }

    if (ret == 0) {
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

        float ttft_ms = first_token.get_time();

        prefill_n_tokens = state.n_prefill_tokens;
        prefill_per_second = prefill_n_tokens / (ttft_ms / 1000.0);

        if (state.n_decode_tokens > 0) {
            tpot = decode_time_ms.get_time() / state.n_decode_tokens;
            tps = state.n_decode_tokens / (decode_time_ms.get_time() / 1000.0);
        }

        printf("[rknn3_model_stress_test_done]\n");
        float final_total_time = (first_token.get_time() + decode_time_ms.get_time()) / 1000.0;

        printf("\n===== RKNN3_LLM_TEST Results Summary =====\n\n");
        printf("Model: %s\n", model_name);
        printf("DeviceID: %s\n", device_id_mac);
        printf("LoadModelCost: %.3f ms\n", init_timer.get_time());
        printf("ModelMemory: %ld MB\n", tot_memory / (1024 * 1024));
        printf("TTFT: %.3f ms\n", ttft_ms);
        printf("TPOT: %.3f ms\n", tpot);
        printf("Prefill: %.3f tokens/s\n", prefill_per_second);
        printf("TPS: %.3f tokens/s\n", tps);
        printf("TotalTime: %.3f ms\n", infer_total_time);
        printf("TotalRuns: %d\n", iter);
        printf("\n=================================\n");
        printf("[rknn3_model_stress_test_done]\n");
    }
    fflush(stdout);

    free_cmdline_args(&args);

    return 0;
}
