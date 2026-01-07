#!/bin/bash

# ============================================================================
# AI Coprocessor Test Script - RKNN Test Module
# ============================================================================

# Define color codes for output formatting
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
PURPLE='\033[1;35m'
CYAN='\033[1;36m'
NC='\033[0m' # Reset color

# Script information
SCRIPT_VERSION="1.0"
TEST_RESULTS_DIR="./test_results"
mkdir -p "$TEST_RESULTS_DIR"

# Global variables for RKNN test
LOOP=1
DEVICES_ID=1
DEVICES_CORE=0xff
SEQ_LEN=512
NEW_TOKENS=512
TEST_DURATION=0

# ============================================================================
# Core utility functions
# ============================================================================

# Logging function
log_message() {
    local message="$1"
    local log_file="${2:-$TEST_RESULTS_DIR/rknn_test_$(date +%Y%m%d_%H%M%S).log}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" | tee -a "$log_file"
}

show_test_header() {
    clear
    echo -e "${GREEN}"
    echo "========================================"
    echo "          AI Coprocessor Test Script"
    echo "          RKNN Test Module"
    echo "========================================"
    echo -e "${NC}"
}

wait_return() {
    echo
    echo -e "${YELLOW}Press Enter to return to menu...${NC}"
    read -r
}

show_test_start() {
    local model_type="$1"
    local model_name="$2"
    local log_file="$3"
    echo
    echo -e "${BLUE}========================================${NC}"
    echo -e "${GREEN}Starting $model_type Test${NC}"
    echo -e "${GREEN}Model: $model_name${NC}"
    echo -e "${BLUE}========================================${NC}"
    log_message "Starting test: $model_type - $model_name" "$log_file"
}

show_test_result() {
    local success="$1"
    local model_name="$2"
    local log_file="$3"

    if [ "$success" -eq 0 ]; then
        echo -e "${GREEN}✓ $model_name test completed${NC}"
        log_message "$model_name test result: Completed" "$log_file"
    else
        echo -e "${RED}✗✗ $model_name test failed${NC}"
        log_message "$model_name test result: Failed" "$log_file"
    fi
}

# ============================================================================
# Input validation functions
# ============================================================================

validate_number_input() {
    local prompt="$1"
    local variable_name="$2"
    local min_value="${3:-0}"
    local max_value="${4:-100000}"

    while true; do
        read -p "$prompt" input

        if [[ -z "$input" ]]; then
            echo -e "${RED}Error: Input cannot be empty, please re-enter!${NC}"
            continue
        fi

        if [[ ! "$input" =~ ^[0-9]+$ ]]; then
            echo -e "${RED}Error: Please enter a valid non-negative integer!${NC}"
            continue
        fi

        input=$((10#$input))

        if [[ "$input" -lt "$min_value" || "$input" -gt "$max_value" ]]; then
            echo -e "${RED}Error: Please enter a number between ${min_value}-${max_value}!${NC}"
            continue
        fi

        case "$variable_name" in
            "LOOP") LOOP="$input" ;;
            "DEVICES_ID") DEVICES_ID="$input" ;;
            "SEQ_LEN") SEQ_LEN="$input" ;;
            "NEW_TOKENS") NEW_TOKENS="$input" ;;
        esac

        break
    done
}

validate_hex_input() {
    local prompt="$1"
    local variable_name="$2"
    local min_value="${3:-0}"
    local max_value="${4:-255}"

    while true; do
        read -p "$prompt" input

        if [[ -z "$input" ]]; then
            echo -e "${RED}Error: Input cannot be empty, please re-enter!${NC}"
            continue
        fi

        if [[ ! "$input" =~ ^0x[0-9a-fA-F]+$ ]]; then
            echo -e "${RED}Error: Please enter a valid hexadecimal format (e.g., 0xff)!${NC}"
            continue
        fi

        local decimal_value=$((input))

        if [[ "$decimal_value" -lt "$min_value" || "$decimal_value" -gt "$max_value" ]]; then
            echo -e "${RED}Error: Please enter a hexadecimal value between 0x00-0xff!${NC}"
            continue
        fi

        case "$variable_name" in
            "DEVICES_CORE") DEVICES_CORE="$input" ;;
        esac

        break
    done
}

get_loop() {
    validate_number_input "Enter number of loops (1-100000): " "LOOP" 1 100000
}

get_test_duration() {
    validate_number_input "Enter test duration in hours: " "TEST_DURATION" 0 999999
}

get_devices_id() {
    validate_number_input "Enter device ID (0-64): " "DEVICES_ID" 0 64
}

get_devices_core() {
    validate_hex_input "Enter device core (e.g., 0xff): " "DEVICES_CORE" 0 255
}

get_seq_len() {
    validate_number_input "Enter sequence length: " "SEQ_LEN" 1 65536
}

get_new_tokens() {
    validate_number_input "Enter number of new tokens to generate: " "NEW_TOKENS" 1 65536
}

# ============================================================================
# Directory scanning functions
# ============================================================================

