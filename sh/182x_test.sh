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
SCRIPT_VERSION="1.0"  # Updated version for new features
TEST_RESULTS_DIR="./test_results"
mkdir -p "$TEST_RESULTS_DIR"
LOG_FILE="$TEST_RESULTS_DIR/rknn_test_$(date +%Y%m%d_%H%M%S).log"

# Global variables
LOOP=1
DEVICES_NUM=1
SEQ_LEN=512
NEW_TOKENS=512

# ============================================================================
# Input validation functions
# ============================================================================

# Generic input validation function
validate_number_input() {
    local prompt="$1"
    local variable_name="$2"
    local min_value="${3:-1}"  # Default minimum value is 1
    local max_value="${4:-100000}"  # Default maximum value is large to accommodate different parameters
    
    while true; do
        read -p "$prompt" input
        
        # Validate if input is empty
        if [[ -z "$input" ]]; then
            echo -e "${RED}Error: Input cannot be empty, please re-enter!${NC}"
            continue
        fi
        
        # Validate if input is a positive integer
        if [[ ! "$input" =~ ^[1-9][0-9]*$ ]]; then
            echo -e "${RED}Error: Please enter a valid positive integer!${NC}"
            continue
        fi
        
        # Validate range
        if [[ "$input" -lt "$min_value" || "$input" -gt "$max_value" ]]; then
            echo -e "${RED}Error: Please enter a number between ${min_value}-${max_value}!${NC}"
            continue
        fi
        
        # Assign to global variable
        if [[ "$variable_name" == "LOOP" ]]; then
            LOOP="$input"
        elif [[ "$variable_name" == "DEVICES_NUM" ]]; then
            DEVICES_NUM="$input"
        elif [[ "$variable_name" == "SEQ_LEN" ]]; then
            SEQ_LEN="$input"
        elif [[ "$variable_name" == "NEW_TOKENS" ]]; then
            NEW_TOKENS="$input"
        fi
        
        break
    done
}

get_loop() {
    validate_number_input "Enter number of loops (1-100000): " "LOOP" 1 100000
}

get_devices_num() {
    validate_number_input "Enter number of devices (1-64): " "DEVICES_NUM" 1 64
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
    ["llm"]="Qwen2.5-3B-Instruct Qwen2.5-7B-Instruct"
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

# Scan for ALL available model directories (all types)
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
                ((count++))
                result_array["$count"]="${found_models[$index]} $model_type"
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
# Generic testing framework
# ============================================================================

# Generic model testing function
test_model() {
    local model_name="$1"
    local model_type="$2"
    local model_path="$3"

    show_test_start "$model_type" "$model_name"
    echo "Executing ${model_name} model test..."

    # Get user input
    get_loop
    get_devices_num
    echo "Number of loops: $LOOP"
    echo "Number of devices: $DEVICES_NUM"

    # Execute different test commands based on model type
    case "$model_type" in
        "llm")
            # LLM models require additional parameters
            get_seq_len
            get_new_tokens
            echo "Sequence length (seq_len): $SEQ_LEN"
            echo "New tokens to generate: $NEW_TOKENS"

            # LLM test command
            echo -e "${CYAN}Executing LLM test command: ./rknn3_llm_test.sh $model_path/$model_name $SEQ_LEN $NEW_TOKENS 0 $LOOP $DEVICES_NUM${NC}"
            ./rknn3_llm_test.sh $model_path/$model_name $SEQ_LEN $NEW_TOKENS 0 $LOOP $DEVICES_NUM
            ;;
        "cnn")
            # CNN test command
            echo -e "${CYAN}Executing CNN test command: ./rknn3_cnn_test.sh $model_path/$model_name 0 $LOOP $DEVICES_NUM${NC}"
            ./rknn3_cnn_test.sh $model_path/$model_name 0 $LOOP $DEVICES_NUM
            ;;
        "vlm")
            # VLM test command
            echo -e "${CYAN}Executing VLM test command: ./rknn3_vlm_test.sh $model_path/$model_name 0 $LOOP $DEVICES_NUM${NC}"
            ./rknn3_vlm_test.sh $model_path/$model_name 0 $LOOP $DEVICES_NUM
            ;;
        *)
            echo -e "${RED}Unknown model type: $model_type${NC}"
            show_test_result 1 "$model_name"
            wait_return
            return 1
            ;;
    esac

    # Check command execution result
    local test_result=$?
    if [ $test_result -eq 0 ]; then
        show_test_result 0 "$model_name"
        log_message "$model_name test completed - Loops: $LOOP, Devices: $DEVICES_NUM, Seq Len: $SEQ_LEN, New Tokens: $NEW_TOKENS"
    else
        show_test_result 1 "$model_name"
        log_message "$model_name test failed - Exit code: $test_result"
    fi

    wait_return
}

