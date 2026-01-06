#!/bin/bash

# Define color codes for output formatting
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
PURPLE='\033[1;35m'
CYAN='\033[1;36m'
NC='\033[0m' # Reset color

# Script information
SCRIPT_VERSION="1.0"  # Fixed background task status detection
TEST_RESULTS_DIR="./test_results"
mkdir -p "$TEST_RESULTS_DIR"
LOG_FILE="$TEST_RESULTS_DIR/rknn_test_$(date +%Y%m%d_%H%M%S).log"

# Global variables
LOOP=1
DEVICES_ID=1
DEVICES_CORE=0xff  # 默认值改为十六进制格式
SEQ_LEN=512
NEW_TOKENS=512

# Background task management
BACKGROUND_TASKS_DIR="$TEST_RESULTS_DIR/background_tasks"
mkdir -p "$BACKGROUND_TASKS_DIR"  # 确保目录存在，但不删除现有内容
declare -A BACKGROUND_TASKS  # Store background task PIDs: key=task_type_model, value=PID

# ============================================================================
# Input validation functions
# ============================================================================

# Generic input validation function
validate_number_input() {
    local prompt="$1"
    local variable_name="$2"
    local min_value="${3:-0}"  # Default minimum value is 0
    local max_value="${4:-100000}"  # Default maximum value is large to accommodate different parameters

    while true; do
        read -p "$prompt" input

        # Validate if input is empty
        if [[ -z "$input" ]]; then
            echo -e "${RED}Error: Input cannot be empty, please re-enter!${NC}"
            continue
        fi

        # Validate if input is a non-negative integer (including 0)
        if [[ ! "$input" =~ ^[0-9]+$ ]]; then
            echo -e "${RED}Error: Please enter a valid non-negative integer!${NC}"
            continue
        fi

        # Remove leading zeros to avoid octal interpretation
        input=$((10#$input))

        # Validate range
        if [[ "$input" -lt "$min_value" || "$input" -gt "$max_value" ]]; then
            echo -e "${RED}Error: Please enter a number between ${min_value}-${max_value}!${NC}"
            continue
        fi

        # Assign to global variable
        case "$variable_name" in
            "LOOP") LOOP="$input" ;;
            "DEVICES_ID") DEVICES_ID="$input" ;;
            "SEQ_LEN") SEQ_LEN="$input" ;;
            "NEW_TOKENS") NEW_TOKENS="$input" ;;
        esac

        break
    done
}

# 新增十六进制输入验证函数
validate_hex_input() {
    local prompt="$1"
    local variable_name="$2"
    local min_value="${3:-0}"  # 十进制最小值
    local max_value="${4:-255}"  # 十进制最大值，0xff=255

    while true; do
        read -p "$prompt" input

        # Validate if input is empty
        if [[ -z "$input" ]]; then
            echo -e "${RED}Error: Input cannot be empty, please re-enter!${NC}"
            continue
        fi

        # Validate if input is a valid hexadecimal format (0x followed by hex digits)
        if [[ ! "$input" =~ ^0x[0-9a-fA-F]+$ ]]; then
            echo -e "${RED}Error: Please enter a valid hexadecimal format (e.g., 0xff)!${NC}"
            continue
        fi

        # Convert hex to decimal for range validation
        local decimal_value=$((input))

        # Validate range
        if [[ "$decimal_value" -lt "$min_value" || "$decimal_value" -gt "$max_value" ]]; then
            echo -e "${RED}Error: Please enter a hexadecimal value between 0x00-0xff!${NC}"
            continue
        fi

        # Assign to global variable
        case "$variable_name" in
            "DEVICES_CORE") DEVICES_CORE="$input" ;;
        esac

        break
    done
}

