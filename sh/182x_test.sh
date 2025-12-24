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
SCRIPT_VERSION="1.0"
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
    validate_number_input "Enter sequence length (seq_len, 1-65536): " "SEQ_LEN" 1 65536
}

get_new_tokens() {
    validate_number_input "Enter number of new tokens to generate (1-65536): " "NEW_TOKENS" 1 65536
}

# ============================================================================
# Generic testing framework
# ============================================================================

# Model configuration array
declare -A MODEL_CONFIGS=(
    # CNN models
    ["cnn_1"]="Dinov3 cnn ../Dinov3/Dinov3"
    ["cnn_2"]="Siglip2 cnn ../Siglip2/Siglip2" 
    ["cnn_3"]="YOLOv5s cnn ../YOLOv5s/YOLOv5s"
    ["cnn_4"]="YOLOv6s cnn ../YOLOv6s/YOLOv6s"
    ["cnn_5"]="YOLOv8s cnn ../YOLOv8s/YOLOv8s"
    ["cnn_6"]="MobilenetV1 cnn ../MobilenetV1/MobilenetV1"
    ["cnn_7"]="MobilenetV2 cnn ../MobilenetV2/MobilenetV2"
    ["cnn_8"]="Resnet50-v2 cnn ../Resnet50-v2/Resnet50-v2"
    
    # LLM models
    ["llm_1"]="Qwen2.5-3B-Instruct llm ../Qwen2.5-3B-Instruct/Qwen2.5-3B-Instruct"
    ["llm_2"]="Qwen2.5-7B-Instruct llm ../Qwen2.5-7B-Instruct/Qwen2.5-7B-Instruct"
    
    # VLM models
    ["vlm_1"]="FasterVLM-llm vlm ../FasterVLM-llm/FasterVLM-llm"
    ["vlm_2"]="InternVL3-2B vlm ../InternVL3-2B/InternVL3-2B"
    ["vlm_3"]="InternVL3_5-4B vlm ../InternVL3_5-4B/InternVL3_5-4B"
    ["vlm_4"]="Qwen2.5-VL-3B vlm ../Qwen2.5-VL-3B/Qwen2.5-VL-3B"
    ["vlm_5"]="Qwen2.5-VL-7B vlm ../Qwen2.5-VL-7B/Qwen2.5-VL-7B"
    ["vlm_6"]="Qwen3-VL-2B vlm ../Qwen3-VL-2B/Qwen3-VL-2B"
    ["vlm_7"]="Qwen3-VL-4B vlm ../Qwen3-VL-4B/Qwen3-VL-4B"
)

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
            echo -e "${CYAN}Executing LLM test command: ./rknn3_llm_test.sh $model_path $SEQ_LEN $NEW_TOKENS 0 $LOOP $DEVICES_NUM${NC}"
            ./rknn3_llm_test.sh $model_path $SEQ_LEN $NEW_TOKENS 0 $LOOP $DEVICES_NUM
            ;;
        "cnn")
            # CNN test command
            echo -e "${CYAN}Executing CNN test command: ./rknn3_cnn_test.sh $model_path 0 $LOOP $DEVICES_NUM${NC}"
            ./rknn3_cnn_test.sh $model_path 0 $LOOP $DEVICES_NUM
            ;;
        "vlm")
            # VLM test command
            echo -e "${CYAN}Executing VLM test command: ./rknn3_vlm_test.sh $model_path 0 $LOOP $DEVICES_NUM${NC}"
            ./rknn3_vlm_test.sh $model_path 0 $LOOP $DEVICES_NUM
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

# ============================================================================
# Menu generation functions
# ============================================================================

# Generic menu generation function
generate_test_menu() {
    local menu_type="$1"
    local menu_title="$2"
    local color="$3"
    
    while true; do
        show_test_header
        echo -e "${color}${menu_title} Options:${NC}"
        
        # Dynamically generate menu options
        local count=1
        local menu_items=()
        
        for key in $(echo "${!MODEL_CONFIGS[@]}" | tr ' ' '\n' | grep "^${menu_type}_" | sort); do
            local model_info=(${MODEL_CONFIGS[$key]})
            echo "$count. ${model_info[0]}"
            menu_items[$count]="$key"
            ((count++))
        done
        
        local return_option=$count
        echo "$return_option. Return to previous menu"
        echo
        
        read -rp "Please select a model to test (1-$return_option): " choice
        
        # Validate input
        if [[ ! "$choice" =~ ^[0-9]+$ ]]; then
            echo -e "${RED}Invalid input, please enter a number!${NC}"
            sleep 2
            continue
        fi
        
        if [[ "$choice" -eq "$return_option" ]]; then
            return
        elif [[ "$choice" -ge 1 && "$choice" -le $((return_option-1)) ]]; then
            local selected_key="${menu_items[$choice]}"
            local model_info=(${MODEL_CONFIGS[$selected_key]})
            test_model "${model_info[0]}" "${model_info[1]}" "${model_info[2]}"
        else
            echo -e "${RED}Invalid selection, please enter 1-$return_option${NC}"
            sleep 2
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
    echo "          182X Computing Card Test Script"
    echo "                Version $SCRIPT_VERSION"
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
# Menu functions (simplified version)
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
                sleep 2
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
        echo "1. CNN Model Validation Test"
        echo "2. LLM Model Validation Test" 
        echo "3. VLM Model Validation Test"
        echo "4. Return to Main Menu"
        echo
        
        read -rp "Please select test type (1-4): " choice
        
        case $choice in
            1) cnn_test_menu ;;
            2) llm_test_menu ;;
            3) vlm_test_menu ;;
            4) return ;;
            *) 
                echo -e "${RED}Invalid selection, please enter 1-4${NC}"
                sleep 2
                ;;
        esac
    done
}

# Use generic menu functions
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