# Generic model testing function with parameters (for loop testing)
test_model_with_params() {
    local model_name="$1"
    local model_type="$2"
    local model_path="$3"
    local loop_count="$4"
    local devices_num="$5"
    local seq_len="$6"
    local new_tokens="$7"

    show_test_start "$model_type" "$model_name"
    echo "Executing ${model_name} model test with parameters:"
    echo "Number of loops: $loop_count"
    echo "Number of devices: $devices_num"

    if [[ "$model_type" == "llm" ]]; then
        echo "Sequence length (seq_len): $seq_len"
        echo "New tokens to generate: $new_tokens"
    fi

    # Execute different test commands based on model type
    case "$model_type" in
        "llm")
            # LLM test command
            echo -e "${CYAN}Executing LLM test command: ./rknn3_llm_test.sh $model_path/$model_name $seq_len $new_tokens 0 $loop_count $devices_num${NC}"
            ./rknn3_llm_test.sh $model_path/$model_name $seq_len $new_tokens 0 $loop_count $devices_num
            ;;
        "cnn")
            # CNN test command
            echo -e "${CYAN}Executing CNN test command: ./rknn3_cnn_test.sh $model_path/$model_name 0 $loop_count $devices_num${NC}"
            ./rknn3_cnn_test.sh $model_path/$model_name 0 $loop_count $devices_num
            ;;
        "vlm")
            # VLM test command
            echo -e "${CYAN}Executing VLM test command: ./rknn3_vlm_test.sh $model_path/$model_name 0 $loop_count $devices_num${NC}"
            ./rknn3_vlm_test.sh $model_path/$model_name 0 $loop_count $devices_num
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
            log_message "$model_name test completed - Loops: $loop_count, Devices: $devices_num, Seq Len: $seq_len, New Tokens: $new_tokens"
        else
            log_message "$model_name test completed - Loops: $loop_count, Devices: $devices_num"
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

    # Get test parameters
    echo -e "${CYAN}Setting test parameters for all models:${NC}"
    get_loop
    get_devices_num

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

    # Confirm test execution
    echo
    echo -e "${RED}WARNING: This will test all ${#all_models[@]} models with the following parameters:${NC}"
    echo "Loops: $LOOP"
    echo "Devices: $DEVICES_NUM"
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

    # Start loop testing
    echo
    echo -e "${GREEN}Starting loop testing of all models...${NC}"
    log_message "=== Starting loop testing of all models ==="
    log_message "Parameters - Loops: $LOOP, Devices: $DEVICES_NUM, LLM Seq Len: $llm_seq_len, LLM New Tokens: $llm_new_tokens"

    local total_models=${#all_models[@]}
    local current_model=0
    local successful_tests=0
    local failed_tests=0

    # Test each model
    for index in $(echo "${!all_models[@]}" | tr ' ' '\n' | sort -n); do
        ((current_model++))
        local model_info=(${all_models[$index]})
        local model_name="${model_info[0]}"
        local model_type="${model_info[1]}"
        local model_path=$(get_model_path "$model_name")

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

        # Test the model with appropriate parameters
        local test_result
        if [[ "$model_type" == "llm" ]]; then
            test_model_with_params "$model_name" "$model_type" "$model_path" "$LOOP" "$DEVICES_NUM" "$llm_seq_len" "$llm_new_tokens"
        else
            test_model_with_params "$model_name" "$model_type" "$model_path" "$LOOP" "$DEVICES_NUM" "512" "512"
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

    # Display summary
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

    log_message "=== Loop testing completed ==="
    log_message "Summary - Total: $total_models, Successful: $successful_tests, Failed: $failed_tests"
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
                    test_model "$model_name" "$menu_type" "$model_path"
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
    echo "            Version $SCRIPT_VERSION"
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
        echo "3. Exit"
        echo

        read -rp "Please select an operation (1-3): " choice

        case $choice in
            1) rknn_test_menu ;;
            2) view_test_logs ;;
            3)
                echo -e "${GREEN}Thank you for using the 182x test script, goodbye!${NC}"
                log_message "Script exited normally"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid selection, please enter 1-3${NC}"
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
    ./install_rknn3_model_stress.sh
    echo -e "${GREEN}Script initialization completed${NC}"
    echo -e "Test results directory: $TEST_RESULTS_DIR"
    echo -e "Log file: $LOG_FILE"
    echo
    log_message "=== Test script started ==="
    
    # Enter main menu
    main_menu
fi