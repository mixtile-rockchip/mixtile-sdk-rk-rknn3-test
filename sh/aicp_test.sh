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

# Define expected model directories for each type
declare -A EXPECTED_MODELS=(
    ["cnn"]="Dinov3 Siglip2 YOLOv5s YOLOv6s YOLOv8s MobilenetV1 MobilenetV2 Resnet50-v2"
    ["llm"]="Qwen2.5-3B-Instruct Qwen2.5-7B-Instruct Qwen2.5-1.5B-Instruct-core-4"
    ["vlm"]="FasterVLM-llm InternVL3-2B InternVL3_5-4B Qwen2.5-VL-3B Qwen2.5-VL-7B Qwen3-VL-2B Qwen3-VL-4B"
)

# Scan for available model directories
scan_model_directories() {
    local model_type="$1"
    local -n result_array="$2"  # Use nameref to modify the passed array

    # Clear the result array
    result_array=()
    local count=0

    # Get the expected models for this type
    local expected_list="${EXPECTED_MODELS[$model_type]}"

    if [[ -z "$expected_list" ]]; then
        echo -e "${RED}Error: Unknown model type '$model_type'${NC}"
        return 1
    fi

    # Scan the parent directory for expected model directories
    for model_name in $expected_list; do
        if [[ -d "../$model_name" ]]; then
            ((count++))
            result_array["$count"]="$model_name"
        fi
    done

    if [[ $count -eq 0 ]]; then
        return 1
    fi

    return 0
}

# Scan for ALL available model directories (all types) - MODIFIED: Filter out core-* models
scan_all_model_directories() {
    local -n result_array="$1"  # Use nameref to modify the passed array

    # Clear the result array
    result_array=()
    local count=0

    # Scan for each model type
    for model_type in "cnn" "llm" "vlm"; do
        declare -A found_models
        if scan_model_directories "$model_type" found_models; then
            for index in $(echo "${!found_models[@]}" | tr ' ' '\n' | sort -n); do
                local model_name="${found_models[$index]}"
                # Filter out models containing "core-"
                if [[ ! "$model_name" =~ core- ]]; then
                    ((count++))
                    result_array["$count"]="$model_name $model_type"
                fi
            done
        fi
    done

    if [[ $count -eq 0 ]]; then
        return 1
    fi

    return 0
}

# Get the full model path
get_model_path() {
    local model_name="$1"

    # Try different possible path patterns
    local possible_paths=(
        "../$model_name"
    )

    for path in "${possible_paths[@]}"; do
        # Check if path exists as a file, directory, or contains .rknn files
        if [[ -e "$path" ]] || [[ -e "$path.rknn" ]] || [[ -n "$(ls "$path"/*.rknn 2>/dev/null)" ]]; then
            echo "$path"
            return 0
        fi
    done

    # If no specific model file found, return the directory path
    echo "../$model_name"
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
# Loop testing functionality
# ============================================================================

# Loop test all available models
loop_test_all_models() {
    show_test_header
    echo -e "${PURPLE}Loop Test All Models${NC}"
    echo "Scanning ../ directory for all available models..."
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
    echo
    echo -e "${CYAN}Select execution mode:${NC}"
    echo "1. Sequential execution (one after another)"
    echo "2. Background execution (all tests run concurrently)"
    read -rp "Please select execution mode (1-2): " exec_mode

    local run_in_background="false"
    if [[ "$exec_mode" == "2" ]]; then
        run_in_background="true"
        echo -e "${YELLOW}All tests will run concurrently in background.${NC}"
    fi

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
            local model_path=$(get_model_path "$model_name")

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
            local model_path=$(get_model_path "$model_name")

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
    wait_return
}

# ============================================================================
# Dynamic menu generation functions
# ============================================================================

# Generic dynamic menu generation function
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
            echo "2. Directory names match expected patterns: ${EXPECTED_MODELS[$menu_type]}"
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
                    local model_path=$(get_model_path "$model_name")

                    # Validate model path exists
                    if [[ ! -e "$model_path" ]] && [[ ! -e "$model_path.rknn" ]] && [[ -z "$(ls "$model_path"/*.rknn 2>/dev/null)" ]]; then
                        echo -e "${RED}Model files not found for $model_name!${NC}"
                        echo "Expected path: $model_path"
                        echo "Please check if the model files exist in the directory."
                        wait_return
                        continue
                    fi

                    echo -e "${GREEN}Selected model: $model_name${NC}"
                    echo -e "${BLUE}Model path: $model_path${NC}"

                    # Ask for execution mode
                    echo
                    echo -e "${CYAN}Select execution mode:${NC}"
                    echo "1. Run in foreground (wait for completion)"
                    echo "2. Run in background (continue using menu)"
                    read -rp "Please select execution mode (1-2): " exec_choice

                    if [[ "$exec_choice" == "2" ]]; then
                        test_model "$model_name" "$menu_type" "$model_path" "true"
                    else
                        test_model "$model_name" "$menu_type" "$model_path" "false"
                    fi
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
        echo "2. Background Tasks Management"
        echo "3. View Test Logs"
        echo "4. Exit"
        echo

        read -rp "Please select an operation (1-4): " choice

        case $choice in
            1) rknn_test_menu ;;
            2) background_tasks_management_menu ;;
            3) view_test_logs ;;
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