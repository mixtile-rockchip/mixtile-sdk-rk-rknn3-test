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
#include "float16.h"
#include "rknn3_api.h"
#include "easy_timer.h"
#include "MemoryMonitor.h"

#define LOGW(fmt, ...) printf("\033[33m" fmt "\033[0m", ##__VA_ARGS__)

rknn3_session *session = nullptr;

// struct timeval start, first_token, end;
TIMER first_token, decode_time_ms;

// 内存监控器实例
MemoryMonitor* memory_monitor = nullptr;

// 打印内存统计数据
void print_memory_statistics(const MemoryStatistics& stats) {
    if (!stats.is_valid) {
        printf("[MemoryMonitor] No valid statistics available\n");
        return;
    }

    printf("\n===== Memory Usage Statistics =====\n");
    printf("Total monitoring duration: %.3f seconds\n", stats.total_duration_seconds);
    printf("Total samples collected: %u\n\n", stats.total_samples);

    for (const DeviceMemoryStats& dev : stats.devices) {
        printf("Device[%d] Chip[%d] Statistics:\n", dev.device_id, dev.chip_id);
        printf("  Total Memory: %.2f MB\n", dev.total_memory / 1024.0f / 1024.0f);
        printf("  Memory Usage:\n");
        printf("    Peak:    %.2f MB (%.1f%%)\n",
               dev.peak_used_memory / 1024.0f / 1024.0f, dev.peak_usage_percent);
        printf("    Average: %.2f MB (%.1f%%)\n",
               dev.avg_used_memory / 1024.0f / 1024.0f, dev.avg_usage_percent);
        printf("    Min:     %.2f MB (%.1f%%)\n",
               dev.min_used_memory / 1024.0f / 1024.0f, dev.min_usage_percent);
        printf("  Free Memory:\n");
        printf("    Min:     %.2f MB\n", dev.min_free_memory / 1024.0f / 1024.0f);
        printf("    Average: %.2f MB\n", dev.avg_free_memory / 1024.0f / 1024.0f);
        printf("    Max:     %.2f MB\n", dev.max_free_memory / 1024.0f / 1024.0f);
        printf("  DDR Frequency:\n");
        printf("    Max: %u MHz, Avg: %u MHz, Min: %u MHz\n",
               dev.max_ddr_freq, dev.avg_ddr_freq, dev.min_ddr_freq);
        printf("  Sample count: %u (%.3f seconds)\n\n",
               dev.sample_count, dev.duration_seconds);
    }
    printf("===================================\n\n");
}
// struct timeval decode, decode_tmp;

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
        extend.device_id = (char*)device_id;
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

void print_usage(char *argv[]) {
    printf("Usage:\n");
    printf("%s [options]\n\n", argv[0]);
    printf("Options:\n");
    printf("  -m, --model_path      \n");
    printf("  -w, --model_weight     \n");
    printf("  -tk, --tokenizer      \n");
    printf("  -em, --embedding      \n");
    printf("  -c, --core_mask   \n");
    printf("  -ctx,--max_context_len \n");
    printf("  -ni,--n_input_tokens \n");
    printf("  -no,--max_new_tokens \n");
    printf("  -cl, --cnt_loop  default:1 \n");
    printf("  -tl, --time_loop(hours) \n");
    printf("  -d, --device_id       specify device ID\n");
    printf("\nUse '%s --help' to display this message.\n", argv[0]);

    return;
}

