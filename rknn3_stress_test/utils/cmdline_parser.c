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

/**
 * @file cmdline_parser.c
 * @brief Common command line argument parser implementation
 */

#include "cmdline_parser.h"

#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <unistd.h>

#define MAX_CUSTOM_PARAMS 32

// Custom parameter storage
static param_def_t g_custom_params[MAX_CUSTOM_PARAMS];
static int g_n_custom_params = 0;

// Static default values
static const uint32_t DEFAULT_CORE_MASK = 0;
static const uint32_t DEFAULT_CNT_LOOP = 1;
static const float DEFAULT_TIME_LOOP = 0.0f;
static const uint32_t DEFAULT_DEVICE_ID = 0;
static const uint32_t DEFAULT_VISION_CORE_MASK = 0;
static const uint32_t DEFAULT_LLM_CORE_MASK = 0;
static const uint32_t DEFAULT_VISION_LOOP = 1;
static const uint32_t DEFAULT_LLM_LOOP = 1;
static const uint32_t DEFAULT_N_INPUT_TOKENS = 128;
static const int32_t DEFAULT_MAX_NEW_TOKENS = 128;

void init_cmdline_args(cmdline_args_t *args) {
    memset(args, 0, sizeof(cmdline_args_t));

    // Set default values
    args->core_mask = DEFAULT_CORE_MASK;
    args->cnt_loop = DEFAULT_CNT_LOOP;
    args->time_loop = DEFAULT_TIME_LOOP;
    args->device_id = DEFAULT_DEVICE_ID;
    args->show_help = false;
    args->yuv_input = false;

    args->max_context_len = 1024;
    args->n_input_tokens = DEFAULT_N_INPUT_TOKENS;
    args->max_new_tokens = DEFAULT_MAX_NEW_TOKENS;
    args->vision_core_mask = DEFAULT_VISION_CORE_MASK;
    args->llm_core_mask = DEFAULT_LLM_CORE_MASK;
    args->vision_loop = DEFAULT_VISION_LOOP;
    args->llm_loop = DEFAULT_LLM_LOOP;
    args->model_folder = NULL;
    args->similarity_threshold = 0.99f;
}

void free_cmdline_args(cmdline_args_t *args) {
    if (!args) return;

#define FREE_IF_SET(ptr) \
    if (ptr) {           \
        free(ptr);       \
        ptr = NULL;      \
    }

    FREE_IF_SET(args->model_path);
    FREE_IF_SET(args->weight_path);
    FREE_IF_SET(args->image_path);
    FREE_IF_SET(args->tokenizer_path);
    FREE_IF_SET(args->embedding_path);
    FREE_IF_SET(args->vision_model_path);
    FREE_IF_SET(args->vision_weight_path);
    FREE_IF_SET(args->llm_model_path);
    FREE_IF_SET(args->llm_weight_path);
    FREE_IF_SET(args->prompt_ini_path);
    FREE_IF_SET(args->model_folder);
    FREE_IF_SET(args->golden_path);
    FREE_IF_SET(args->user_params);
}

int register_custom_params(const param_def_t *params, int n_params, cmdline_args_t *args) {
    if (!params || n_params <= 0 || !args) {
        printf("[rknn3_model_stress_test_error] Invalid arguments for register_custom_params\n");
        return -1;
    }

    if (g_n_custom_params + n_params > MAX_CUSTOM_PARAMS) {
        printf("[rknn3_model_stress_test_error] Too many custom parameters (max %d)\n", MAX_CUSTOM_PARAMS);
        return -1;
    }

    for (int i = 0; i < n_params; i++) {
        if (g_n_custom_params >= MAX_CUSTOM_PARAMS) {
            break;
        }
        g_custom_params[g_n_custom_params++] = params[i];
    }

    return 0;
}

