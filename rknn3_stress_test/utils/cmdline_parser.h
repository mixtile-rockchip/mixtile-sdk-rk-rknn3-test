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
 * @file cmdline_parser.h
 * @brief Common command line argument parser for RKNN3 stress tests
 */

#ifndef _CMDLINE_PARSER_H_
#define _CMDLINE_PARSER_H_

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Parameter definition structure
 */
typedef struct {
    int id;
    const char *short_name;
    const char *long_name;
    const char *description;
    bool required;
    void *default_value;  // Pointer to default value
} param_def_t;

/**
 * @brief Parsed command line arguments
 */
typedef struct {
    // Common parameters
    char *model_path;
    char *weight_path;
    char *model_folder;
    uint32_t core_mask;
    uint32_t cnt_loop;
    float time_loop;
    uint32_t device_id;
    bool show_help;

    // CNN/Vision specific
    char *image_path;
    bool yuv_input;

    // LLM specific
    char *tokenizer_path;
    char *embedding_path;
    int32_t max_context_len;
    uint32_t n_input_tokens;
    int32_t max_new_tokens;

    // VLM specific
    char *vision_model_path;
    char *vision_weight_path;
    char *llm_model_path;
    char *llm_weight_path;
    uint32_t vision_core_mask;
    uint32_t llm_core_mask;
    uint32_t vision_loop;
    uint32_t llm_loop;
    char *prompt_ini_path;

    // Audio specific
    char *audio_path;

    // User parameters storage
    void *user_params;
} cmdline_args_t;

/**
 * @brief Parse command line arguments
 * @param argc Argument count from main()
 * @param argv Argument vector from main()
 * @param args Pointer to cmdline_args_t structure to store results
 * @return 0 on success, -1 on error
 */
int parse_cmdline_args(int argc, char **argv, cmdline_args_t *args);

/**
 * @brief Print usage/help message
 * @param argv0 Program name (argv[0])
 * @param program_type Program type identifier (0=CNN, 1=LLM, 2=VLM)
 * @param custom_params Optional custom parameter definitions
 * @param n_custom_params Number of custom parameters
 */
void print_usage(const char *argv0, int program_type, const param_def_t *custom_params, int n_custom_params);

/**
 * @brief Free allocated memory in cmdline_args_t
 * @param args Pointer to cmdline_args_t structure
 */
void free_cmdline_args(cmdline_args_t *args);

/**
 * @brief Initialize cmdline_args_t with default values
 * @param args Pointer to cmdline_args_t structure
 */
void init_cmdline_args(cmdline_args_t *args);

/**
 * @brief Register custom parameters
 * @param params Array of parameter definitions
 * @param n_params Number of parameters
 * @param args Pointer to cmdline_args_t structure
 * @return 0 on success, -1 on error
 */
int register_custom_params(const param_def_t *params, int n_params, cmdline_args_t *args);

/**
 * @brief Program type enumeration
 */
typedef enum {
    PROGRAM_TYPE_CNN = 0,
    PROGRAM_TYPE_LLM = 1,
    PROGRAM_TYPE_VLM = 2,
    PROGRAM_TYPE_AUDIO = 3
} program_type_t;

/**
 * @brief Populate model/tokenizer paths from model_folder
 * @param args Pointer to cmdline_args_t structure
 * @param program_type Program type (CNN/LLM/VLM/AUDIO)
 * @return 0 on success, -1 on error
 */
int populate_args_from_model_folder(cmdline_args_t *args, program_type_t program_type);

/**
 * @brief Validate required parameters based on program type
 * @param args Pointer to cmdline_args_t structure
 * @param program_type Program type (CNN/LLM/VLM)
 * @return 0 if valid, -1 if missing required parameters
 */
int validate_required_params(cmdline_args_t *args, program_type_t program_type);

/**
 * @brief Print configuration based on program type
 * @param args Pointer to cmdline_args_t structure
 * @param program_type Program type (CNN/LLM/VLM)
 */
void print_configuration(const cmdline_args_t *args, program_type_t program_type);

/**
 * @brief Handle time_loop override logic
 * @param args Pointer to cmdline_args_t structure
 * @param program_type Program type (CNN/LLM/VLM)
 */
void handle_time_loop_override(cmdline_args_t *args, program_type_t program_type);

#ifdef __cplusplus
}
#endif

#endif // _CMDLINE_PARSER_H_