static void check_perfance(float last_perf, float cur_perf, int32_t last_decode_tokens, int32_t cur_decode_tokens) {
    if (last_perf <= 0) {
        fprintf(stderr, "Error: last_perf must be positive.\n");
        return;
    }

    // 检测 decode_tokens 是否一致
    if (last_decode_tokens != cur_decode_tokens) {
        fprintf(stderr, "[rknn3_model_stress_test_error] decode_tokens inconsistency! (last=%d, cur=%d)\n",
                last_decode_tokens, cur_decode_tokens);
        exit(EXIT_FAILURE);  // 异常退出
    }

    float diff = fabsf(cur_perf - last_perf);
    float ratio = diff / last_perf;  // 抖动比例

    if (ratio > 0.5f) {
        fprintf(stderr, "[rknn3_model_stress_test_error] perf jitter %.2f%% exceeds 20%% (last=%.3f, cur=%.3f)\n",
                ratio * 100, last_perf, cur_perf);
        exit(EXIT_FAILURE);  // 异常退出
    } else if (ratio > 0.2f) {
        fprintf(stderr, "[rknn3_model_stress_test_warnning] perf jitter %.2f%% exceeds 10%% (last=%.3f, cur=%.3f)\n",
                ratio * 100, last_perf, cur_perf);
    }
}