void print_usage(const char *argv0, int program_type, const param_def_t *custom_params, int n_custom_params) {
    const char *program_name = "rknn3_test";

    if (argv0) {
        // Extract program name from path
        const char *last_slash = strrchr(argv0, '/');
        if (!last_slash) last_slash = strrchr(argv0, '\\');
        program_name = last_slash ? last_slash + 1 : argv0;
    }

    printf("Usage:\n");
    printf("%s [options]\n\n", program_name);
    printf("Options:\n");

    // Common parameters
    printf("Common Parameters:\n");
    printf("  -f, --model_folder           Model folder path\n");
    printf("  -cl, --cnt_loop              Loop count (default: 1)\n");
    printf("  -tl, --time_loop             Time loop in hours (overrides cnt_loop)\n");
    printf("  -id, --device_id             Device ID (default: 0)\n");
    printf("  -h, --help                   Show this help message\n");

    // CNN/Vision specific
    if (program_type == PROGRAM_TYPE_CNN) {
        printf("\nCNN/Vision Specific Parameters:\n");
        printf("  -m, --model_path             Model path (.rknn)\n");
        printf("  -w, --weight_path            Weight path (.weight)\n");
        printf("  -c, --core_mask              Core mask (hex, e.g. 0x1,auto-generated when not specified)\n");
        printf("  -i, --image_path            Image path\n");
        printf("  --yuv                       Input image is YUV420SP NV12\n");
    }

    // LLM specific
    if (program_type == PROGRAM_TYPE_LLM) {
        printf("\nLLM Specific Parameters:\n");
        printf("  -m, --model_path             Model path (.rknn)\n");
        printf("  -w, --weight_path            Weight path (.weight)\n");
        printf("  -c, --core_mask              Core mask (hex, e.g. 0x1,auto-generated when not specified)\n");
        printf("  -tk, --tokenizer             Tokenizer file path\n");
        printf("  -em, --embedding             Embedding file path\n");
        printf("  -ctx, --max_context_len      Max context length\n");
        printf("  -ni, --n_input_tokens        Number of input tokens (default: 128)\n");
        printf("  -no, --max_new_tokens        Max new tokens (default: 128)\n");
        printf("  -gp, --golden_path           Golden data directory for accuracy test\n");
        printf("  -st, --similarity_threshold  Cosine similarity threshold (default: 0.99)\n");
    }

    // VLM specific
    if (program_type == PROGRAM_TYPE_VLM) {
        printf("\nVLM/ASR Specific Parameters:\n");
        printf("  -vm, --vision_model          Vision model path (ASR mode: audio encoder model)\n");
        printf("  -vw, --vision_weight         Vision weight path (ASR mode: audio encoder weight)\n");
        printf("  -lm, --llm_model             LLM model path\n");
        printf("  -lw, --llm_weight            LLM weight path\n");
        printf("  -tk, --tokenizer             Tokenizer file path\n");
        printf("  -em, --embedding             Embedding file path\n");
        printf("  -vc, --vision_core_mask      Vision core mask (ASR mode: audio encoder core mask)\n");
        printf("  -lc, --llm_core_mask         LLM core mask\n");
        printf("  -im, --image_path            Image path (VLM mode)\n");
        printf("  -a,  --audio_path            Audio file path (ASR mode, triggers ASR mode)\n");
        printf("  -pi, --prompt_ini            Prompt INI file path\n");
        printf("  -vl, --vision_loop           Vision loop count (default: 1)\n");
        printf("  -ll, --llm_loop              LLM loop count (default: 1)\n");
    }
    // Audio specific parameters
    if (program_type == PROGRAM_TYPE_AUDIO) {
        printf("\nAudio Encoder Specific Parameters:\n");
        printf("  -m, --model_path             Model path (.rknn)\n");
        printf("  -w, --weight_path            Weight path (.weight)\n");
        printf("  -c, --core_mask              Core mask (hex, e.g. 0x1,auto-generated when not specified)\n");
        printf("  -a, --audio_path             Audio file path (.wav)\n");  // Reuse audio_path field for audio
    }
    // Custom parameters
    if (custom_params && n_custom_params > 0) {
        printf("\nCustom Parameters:\n");
        for (int i = 0; i < n_custom_params; i++) {
            const param_def_t *p = &custom_params[i];
            if (p->short_name && p->long_name) {
                printf("  -%s, --%-20s  %s\n", p->short_name, p->long_name, p->description);
            } else if (p->short_name) {
                printf("  -%s                        %s\n", p->short_name, p->description);
            } else if (p->long_name) {
                printf("  --%-20s  %s\n", p->long_name, p->description);
            }
        }
    }

    printf("\nExamples:\n");
    if (program_type == PROGRAM_TYPE_CNN) {
        printf("  %s -f model_folder -c 0x01 -cl 100\n", program_name);
        printf("  %s -m model.rknn -w model.weight -c 0x1 -i image.jpg -cl 100\n", program_name);
    } else if (program_type == PROGRAM_TYPE_LLM) {
        printf("  %s -f model_folder -c 0xff -cl 10\n", program_name);
        printf("  %s -m model.rknn -w model.weight -tk tokenizer.spm -em embedding.bin -c 0xff -cl 10\n", program_name);
    } else if (program_type == PROGRAM_TYPE_VLM) {
        printf("   %s -f model_folder -vc 0xff -lc 0xff -vl 10 -ll 10\n", program_name);
        printf("  %s -vm vision.rknn -vw vision.weight -lm llm.rknn -lw llm.weight \\\n", program_name);
        printf("        -tk tokenizer.spm -em embedding.bin -vc 0x3 -lc 0xfc -i image.jpg\n");
    }
}