get_loop() {
    validate_number_input "Enter number of loops (1-100000): " "LOOP" 1 100000
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
# Dynamic directory scanning functions
# ============================================================================

# Scan for available model directories using dynamic directory structure
scan_model_directories() {
    local model_type="$1"
    local -n result_array="$2"  # Use nameref to modify the passed array

    # Clear the result array
    result_array=()
    local count=0

    # Define the base directory for this model type
    local base_dir="../$model_type"

    echo -e "${CYAN}Scanning for $model_type models in directory: $base_dir/${NC}"

    # Check if the directory exists
    if [[ ! -d "$base_dir" ]]; then
        echo -e "${YELLOW}Directory $base_dir does not exist for model type: $model_type${NC}"
        echo -e "${BLUE}Please create the directory structure:${NC}"
        echo "  mkdir -p ../cnn/"
        echo "  mkdir -p ../llm/" 
        echo "  mkdir -p ../vlm/"
        return 1
    fi

    # Check if directory is empty
    if [[ -z "$(ls -A "$base_dir" 2>/dev/null)" ]]; then
        echo -e "${YELLOW}Directory $base_dir is empty. No $model_type models found.${NC}"
        return 1
    fi

    # Scan all subdirectories in the model type directory
    local found_any=false
    for model_dir in "$base_dir"/*; do
        if [[ -d "$model_dir" ]]; then
            local model_name=$(basename "$model_dir")
            found_any=true

            # Check if directory contains model files
            local has_model_files=false

            # Check for .rknn files
            if [[ -n "$(find "$model_dir" -maxdepth 1 -name "*.rknn" 2>/dev/null)" ]]; then
                has_model_files=true
            fi

            # Check for weight files
            if [[ -n "$(find "$model_dir" -maxdepth 1 -name "*.weight" 2>/dev/null)" ]] || 
               [[ -n "$(find "$model_dir" -maxdepth 1 -name "*.bin" 2>/dev/null)" ]]; then
                has_model_files=true
            fi

            # Check for other common model file extensions
            if [[ -n "$(find "$model_dir" -maxdepth 1 -name "*.gguf" 2>/dev/null)" ]] || 
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

# Scan for ALL available model directories (all types) using new directory structure
scan_all_model_directories() {
    local -n result_array="$1"  # Use nameref to modify the passed array

    # Clear the result array
    result_array=()
    local total_count=0

    echo -e "${CYAN}Scanning for all models using directory structure: ../cnn/, ../llm/, ../vlm/${NC}"
    echo

    # Scan for each model type
    for model_type in "cnn" "llm" "vlm"; do
        declare -A found_models
        echo -e "${BLUE}Scanning $model_type models in ../$model_type/${NC}"

        if scan_model_directories "$model_type" found_models; then
            for index in $(echo "${!found_models[@]}" | tr ' ' '\n' | sort -n); do
                local model_name="${found_models[$index]}"
                # Filter out models containing "core-" if needed
                if [[ ! "$model_name" =~ core- ]]; then
                    ((total_count++))
                    result_array["$total_count"]="$model_name $model_type"
                    echo -e "${GREEN}Added model: $model_name ($model_type)${NC}"
                else
                    echo -e "${YELLOW}Filtered out core model: $model_name${NC}"
                fi
            done
        else
            echo -e "${YELLOW}No models found for type: $model_type${NC}"
        fi
        echo
    done

    if [[ $total_count -eq 0 ]]; then
        echo -e "${RED}No models found in any directory!${NC}"
        echo
        echo -e "${YELLOW}Please ensure the following directory structure exists:${NC}"
        echo "  ../cnn/     - for CNN models (e.g., ../cnn/MobilenetV2/)"
        echo "  ../llm/     - for LLM models (e.g., ../llm/Qwen2.5-3B-Instruct/)"
        echo "  ../vlm/     - for VLM models (e.g., ../vlm/Qwen3-VL-2B/)"
        echo
        echo -e "${BLUE}Each model directory should contain the corresponding model files.${NC}"
        return 1
    fi

    echo -e "${GREEN}Total models found: $total_count${NC}"
    return 0
}

# Get the full model path with type-specific directory support - FIXED VERSION
get_model_path() {
    local model_name="$1"
    local model_type="$2"  # Model type parameter

    # Always use the new directory structure: ../<model_type>/<model_name>
    # This ensures we only search in type-specific directories
    if [[ -n "$model_type" ]]; then
        echo "../$model_type/$model_name"
    else
        # Fallback (should not happen with proper usage)
        echo "../$model_name"
    fi
}

# ============================================================================
# RKNN-SMI Test Function
# ============================================================================

rknn_smi_test() {
    # Color definitions for output
    local RED='\033[0;31m'
    local GREEN='\033[0;32m'
    local YELLOW='\033[1;33m'
    local BLUE='\033[0;34m'
    local NC='\033[0m' # No Color

    # Logging functions
    log_info() {
        echo -e "${BLUE}[INFO]${NC} $1"
    }

    log_success() {
        echo -e "${GREEN}[SUCCESS]${NC} $1"
    }

    log_warning() {
        echo -e "${YELLOW}[WARNING]${NC} $1"
    }

    log_error() {
        echo -e "${RED}[ERROR]${NC} $1"
    }

    # Check if rknn-smi command exists
    check_rknn_smi() {
        if ! command -v rknn-smi &> /dev/null; then
            log_error "rknn-smi command not found, please ensure RKNN driver is properly installed"
            return 1
        fi
        return 0
    }

    # Get device list
    get_device_list() {
        rknn-smi info -l 2>/dev/null | grep "Device ID" | awk '{print $NF}' | sort -n
    }

    # Get chip list for specific device
    get_chip_list() {
        local device_id=$1
        rknn-smi info -t cpu_freq -d $device_id 2>/dev/null | grep "Chip ID" | awk '{print $NF}' | sort -n
    }

    # Get available CPU frequencies
    get_available_cpu_freq() {
        local device_id=$1
        local chip_id=$2
        rknn-smi info -t cpu_freq -d $device_id -c $chip_id 2>/dev/null | grep "Available CPU Freq" | awk -F':' '{print $2}' | xargs
    }

    # Get available NPU frequencies
    get_available_npu_freq() {
        local device_id=$1
        local chip_id=$2
        rknn-smi info -t npu_freq -d $device_id -c $chip_id 2>/dev/null | grep "Available NPU Freq" | awk -F':' '{print $2}' | xargs
    }

    # Basic information query
    query_basic_info() {
        log_info "=== Basic RKNN Device Information Query ==="

        log_info "1. Query version information:"
        rknn-smi -v
        echo

        log_info "2. Query device information:"
        rknn-smi info
        echo

        log_info "3. Query topology information:"
        rknn-smi info -l
        echo

        log_info "4. Query all devices and chips detailed information:"
        rknn-smi info -t board
        echo
    }

    # Detailed status query
    query_detailed_status() {
        log_info "=== Detailed RKNN Device Status Query ==="

        local info_types=("memory" "fan" "temp" "voltage" "health" "sys_time" "reset_reason" "pcie_err")
        local type_names=("Memory Information" "Fan Speed Ratio" "Temperature Information" "Voltage Information" "Health Status" "System Time" "Last Reset Time" "PCIe Error Count")

        for i in "${!info_types[@]}"; do
            log_info "$((i+5)). Query all devices ${type_names[i]}:"
            rknn-smi info -t ${info_types[i]}
            echo
            sleep 1
        done
    }

    # Query frequency and work mode information
    query_frequency_mode_info() {
        log_info "=== Frequency and Work Mode Information Query ==="

        local devices=$(get_device_list)

        if [ -z "$devices" ]; then
            log_warning "No RKNN devices found"
            return 1
        fi

        for device in $devices; do
            log_info "Querying device $device:"

            log_info "  CPU frequency information:"
            rknn-smi info -t cpu_freq -d $device
            echo

            log_info "  NPU frequency information:"
            rknn-smi info -t npu_freq -d $device
            echo

            log_info "  Work mode information:"
            rknn-smi info -t work_mode -d $device
            echo

            sleep 1
        done
    }

    # CPU frequency setting test
    test_cpu_freq_settings() {
        log_info "=== Starting CPU Frequency Setting Test ==="

        local devices=$(get_device_list)

        if [ -z "$devices" ]; then
            log_warning "No RKNN devices found for CPU frequency test"
            return 1
        fi

        for device in $devices; do
            log_info "Processing device $device"
            local chips=$(get_chip_list $device)

            if [ -z "$chips" ]; then
                log_warning "  No chips found for device $device"
                continue
            fi

            for chip in $chips; do
                log_info "  Processing chip $chip"
                local freq_list=$(get_available_cpu_freq $device $chip)

                if [ -z "$freq_list" ]; then
                    log_warning "    No available CPU frequency information for device $device chip $chip, skipping"
                    continue
                fi

                log_info "    Available CPU frequencies: $freq_list"

                for freq in $freq_list; do
                    log_info "    Setting device ${device} chip ${chip} CPU frequency to: ${freq}MHz"
                    log_info "Execute the command： rknn-smi set -t cpu_freq -d $device -c $chip -s $freq "
                    rknn-smi set -t cpu_freq -d $device -c $chip -s $freq 2>/dev/null
                    log_success "    Setting successful"
                    # Verify setting
                    sleep 1
                    local current_freq=$(rknn-smi info -t cpu_freq -d $device -c $chip 2>/dev/null | grep "Current CPU Freq" | awk '{print $5}')
                    log_info "    Current CPU frequency: ${current_freq}MHz"
                    echo
                    sleep 1
                done
            done
        done
    }

    # NPU frequency setting test
    test_npu_freq_settings() {
        log_info "=== Starting NPU Frequency Setting Test ==="

        local devices=$(get_device_list)

        if [ -z "$devices" ]; then
            log_warning "No RKNN devices found for NPU frequency test"
            return 1
        fi

        for device in $devices; do
            log_info "Processing device $device"
            local chips=$(get_chip_list $device)

            if [ -z "$chips" ]; then
                log_warning "  No chips found for device $device"
                continue
            fi

            for chip in $chips; do
                log_info "  Processing chip $chip"
                local freq_list=$(get_available_npu_freq $device $chip)

                if [ -z "$freq_list" ]; then
                    log_warning "    No available NPU frequency information for device $device chip $chip, skipping"
                    continue
                fi

                log_info "    Available NPU frequencies: $freq_list"

                for freq in $freq_list; do
                    log_info "    Setting device ${device} chip ${chip} NPU frequency to: ${freq}MHz"
                    log_info "Execute the command： rknn-smi set -t npu_freq -d $device -c $chip -s $freq "
                    rknn-smi set -t npu_freq -d $device -c $chip -s $freq 2>/dev/null
                    # Verify setting
                    sleep 1
                    local current_freq=$(rknn-smi info -t npu_freq -d $device -c $chip 2>/dev/null | grep "Current NPU Freq" | awk '{print $5}')
                    log_info "    Current NPU frequency: ${current_freq}MHz"
                    echo
                    sleep 1
                done
            done
        done
    }

    # Work mode setting test
    test_work_mode_settings() {
        log_info "=== Starting Work Mode Setting Test ==="

        local devices=$(get_device_list)

        if [ -z "$devices" ]; then
            log_warning "No RKNN devices found for work mode test"
            return 1
        fi

        local modes=("0" "1" "2")
        local mode_names=("EFFICIENT" "NORMAL" "PERFORMANCE")

        for device in $devices; do
            log_info "Processing device $device"
            local chips=$(get_chip_list $device)

            if [ -z "$chips" ]; then
                log_warning "  No chips found for device $device"
                continue
            fi

            for chip in $chips; do
                log_info "  Processing chip $chip"

                for i in "${!modes[@]}"; do
                    log_info "    Setting device ${device} chip ${chip} work mode to: ${mode_names[i]} (${modes[i]})"
                    log_info "Execute the command： rknn-smi set -t work_mode -d $device -c $chip -s ${modes[i]} "
                    rknn-smi set -t work_mode -d $device -c $chip -s ${modes[i]} 2>/dev/null
                    # Verify setting
                    sleep 1
                    local current_mode=$(rknn-smi info -t work_mode -d $device -c $chip 2>/dev/null | grep "Chip Work Mode" | awk '{print $NF}')
                    log_info "    Current work mode: $current_mode"
                    echo
                    sleep 1
                done
            done
        done
    }

    # Final status summary
    final_status_summary() {
        log_info "=== Final Status Summary ==="

        log_info "Device list:"
        rknn-smi info -l
        echo

        local devices=$(get_device_list)

        log_info "Current frequency status:"
        for device in $devices; do
            log_info "Device $device CPU frequency:"
            rknn-smi info -t cpu_freq -d $device | grep -E "(Current|Available)" || true
            log_info " Device $device NPU frequency:"
            rknn-smi info -t npu_freq -d $device | grep -E "(Current|Available)" || true
            log_info " Device $device work mode:"
            rknn-smi info -t work_mode -d $device | grep "Chip Work Mode" || true
            echo
        done
    }

    # Main execution function
    main_execution() {
        log_info "RKNN-SMI Comprehensive Test Started"
        echo

        # Check if rknn-smi command exists
        if ! check_rknn_smi; then
            return 1
        fi

        # Basic information query
        query_basic_info
        sleep 1

        # Detailed status query
        query_detailed_status
        sleep 1

        # Frequency and work mode information query
        query_frequency_mode_info
        sleep 1


        # CPU frequency setting test
        test_cpu_freq_settings
        sleep 1

        # NPU frequency setting test
        test_npu_freq_settings
        sleep 1

        # Work mode setting test
        test_work_mode_settings

        # Final status summary
        final_status_summary

        log_success "RKNN-SMI Comprehensive Test Completed Successfully"
        return 0
    }

    # Execute main function
    main_execution
}

# ============================================================================
# Reboot Test Function
# ============================================================================

reboot_test() {
    # Color definitions for output
    local RED='\033[0;31m'
    local GREEN='\033[0;32m'
    local YELLOW='\033[1;33m'
    local BLUE='\033[0;34m'
    local NC='\033[0m' # No Color

    # Logging functions
    log_info() {
        echo -e "${BLUE}[INFO]${NC} $1"
    }

    log_success() {
        echo -e "${GREEN}[SUCCESS]${NC} $1"
    }

    log_warning() {
        echo -e "${YELLOW}[WARNING]${NC} $1"
    }

    log_error() {
        echo -e "${RED}[ERROR]${NC} $1"
    }

    # Check if required commands exist
    check_commands() {
        if ! command -v rknn-smi &> /dev/null; then
            log_error "rknn-smi command not found"
            return 1
        fi

        if ! command -v rknn3_startup &> /dev/null; then
            log_error "rknn3_startup command not found"
            return 1
        fi

        return 0
    }

    # Verify reboot success by checking rknn-smi version output
    verify_reboot_success() {
        log_info "Verifying reboot success..."
        local version_output
        version_output=$(rknn-smi --version 2>/dev/null)

        if echo "$version_output" | grep -q "rknn-smi version"; then
            log_success "Reboot successful - rknn-smi version information found"
            return 0
        else
            log_error "Reboot failed - rknn-smi version information not found"
            return 1
        fi
    }

    # Main reboot test function
    main_reboot_test() {
        # 创建日志文件路径
        local reboot_log_file="$TEST_RESULTS_DIR/reboot.log"

        # 清空日志文件
        > "$reboot_log_file"

        log_info "=== Starting Reboot Test ==="
        log_info "All reboot test output will be保存到: $reboot_log_file"

        # Check if required commands exist
        if ! check_commands; then
            return 1
        fi

        # Get number of loops
        echo
        validate_number_input "Enter number of reboot loops (1-100): " "LOOP" 1 100
        local loop_count=$LOOP

        log_info "Reboot test will run $loop_count times"
        echo

        # Confirm test execution
        echo -e "${YELLOW}WARNING: This will reboot the RKNN device $loop_count times.${NC}"
        echo -e "${YELLOW}Continue?${NC}"
        echo "1. Yes, start reboot test"
        echo "2. No, return to menu"

        read -rp "Please select (1-2): " confirm_choice

        if [[ "$confirm_choice" != "1" ]]; then
            log_info "Reboot test cancelled"
            return
        fi

        # 使用 tee 命令将后续所有输出同时显示在屏幕并保存到日志文件
        {
            local successful_reboots=0
            local failed_reboots=0

            log_info "Starting reboot test sequence..."
            echo

            for ((i=1; i<=loop_count; i++)); do
                log_info "=== Reboot Test Iteration $i of $loop_count ==="

                # The background program of npu needs to be closed first
                pkill -f "rknn3_transfer_proxy"

                # Step 1: Hardware reset
                log_info "1. Executing hardware reset: rknn-smi reset -t hw"
                rknn-smi reset -t hw 2>/dev/null
                # Step 2: Sleep for 1 second
                log_info "2. Waiting for 1 second..."
                sleep 2
                # Step 3: Restart rknn3 startup
                log_info "3. Restarting rknn3 startup: rknn3_startup restart"
                rknn3_startup restart 2>/dev/null
                # Additional wait for system to stabilize
                log_info "Waiting 3 seconds for system to stabilize..."
                sleep 2

                # Step 4: Verify reboot success
                if verify_reboot_success; then
                    log_success "Reboot iteration $i completed successfully"
                    ((successful_reboots++))
                else
                    log_error "Reboot iteration $i failed"
                    ((failed_reboots++))
                fi

                # Add separator between iterations
                if [[ $i -lt $loop_count ]]; then
                    echo
                    log_info "Preparing for next iteration..."
                    sleep 2
                    echo
                fi
            done

            # Display test summary
            echo
            log_info "=== Reboot Test Summary ==="
            log_info "Total iterations: $loop_count"
            log_success "Successful reboots: $successful_reboots"

            if [[ $failed_reboots -gt 0 ]]; then
                log_error "Failed reboots: $failed_reboots"
            else
                log_success "All reboot tests completed successfully!"
            fi

            # Final verification
            echo
            log_info "Final system status verification:"
            rknn-smi --version

            return $((failed_reboots > 0 ? 1 : 0))

        } | tee -a "$reboot_log_file"  # 将所有输出追加到日志文件

        log_info "Reboot test completed. Full output saved to: $reboot_log_file"
    }

    # Execute main function
    main_reboot_test
}

# ============================================================================
# RKNN-SMI Test Menu
# ============================================================================

rknn_smi_test_menu() {
    while true; do
        show_test_header
        echo -e "${PURPLE}RKNN-SMI Test Menu${NC}"
        echo "========================================"
        echo "1. Run RKNN-SMI Test"
        echo "2. Reboot Test"
        echo "3. Return to Main Menu"
        echo

        read -rp "Please select an option (1-4): " choice

        case $choice in
            1)
                echo -e "${YELLOW}Starting comprehensive RKNN-SMI test...${NC}"
                rknn_smi_test
                wait_return
                ;;
            2)
                echo -e "${YELLOW}Starting Reboot Test...${NC}"
                reboot_test
                wait_return
                ;;
            3)
                return
                ;;
            *)
                echo -e "${RED}Invalid selection, please enter 1-4${NC}"
                wait_return
                ;;
        esac
    done
}

# ============================================================================
# Background Task Management Functions
# ============================================================================

# Start a background test task
start_background_test() {
    local model_name="$1"
    local model_type="$2"
    local model_path="$3"
    local loop_count="$4"
    local devices_id="$5"
    local devices_core="$6"
    local seq_len="$7"
    local new_tokens="$8"

    # 确保后台任务目录存在
    mkdir -p "$BACKGROUND_TASKS_DIR"

    local task_id="${model_type}_${model_name}_$(date +%Y%m%d_%H%M%S)"
    local task_log="$BACKGROUND_TASKS_DIR/${task_id}.log"
    local task_pid_file="$BACKGROUND_TASKS_DIR/${task_id}.pid"

    # Create task info file
    local task_info_file="$BACKGROUND_TASKS_DIR/${task_id}.info"

    # 检查并创建任务信息文件
    if [ ! -f "$task_info_file" ]; then
        touch "$task_info_file"
        if [ $? -ne 0 ]; then
            echo -e "${RED}Error: Failed to create task info file: $task_info_file${NC}"
            echo -e "${YELLOW}Please check directory permissions: $BACKGROUND_TASKS_DIR${NC}"
            return 1
        fi
        echo -e "${GREEN}Task info file created: $task_info_file${NC}"
    fi

    # 确保文件可写
    if [ ! -w "$task_info_file" ]; then
        chmod 644 "$task_info_file" 2>/dev/null || {
            echo -e "${RED}Error: Cannot set permissions for $task_info_file${NC}"
            return 1
        }
    fi

    # 写入任务信息到文件
    {
        echo "MODEL_NAME=$model_name"
        echo "MODEL_TYPE=$model_type"
        echo "MODEL_PATH=$model_path"
        echo "LOOP_COUNT=$loop_count"
        echo "DEVICES_ID=$devices_id"
        echo "DEVICES_CORE=$devices_core"
        echo "SEQ_LEN=$seq_len"
        echo "NEW_TOKENS=$new_tokens"
        echo "START_TIME=$(date)"
        echo "TASK_ID=$task_id"
        echo "STATUS=RUNNING"
    } > "$task_info_file"

    # Execute the test command in background
    {
        echo "=== Starting background test: $model_name ($model_type) ==="
        echo "Start time: $(date)"
        echo "Parameters: Loops=$loop_count, Device ID=$devices_id, Device Core=$devices_core"
        if [[ "$model_type" == "llm" ]]; then
            echo "Additional parameters: Seq Len=$seq_len, New Tokens=$new_tokens"
        fi
        echo

        local test_result
        case "$model_type" in
            "llm")
                # 在执行LLM测试命令前打印完整命令
                echo "Command to execute:"
                echo "./rknn3_llm_test.sh $model_path/$model_name $seq_len $new_tokens 0 $loop_count $devices_id $devices_core"
                echo
                ./rknn3_llm_test.sh $model_path/$model_name $seq_len $new_tokens 0 $loop_count $devices_id $devices_core
                test_result=$?
                ;;
            "cnn")
                # 在执行CNN测试命令前打印完整命令
                echo "Command to execute:"
                echo "./rknn3_cnn_test.sh $model_path/$model_name 0 $loop_count $devices_id $devices_core"
                echo
                ./rknn3_cnn_test.sh $model_path/$model_name 0 $loop_count $devices_id $devices_core
                test_result=$?
                ;;
            "vlm")
                # 在执行VLM测试命令前打印完整命令
                echo "Command to execute:"
                echo "./rknn3_vlm_test.sh $model_path/$model_name 0 $loop_count $devices_id $devices_core"
                echo
                ./rknn3_vlm_test.sh $model_path/$model_name 0 $loop_count $devices_id $devices_core
                test_result=$?
                ;;
        esac

        echo
        echo "=== Test completed: $model_name ($model_type) ==="
        echo "End time: $(date)"
        echo "Exit code: $test_result"

        # Update task info with result - 使用追加模式确保所有信息都被写入
        {
            echo "EXIT_CODE=$test_result"
            echo "END_TIME=$(date)"
            echo "STATUS=COMPLETED"
            if [ $test_result -eq 0 ]; then
                echo "RESULT=SUCCESS"
            else
                echo "RESULT=FAILED"
            fi
        } >> "$task_info_file"

    } > "$task_log" 2>&1 &

    local pid=$!

    # 创建PID文件
    echo "$pid" > "$task_pid_file"
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Failed to create PID file: $task_pid_file${NC}"
        # 杀死后台进程
        kill $pid 2>/dev/null
        return 1
    fi

    BACKGROUND_TASKS["$task_id"]=$pid

    echo -e "${GREEN}Background task started successfully!${NC}"
    echo -e "Task ID: ${CYAN}$task_id${NC}"
    echo -e "PID: ${CYAN}$pid${NC}"
    echo -e "Log file: ${CYAN}$task_log${NC}"

    log_message "Background task started: $task_id - Model: $model_name, Type: $model_type, PID: $pid"

    return 0
}

# Check running background tasks only
check_running_background_tasks() {
    echo -e "${CYAN}Currently Running Background Tasks${NC}"
    echo "========================================"

    # 确保目录存在
    mkdir -p "$BACKGROUND_TASKS_DIR"

    local task_files=("$BACKGROUND_TASKS_DIR"/*.info)
    if [[ ${#task_files[@]} -eq 1 && "${task_files[0]}" == "$BACKGROUND_TASKS_DIR/*.info" ]]; then
        echo -e "${YELLOW}No background tasks found.${NC}"
        return
    fi

    local running_count=0

    for info_file in "${task_files[@]}"; do
        if [[ ! -f "$info_file" ]]; then
            continue
        fi

        # Source the info file to get variables
        local model_name="" model_type="" start_time="" status="" exit_code="" end_time="" task_id=""
        source "$info_file" 2>/dev/null || continue

        # Get PID file
        local pid_file="$BACKGROUND_TASKS_DIR/${task_id}.pid"
        local pid=""
        if [[ -f "$pid_file" ]]; then
            pid=$(cat "$pid_file" 2>/dev/null)
        fi

        # Check if process is still running
        if [[ -n "$pid" ]] && ps -p "$pid" > /dev/null 2>&1; then
            status="RUNNING"
            ((running_count++))
            echo -e "${GREEN}[RUNNING]${NC} $model_name ($model_type)"
            echo "  PID: $pid | Started: $start_time"
            echo "  Task ID: $task_id"
            echo "----------------------------------------"
        fi
    done

    if [[ $running_count -eq 0 ]]; then
        echo -e "${YELLOW}No running background tasks found.${NC}"
    else
        echo -e "${GREEN}Total running tasks: $running_count${NC}"
    fi
}

# View historical background task results - FIXED VERSION
view_historical_background_tasks() {
    echo -e "${CYAN}Historical Background Task Results${NC}"
    echo "========================================"

    # 确保目录存在
    mkdir -p "$BACKGROUND_TASKS_DIR"

    local task_files=("$BACKGROUND_TASKS_DIR"/*.info)
    if [[ ${#task_files[@]} -eq 1 && "${task_files[0]}" == "$BACKGROUND_TASKS_DIR/*.info" ]]; then
        echo -e "${YELLOW}No historical background tasks found.${NC}"
        return
    fi

    local running_count=0
    local success_count=0
    local failed_count=0
    local interrupted_count=0

    for info_file in "${task_files[@]}"; do
        if [[ ! -f "$info_file" ]]; then
            continue
        fi

        # 从文件名获取task_id
        local task_id=$(basename "$info_file" .info)
        local model_name="" model_type="" start_time="" STATUS="" EXIT_CODE="" end_time="" RESULT=""

        # Source the info file to get variables
        if source "$info_file" 2>/dev/null; then
            # 如果source成功，使用文件中的变量
            : # 变量已设置
        else
            # 如果source失败，状态未知
            STATUS="UNKNOWN"
        fi

        # 获取PID并检查进程是否运行
        local pid_file="$BACKGROUND_TASKS_DIR/${task_id}.pid"
        local pid=""
        if [[ -f "$pid_file" ]]; then
            pid=$(cat "$pid_file" 2>/dev/null)
        fi

        local current_status="UNKNOWN"
        local display_status="UNKNOWN"

        # 检查进程是否实际运行
        if [[ -n "$pid" ]] && ps -p "$pid" > /dev/null 2>&1; then
            current_status="RUNNING"
            display_status="RUNNING"
            ((running_count++))
        else
            # 进程不在运行，检查记录的状态
            if [[ "$STATUS" == "COMPLETED" ]]; then
                if [[ "$RESULT" == "SUCCESS" ]] || [[ "${EXIT_CODE:-1}" -eq 0 ]]; then
                    current_status="SUCCESS"
                    display_status="SUCCESS"
                    ((success_count++))
                else
                    current_status="FAILED"
                    display_status="FAILED"
                    ((failed_count++))
                fi
            else
                # 状态不是COMPLETED，但进程已结束，可能是被中断
                current_status="INTERRUPTED"
                display_status="INTERRUPTED"
                ((interrupted_count++))
            fi
        fi

        # 显示Task ID和状态
        case "$display_status" in
            "RUNNING")
                echo -e "${YELLOW}Task ID: $task_id, Status: RUNNING${NC}"
                ;;
            "SUCCESS")
                echo -e "${GREEN}Task ID: $task_id, Status: SUCCESS${NC}"
                ;;
            "FAILED")
                echo -e "${RED}Task ID: $task_id, Status: FAILED${NC}"
                ;;
            "INTERRUPTED")
                echo -e "${RED}Task ID: $task_id, Status: INTERRUPTED${NC}"
                ;;
            *)
                echo -e "${RED}Task ID: $task_id, Status: UNKNOWN${NC}"
                ;;
        esac
    done

    echo "========================================"
    echo -e "${GREEN}Success: $success_count${NC}, ${RED}Failed: $failed_count${NC}, ${YELLOW}Running: $running_count${NC}, ${RED}Interrupted: $interrupted_count${NC}"
}

# Clear background task records
clear_background_tasks() {
    echo -e "${CYAN}Clearing Background Task Records${NC}"
    echo "========================================"

    # 确保目录存在
    mkdir -p "$BACKGROUND_TASKS_DIR"

    local task_files=("$BACKGROUND_TASKS_DIR"/*.info)
    if [[ ${#task_files[@]} -eq 1 && "${task_files[0]}" == "$BACKGROUND_TASKS_DIR/*.info" ]]; then
        echo -e "${YELLOW}No background task records found to clear.${NC}"
        return
    fi

    local count=0
    for info_file in "${task_files[@]}"; do
        if [[ ! -f "$info_file" ]]; then
            continue
        fi

        # Get task ID from filename
        local task_id=$(basename "$info_file" .info)
        local pid_file="$BACKGROUND_TASKS_DIR/${task_id}.pid"
        local log_file="$BACKGROUND_TASKS_DIR/${task_id}.log"

        # Check if task is still running
        local pid=""
        if [[ -f "$pid_file" ]]; then
            pid=$(cat "$pid_file" 2>/dev/null)
        fi

        if [[ -n "$pid" ]] && ps -p "$pid" > /dev/null 2>&1; then
            echo -e "${YELLOW}Skipping running task: $task_id (PID: $pid)${NC}"
            continue
        fi

        # Remove task files
        rm -f "$info_file" "$pid_file" "$log_file" 2>/dev/null
        if [ $? -eq 0 ]; then
            ((count++))
            echo -e "${GREEN}Removed task: $task_id${NC}"
        else
            echo -e "${RED}Failed to remove task: $task_id${NC}"
        fi
    done

    echo -e "${GREEN}Cleared $count background task records.${NC}"
    log_message "Cleared $count background task records"
}

# ============================================================================
# Background Tasks Management Menu
# ============================================================================

background_tasks_management_menu() {
    while true; do
        show_test_header
        echo -e "${PURPLE}Background Tasks Management${NC}"
        echo "========================================"
        echo "1. View Running Background Tasks"
        echo "2. View Historical Background Task Results"
        echo "3. Clear Task Records"
        echo "4. Return to Main Menu"
        echo

        read -rp "Please select an option (1-4): " choice

        case $choice in
            1)
                check_running_background_tasks
                wait_return
                ;;
            2)
                view_historical_background_tasks
                wait_return
                ;;
            3)
                echo -e "${YELLOW}Are you sure you want to clear all completed background task records?${NC}"
                echo "This will remove all task history files but will NOT stop running tasks."
                echo "1. Yes, clear all completed task records"
                echo "2. No, return to menu"
                read -rp "Please select (1-2): " clear_choice

                if [[ "$clear_choice" == "1" ]]; then
                    clear_background_tasks
                else
                    echo -e "${YELLOW}Clear operation cancelled.${NC}"
                fi
                wait_return
                ;;
            4)
                return
                ;;
            *)
                echo -e "${RED}Invalid selection, please enter 1-4${NC}"
                wait_return
                ;;
        esac
    done
}

# ============================================================================
# Generic testing framework
# ============================================================================

# Generic model testing function
test_model() {
    local model_name="$1"
    local model_type="$2"
    local model_path="$3"
    local run_in_background="${4:-false}"  # Default to foreground execution

    show_test_start "$model_type" "$model_name"

    if [[ "$run_in_background" == "true" ]]; then
        echo -e "${YELLOW}This test will run in background.${NC}"
        echo "You can continue using the menu while it runs."
        echo "Check 'Background Tasks Management' menu for status."
    else
        echo "Executing ${model_name} model test in foreground..."
    fi

    # Get user input
    get_loop
    get_devices_id
    get_devices_core
    echo "Number of loops: $LOOP"
    echo "Device ID: $DEVICES_ID"
    echo "Device core: $DEVICES_CORE"

    # Additional parameters for LLM
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

    # Execute test based on background flag
    if [[ "$run_in_background" == "true" ]]; then
        # Start background task
        if start_background_test "$model_name" "$model_type" "$model_path" "$LOOP" "$DEVICES_ID" "$DEVICES_CORE" "$seq_len" "$new_tokens"; then
            log_message "Started background test: $model_name ($model_type)"
        else
            echo -e "${RED}Failed to start background task for $model_name${NC}"
            log_message "Failed to start background test: $model_name ($model_type)"
        fi
    else
        # Execute in foreground
        echo -e "${CYAN}Executing $model_type test command...${NC}"

        local test_result
        case "$model_type" in
            "llm")
                # 在执行LLM测试命令前打印完整命令
                echo -e "${YELLOW}Command to execute:${NC}"
                echo -e "${GREEN}./rknn3_llm_test.sh $model_path/$model_name $seq_len $new_tokens 0 $LOOP $DEVICES_ID $DEVICES_CORE${NC}"
                echo
                ./rknn3_llm_test.sh $model_path/$model_name $seq_len $new_tokens 0 $LOOP $DEVICES_ID $DEVICES_CORE
                test_result=$?
                ;;
            "cnn")
                # 在执行CNN测试命令前打印完整命令
                echo -e "${YELLOW}Command to execute:${NC}"
                echo -e "${GREEN}./rknn3_cnn_test.sh $model_path/$model_name 0 $LOOP $DEVICES_ID $DEVICES_CORE${NC}"
                echo
                ./rknn3_cnn_test.sh $model_path/$model_name 0 $LOOP $DEVICES_ID $DEVICES_CORE
                test_result=$?
                ;;
            "vlm")
                # 在执行VLM测试命令前打印完整命令
                echo -e "${YELLOW}Command to execute:${NC}"
                echo -e "${GREEN}./rknn3_vlm_test.sh $model_path/$model_name 0 $LOOP $DEVICES_ID $DEVICES_CORE${NC}"
                echo
                ./rknn3_vlm_test.sh $model_path/$model_name 0 $LOOP $DEVICES_ID $DEVICES_CORE
                test_result=$?
                ;;
            *)
                echo -e "${RED}Unknown model type: $model_type${NC}"
                show_test_result 1 "$model_name"
                wait_return
                return 1
                ;;
        esac

        # Check command execution result
        if [ $test_result -eq 0 ]; then
            show_test_result 0 "$model_name"
            log_message "$model_name test completed - Loops: $LOOP, Device ID: $DEVICES_ID, Device Core: $DEVICES_CORE, Seq Len: $seq_len, New Tokens: $new_tokens"
        else
            show_test_result 1 "$model_name"
            log_message "$model_name test failed - Exit code: $test_result"
        fi
    fi

    wait_return
}

# Generic model testing function with parameters (for loop testing)
test_model_with_params() {
    local model_name="$1"
    local model_type="$2"
    local model_path="$3"
    local loop_count="$4"
    local devices_id="$5"
    local devices_core="$6"
    local seq_len="$7"
    local new_tokens="$8"

    show_test_start "$model_type" "$model_name"
    echo "Executing ${model_name} model test with parameters:"
    echo "Number of loops: $loop_count"
    echo "Device ID: $devices_id"
    echo "Device core: $devices_core"

    if [[ "$model_type" == "llm" ]]; then
        echo "Sequence length (seq_len): $seq_len"
        echo "New tokens to generate: $new_tokens"
    fi

    # Execute different test commands based on model type
    case "$model_type" in
        "llm")
            # 在执行LLM测试命令前打印完整命令
            echo -e "${YELLOW}Command to execute:${NC}"
            echo -e "${GREEN}./rknn3_llm_test.sh $model_path/$model_name $seq_len $new_tokens 0 $loop_count $devices_id $devices_core${NC}"
            echo
            ./rknn3_llm_test.sh $model_path/$model_name $seq_len $new_tokens 0 $loop_count $devices_id $devices_core
            ;;
        "cnn")
            # 在执行CNN测试命令前打印完整命令
            echo -e "${YELLOW}Command to execute:${NC}"
            echo -e "${GREEN}./rknn3_cnn_test.sh $model_path/$model_name 0 $loop_count $devices_id $devices_core${NC}"
            echo
            ./rknn3_cnn_test.sh $model_path/$model_name 0 $loop_count $devices_id $devices_core
            ;;
        "vlm")
            # 在执行VLM测试命令前打印完整命令
            echo -e "${YELLOW}Command to execute:${NC}"
            echo -e "${GREEN}./rknn3_vlm_test.sh $model_path/$model_name 0 $loop_count $devices_id $devices_core${NC}"
            echo
            ./rknn3_vlm_test.sh $model_path/$model_name 0 $loop_count $devices_id $devices_core
            ;;
        *)
            echo -e "${RED}Unknown model type: $model_type${NC}"
            show_test_result 1 "$model_name"
            return 1
            ;;
    esac

    # Check command execution result
    local test_result=$?
    if [ $test_result -eq 0 ]; then
        show_test_result 0 "$model_name"
        if [[ "$model_type" == "llm" ]]; then
            log_message "$model_name test completed - Loops: $loop_count, Device ID: $devices_id, Device Core: $devices_core, Seq Len: $seq_len, New Tokens: $new_tokens"
        else
            log_message "$model_name test completed - Loops: $loop_count, Device ID: $devices_id, Device Core: $devices_core"
        fi
    else
        show_test_result 1 "$model_name"
        log_message "$model_name test failed - Exit code: $test_result"
    fi

    return $test_result
}

# ============================================================================
# Performance Report Generation Functions
# ============================================================================

# Generate Comprehensive Performance Report
generate_performance_report() {
    local performance_dir="$1"
    local total_models="$2"
    local successful_tests="$3"
    local failed_tests="$4"

    local report_file="$performance_dir/Performance_Report_$(date +%Y%m%d_%H%M%S).txt"

    echo
    echo -e "${CYAN}Generating Performance Report...${NC}"
    echo -e "Report File: $report_file"

    # Create report file and start writing
    {
        echo "================================================"
        echo "           AI Co-processor Performance Test Report"
        echo "================================================"
        echo "Generation Time: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Report File: $report_file"
        echo

        # Add RKNN-SMI version information
        echo "=== RKNN-SMI Version Information ==="
        if command -v rknn-smi &> /dev/null; then
            rknn-smi --version 2>/dev/null
        else
            echo "rknn-smi command not found"
        fi
        echo

        # Test Summary
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

        # Test Parameters
        echo "=== Test Parameters ==="
        echo "Loop Count: $LOOP"
        echo "Device ID: $DEVICES_ID"
        echo "Device Core: $DEVICES_CORE"
        echo

        # CNN Model Performance Analysis
        if [[ -f "$performance_dir/cnn.log" ]] && [[ -s "$performance_dir/cnn.log" ]]; then
            echo "=== CNN Model Performance Analysis ==="
            analyze_cnn_performance "$performance_dir/cnn.log"
            echo
        else
            echo "=== CNN Model Performance Analysis ==="
            echo "No CNN model performance data"
            echo
        fi

        # LLM Model Performance Analysis
        if [[ -f "$performance_dir/llm.log" ]] && [[ -s "$performance_dir/llm.log" ]]; then
            echo "=== LLM Model Performance Analysis ==="
            analyze_llm_performance "$performance_dir/llm.log"
            echo
        else
            echo "=== LLM Model Performance Analysis ==="
            echo "No LLM model performance data"
            echo
        fi

        # VLM Model Performance Analysis
        if [[ -f "$performance_dir/vlm.log" ]] && [[ -s "$performance_dir/vlm.log" ]]; then
            echo "=== VLM Model Performance Analysis ==="
            analyze_vlm_performance "$performance_dir/vlm.log"
            echo
        else
            echo "=== VLM Model Performance Analysis ==="
            echo "No VLM model performance data"
            echo
        fi

        # Performance Comparison Summary
        echo "=== Performance Comparison Summary ==="
        generate_performance_comparison "$performance_dir" "$total_models" "$successful_tests" "$failed_tests"
        echo

        echo "================================================"
        echo "              Report Generation Completed"
        echo "================================================"

    } > "$report_file"

    # Display report generation success message
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

# CNN Model Performance Analysis
analyze_cnn_performance() {
    local cnn_log="$1"

    if [[ ! -f "$cnn_log" ]] || [[ ! -s "$cnn_log" ]]; then
        echo "No CNN performance data"
        return
    fi

    # Count number of models
    local model_count=$(grep -c "^cnn:" "$cnn_log")
    echo "CNN Model Count: $model_count"
    echo

    # Display each model's performance data
    echo "Individual Model Performance Data:"
    echo "------------------------------------------------"

    # Use awk to parse performance data
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

    # Calculate performance statistics
    local avg_fps=$(awk '/^fps:/ {sum += $2; count++} END {if (count>0) printf "%.2f", sum/count}' "$cnn_log" 2>/dev/null || echo "N/A")
    local max_fps=$(awk 'BEGIN{max=0} /^fps:/ {if ($2 > max) max = $2} END {print max+0}' "$cnn_log" 2>/dev/null || echo "N/A")
    local min_fps=$(awk 'BEGIN{min=999999} /^fps:/ {if ($2 < min) min = $2} END {print min+0}' "$cnn_log" 2>/dev/null || echo "N/A")
    local best_model=$(awk '/^fps:/ {fps=$2} /^model:/ {model=$2} {if (fps == '"$max_fps"') {print model; exit}}' "$cnn_log" 2>/dev/null || echo "N/A")

    echo
    echo "Performance Statistics:"
    echo "Average FPS: ${avg_fps}"
    echo "Maximum FPS: ${max_fps} (Model: ${best_model})"
    echo "Minimum FPS: ${min_fps}"
    if [[ "$max_fps" != "N/A" ]] && [[ "$min_fps" != "N/A" ]]; then
        local fps_range=$((max_fps - min_fps))
        echo "FPS Range: $fps_range"
    fi
}

# LLM Model Performance Analysis
analyze_llm_performance() {
    local llm_log="$1"

    if [[ ! -f "$llm_log" ]] || [[ ! -s "$llm_log" ]]; then
        echo "No LLM performance data"
        return
    fi

    # Count number of models
    local model_count=$(grep -c "^llm:" "$llm_log")
    echo "LLM Model Count: $model_count"
    echo

    # Display each model's performance data
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

    # Calculate performance statistics - FIXED: Use awk for all calculations to avoid bash arithmetic errors
    local avg_ttft=$(awk '/^TTFT:/ {gsub(/[^0-9.]/, "", $2); sum += $2; count++} END {if (count>0) printf "%.2f", sum/count; else print "N/A"}' "$llm_log" 2>/dev/null)
    local avg_tps=$(awk '/^TPS:/ {gsub(/[^0-9.]/, "", $2); sum += $2; count++} END {if (count>0) printf "%.2f", sum/count; else print "N/A"}' "$llm_log" 2>/dev/null)
    local max_tps=$(awk 'BEGIN{max=0} /^TPS:/ {gsub(/[^0-9.]/, "", $2); if ($2+0 > max+0) max=$2+0} END {if (max>0) printf "%.2f", max; else print "N/A"}' "$llm_log" 2>/dev/null)

    # Use awk to find the best model to avoid bash arithmetic issues
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

# VLM Model Performance Analysis
analyze_vlm_performance() {
    local vlm_log="$1"

    if [[ ! -f "$vlm_log" ]] || [[ ! -s "$vlm_log" ]]; then
        echo "No VLM performance data"
        return
    fi

    # Count number of models
    local model_count=$(grep -c "^vlm:" "$vlm_log")
    echo "VLM Model Count: $model_count"
    echo

    # Display each model's performance data
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

    # Calculate performance statistics - FIXED: Use awk for all calculations
    local avg_ttft=$(awk '/^TTFT:/ {gsub(/[^0-9.]/, "", $2); sum += $2; count++} END {if (count>0) printf "%.2f", sum/count; else print "N/A"}' "$vlm_log" 2>/dev/null)
    local avg_tps=$(awk '/^TPS:/ {gsub(/[^0-9.]/, "", $2); sum += $2; count++} END {if (count>0) printf "%.2f", sum/count; else print "N/A"}' "$vlm_log" 2>/dev/null)
    local max_tps=$(awk 'BEGIN{max=0} /^TPS:/ {gsub(/[^0-9.]/, "", $2); if ($2+0 > max+0) max=$2+0} END {if (max>0) printf "%.2f", max; else print "N/A"}' "$vlm_log" 2>/dev/null)

    # Use awk to find the best model
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

# CNN Model Performance Analysis
analyze_cnn_performance() {
    local cnn_log="$1"

    if [[ ! -f "$cnn_log" ]] || [[ ! -s "$cnn_log" ]]; then
        echo "No CNN performance data"
        return
    fi

    # Count number of models
    local model_count=$(grep -c "^cnn:" "$cnn_log")
    echo "CNN Model Count: $model_count"
    echo

    # Display each model's performance data
    echo "Individual Model Performance Data:"
    echo "------------------------------------------------"

    # Use awk to parse performance data
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

    # Calculate performance statistics - FIXED: Use proper awk formatting
    local avg_fps=$(awk '/^fps:/ {sum += $2; count++} END {if (count>0) printf "%.2f", sum/count; else print "N/A"}' "$cnn_log" 2>/dev/null)
    local max_fps=$(awk 'BEGIN{max=0} /^fps:/ {if ($2 > max) max = $2} END {if (max>0) printf "%.2f", max; else print "N/A"}' "$cnn_log" 2>/dev/null)
    local min_fps=$(awk 'BEGIN{min=999999} /^fps:/ {if ($2 < min) min = $2} END {if (min<999999) printf "%.2f", min; else print "N/A"}' "$cnn_log" 2>/dev/null)

    # Use awk to find the best model
    local best_model=$(awk '
    /^fps:/ {
        current_fps = $2+0;
        if (current_fps > max_fps) {
            max_fps = current_fps;
            best_model = "";
        }
    }
    /^model:/ {
        if (best_model == "" && max_fps > 0) {
            best_model = $2;
        }
    }
    END {
        if (best_model != "") print best_model;
        else print "N/A";
    }' "$cnn_log" 2>/dev/null)

    echo
    echo "Performance Statistics:"
    echo "Average FPS: ${avg_fps}"
    echo "Maximum FPS: ${max_fps} (Model: ${best_model})"
    echo "Minimum FPS: ${min_fps}"

    # Calculate FPS range only if both values are numeric
    if [[ "$max_fps" != "N/A" ]] && [[ "$min_fps" != "N/A" ]] && [[ "$max_fps" =~ ^[0-9.]+$ ]] && [[ "$min_fps" =~ ^[0-9.]+$ ]]; then
        # Use bc for floating point arithmetic
        local fps_range=$(echo "$max_fps - $min_fps" | bc 2>/dev/null || echo "N/A")
        echo "FPS Range: $fps_range"
    else
        echo "FPS Range: N/A"
    fi
}

# Generate Performance Comparison Summary
generate_performance_comparison() {
    local performance_dir="$1"
    local total_models="$2"
    local successful_tests="$3"
    local failed_tests="$4"

    echo "Performance Comparison Summary:"
    echo "------------------------------------------------"

    # Count models by type
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

    # Performance metrics comparison
    echo "Best Performance Model Comparison:"
    echo "------------------------------------------------"

    # CNN performance comparison
    if [[ $cnn_count -gt 0 ]]; then
        local best_cnn_fps=$(awk 'BEGIN{max=0} /^fps:/ {if ($2 > max) max = $2} END {print max+0}' "$performance_dir/cnn.log" 2>/dev/null || echo "N/A")
        local best_cnn_model=$(awk '/^fps:/ {fps=$2} /^model:/ {model=$2} {if (fps == '"$best_cnn_fps"') {print model; exit}}' "$performance_dir/cnn.log" 2>/dev/null || echo "N/A")
        echo "CNN Highest FPS: $best_cnn_fps (Model: $best_cnn_model)"
    fi

    # LLM performance comparison
    if [[ $llm_count -gt 0 ]]; then
        local best_llm_tps=$(awk 'BEGIN{max=0} /^TPS:/ {gsub(/[^0-9.]/, "", $2); if ($2 > max) max = $2} END {print max+0}' "$performance_dir/llm.log" 2>/dev/null || echo "N/A")
        local best_llm_model=$(awk '/^TPS:/ {gsub(/[^0-9.]/, "", $2); tps=$2} /^model:/ {model=$2} {if (tps == '"$best_llm_tps"') {print model; exit}}' "$performance_dir/llm.log" 2>/dev/null || echo "N/A")
        echo "LLM Highest TPS: $best_llm_tps tokens/s (Model: $best_llm_model)"
    fi

    # VLM performance comparison
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
        echo "Overall Status: Some tests failed, please check logs ✗"
    fi
    echo "Recommendation: Evaluate model suitability based on specific performance data"
}

# ============================================================================
# Loop testing functionality
# ============================================================================

# Loop test all available models
loop_test_all_models() {
    show_test_header
    echo -e "${PURPLE}Loop Test All Models${NC}"
    echo "Scanning ../ directory for all available models..."
    echo

    local performance_dir="$TEST_RESULTS_DIR/performance"
    rm -rf "$performance_dir"
    mkdir -p "$performance_dir"
    echo -e "${GREEN}The performance data directory has been created: $performance_dir${NC}"
    echo

    # Declare array to store all found models
    declare -A all_models

    # Scan for all model directories
    if ! scan_all_model_directories all_models; then
        echo -e "${YELLOW}No models found in ../ directory!${NC}"
        echo
        echo -e "${BLUE}Please ensure:${NC}"
        echo "1. Model directories are placed in the parent directory (../)"
        echo "2. Directory names match expected patterns"
        echo "3. Model files exist in the directories"
        wait_return
        return 1
    fi

    # Display found models
    echo -e "${GREEN}Found ${#all_models[@]} models:${NC}"
    local count=0
    for index in $(echo "${!all_models[@]}" | tr ' ' '\n' | sort -n); do
        ((count++))
        local model_info=(${all_models[$index]})
        echo "$count. ${model_info[0]} (${model_info[1]})"
    done
    echo

    # Get test parameters - MODIFIED: Remove get_devices_core, device core will be set per model type
    echo -e "${CYAN}Setting test parameters for all models:${NC}"
    get_loop
    get_devices_id
    # Device core will be set per model type in the loop below
    echo "Note: Device core will be set automatically based on model type (0x01 for CNN, 0xff for LLM/VLM)"

    local llm_seq_len=512
    local llm_new_tokens=512

    # Check if we have LLM models
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

    # Ask for execution mode
    # echo
    # echo -e "${CYAN}Select execution mode:${NC}"
    # echo "1. Sequential execution (one after another)"
    # echo "2. Background execution (all tests run concurrently)"
    # read -rp "Please select execution mode (1-2): " exec_mode

    # local run_in_background="false"
    # if [[ "$exec_mode" == "2" ]]; then
    #     run_in_background="true"
    #     echo -e "${YELLOW}All tests will run concurrently in background.${NC}"
    # fi
    local run_in_background="false"

    # Confirm test execution
    echo
    echo -e "${RED}WARNING: This will test all ${#all_models[@]} models with the following parameters:${NC}"
    echo "Loops: $LOOP"
    echo "Device ID: $DEVICES_ID"
    echo "Device Core: Auto-set (0x01 for CNN, 0xff for LLM/VLM)"
    if [[ "$has_llm" == true ]]; then
        echo "LLM Sequence Length: $llm_seq_len"
        echo "LLM New Tokens: $llm_new_tokens"
    fi
    echo "Execution mode: $( [[ "$run_in_background" == "true" ]] && echo "Concurrent" || echo "Sequential" )"
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

    # Start loop testing
    echo
    echo -e "${GREEN}Starting loop testing of all models...${NC}"
    log_message "=== Starting loop testing of all models ==="
    log_message "Parameters - Loops: $LOOP, Device ID: $DEVICES_ID, Device Core: Auto-set, LLM Seq Len: $llm_seq_len, LLM New Tokens: $llm_new_tokens"
    log_message "Execution mode: $( [[ "$run_in_background" == "true" ]] && echo "Concurrent" || echo "Sequential" )"

    local total_models=${#all_models[@]}
    local current_model=0
    local successful_tests=0
    local failed_tests=0

    if [[ "$run_in_background" == "true" ]]; then
        # Start all tests concurrently in background
        for index in $(echo "${!all_models[@]}" | tr ' ' '\n' | sort -n); do
            ((current_model++))
            local model_info=(${all_models[$index]})
            local model_name="${model_info[0]}"
            local model_type="${model_info[1]}"
            local model_path=$(get_model_path "$model_name" "$model_type")

            # MODIFIED: Set device core based on model type
            local devices_core="0xff"  # Default for LLM/VLM
            if [[ "$model_type" == "cnn" ]]; then
                devices_core="0x01"  # CNN uses 0x01
            fi

            echo
            echo -e "${BLUE}========================================${NC}"
            echo -e "${GREEN}Starting background test for model $current_model of $total_models${NC}"
            echo -e "${GREEN}Model: $model_name ($model_type)${NC}"
            echo -e "${BLUE}========================================${NC}"

            # Validate model path exists
            if [[ ! -e "$model_path" ]] && [[ ! -e "$model_path.rknn" ]] && [[ -z "$(ls "$model_path"/*.rknn 2>/dev/null)" ]]; then
                echo -e "${RED}Model files not found for $model_name!${NC}"
                echo "Expected path: $model_path"
                echo "Skipping this model."
                ((failed_tests++))
                log_message "$model_name test skipped - Model files not found"
                continue
            fi

            # Start background test with model-specific device core
            if [[ "$model_type" == "llm" ]]; then
                if start_background_test "$model_name" "$model_type" "$model_path" "$LOOP" "$DEVICES_ID" "$devices_core" "$llm_seq_len" "$llm_new_tokens"; then
                    ((successful_tests++))
                else
                    ((failed_tests++))
                fi
            else
                if start_background_test "$model_name" "$model_type" "$model_path" "$LOOP" "$DEVICES_ID" "$devices_core" "512" "512"; then
                    ((successful_tests++))
                else
                    ((failed_tests++))
                fi
            fi

            # Small delay between starting tasks to avoid resource contention
            sleep 1
        done

        echo
        echo -e "${GREEN}All $total_models tests started in background!${NC}"
        echo -e "${YELLOW}Use 'Background Tasks Management' menu to monitor progress.${NC}"

    else
        # Sequential execution (original behavior)
        for index in $(echo "${!all_models[@]}" | tr ' ' '\n' | sort -n); do
            ((current_model++))
            local model_info=(${all_models[$index]})
            local model_name="${model_info[0]}"
            local model_type="${model_info[1]}"
            local model_path=$(get_model_path "$model_name" "$model_type")

            # MODIFIED: Set device core based on model type
            local devices_core="0xff"  # Default for LLM/VLM
            if [[ "$model_type" == "cnn" ]]; then
                devices_core="0x01"  # CNN uses 0x01
            fi

            echo
            echo -e "${BLUE}========================================${NC}"
            echo -e "${GREEN}Testing model $current_model of $total_models${NC}"
            echo -e "${GREEN}Model: $model_name ($model_type)${NC}"
            echo -e "${BLUE}========================================${NC}"

            # Validate model path exists
            if [[ ! -e "$model_path" ]] && [[ ! -e "$model_path.rknn" ]] && [[ -z "$(ls "$model_path"/*.rknn 2>/dev/null)" ]]; then
                echo -e "${RED}Model files not found for $model_name!${NC}"
                echo "Expected path: $model_path"
                echo "Skipping this model."
                ((failed_tests++))
                log_message "$model_name test skipped - Model files not found"
                continue
            fi

            # Test the model with appropriate parameters and model-specific device core
            local test_result
            if [[ "$model_type" == "llm" ]]; then
                test_model_with_params "$model_name" "$model_type" "$model_path" "$LOOP" "$DEVICES_ID" "$devices_core" "$llm_seq_len" "$llm_new_tokens"
            else
                test_model_with_params "$model_name" "$model_type" "$model_path" "$LOOP" "$DEVICES_ID" "$devices_core" "512" "512"
            fi

            test_result=$?
            if [ $test_result -eq 0 ]; then
                ((successful_tests++))
            else
                ((failed_tests++))
            fi

            # Small delay between tests
            sleep 2
        done

        # Display summary for sequential execution
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
    fi

    log_message "=== Loop testing completed ==="
    if [[ "$run_in_background" != "true" ]]; then
        log_message "Summary - Total: $total_models, Successful: $successful_tests, Failed: $failed_tests"
    fi
    generate_performance_report "$performance_dir" "$total_models" "$successful_tests" "$failed_tests"
    wait_return
}

# ============================================================================
# Dynamic menu generation functions
# ============================================================================

# Generic dynamic menu generation function - FIXED VERSION
generate_test_menu() {
    local menu_type="$1"
    local menu_title="$2"
    local color="$3"

    while true; do
        show_test_header
        echo -e "${color}${menu_title} Options:${NC}"
        echo "Scanning ../ directory for ${menu_type} models..."
        echo

        # Declare array to store found models
        declare -A found_models

        # Scan for model directories
        if ! scan_model_directories "$menu_type" found_models; then
            echo -e "${YELLOW}No ${menu_type} models found in ../ directory!${NC}"
            echo
            echo -e "${BLUE}Please ensure:${NC}"
            echo "1. Model directories are placed in the parent directory (../)"
            echo "2. Directory names match expected patterns"
            echo "3. Model files exist in the directories"
            echo
            echo "1. Rescan directories"
            echo "2. Return to previous menu"
            echo

            read -rp "Please select an option (1-2): " retry_choice

            case $retry_choice in
                1)
                    echo -e "${CYAN}Rescanning directories...${NC}"
                    continue
                    ;;
                2)
                    return
                    ;;
                *)
                    echo -e "${RED}Invalid selection!${NC}"
                    continue
                    ;;
            esac
        fi

        # Display found models with numbering
        local count=0
        for index in $(echo "${!found_models[@]}" | tr ' ' '\n' | sort -n); do
            ((count++))
            echo "$count. ${found_models[$index]}"
        done

        local return_option=$((count + 1))
        echo "$return_option. Return to previous menu"
        echo

        read -rp "Please select a model to test (1-$return_option): " choice

        # Validate input
        if [[ ! "$choice" =~ ^[0-9]+$ ]]; then
            echo -e "${RED}Invalid input, please enter a number!${NC}"
            continue
        fi

        if [[ "$choice" -eq "$return_option" ]]; then
            return
        elif [[ "$choice" -ge 1 && "$choice" -le $count ]]; then
            # Find the selected model name
            local selected_index=0
            for index in $(echo "${!found_models[@]}" | tr ' ' '\n' | sort -n); do
                ((selected_index++))
                if [[ $selected_index -eq $choice ]]; then
                    local model_name="${found_models[$index]}"

                    # FIXED: Use $menu_type instead of undefined $model_type
                    local model_path=$(get_model_path "$model_name" "$menu_type")

                    echo -e "${YELLOW}Debug: Model name: $model_name, Menu type: $menu_type, Model path: $model_path${NC}"

                    # Enhanced path validation
                    local has_model_files=false

                    # Check for model files in various locations
                    if [[ -d "$model_path" ]]; then
                        echo -e "${YELLOW}Debug: Directory exists: $model_path${NC}"
                        if [[ -n "$(find "$model_path" -maxdepth 1 \( -name "*.rknn" -o -name "*.weight" -o -name "*.bin" -o -name "*.gguf" -o -name "*.ini" \) 2>/dev/null)" ]]; then
                            has_model_files=true
                            echo -e "${GREEN}Debug: Found model files in main directory${NC}"
                        elif [[ -d "$model_path/models" ]] && [[ -n "$(find "$model_path/models" -maxdepth 1 \( -name "*.rknn" -o -name "*.weight" -o -name "*.bin" \) 2>/dev/null)" ]]; then
                            has_model_files=true
                            echo -e "${GREEN}Debug: Found model files in models subdirectory${NC}"
                        else
                            echo -e "${YELLOW}Debug: No model files found in: $model_path${NC}"
                            echo "Directory contents:"
                            ls -la "$model_path" 2>/dev/null || echo "Cannot list directory contents"
                        fi
                    elif [[ -e "$model_path.rknn" ]]; then
                        has_model_files=true
                        echo -e "${GREEN}Debug: Found direct .rknn file: $model_path.rknn${NC}"
                    else
                        echo -e "${YELLOW}Debug: Path does not exist: $model_path${NC}"
                    fi

                    if [[ "$has_model_files" != "true" ]]; then
                        echo -e "${RED}Model files not found for $model_name!${NC}"
                        echo "Expected path: $model_path"
                        echo "Please check if the model files exist in the directory."

                        # Debug information
                        echo -e "${YELLOW}Debug information:${NC}"
                        if [[ -d "$model_path" ]]; then
                            echo "Directory exists. Contents:"
                            ls -la "$model_path" 2>/dev/null || echo "Cannot list directory contents"
                            echo
                            echo "Searching for model files..."
                            find "$model_path" -name "*.rknn" -o -name "*.weight" -o -name "*.bin" -o -name "*.gguf" -o -name "*.ini" 2>/dev/null
                        else
                            echo "Path does not exist: $model_path"
                            # Check if direct file exists
                            if [[ -e "$model_path.rknn" ]]; then
                                echo "But found direct file: $model_path.rknn"
                            fi
                        fi

                        wait_return
                        continue
                    fi

                    echo -e "${GREEN}Selected model: $model_name${NC}"
                    echo -e "${BLUE}Model path: $model_path${NC}"

                    # FIXED: Use $menu_type instead of undefined $model_type
                    test_model "$model_name" "$menu_type" "$model_path" "false"
                    break
                fi
            done
        else
            echo -e "${RED}Invalid selection, please enter 1-$return_option${NC}"
        fi
    done
}
# ============================================================================
# Core functionality functions
# ============================================================================

# Logging function
log_message() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" | tee -a "$LOG_FILE"
}

# Display test header information
show_test_header() {
    clear
    echo -e "${GREEN}"
    echo "========================================"
    echo "          AI Coprocessor Test Script"
    echo "          Version $SCRIPT_VERSION "
    echo "========================================"
    echo -e "${NC}"
}

# Wait for user key press to return
wait_return() {
    echo
    echo -e "${YELLOW}Press Enter to return to menu...${NC}"
    read -r
}

# Display test start information
show_test_start() {
    local model_type="$1"
    local model_name="$2"
    echo
    echo -e "${BLUE}========================================${NC}"
    echo -e "${GREEN}Starting $model_type Test${NC}"
    echo -e "${GREEN}Model: $model_name${NC}"
    echo -e "${BLUE}========================================${NC}"
    log_message "Starting test: $model_type - $model_name"
}

# Display test result
show_test_result() {
    local success="$1"
    local model_name="$2"

    if [ "$success" -eq 0 ]; then
        echo -e "${GREEN}✓ $model_name test completed${NC}"
        log_message "$model_name test result: Completed"
    else
        echo -e "${RED}✗ $model_name test failed${NC}"
        log_message "$model_name test result: Failed"
    fi
}

# ============================================================================
# Menu functions
# ============================================================================

# Main menu
main_menu() {
    while true; do
        show_test_header
        echo -e "${GREEN}Main Menu Options:${NC}"
        echo "1. RKNN Test"
        echo "2. View Test Logs"
        echo "3. RKNN-SMI Test"
        echo "4. Exit"
        echo

        read -rp "Please select an operation (1-5): " choice

        case $choice in
            1) rknn_test_menu ;;
            # 2) background_tasks_management_menu ;;
            2) view_test_logs ;;
            3) rknn_smi_test_menu ;;
            4)
                # Check if there are running background tasks
                # 确保目录存在
                mkdir -p "$BACKGROUND_TASKS_DIR"
                local running_tasks=0
                local task_files=("$BACKGROUND_TASKS_DIR"/*.pid)
                for pid_file in "${task_files[@]}"; do
                    if [[ -f "$pid_file" ]] && ps -p "$(cat "$pid_file" 2>/dev/null)" > /dev/null 2>&1; then
                        ((running_tasks++))
                    fi
                done

                if [[ $running_tasks -gt 0 ]]; then
                    echo -e "${YELLOW}WARNING: There are $running_tasks background tasks still running.${NC}"
                    echo -e "${YELLOW}Exiting now will terminate these tasks. Continue?${NC}"
                    echo "1. Yes, exit and stop all tasks"
                    echo "2. No, return to menu"
                    read -rp "Please select (1-2): " exit_choice

                    if [[ "$exit_choice" == "1" ]]; then
                        # Stop all running tasks
                        for pid_file in "${task_files[@]}"; do
                            if [[ -f "$pid_file" ]]; then
                                local pid=$(cat "$pid_file" 2>/dev/null)
                                local task_id=$(basename "${pid_file%.pid}")
                                if [[ -n "$pid" ]] && ps -p "$pid" > /dev/null 2>&1; then
                                    kill "$pid" 2>/dev/null
                                    echo -e "${YELLOW}Stopped task: $task_id${NC}"
                                fi
                            fi
                        done
                        echo -e "${GREEN}Thank you for using the 182x test script, goodbye!${NC}"
                        log_message "Script exited with background tasks stopped"
                        exit 0
                    else
                        continue
                    fi
                else
                    echo -e "${GREEN}Thank you for using the 182x test script, goodbye!${NC}"
                    log_message "Script exited normally"
                    exit 0
                fi
                ;;
            *)
                echo -e "${RED}Invalid selection, please enter 1-4${NC}"
                ;;
        esac
    done
}

# RKNN test main menu
rknn_test_menu() {
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
            1) cnn_test_menu ;;
            2) llm_test_menu ;;
            3) vlm_test_menu ;;
            4) loop_test_all_models ;;
            5) return ;;
            *)
                echo -e "${RED}Invalid selection, please enter 1-5${NC}"
                ;;
        esac
    done
}

# Model-specific test menus using dynamic directory scanning
cnn_test_menu() {
    generate_test_menu "cnn" "CNN Model Validation Test" "${CYAN}"
}

llm_test_menu() {
    generate_test_menu "llm" "LLM Model Validation Test" "${PURPLE}"
}

vlm_test_menu() {
    generate_test_menu "vlm" "VLM Model Validation Test" "${YELLOW}"
}

# ============================================================================
# Log viewing functionality
# ============================================================================

view_test_logs() {
    show_test_header
    echo -e "${CYAN}Test Log Content:${NC}"
    echo "=========================================="

    if [ -f "$LOG_FILE" ]; then
        if [ -s "$LOG_FILE" ]; then
            tail -20 "$LOG_FILE"
        else
            echo "Log file is empty"
        fi
    else
        echo "Log file does not exist"
    fi

    echo "=========================================="
    wait_return
}

# ============================================================================
# Script initialization
# ============================================================================

# Check if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Set signal handling for graceful exit
    trap 'echo -e "\n${RED}Script interrupted by user${NC}"; log_message "Script interrupted by user"; exit 1' INT TERM

    # Display welcome message
    show_test_header
    rm -rf "$BACKGROUND_TASKS_DIR"
    mkdir -p "$BACKGROUND_TASKS_DIR"
    ./install_rknn3_model_stress.sh
    echo -e "${GREEN}Script initialization completed${NC}"
    echo -e "Test results directory: $TEST_RESULTS_DIR"
    echo -e "Background tasks directory: $BACKGROUND_TASKS_DIR"
    echo -e "Log file: $LOG_FILE"
    echo
    log_message "=== Test script started ==="

    # Enter main menu
    main_menu
fi