#define RKNN3_DEFAULT_DEVICE_ID 0
int main(int argc, char **argv) {
    int ret = 0;
    char *model_path = NULL;
    char *weight_path =  NULL;
    const char *tokenizer_path =  NULL;
    const char *embedding_path =  NULL;
    // const char *device_id = NULL;
    int32_t max_context_len = 0;
    uint64_t n_input_tokens = 128;
    int32_t max_new_tokens = 128;
    uint32_t core_mask = 0xff;
    uint32_t cnt_loop = 1;
    float time_loop = 0.f;
    uint32_t device_id = 0;

     for (int i = 1; i < argc; i += 2) {
        if (strcmp(argv[i], "-m") == 0 || strcmp(argv[i], "--model_path") == 0) {
            model_path = argv[i + 1];
        } else if (strcmp(argv[i], "-w") == 0 || strcmp(argv[i], "--model_weight") == 0) {
            weight_path = argv[i + 1];
        } else if (strcmp(argv[i], "-tk") == 0 || strcmp(argv[i], "--tokenizer") == 0) {
            tokenizer_path = argv[i + 1];
        } else if (strcmp(argv[i], "-em") == 0 || strcmp(argv[i], "--embedding") == 0) {
            embedding_path = argv[i + 1];
        } else if (strcmp(argv[i], "-c") == 0 || strcmp(argv[i], "--core_mask") == 0) {
            core_mask = strtoul(argv[i + 1],nullptr, 16);
        } else if (strcmp(argv[i], "-cl") == 0 || strcmp(argv[i], "--cnt_loop") == 0) {
            cnt_loop = atoi(argv[i + 1]);
        } else if(strcmp(argv[i], "-tl") == 0 || strcmp(argv[i], "--time_loop") == 0) {
            time_loop = atof(argv[i + 1]);
        }else if(strcmp(argv[i], "-ctx") == 0 || strcmp(argv[i], "--max_context_len") == 0) {
            max_context_len = atoi(argv[i + 1]);
        } else if(strcmp(argv[i], "-ni") == 0 || strcmp(argv[i], "--n_input_tokens") == 0) {
            n_input_tokens = atoi(argv[i+1]);
        }else if (strcmp(argv[i], "-no") == 0 || strcmp(argv[i], "--max_new_tokens") == 0){
            max_new_tokens = atoi(argv[i+1]);
        } else if (strcmp(argv[i], "-id") == 0 || strcmp(argv[i], "--device_id") == 0){
            device_id = atoi(argv[i+1]);  // 指定设备ID
        } else if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0) {
            print_usage(argv);
            return 0;
        }else {
            printf("[rknn3_model_stress_test_error] Unknown option: %s\n", argv[i]);
            return -1;
        }
    }

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

    // float ttft_us = 0.0f;
    int prefill_n_tokens = 0;
    float prefill_per_second = 0.f;

    // Save memory statistics before monitor is deleted
    MemoryStatistics saved_mem_stats;
    // float decode_time_us = 0.f;
    float tpot = 0.f;
    float tps = 0.f;
    float total_time = 0.f;
    float infer_total_time = 0.f;

    float last_time = 0.0f;
    int32_t last_decode_tokens = 0;
    TIMER cost_time;    // 记录累计运行总时间
    TIMER cur_time;     // 记录当前单次推理时间
    float print_log_ms = 1.f *1000.f*60.f; // 1min print
    float acc_ms = 0.f;
    int acc_cnt = 0;

    int iter = 0;
    float time_limit_ms = (time_loop != 0) ? (time_loop * 3600.0f * 1000.0f) : -1.0f;

    rknn3_llm_infer_param llm_infer_param = { .keep_history = 0, .max_new_tokens = max_new_tokens };
    rknn3_llm_input llm_inputs[llm_n_inputs];
    // Generate fixed tokens for performance testing
    std::vector<int32_t> tokens(n_input_tokens);

    rknn3_llm_tensor input_tensor = { .name = NULL, .prompt = NULL, .embed = NULL, .tokens = tokens.data(), .n_tokens = n_input_tokens };
    rknn3_llm_input input;


    printf("*******************************RKNN3_LLM_TEST**********************************\n");

    // uint32_t device_id = vision_ctx->device_id;
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

    printf("[rknn3_stress_test_log] device[%d].id=%s\n", device_id, rknn3_devices.devices[device_id].id);

    // 初始化内存监控器（提前到模型加载前，便于诊断内存问题）
    memory_monitor = new MemoryMonitor(100000); // 100ms监控间隔

    // 设置目标设备（只监控推理使用的设备）
    std::vector<uint16_t> target_devices = {(uint16_t)device_id};
    memory_monitor->set_target_devices(target_devices);

    if (!memory_monitor->initialize()) {
        printf("[rknn3_model_stress_test_warning] Memory monitor initialization failed, memory monitoring will be disabled\n");
        delete memory_monitor;
        memory_monitor = nullptr;
    } else {
        memory_monitor->set_realtime_print(false);
        printf("[rknn3_model_stress_test] Memory monitor initialized successfully with 100ms interval\n");
    }

    rknn3_init_extend init_extend = {0};
    init_extend.device_id = rknn3_devices.devices[device_id].id;
    char device_id_mac[128];
    memcpy(device_id_mac,rknn3_devices.devices[device_id].id,sizeof(rknn3_devices.devices[device_id].id));
    // init context and model
    ctx = init_context_and_model(model_path, weight_path, core_mask, device_id_mac);
    if (ctx < 0) {
        printf("[rknn3_model_stress_test_error] rknn3_session_init_model fail! ctx=%lu\n", ctx);
        goto exit;
    }

    // get_tokenizer_and_embedding
    ret = get_tokenizer_and_embedding(tokenizer_path, &vocab_info, &tokenizer, &embedding_info, embedding_path, &emb_st);
    if (ret < 0) {
        printf("[rknn3_model_stress_test_error] get_tokenizer_and_embedding fail! ret=%d\n", ret);
        goto exit;
    }

    // set session params
    params.logits_name = (char *)"output";
    params.max_context_len = max_context_len;
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
    for (i = 0; i < n_input_tokens; i++) {
        tokens[i] = rand() % 1024;
    }

    input.input_type = RKNN3_LLM_INPUT_TOKEN;
    input.llm_input = input_tensor;
    llm_inputs[0] = input;

    cost_time.tik();

    if (memory_monitor) {
        memory_monitor->start_monitoring();
    }

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

        total_time = cur_time.get_time(); // 当前单次耗时
        infer_total_time = cost_time.get_time(); // 累计运行耗时

        // 查询当前 state 以获取 decode_tokens
        ret = rknn3_session_query_state(session, &state);
        if (ret != RKNN3_SUCCESS) {
            printf("[rknn3_model_stress_test_error] rknn3_session_query_state failed during loop, ret=%d\n", ret);
            goto exit;
        }

        // 4. 性能波动检查
        if (last_time != 0.0f || (time_loop != 0 ? infer_total_time > 5000.0f : iter > 10)) {
            check_perfance(last_time, total_time, last_decode_tokens, state.n_decode_tokens);
        }
        last_time = total_time;
        last_decode_tokens = state.n_decode_tokens;

        // 5. 迭代计数更新
        iter++;
        acc_cnt ++;
        acc_ms += total_time;

        if(acc_cnt >= 100) {
            printf("run_cnt diff: %d, run cost: %8.2f ms \n",acc_cnt,acc_ms);
            acc_cnt = 0;
            acc_ms = 0.0f;
        }

        // 6. 统一退出条件判断
        if (time_loop != 0.f) {
            // 时间模式：达到指定小时数退出
            if (infer_total_time >= time_limit_ms) {
                infer_total_time = infer_total_time;
                printf("Time limit reached. cost_time: %8.3f h\n", infer_total_time/1000.f/60.f/60.f);
                break;
            }
        } else {
            // 次数模式：达到指定次数退出
            // printf("run cnt: %d / %d \n",iter,cnt_loop);
            if (iter >= cnt_loop) {
                break;
            }
        }
    }

    // Stop memory monitoring and get statistics (value copy)
    if (memory_monitor) {
        memory_monitor->stop_monitoring();
        saved_mem_stats = memory_monitor->get_statistics();

        // Cleanup memory monitor now (this will print library logs)
        delete memory_monitor;
        memory_monitor = nullptr;
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

    if(ret == 0) {
        const char *last_slash = strrchr(model_path, '/');
        const char *filename;

        if (last_slash != NULL) {
            filename = last_slash + 1;
        } else {
            filename = model_path;
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

        // TTFT 计算
        // ttft_us = (first_token.tv_sec - start.tv_sec) * 1000000 + (first_token.tv_usec - start.tv_usec);
        float ttft_ms = first_token.get_time();
        // first_token.print_time("TTFT: ");
        // printf("\nTTFT: %.3f s (%.3f ms)\n", ttft_us / 1000000.0, ttft_us / 1000.0);

        // Prefill 计算
        prefill_n_tokens = state.n_prefill_tokens;
        prefill_per_second = prefill_n_tokens / (ttft_ms / 1000.0);

        // TPOT 计算
        // decode_time_us = ((end.tv_sec - first_token.tv_sec) * 1000000) + (end.tv_usec - first_token.tv_usec);
        if (state.n_decode_tokens > 0) {
            tpot = decode_time_ms.get_time() / state.n_decode_tokens;
            tps = state.n_decode_tokens / (decode_time_ms.get_time() / 1000.0);

        }
        printf("[rknn3_model_stress_test_done]\n");
        // Total time
        float final_total_time = (first_token.get_time() + decode_time_ms.get_time()) / 1000.0;

        printf("\n===== RKNN3_LLM_TEST Results Summary =====\n\n");
        printf("Model: %s\n",model_name);
        printf("DeviceID: %s\n",device_id_mac);
        printf("TTFT: %.3f ms\n", ttft_ms);
        printf("TPOT: %.3f ms\n", tpot);
        printf("Prefill: %.3f tokens/s\n", prefill_per_second);
        printf("TPS: %.3f tokens/s\n", tps);
        printf("TotalTime: %.3f ms\n",infer_total_time);
        printf("TotalRuns: %d\n",iter);

        // Print memory usage statistics (use saved data from exit section)
        bool has_valid_data = saved_mem_stats.is_valid && !saved_mem_stats.devices.empty();
        if (has_valid_data) {
            const DeviceMemoryStats& dev = saved_mem_stats.devices[0];
            printf("AvgMemoryUsage: %.2f MB (%.1f%%)\n",
                   dev.avg_used_memory / 1024.0f / 1024.0f, dev.avg_usage_percent);
            printf("AvgNpuUtilization: %u%%\n", dev.avg_npu_util);
        } else {
            printf("AvgMemoryUsage: unavailable\n");
            printf("AvgNpuUtilization: unavailable\n");
        }

        printf("\n=================================\n");
        printf("[rknn3_model_stress_test_done]\n");
    }
    fflush(stdout);


    return 0;
}