// Helper function to check if string matches parameter name
static bool param_matches(const char *arg, const char *short_name, const char *long_name) {
    if (!arg || !short_name) return false;

    // Check short name (e.g., "-m")
    if (short_name && strlen(arg) >= 2 && arg[0] == '-' && arg[1] != '-') {
        if (strcmp(arg, short_name) == 0) {
            return true;
        }
    }

    // Check long name (e.g., "--model_path")
    if (long_name && strlen(arg) >= 3 && arg[0] == '-' && arg[1] == '-') {
        if (strcmp(arg, long_name) == 0) {
            return true;
        }
    }

    return false;
}

// Helper to parse hex value
static uint32_t parse_hex(const char *str) {
    return (uint32_t)strtoul(str, NULL, 16);
}

int parse_cmdline_args(int argc, char **argv, cmdline_args_t *args) {
    if (!args) {
        printf("[cmdline_parser_error] args is NULL\n");
        return -1;
    }

    init_cmdline_args(args);

    for (int i = 1; i < argc;) {
        const char *arg = argv[i];

        // Help
        if (param_matches(arg, "-h", "--help")) {
            args->show_help = true;
            i += 1;
            continue;
        }

        // YUV input flag (no value)
        if (strcmp(arg, "--yuv") == 0) {
            args->yuv_input = true;
            i += 1;
            continue;
        }

        // Parameters with values
        if (i + 1 >= argc) {
            printf("[cmdline_parser_error] Missing value for parameter: %s\n", arg);
            return -1;
        }

        const char *value = argv[i + 1];

        // Common parameters
        if (param_matches(arg, "-f", "--model_folder")) {
            args->model_folder = strdup(value);
            i += 2;
        } else if (param_matches(arg, "-c", "--core_mask")) {
            args->core_mask = parse_hex(value);
            i += 2;
        } else if (param_matches(arg, "-cl", "--cnt_loop")) {
            args->cnt_loop = (uint32_t)atoi(value);
            i += 2;
        } else if (param_matches(arg, "-tl", "--time_loop")) {
            args->time_loop = (float)atof(value);
            i += 2;
        } else if (param_matches(arg, "-id", "--device_id")) {
            args->device_id = (uint32_t)atoi(value);
            i += 2;
        }
        // CNN/Vision specific
        else if (param_matches(arg, "-m", "--model_path")) {
            args->model_path = strdup(value);
            i += 2;
        } else if (param_matches(arg, "-w", "--weight_path")) {
            args->weight_path = strdup(value);
            i += 2;
        } else if (param_matches(arg, "-i", "--image_path")) {
            args->image_path = strdup(value);
            i += 2;
        }
        // LLM specific
        else if (param_matches(arg, "-tk", "--tokenizer")) {
            args->tokenizer_path = strdup(value);
            i += 2;
        } else if (param_matches(arg, "-em", "--embedding")) {
            args->embedding_path = strdup(value);
            i += 2;
        } else if (param_matches(arg, "-ctx", "--max_context_len")) {
            args->max_context_len = atoi(value);
            i += 2;
        } else if (param_matches(arg, "-ni", "--n_input_tokens")) {
            args->n_input_tokens = (uint32_t)atoi(value);
            i += 2;
        } else if (param_matches(arg, "-no", "--max_new_tokens")) {
            args->max_new_tokens = atoi(value);
            i += 2;
        } else if (param_matches(arg, "-gp", "--golden_path")) {
            args->golden_path = strdup(value);
            i += 2;
        } else if (param_matches(arg, "-st", "--similarity_threshold")) {
            args->similarity_threshold = (float)atof(value);
            i += 2;
        }
        // VLM specific
        else if (param_matches(arg, "-vm", "--vision_model")) {
            args->vision_model_path = strdup(value);
            i += 2;
        } else if (param_matches(arg, "-vw", "--vision_weight")) {
            args->vision_weight_path = strdup(value);
            i += 2;
        } else if (param_matches(arg, "-lm", "--llm_model")) {
            args->llm_model_path = strdup(value);
            i += 2;
        } else if (param_matches(arg, "-lw", "--llm_weight")) {
            args->llm_weight_path = strdup(value);
            i += 2;
        } else if (param_matches(arg, "-vc", "--vision_core_mask")) {
            args->vision_core_mask = parse_hex(value);
            i += 2;
        } else if (param_matches(arg, "-lc", "--llm_core_mask")) {
            args->llm_core_mask = parse_hex(value);
            i += 2;
        } else if (param_matches(arg, "-vl", "--vision_loop")) {
            args->vision_loop = (uint32_t)atoi(value);
            i += 2;
        } else if (param_matches(arg, "-ll", "--llm_loop")) {
            args->llm_loop = (uint32_t)atoi(value);
            i += 2;
        } else if (param_matches(arg, "-im", "--image_path")) {
            args->image_path = strdup(value);
            i += 2;
        } else if (param_matches(arg, "-pi", "--prompt_ini")) {
            args->prompt_ini_path = strdup(value);
            i += 2;
        }
        // Audio specific
        else if (param_matches(arg, "-a", "--audio_path")) {
            args->audio_path = strdup(value);
            i += 2;
        }
        // Check custom parameters
        else {
            bool matched = false;
            for (int j = 0; j < g_n_custom_params; j++) {
                if (param_matches(arg, g_custom_params[j].short_name, g_custom_params[j].long_name)) {
                    // Store in user_params area (simplified - can be extended)
                    matched = true;
                    i += 2;
                    break;
                }
            }
            if (!matched) {
                printf("[cmdline_parser_error] Unknown option: %s\n", arg);
                printf("Use '%s --help' for usage information.\n", argv[0]);
                return -1;
            }
        }
    }

    return 0;
}