scan_model_directories() {
    local model_type="$1"
    local -n result_array="$2"

    result_array=()
    local count=0
    local base_dir="../$model_type"

    echo -e "${CYAN}Scanning for $model_type models in directory: $base_dir/${NC}"

    if [[ ! -d "$base_dir" ]]; then
        echo -e "${YELLOW}Directory $base_dir does not exist for model type: $model_type${NC}"
        return 1
    fi

    if [[ -z "$(ls -A "$base_dir" 2>/dev/null)" ]]; then
        echo -e "${YELLOW}Directory $base_dir is empty. No $model_type models found.${NC}"
        return 1
    fi

    local found_any=false
    for model_dir in "$base_dir"/*; do
        if [[ -d "$model_dir" ]]; then
            local model_name=$(basename "$model_dir")
            found_any=true

            local has_model_files=false
            if [[ -n "$(find "$model_dir" -maxdepth 1 -name "*.rknn" 2>/dev/null)" ]] ||
               [[ -n "$(find "$model_dir" -maxdepth 1 -name "*.weight" 2>/dev/null)" ]] ||
               [[ -n "$(find "$model_dir" -maxdepth 1 -name "*.bin" 2>/dev/null)" ]] ||
               [[ -n "$(find "$model_dir" -maxdepth 1 -name "*.gguf" 2>/dev/null)" ]] ||
               [[ -n "$(find "$model_dir" -maxdepth 1 -name "*.ini" 2>/dev/null)" ]]; then
                has_model_files=true
            fi

            if [[ "$has_model_files" == "true" ]]; then
                ((count++))
                result_array["$count"]="$model_name"
                echo -e "${GREEN}Found valid $model_type model: $model_name${NC}"
            else
                echo -e "${YELLOW}Directory $model_dir exists but contains no recognizable model files, skipping${NC}"
            fi
        fi
    done

    if [[ "$found_any" == "false" ]]; then
        echo -e "${YELLOW}No model directories found in $base_dir/${NC}"
        return 1
    fi

    if [[ $count -eq 0 ]]; then
        echo -e "${YELLOW}No valid $model_type models found in $base_dir (directories exist but contain no model files)${NC}"
        return 1
    fi

    echo -e "${GREEN}Found $count valid $model_type models in $base_dir/${NC}"
    return 0
}

scan_all_model_directories() {
    local -n result_array="$1"
    result_array=()
    local total_count=0

    echo -e "${CYAN}Scanning for all models using directory structure: ../cnn/, ../llm/, ../vlm/${NC}"
    echo

    for model_type in "cnn" "llm" "vlm"; do
        declare -A found_models
        echo -e "${BLUE}Scanning $model_type models in ../$model_type/${NC}"

        if scan_model_directories "$model_type" found_models; then
            for index in $(echo "${!found_models[@]}" | tr ' ' '\n' | sort -n); do
                local model_name="${found_models[$index]}"
                if [[ ! "$model_name" =~ core- ]]; then
                    ((total_count++))
                    result_array["$total_count"]="$model_name $model_type"
                    echo -e "${GREEN}Added model: $model_name ($model_type)${NC}"
                fi
            done
        else
            echo -e "${YELLOW}No models found for type: $model_type${NC}"
        fi
        echo
    done

    if [[ $total_count -eq 0 ]]; then
        echo -e "${RED}No models found in any directory!${NC}"
        return 1
    fi

    echo -e "${GREEN}Total models found: $total_count${NC}"
    return 0
}

get_model_path() {
    local model_name="$1"
    local model_type="$2"
    echo "../$model_type/$model_name"
}

# ============================================================================
# Model testing functions
# ============================================================================

test_model() {
    local model_name="$1"
    local model_type="$2"
    local model_path="$3"
    local log_file="$4"

    show_test_start "$model_type" "$model_name" "$log_file"
    echo "Executing ${model_name} model test in foreground..."

    get_loop
    get_test_duration
    get_devices_id
    get_devices_core
    echo "Number of loops: $LOOP"
    echo "Device ID: $DEVICES_ID"
    echo "Device core: $DEVICES_CORE"

    local seq_len=512
    local new_tokens=512
    if [[ "$model_type" == "llm" ]]; then
        get_seq_len
        get_new_tokens
        seq_len="$SEQ_LEN"
        new_tokens="$NEW_TOKENS"
        echo "Sequence length (seq_len): $seq_len"
        echo "New tokens to generate: $new_tokens"
    fi

    echo -e "${CYAN}Executing $model_type test command...${NC}"

    local test_result
    case "$model_type" in
        "llm")
            echo -e "${YELLOW}Command to execute:${NC}"
            echo -e "${GREEN}./rknn3_llm_test.sh $model_path/$model_name $seq_len $new_tokens 0 $LOOP $DEVICES_ID $DEVICES_CORE${NC}"
            echo
            ./rknn3_llm_test.sh $model_path/$model_name $seq_len $new_tokens 0 $LOOP $DEVICES_ID $DEVICES_CORE
            test_result=$?
            ;;
        "cnn")
            echo -e "${YELLOW}Command to execute:${NC}"
            echo -e "${GREEN}./rknn3_cnn_test.sh $model_path/$model_name 0 $LOOP $DEVICES_ID $DEVICES_CORE${NC}"
            echo
            ./rknn3_cnn_test.sh $model_path/$model_name 0 $LOOP $DEVICES_ID $DEVICES_CORE
            test_result=$?
            ;;
        "vlm")
            echo -e "${YELLOW}Command to execute:${NC}"
            echo -e "${GREEN}./rknn3_vlm_test.sh $model_path/$model_name 0 $LOOP $DEVICES_ID $DEVICES_CORE${NC}"
            echo
            ./rknn3_vlm_test.sh $model_path/$model_name 0 $LOOP $DEVICES_ID $DEVICES_CORE
            test_result=$?
            ;;
        *)
            echo -e "${RED}Unknown model type: $model_type${NC}"
            show_test_result 1 "$model_name" "$log_file"
            wait_return
            return 1
            ;;
    esac

    if [ $test_result -eq 0 ]; then
        show_test_result 0 "$model_name" "$log_file"
        log_message "$model_name test completed - Loops: $LOOP, Device ID: $DEVICES_ID, Device Core: $DEVICES_CORE, Seq Len: $seq_len, New Tokens: $new_tokens" "$log_file"
    else
        show_test_result 1 "$model_name" "$log_file"
        log_message "$model_name test failed - Exit code: $test_result" "$log_file"
    fi

    wait_return
}

test_model_with_params() {
    local model_name="$1"
    local model_type="$2"
    local model_path="$3"
    local loop_count="$4"
    local devices_id="$5"
    local devices_core="$6"
    local seq_len="$7"
    local new_tokens="$8"
    local test_duration="$9"
    local log_file="${10}"

    show_test_start "$model_type" "$model_name" "$log_file"
    echo "Executing ${model_name} model test with parameters:"
    echo "Number of loops: $loop_count"
    echo "Device ID: $devices_id"
    echo "Device core: $devices_core"

    if [[ "$model_type" == "llm" ]]; then
        echo "Sequence length (seq_len): $seq_len"
        echo "New tokens to generate: $new_tokens"
    fi

    case "$model_type" in
        "llm")
            echo -e "${YELLOW}Command to execute:${NC}"
            echo -e "${GREEN}./rknn3_llm_test.sh $model_path/$model_name $seq_len $new_tokens $test_duration $loop_count $devices_id $devices_core${NC}"
            echo
            ./rknn3_llm_test.sh $model_path/$model_name $seq_len $new_tokens $test_duration $loop_count $devices_id $devices_core
            ;;
        "cnn")
            echo -e "${YELLOW}Command to execute:${NC}"
            echo -e "${GREEN}./rknn3_cnn_test.sh $model_path/$model_name $test_duration $loop_count $devices_id $devices_core${NC}"
            echo
            ./rknn3_cnn_test.sh $model_path/$model_name $test_duration $loop_count $devices_id $devices_core
            ;;
        "vlm")
            echo -e "${YELLOW}Command to execute:${NC}"
            echo -e "${GREEN}./rknn3_vlm_test.sh $model_path/$model_name $test_duration $loop_count $devices_id $devices_core${NC}"
            echo
            ./rknn3_vlm_test.sh $model_path/$model_name $test_duration $loop_count $devices_id $devices_core
            ;;
        *)
            echo -e "${RED}Unknown model type: $model_type${NC}"
            show_test_result 1 "$model_name" "$log_file"
            return 1
            ;;
    esac

    local test_result=$?
    if [ $test_result -eq 0 ]; then
        show_test_result 0 "$model_name" "$log_file"
        if [[ "$model_type" == "llm" ]]; then
            log_message "$model_name test completed - Loops: $loop_count, Device ID: $devices_id, Device Core: $devices_core, Seq Len: $seq_len, New Tokens: $new_tokens" "$log_file"
        else
            log_message "$model_name test completed - Loops: $loop_count, Device ID: $devices_id, Device Core: $devices_core" "$log_file"
        fi
    else
        show_test_result 1 "$model_name" "$log_file"
        log_message "$model_name test failed - Exit code: $test_result" "$log_file"
    fi

    return $test_result
}

# ============================================================================
# Performance report functions
# ============================================================================

analyze_cnn_performance() {
    local cnn_log="$1"

    if [[ ! -f "$cnn_log" ]] || [[ ! -s "$cnn_log" ]]; then
        echo "No CNN performance data"
        return
    fi

    local model_count=$(grep -c "^cnn:" "$cnn_log")
    echo "CNN Model Count: $model_count"
    echo

    echo "Individual Model Performance Data:"
    echo "------------------------------------------------"

    awk '
    /^cnn:/ {
        if (model != "") {
            print "Model: " model
            print "Core: " core
            print "Input Dimensions: " input_width "x" input_height "x" input_channel
            print "Total Frames: " total_frames
            print "Total Time: " total_time
            print "FPS: " fps
            print "Average Cost: " avg_cost
            print "------------------------------------------------"
        }
        model = ""; core = ""; input_width = ""; input_height = ""; input_channel = ""
        total_frames = ""; total_time = ""; fps = ""; avg_cost = ""
    }
    /^model:/ { model = $2 }
    /^core:/ { core = $2 }
    /^input_width:/ { input_width = $2 }
    /^input_height:/ { input_height = $2 }
    /^input_channel:/ { input_channel = $2 }
    /^total_frames:/ { total_frames = $2 }
    /^total_time:/ { total_time = $2 " " $3 " " $4 }
    /^fps:/ { fps = $2 }
    /^avg_cost:/ { avg_cost = $2 " " $3 }
    END {
        if (model != "") {
            print "Model: " model
            print "Core: " core
            print "Input Dimensions: " input_width "x" input_height "x" input_channel
            print "Total Frames: " total_frames
            print "Total Time: " total_time
            print "FPS: " fps
            print "Average Cost: " avg_cost
            print "------------------------------------------------"
        }
    }
    ' "$cnn_log"

    local avg_fps=$(awk '/^fps:/ {sum += $2; count++} END {if (count>0) printf "%.2f", sum/count}' "$cnn_log" 2>/dev/null || echo "N/A")
    local max_fps=$(awk 'BEGIN{max=0} /^fps:/ {if ($2 > max) max = $2} END {print max+0}' "$cnn_log" 2>/dev/null || echo "N/A")
    local min_fps=$(awk 'BEGIN{min=999999} /^fps:/ {if ($2 < min) min = $2} END {print min+0}' "$cnn_log" 2>/dev/null || echo "N/A")
    local best_model=$(awk '/^fps:/ {fps=$2} /^model:/ {model=$2} {if (fps == '"$max_fps"') {print model; exit}}' "$cnn_log" 2>/dev/null || echo "N/A")

    echo
    echo "Performance Statistics:"
    echo "Average FPS: ${avg_fps}"
    echo "Maximum FPS: ${max_fps} (Model: ${best_model})"
    echo "Minimum FPS: ${min_fps}"
}

analyze_llm_performance() {
    local llm_log="$1"

    if [[ ! -f "$llm_log" ]] || [[ ! -s "$llm_log" ]]; then
        echo "No LLM performance data"
        return
    fi

    local model_count=$(grep -c "^llm:" "$llm_log")
    echo "LLM Model Count: $model_count"
    echo

    echo "Individual Model Performance Data:"
    echo "------------------------------------------------"

    awk '
    /^llm:/ {
        if (model != "") {
            print "Model: " model
            print "Core: " core
            print "Sequence Length: " seq_len
            print "Generated Tokens: " token
            print "Time to First Token (TTFT): " ttft
            print "Time Per Output Token (TPOT): " tpot
            print "Prefill Speed: " prefill
            print "Tokens Per Second (TPS): " tps
            print "Total Time: " total_time
            print "Total Runs: " total_runs
            print "------------------------------------------------"
        }
        model = ""; core = ""; seq_len = ""; token = ""; ttft = ""; tpot = ""
        prefill = ""; tps = ""; total_time = ""; total_runs = ""
    }
    /^model:/ { model = $2 }
    /^core:/ { core = $2 }
    /^seq_len:/ { seq_len = $2 }
    /^token:/ { token = $2 }
    /^TTFT:/ { ttft = $2 " " $3 }
    /^TPOT:/ { tpot = $2 " " $3 " " $4 }
    /^Prefill:/ { prefill = $2 " " $3 " " $4 }
    /^TPS:/ { tps = $2 " " $3 " " $4 }
    /^TotalTime:/ { total_time = $2 " " $3 " " $4 }
    /^TotalRuns:/ { total_runs = $2 }
    END {
        if (model != "") {
            print "Model: " model
            print "Core: " core
            print "Sequence Length: " seq_len
            print "Generated Tokens: " token
            print "Time to First Token (TTFT): " ttft
            print "Time Per Output Token (TPOT): " tpot
            print "Prefill Speed: " prefill
            print "Tokens Per Second (TPS): " tps
            print "Total Time: " total_time
            print "Total Runs: " total_runs
            print "------------------------------------------------"
        }
    }
    ' "$llm_log"

    local avg_ttft=$(awk '/^TTFT:/ {gsub(/[^0-9.]/, "", $2); sum += $2; count++} END {if (count>0) printf "%.2f", sum/count}' "$llm_log" 2>/dev/null)
    local avg_tps=$(awk '/^TPS:/ {gsub(/[^0-9.]/, "", $2); sum += $2; count++} END {if (count>0) printf "%.2f", sum/count}' "$llm_log" 2>/dev/null)
    local max_tps=$(awk 'BEGIN{max=0} /^TPS:/ {gsub(/[^0-9.]/, "", $2); if ($2+0 > max+0) max=$2+0} END {if (max>0) printf "%.2f", max}' "$llm_log" 2>/dev/null)
    local best_model=$(awk '
    /^TPS:/ {
        gsub(/[^0-9.]/, "", $2);
        current_tps = $2+0;
        if (current_tps > max_tps) {
            max_tps = current_tps;
            best_model = "";
        }
    }
    /^model:/ {
        if (best_model == "" && max_tps > 0) {
            best_model = $2;
        }
    }
    END {
        if (best_model != "") print best_model;
        else print "N/A";
    }' "$llm_log" 2>/dev/null)

    echo
    echo "Performance Statistics:"
    echo "Average TTFT: ${avg_ttft} ms"
    echo "Average TPS: ${avg_tps} tokens/s"
    echo "Maximum TPS: ${max_tps} tokens/s (Model: ${best_model})"
}

analyze_vlm_performance() {
    local vlm_log="$1"

    if [[ ! -f "$vlm_log" ]] || [[ ! -s "$vlm_log" ]]; then
        echo "No VLM performance data"
        return
    fi

    local model_count=$(grep -c "^vlm:" "$vlm_log")
    echo "VLM Model Count: $model_count"
    echo

    echo "Individual Model Performance Data:"
    echo "------------------------------------------------"

    awk '
    /^vlm:/ {
        if (model != "") {
            print "Model: " model
            print "Core: " core
            print "Input Dimensions: " input_width "x" input_height
            print "Vision Processing Time: " vision
            print "Generated Tokens: " gen_len
            print "Time to First Token (TTFT): " ttft
            print "Tokens Per Second (TPS): " tps
            print "Total Time: " total_time
            print "Total Runs: " total_runs
            print "------------------------------------------------"
        }
        model = ""; core = ""; input_width = ""; input_height = ""; vision = ""
        gen_len = ""; ttft = ""; tps = ""; total_time = ""; total_runs = ""
    }
    /^model:/ { model = $2 }
    /^core:/ { core = $2 }
    /^input_width:/ { input_width = $2 }
    /^input_height:/ { input_height = $2 }
    /^Vision:/ { vision = $2 " " $3 " " $4 }
    /^GenLen:/ { gen_len = $2 " " $3 " " $4 }
    /^TTFT:/ { ttft = $2 " " $3 " " $4 }
    /^TPS:/ { tps = $2 " " $3 " " $4 }
    /^TotalTime:/ { total_time = $2 " " $3 " " $4 }
    /^TotalRuns:/ { total_runs = $2 }
    END {
        if (model != "") {
            print "Model: " model
            print "Core: " core
            print "Input Dimensions: " input_width "x" input_height
            print "Vision Processing Time: " vision
            print "Generated Tokens: " gen_len
            print "Time to First Token (TTFT): " ttft
            print "Tokens Per Second (TPS): " tps
            print "Total Time: " total_time
            print "Total Runs: " total_runs
            print "------------------------------------------------"
        }
    }
    ' "$vlm_log"

    local avg_ttft=$(awk '/^TTFT:/ {gsub(/[^0-9.]/, "", $2); sum += $2; count++} END {if (count>0) printf "%.2f", sum/count}' "$vlm_log" 2>/dev/null)
    local avg_tps=$(awk '/^TPS:/ {gsub(/[^0-9.]/, "", $2); sum += $2; count++} END {if (count>0) printf "%.2f", sum/count}' "$vlm_log" 2>/dev/null)
    local max_tps=$(awk 'BEGIN{max=0} /^TPS:/ {gsub(/[^0-9.]/, "", $2); if ($2+0 > max+0) max=$2+0} END {if (max>0) printf "%.2f", max}' "$vlm_log" 2>/dev/null)
    local best_model=$(awk '
    /^TPS:/ {
        gsub(/[^0-9.]/, "", $2);
        current_tps = $2+0;
        if (current_tps > max_tps) {
            max_tps = current_tps;
            best_model = "";
        }
    }
    /^model:/ {
        if (best_model == "" && max_tps > 0) {
            best_model = $2;
        }
    }
    END {
        if (best_model != "") print best_model;
        else print "N/A";
    }' "$vlm_log" 2>/dev/null)

    echo
    echo "Performance Statistics:"
    echo "Average TTFT: ${avg_ttft} ms"
    echo "Average TPS: ${avg_tps} tokens/s"
    echo "Maximum TPS: ${max_tps} tokens/s (Model: ${best_model})"
}

generate_performance_comparison() {
    local performance_dir="$1"
    local total_models="$2"
    local successful_tests="$3"
    local failed_tests="$4"

    echo "Performance Comparison Summary:"
    echo "------------------------------------------------"

    local cnn_count=0
    local llm_count=0
    local vlm_count=0

    if [[ -f "$performance_dir/cnn.log" ]] && [[ -s "$performance_dir/cnn.log" ]]; then
        cnn_count=$(grep -c "^cnn:" "$performance_dir/cnn.log")
    fi

    if [[ -f "$performance_dir/llm.log" ]] && [[ -s "$performance_dir/llm.log" ]]; then
        llm_count=$(grep -c "^llm:" "$performance_dir/llm.log")
    fi

    if [[ -f "$performance_dir/vlm.log" ]] && [[ -s "$performance_dir/vlm.log" ]]; then
        vlm_count=$(grep -c "^vlm:" "$performance_dir/vlm.log")
    fi

    echo "Total Test Models: $total_models"
    echo "CNN Models: $cnn_count"
    echo "LLM Models: $llm_count"
    echo "VLM Models: $vlm_count"
    echo

    echo "Best Performance Model Comparison:"
    echo "------------------------------------------------"

    if [[ $cnn_count -gt 0 ]]; then
        local best_cnn_fps=$(awk 'BEGIN{max=0} /^fps:/ {if ($2 > max) max = $2} END {print max+0}' "$performance_dir/cnn.log" 2>/dev/null || echo "N/A")
        local best_cnn_model=$(awk '/^fps:/ {fps=$2} /^model:/ {model=$2} {if (fps == '"$best_cnn_fps"') {print model; exit}}' "$performance_dir/cnn.log" 2>/dev/null || echo "N/A")
        echo "CNN Highest FPS: $best_cnn_fps (Model: $best_cnn_model)"
    fi

    if [[ $llm_count -gt 0 ]]; then
        local best_llm_tps=$(awk 'BEGIN{max=0} /^TPS:/ {gsub(/[^0-9.]/, "", $2); if ($2 > max) max = $2} END {print max+0}' "$performance_dir/llm.log" 2>/dev/null || echo "N/A")
        local best_llm_model=$(awk '/^TPS:/ {gsub(/[^0-9.]/, "", $2); tps=$2} /^model:/ {model=$2} {if (tps == '"$best_llm_tps"') {print model; exit}}' "$performance_dir/llm.log" 2>/dev/null || echo "N/A")
        echo "LLM Highest TPS: $best_llm_tps tokens/s (Model: $best_llm_model)"
    fi

    if [[ $vlm_count -gt 0 ]]; then
        local best_vlm_tps=$(awk 'BEGIN{max=0} /^TPS:/ {gsub(/[^0-9.]/, "", $2); if ($2 > max) max = $2} END {print max+0}' "$performance_dir/vlm.log" 2>/dev/null || echo "N/A")
        local best_vlm_model=$(awk '/^TPS:/ {gsub(/[^0-9.]/, "", $2); tps=$2} /^model:/ {model=$2} {if (tps == '"$best_vlm_tps"') {print model; exit}}' "$performance_dir/vlm.log" 2>/dev/null || echo "N/A")
        echo "VLM Highest TPS: $best_vlm_tps tokens/s (Model: $best_vlm_model)"
    fi

    echo
    echo "Test Result Summary:"
    echo "------------------------------------------------"
    if [[ $failed_tests -eq 0 ]]; then
        echo "Overall Status: All tests completed successfully ✓"
    else
        echo "Overall Status: Some tests failed, please check logs ✗✗"
    fi
    echo "Recommendation: Evaluate model suitability based on specific performance data"
}

generate_performance_report() {
    local performance_dir="$1"
    local total_models="$2"
    local successful_tests="$3"
    local failed_tests="$4"

    local report_file="$performance_dir/Performance_Report_$(date +%Y%m%d_%H%M%S).txt"

    echo
    echo -e "${CYAN}Generating Performance Report...${NC}"
    echo -e "Report File: $report_file"

    {
        echo "================================================"
        echo "           AI Co-processor Performance Test Report"
        echo "================================================"
        echo "Generation Time: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Report File: $report_file"
        echo

        echo "=== Test Summary ==="
        echo "Total Test Models: $total_models"
        echo "Successful Tests: $successful_tests"
        echo "Failed Tests: $failed_tests"
        if [[ $total_models -gt 0 ]]; then
            local success_rate=$((successful_tests * 100 / total_models))
            echo "Test Success Rate: ${success_rate}%"
        else
            echo "Test Success Rate: 0%"
        fi
        echo

        echo "=== Test Parameters ==="
        echo "Loop Count: $LOOP"
        echo "Device ID: $DEVICES_ID"
        echo "Device Core: $DEVICES_CORE"
        echo

        if [[ -f "$performance_dir/cnn.log" ]] && [[ -s "$performance_dir/cnn.log" ]]; then
            echo "=== CNN Model Performance Analysis ==="
            analyze_cnn_performance "$performance_dir/cnn.log"
            echo
        else
            echo "=== CNN Model Performance Analysis ==="
            echo "No CNN model performance data"
            echo
        fi

        if [[ -f "$performance_dir/llm.log" ]] && [[ -s "$performance_dir/llm.log" ]]; then
            echo "=== LLM Model Performance Analysis ==="
            analyze_llm_performance "$performance_dir/llm.log"
            echo
        else
            echo "=== LLM Model Performance Analysis ==="
            echo "No LLM model performance data"
            echo
        fi

        if [[ -f "$performance_dir/vlm.log" ]] && [[ -s "$performance_dir/vlm.log" ]]; then
            echo "=== VLM Model Performance Analysis ==="
            analyze_vlm_performance "$performance_dir/vlm.log"
            echo
        else
            echo "=== VLM Model Performance Analysis ==="
            echo "No VLM model performance data"
            echo
        fi

        echo "=== Performance Comparison Summary ==="
        generate_performance_comparison "$performance_dir" "$total_models" "$successful_tests" "$failed_tests"
        echo

        echo "================================================"
        echo "              Report Generation Completed"
        echo "================================================"

    } > "$report_file"

    echo -e "${GREEN}Performance Report Generated: $report_file${NC}"
    echo
    echo -e "${CYAN}Report Summary:${NC}"
    echo "================================================"
    echo "Total Test Models: $total_models"
    echo "Successful: $successful_tests"
    echo "Failed: $failed_tests"
    if [[ $total_models -gt 0 ]]; then
        local success_rate=$((successful_tests * 100 / total_models))
        echo "Success Rate: ${success_rate}%"
    else
        echo "Success Rate: 0%"
    fi
    echo "Report File: $report_file"
    echo "================================================"
}

# ============================================================================
# Menu functions
# ============================================================================

generate_test_menu() {
    local menu_type="$1"
    local menu_title="$2"
    local color="$3"
    local log_file="$4"

    while true; do
        show_test_header
        echo -e "${color}${menu_title} Options:${NC}"
        echo "Scanning ../ directory for ${menu_type} models..."
        echo

        declare -A found_models

        if ! scan_model_directories "$menu_type" found_models; then
            echo -e "${YELLOW}No ${menu_type} models found in ../ directory!${NC}"
            echo
            echo "1. Rescan directories"
            echo "2. Return to previous menu"
            echo

            read -rp "Please select an option (1-2): " retry_choice

            case $retry_choice in
                1) continue ;;
                2) return ;;
                *) echo -e "${RED}Invalid selection!${NC}"; continue ;;
            esac
        fi

        local count=0
        for index in $(echo "${!found_models[@]}" | tr ' ' '\n' | sort -n); do
            ((count++))
            echo "$count. ${found_models[$index]}"
        done

        local return_option=$((count + 1))
        echo "$return_option. Return to previous menu"
        echo

        read -rp "Please select a model to test (1-$return_option): " choice

        if [[ ! "$choice" =~ ^[0-9]+$ ]]; then
            echo -e "${RED}Invalid input, please enter a number!${NC}"
            continue
        fi

        if [[ "$choice" -eq "$return_option" ]]; then
            return
        elif [[ "$choice" -ge 1 && "$choice" -le $count ]]; then
            local selected_index=0
            for index in $(echo "${!found_models[@]}" | tr ' ' '\n' | sort -n); do
                ((selected_index++))
                if [[ $selected_index -eq $choice ]]; then
                    local model_name="${found_models[$index]}"
                    local model_path=$(get_model_path "$model_name" "$menu_type")

                    if [[ ! -e "$model_path" ]] && [[ ! -e "$model_path.rknn" ]] && [[ -z "$(ls "$model_path"/*.rknn 2>/dev/null)" ]]; then
                        echo -e "${RED}Model files not found for $model_name!${NC}"
                        echo "Expected path: $model_path"
                        wait_return
                        continue
                    fi

                    echo -e "${GREEN}Selected model: $model_name${NC}"
                    test_model "$model_name" "$menu_type" "$model_path" "$log_file"
                    break
                fi
            done
        else
            echo -e "${RED}Invalid selection, please enter 1-$return_option${NC}"
        fi
    done
}

cnn_test_menu() {
    local log_file="$1"
    generate_test_menu "cnn" "CNN Model Validation Test" "${CYAN}" "$log_file"
}

llm_test_menu() {
    local log_file="$1"
    generate_test_menu "llm" "LLM Model Validation Test" "${PURPLE}" "$log_file"
}

vlm_test_menu() {
    local log_file="$1"
    generate_test_menu "vlm" "VLM Model Validation Test" "${YELLOW}" "$log_file"
}

loop_test_all_models() {
    local log_file="$1"
    show_test_header
    echo -e "${PURPLE}Loop Test All Models${NC}"
    echo "Scanning ../ directory for all available models..."
    echo

    local performance_dir="$TEST_RESULTS_DIR/performance"
    rm -rf "$performance_dir"
    mkdir -p "$performance_dir"
    echo -e "${GREEN}The performance data directory has been created: $performance_dir${NC}"
    echo

    declare -A all_models

    if ! scan_all_model_directories all_models; then
        echo -e "${YELLOW}No models found in ../ directory!${NC}"
        wait_return
        return 1
    fi

    echo -e "${GREEN}Found ${#all_models[@]} models:${NC}"
    local count=0
    for index in $(echo "${!all_models[@]}" | tr ' ' '\n' | sort -n); do
        ((count++))
        local model_info=(${all_models[$index]})
        echo "$count. ${model_info[0]} (${model_info[1]})"
    done
    echo

    echo -e "${CYAN}Setting test parameters for all models:${NC}"
    get_loop
    get_test_duration
    get_devices_id
    echo "Note: Device core will be set automatically based on model type (0x01 for CNN, 0xff for LLM/VLM)"

    local llm_seq_len=512
    local llm_new_tokens=512
    local has_llm=false

    for index in "${!all_models[@]}"; do
        local model_info=(${all_models[$index]})
        if [[ "${model_info[1]}" == "llm" ]]; then
            has_llm=true
            break
        fi
    done

    if [[ "$has_llm" == true ]]; then
        echo -e "${YELLOW}LLM models detected. Setting LLM-specific parameters:${NC}"
        get_seq_len
        get_new_tokens
        llm_seq_len="$SEQ_LEN"
        llm_new_tokens="$NEW_TOKENS"
    fi

    echo
    echo -e "${RED}WARNING: This will test all ${#all_models[@]} models with the following parameters:${NC}"
    echo "Loops: $LOOP"
    echo "Device ID: $DEVICES_ID"
    echo "Device Core: Auto-set (0x01 for CNN, 0xff for LLM/VLM)"
    if [[ "$has_llm" == true ]]; then
        echo "LLM Sequence Length: $llm_seq_len"
        echo "LLM New Tokens: $llm_new_tokens"
    fi

    echo
    echo -e "${YELLOW}This may take a significant amount of time. Continue?${NC}"
    echo "1. Yes, start loop testing"
    echo "2. No, return to menu"

    read -rp "Please select an option (1-2): " confirm_choice

    if [[ "$confirm_choice" != "1" ]]; then
        echo -e "${YELLOW}Loop testing cancelled.${NC}"
        wait_return
        return
    fi

    echo
    echo -e "${GREEN}Starting loop testing of all models...${NC}"
    log_message "=== Starting loop testing of all models ===" "$log_file"

    local total_models=${#all_models[@]}
    local current_model=0
    local successful_tests=0
    local failed_tests=0

    for index in $(echo "${!all_models[@]}" | tr ' ' '\n' | sort -n); do
        ((current_model++))
        local model_info=(${all_models[$index]})
        local model_name="${model_info[0]}"
        local model_type="${model_info[1]}"
        local model_path=$(get_model_path "$model_name" "$model_type")

        local devices_core="0xff"
        if [[ "$model_type" == "cnn" ]]; then
            devices_core="0x01"
        fi

        echo
        echo -e "${BLUE}========================================${NC}"
        echo -e "${GREEN}Testing model $current_model of $total_models${NC}"
        echo -e "${GREEN}Model: $model_name ($model_type)${NC}"
        echo -e "${BLUE}========================================${NC}"

        if [[ ! -e "$model_path" ]] && [[ ! -e "$model_path.rknn" ]] && [[ -z "$(ls "$model_path"/*.rknn 2>/dev/null)" ]]; then
            echo -e "${RED}Model files not found for $model_name!${NC}"
            ((failed_tests++))
            log_message "$model_name test skipped - Model files not found" "$log_file"
            continue
        fi

        local test_result
        if [[ "$model_type" == "llm" ]]; then
            test_model_with_params "$model_name" "$model_type" "$model_path" "$LOOP" "$DEVICES_ID" "$devices_core" "$llm_seq_len" "$llm_new_tokens" "$TEST_DURATION" "$log_file"
        else
            test_model_with_params "$model_name" "$model_type" "$model_path" "$LOOP" "$DEVICES_ID" "$devices_core" "512" "512" "$TEST_DURATION" "$log_file"
        fi

        test_result=$?
        if [ $test_result -eq 0 ]; then
            ((successful_tests++))
        else
            ((failed_tests++))
        fi

        sleep 2
    done

    echo
    echo -e "${BLUE}========================================${NC}"
    echo -e "${GREEN}Loop Testing Summary${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo -e "Total models tested: $total_models"
    echo -e "${GREEN}Successful tests: $successful_tests${NC}"
    echo -e "${RED}Failed tests: $failed_tests${NC}"

    if [[ $failed_tests -eq 0 ]]; then
        echo -e "${GREEN}All tests completed successfully!${NC}"
    else
        echo -e "${YELLOW}Some tests failed. Check the log for details.${NC}"
    fi

    log_message "=== Loop testing completed ===" "$log_file"
    log_message "Summary - Total: $total_models, Successful: $successful_tests, Failed: $failed_tests" "$log_file"
    generate_performance_report "$performance_dir" "$total_models" "$successful_tests" "$failed_tests"
    wait_return
}

rknn_test_menu() {
    local log_file="$TEST_RESULTS_DIR/rknn_test_$(date +%Y%m%d_%H%M%S).log"

    while true; do
        show_test_header
        echo "Before testing, please place the required model files in the directory at the same level as the rk3588_linux_aarch64_rk1820_stress_test package directory"
        echo -e "${BLUE}RKNN Test Options:${NC}"
        echo "1. CNN Model Test"
        echo "2. LLM Model Test"
        echo "3. VLM Model Test"
        echo "4. Loop Test All Models"
        echo "5. Return to Main Menu"
        echo

        read -rp "Please select test type (1-5): " choice

        case $choice in
            1) cnn_test_menu "$log_file" ;;
            2) llm_test_menu "$log_file" ;;
            3) vlm_test_menu "$log_file" ;;
            4) loop_test_all_models "$log_file" ;;
            5) return ;;
            *)
                echo -e "${RED}Invalid selection, please enter 1-5${NC}"
                ;;
        esac
    done
}

# ============================================================================
# Main RKNN test function
# ============================================================================

run_rknn_test() {
    echo -e "${GREEN}Starting RKNN Test Module${NC}"
    rknn_test_menu
}

# ============================================================================
# Standalone execution support
# ============================================================================

# If script is executed directly, run the test menu
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo -e "${GREEN}RKNN Test Module - Standalone Execution${NC}"
    run_rknn_test
fi