static void populate_args_from_folder(cmdline_args_t *args, program_type_t program_type) {
    if (!args || !args->model_folder) return;

    DIR *dir = opendir(args->model_folder);
    if (!dir) {
        printf("[rknn3_model_stress_test_warnning] Could not open model_folder: %s\n", args->model_folder);
        return;
    }

    struct dirent *ent;
    while ((ent = readdir(dir)) != NULL) {
        if (strcmp(ent->d_name, ".") == 0 || strcmp(ent->d_name, "..") == 0) continue;

        char full_path[1024];
        snprintf(full_path, sizeof(full_path), "%s/%s", args->model_folder, ent->d_name);

#define SET_IF_NULL(target, val) \
    if (!target) target = strdup(val)

        if (program_type == PROGRAM_TYPE_CNN) {
            if (strstr(ent->d_name, ".rknn")) {
                SET_IF_NULL(args->model_path, full_path);
            } else if (strstr(ent->d_name, ".weight")) {
                SET_IF_NULL(args->weight_path, full_path);
            }
        } else if (program_type == PROGRAM_TYPE_LLM) {
            if (strstr(ent->d_name, ".rknn")) {
                SET_IF_NULL(args->model_path, full_path);
            } else if (strstr(ent->d_name, ".weight")) {
                SET_IF_NULL(args->weight_path, full_path);
            } else if (strstr(ent->d_name, ".tokenizer.gguf")) {
                SET_IF_NULL(args->tokenizer_path, full_path);
            } else if (strstr(ent->d_name, ".embed.bin")) {
                SET_IF_NULL(args->embedding_path, full_path);
            }
        } else if (program_type == PROGRAM_TYPE_VLM) {
            if (strstr(ent->d_name, ".rknn")) {
                if (strstr(ent->d_name, "vision") || strstr(ent->d_name, "encoder")) {
                    SET_IF_NULL(args->vision_model_path, full_path);
                } else {
                    // Fallback: any other .rknn file is treated as LLM model
                    SET_IF_NULL(args->llm_model_path, full_path);
                }
            } else if (strstr(ent->d_name, ".weight")) {
                if (strstr(ent->d_name, "vision") || strstr(ent->d_name, "encoder")) {
                    SET_IF_NULL(args->vision_weight_path, full_path);
                } else {
                    // Fallback: any other .weight file is treated as LLM weight
                    SET_IF_NULL(args->llm_weight_path, full_path);
                }
            } else if (strstr(ent->d_name, "tokenizer")) {
                SET_IF_NULL(args->tokenizer_path, full_path);
            } else if (strstr(ent->d_name, "embed")) {
                SET_IF_NULL(args->embedding_path, full_path);
            } else if (strstr(ent->d_name, ".ini")) {
                SET_IF_NULL(args->prompt_ini_path, full_path);
            }
        } else if (program_type == PROGRAM_TYPE_AUDIO) {
            if (strstr(ent->d_name, ".rknn")) {
                SET_IF_NULL(args->model_path, full_path);
            } else if (strstr(ent->d_name, ".weight")) {
                SET_IF_NULL(args->weight_path, full_path);
            }
        }
#undef SET_IF_NULL
    }
    closedir(dir);
}

int populate_args_from_model_folder(cmdline_args_t *args, program_type_t program_type) {
    if (!args) {
        printf("[rknn3_model_stress_test_error] args is NULL\n");
        return -1;
    }

    populate_args_from_folder(args, program_type);
    return 0;
}

int validate_required_params(cmdline_args_t *args, program_type_t program_type) {
    if (!args) {
        printf("[rknn3_model_stress_test_error] args is NULL\n");
        return -1;
    }

    if (args->model_folder) {
        populate_args_from_folder(args, program_type);
    }

    switch (program_type) {
        case PROGRAM_TYPE_CNN:
            if (!args->model_folder && (!args->model_path || !args->weight_path)) {
                printf("[rknn3_model_stress_test_error] Missing required arguments: model_path or weight_path\n");
                return -1;
            }
            break;

        case PROGRAM_TYPE_LLM:
            if (!args->model_folder && (!args->model_path || !args->weight_path || !args->tokenizer_path || !args->embedding_path)) {
                printf("[rknn3_model_stress_test_error] Missing required arguments\n");
                return -1;
            }
            break;

        case PROGRAM_TYPE_VLM:
            if (!args->model_folder && (!args->vision_model_path || !args->vision_weight_path || !args->llm_model_path ||
                                        !args->llm_weight_path || !args->tokenizer_path || !args->embedding_path)) {
                printf("[rknn3_model_stress_test_error] Missing required arguments\n");
                return -1;
            }
            break;

        case PROGRAM_TYPE_AUDIO:
            if (!args->model_folder && (!args->model_path || !args->weight_path)) {
                printf("[rknn3_model_stress_test_error] Missing required arguments: model_path or weight_path\n");
                return -1;
            }
            if (!args->audio_path) {  // Using audio_path field for audio path
                printf("[rknn3_model_stress_test_error] Missing required argument: audio_path\n");
                return -1;
            }
            if (args->core_mask == 0) {
                printf("[rknn3_model_stress_test_error] Invalid core_mask (must not be 0)\n");
                return -1;
            }
            break;

        default:
            printf("[rknn3_model_stress_test_error] Unknown program type: %d\n", program_type);
            return -1;
    }

    return 0;
}

void print_configuration(const cmdline_args_t *args, program_type_t program_type) {
    if (!args) return;

    switch (program_type) {
        case PROGRAM_TYPE_CNN:
            printf("===== RKNN3_CNN_TEST Configuration =====\n");
            printf("model_folder: %s\n", args->model_folder ? args->model_folder : "null");
            printf("model_path: %s\n", args->model_path ? args->model_path : "null");
            printf("weight_path: %s\n", args->weight_path ? args->weight_path : "null");
            printf("core_mask: 0x%x\n", args->core_mask);
            printf("image_path: %s\n", args->image_path ? args->image_path : "null");
            printf("image_format: %s\n", args->yuv_input ? "YUV420SP_NV12" : "RGB888");
            printf("cnt_loop: %u\n", args->cnt_loop);
            printf("time_loop: %.2f hours\n", args->time_loop);
            printf("device_id: %u\n", args->device_id);
            printf("======================================\n\n");
            break;

        case PROGRAM_TYPE_LLM:
            printf("\n===== RKNN3_LLM_TEST Configuration =====\n");
            printf("model_path: %s\n", args->model_path ? args->model_path : "null");
            printf("weight_path: %s\n", args->weight_path ? args->weight_path : "null");
            printf("tokenizer: %s\n", args->tokenizer_path ? args->tokenizer_path : "null");
            printf("embedding: %s\n", args->embedding_path ? args->embedding_path : "null");
            printf("core_mask: 0x%x\n", args->core_mask);
            printf("max_context_len: %d\n", args->max_context_len);
            printf("n_input_tokens: %u\n", args->n_input_tokens);
            printf("max_new_tokens: %d\n", args->max_new_tokens);
            printf("cnt_loop: %u\n", args->cnt_loop);
            printf("time_loop: %.2f hours\n", args->time_loop);
            printf("device_id: %u\n", args->device_id);
            printf("=======================================\n\n");
            break;

        case PROGRAM_TYPE_VLM:
            printf("\n===== RKNN3_VLM_TEST Configuration =====\n");
            printf("vision_model: %s\n", args->vision_model_path ? args->vision_model_path : "null");
            printf("vision_weight: %s\n", args->vision_weight_path ? args->vision_weight_path : "null");
            printf("llm_model: %s\n", args->llm_model_path ? args->llm_model_path : "null");
            printf("llm_weight: %s\n", args->llm_weight_path ? args->llm_weight_path : "null");
            printf("tokenizer: %s\n", args->tokenizer_path ? args->tokenizer_path : "null");
            printf("embedding: %s\n", args->embedding_path ? args->embedding_path : "null");
            printf("vision_core_mask: 0x%x\n", args->vision_core_mask);
            printf("llm_core_mask: 0x%x\n", args->llm_core_mask);
            printf("image_path: %s\n", args->image_path ? args->image_path : "null");
            printf("prompt.ini: %s\n", args->prompt_ini_path ? args->prompt_ini_path : "null");
            printf("vision_loop: %u\n", args->vision_loop);
            printf("llm_loop: %u\n", args->llm_loop);
            printf("device_id: %u\n", args->device_id);
            printf("time_loop: %.2f hours\n", args->time_loop);
            printf("=======================================\n\n");
            break;

        case PROGRAM_TYPE_AUDIO:
            printf("\n===== RKNN3_AUDIO_ENCODER_TEST Configuration =====\n");
            printf("audio_model: %s\n", args->model_path ? args->model_path : "null");
            printf("audio_weight: %s\n", args->weight_path ? args->weight_path : "null");
            printf("audio_core_mask: 0x%x\n", args->core_mask);
            printf("audio_path: %s\n", args->audio_path ? args->audio_path : "null");  // Using audio_path field for audio
            printf("audio_loop: %u\n", args->cnt_loop);                                // Using cnt_loop for audio_loop
            printf("device_id: %u\n", args->device_id);
            printf("time_loop: %.2f hours\n", args->time_loop);
            printf("=======================================\n\n");
            break;
    }
}

void handle_time_loop_override(cmdline_args_t *args, program_type_t program_type) {
    if (!args) return;

    if (args->time_loop != 0.0f) {
        switch (program_type) {
            case PROGRAM_TYPE_CNN:
            case PROGRAM_TYPE_LLM:
            case PROGRAM_TYPE_AUDIO:
                args->cnt_loop = 1;
                break;
            case PROGRAM_TYPE_VLM:
                args->vision_loop = 1;
                args->llm_loop = 1;
                break;
        }
    }
}