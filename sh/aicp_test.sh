#!/bin/bash

# AICP Test Script - Interactive menu-driven testing framework for RKNN devices
# Created based on the requirements in claude.txt

# Function to copy binaries to system path
install_binaries_to_system() {
    local script_dir="$1"
    local binaries=("rknn3_cnn_demo" "rknn3_llm_demo" "rknn3_vlm_demo")

    # Validate script_dir input
    if [[ -z "$script_dir" ]]; then
        echo -e "${RED}Error: Script directory is empty.${NC}" >&2
        return 1
    fi

    # Check if script directory exists
    if [[ ! -d "$script_dir" ]]; then
        echo -e "${RED}Error: Script directory does not exist: $script_dir${NC}" >&2
        return 1
    fi

    for binary in "${binaries[@]}"; do
        local src_path="$script_dir/$binary"
        local dest_path="/usr/bin/$binary"

        # Validate binary name to prevent path traversal
        if [[ "$binary" =~ [^a-zA-Z0-9_.-] ]]; then
            echo -e "${RED}Error: Invalid binary name: $binary${NC}" >&2
            continue
        fi

        if [[ -f "$src_path" ]]; then
            echo "Installing $binary to /usr/bin..."

            # Check if source file is readable
            if [[ ! -r "$src_path" ]]; then
                echo -e "${RED}Error: Cannot read source file: $src_path${NC}" >&2
                continue
            fi

            # Copy without sudo - only attempt if user has permissions
            if cp "$src_path" "$dest_path" 2>/dev/null; then
                chmod +x "$dest_path"
                echo "✓ Successfully installed $binary to /usr/bin/"
            else
                # Show manual command for user to run
                echo "✗ Failed to install $binary to /usr/bin/ - insufficient permissions"
                echo "  Manual install command: sudo cp '$src_path' /usr/bin/ && sudo chmod +x /usr/bin/'$binary'"
                echo "  Or run this script with appropriate permissions."
            fi
        else
            echo "⚠ Binary $binary not found in $script_dir, skipping..."
        fi
    done
}

# Check for and copy demo binaries to system path
check_and_copy_binaries() {
    # Get the directory where the script is located
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    echo "Checking for demo binaries in directory: $script_dir"

    # Validate script_dir
    if [[ ! -d "$script_dir" ]]; then
        echo -e "${RED}Error: Script directory does not exist: $script_dir${NC}" >&2
        return 1
    fi

    # Check if any of the binaries exist before attempting to install
    local has_binaries=false
    local binaries=("rknn3_cnn_demo" "rknn3_llm_demo" "rknn3_vlm_demo")
    local found_binaries=0

    for binary in "${binaries[@]}"; do
        # Validate binary name to prevent path traversal
        if [[ "$binary" =~ [^a-zA-Z0-9_.-] ]]; then
            echo -e "${RED}Error: Invalid binary name: $binary${NC}" >&2
            continue
        fi

        if [[ -f "$script_dir/$binary" ]]; then
            has_binaries=true
            ((found_binaries++))
        fi
    done

    if [[ "$has_binaries" == true ]]; then
        echo "Found $found_binaries demo binaries, proceeding with installation..."
        install_binaries_to_system "$script_dir"
    else
        echo "No demo binaries found in $script_dir, skipping installation..."
    fi

    # Verify at least one demo executable is available in PATH after attempted installation
    local demo_found=false
    for binary in "${binaries[@]}"; do
        if command -v "$binary" &> /dev/null; then
            demo_found=true
            break
        fi
    done

    if [[ "$demo_found" == false ]]; then
        echo "Warning: No demo executables found in PATH. Please ensure rknn3 demo binaries are available."
        echo "Expected binaries: ${binaries[*]}"
        return 1
    fi

    echo
}

# Only run binary check when script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    check_and_copy_binaries || exit 1
fi

# Color variables for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Global variables
DEVICE_COUNT=0
SELECTED_DEVICE=""
MODEL_PATHS=()
RETURN_TO_MAIN_MENU=false  # Flag to indicate if we should return to main menu

# Device info arrays
declare -A DEVICE_COMM_MODES  # Store communication mode for each device (key: device_id, value: comm_mode)
declare -a DEVICE_IDS         # Store actual device IDs in order (for menu display mapping)

# Task status enum
TASK_STATUS_RUNNING="RUNNING"
TASK_STATUS_SUCCESS="SUCCESS"
TASK_STATUS_FAILED="FAILED"

# Task management arrays
declare -a TASK_PIDS         # Stores background task PIDs
declare -a TASK_DEVICE_IDS   # Corresponding device IDs
declare -a TASK_STATUSES     # Task statuses
declare -a TASK_START_TIMES  # Task start times
declare -a TASK_CONFIG_TYPES # Configuration types (Model Testing, SMI Testing, etc.)
declare -a TASK_LOG_FILES    # Log files for each task
declare -a TASK_PREV_LOG_SIZES  # Previous log file sizes for each task
declare -a TASK_LAST_UPDATE_TIMES  # Last time log file sizes were checked for each task

# Array to store configurations for each device
declare -A DEVICE_CONFIGS

# Function to store device configuration
store_device_config() {
    local device_id="$1"
    local config_type="$2"  # model_category, specific_model, test_type, etc.
    local config_value="$3"

    DEVICE_CONFIGS["$device_id:$config_type"]="$config_value"
}

# Function to get device configuration
get_device_config() {
    local device_id="$1"
    local config_type="$2"

    echo "${DEVICE_CONFIGS["$device_id:$config_type"]}"
}

# Function to clear device configuration
clear_device_config() {
    local device_id="$1"
    local config_keys=("${!DEVICE_CONFIGS[@]}")

    # Remove all configurations for this device
    for key in "${config_keys[@]}"; do
        if [[ "$key" == "$device_id:"* ]]; then
            unset DEVICE_CONFIGS["$key"]
        fi
    done
}

# Function to display the main header
show_main_header() {
    clear
    echo -e "${CYAN}=================================${NC}"
    echo -e "${CYAN}       AICP Test Framework       ${NC}"
    echo -e "${CYAN}=================================${NC}"
    echo
}

# Function to enumerate devices using rknn-smi
enumerate_devices() {
    local output

    if ! command -v rknn-smi &> /dev/null; then
        echo -e "${RED}Error: rknn-smi command not found.${NC}"
        echo "Command 'rknn-smi' is not available in PATH."
        DEVICE_COUNT=0
        return 1
    fi

    output=$(rknn-smi info -l 2>&1)

    if [ -z "$output" ]; then
        echo -e "${RED}Error: rknn-smi command executed but returned no output.${NC}"
        DEVICE_COUNT=0
        return 1
    fi

    # Check if the output contains device information by looking for "Device Count"
    if ! echo "$output" | grep -q "Device Count"; then
        echo -e "${RED}Error: rknn-smi command executed but no device information found.${NC}"
        echo "Command output: $output"
        DEVICE_COUNT=0
        return 1
    fi

    # Extract device count
    local count_line=$(echo "$output" | grep -o "Device Count[[:space:]]*:[[:space:]]*[0-9]*" | grep -o "[0-9]*")
    DEVICE_COUNT=$count_line

    if [ -z "$DEVICE_COUNT" ] || [ "$DEVICE_COUNT" -lt 0 ]; then
        DEVICE_COUNT=0
    fi

    # Validate extracted count
    if [[ ! "$DEVICE_COUNT" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Error: Invalid device count extracted from output: $DEVICE_COUNT${NC}"
        DEVICE_COUNT=0
        return 1
    fi

    # Parse communication mode for each device and store actual Device IDs
    DEVICE_COMM_MODES=()
    DEVICE_IDS=()  # Reset the array
    local current_device_id=""
    local device_index=0
    while IFS= read -r line; do
        # Check for Device ID line
        if echo "$line" | grep -q "Device ID[[:space:]]*:"; then
            current_device_id=$(echo "$line" | grep -o "Device ID[[:space:]]*:[[:space:]]*[0-9]*" | grep -o "[0-9]*")
            # Store the actual Device ID in order
            DEVICE_IDS[$device_index]="$current_device_id"
            ((device_index++))
        fi
        # Check for Communication mode line
        if [[ -n "$current_device_id" ]] && echo "$line" | grep -q "Communication mode[[:space:]]*:"; then
            local comm_mode=$(echo "$line" | sed 's/.*Communication mode[[:space:]]*:[[:space:]]*//' | tr -d '[:space:]')
            DEVICE_COMM_MODES["$current_device_id"]="$comm_mode"
            # Also store in DEVICE_CONFIGS for use in test execution
            store_device_config "$current_device_id" "comm_mode" "$comm_mode"
            current_device_id=""  # Reset for next device
        fi
    done <<< "$output"

    return 0
}

# Function to get device communication mode
# Usage: get_device_comm_mode <device_id>
get_device_comm_mode() {
    local device_id="$1"
    echo "${DEVICE_COMM_MODES[$device_id]:-UNKNOWN}"
}

# Function to display device information
display_device_info() {
    local output

    if ! command -v rknn-smi &> /dev/null; then
        echo "rknn-smi command not found"
        return 1
    fi

    output=$(rknn-smi info -l 2>&1)

    if [ -z "$output" ]; then
        echo "Error executing rknn-smi command: No output received"
        return 1
    fi

    # Check if the output contains device information by looking for "Device Count"
    if ! echo "$output" | grep -q "Device Count"; then
        echo "Error executing rknn-smi command: No device information found"
        echo "Command output: $output"
        return 1
    fi

    echo "$output"
    echo
}

# Function to wait for user input
wait_for_user() {
    echo
    read -n 1 -s -r -p "Press any key to continue..."
    echo
}

# Function to initialize task management arrays
initialize_task_system() {
    TASK_PIDS=()
    TASK_DEVICE_IDS=()
    TASK_STATUSES=()
    TASK_START_TIMES=()
    TASK_CONFIG_TYPES=()
    TASK_LOG_FILES=()
    TASK_PREV_LOG_SIZES=()
    TASK_LAST_UPDATE_TIMES=()
    TASK_STUCK_COUNTS=()  # Track consecutive stuck detections
}

# Function to add a new task to the tracking system
add_task() {
    local pid="$1"
    local device_id="$2"
    local config_type="$3"
    local log_file="$4"

    # Validate inputs
    if [[ ! "$pid" =~ ^[0-9]+$ ]]; then
        echo "Error: Invalid PID: $pid" >&2
        return 1
    fi

    TASK_PIDS+=("$pid")
    TASK_DEVICE_IDS+=("$device_id")
    TASK_STATUSES+=("$TASK_STATUS_RUNNING")

    # Capture start time with validation
    local task_start_time
    task_start_time=$(date +%s)

    # Validate the captured time is reasonable (should be > 1600000000, after year 2020)
    if [[ ! "$task_start_time" =~ ^[0-9]+$ ]] || [[ "$task_start_time" -lt 1600000000 ]]; then
        echo "Warning: Invalid start_time captured: $task_start_time, using fallback" >&2
        task_start_time=$(date +%s)
    fi

    TASK_START_TIMES+=("$task_start_time")

    TASK_CONFIG_TYPES+=("$config_type")
    TASK_LOG_FILES+=("${log_file:-./test_results/task_${device_id}_$(date +%s%N).log}")

    # Initialize log size tracking with same start time for consistency
    TASK_PREV_LOG_SIZES+=(0)
    TASK_LAST_UPDATE_TIMES+=("$task_start_time")
    TASK_STUCK_COUNTS+=(0)  # Initialize stuck detection counter
}

# Function to update task status
update_task_status() {
    local task_idx="$1"
    local new_status="$2"

    if [[ $task_idx -lt ${#TASK_STATUSES[@]} ]]; then
        TASK_STATUSES[$task_idx]="$new_status"
    fi
}

# Function to get task status by PID
get_task_status_by_pid() {
    local pid="$1"

    for i in "${!TASK_PIDS[@]}"; do
        if [[ "${TASK_PIDS[$i]}" == "$pid" ]]; then
            echo $i  # Output the index instead of using return
            return 0
        fi
    done

    echo -1  # Output -1 for not found instead of using return -1
    return 1
}

# Function to check if a process is still running
is_process_running() {
    local pid="$1"

    kill -0 "$pid" 2>/dev/null
    return $?
}

# Get demo executable name based on model category
get_demo_executable() {
    local category="$1"
    case "$category" in
        CNN|cnn) echo "rknn3_cnn_demo" ;;
        LLM|llm) echo "rknn3_llm_demo" ;;
        VLM|vlm) echo "rknn3_vlm_demo" ;;
        *) return 1 ;;
    esac
}

# Execute a test in the background
execute_test_in_background() {
    local device_id="$1"
    local test_category="$2"
    local log_file="$3"

    # Serialize device configurations to a temporary file to pass to the subshell
    local temp_config_file=$(mktemp "/tmp/device_config_${device_id}_XXXXXX")
    trap 'rm -f "$temp_config_file"' EXIT RETURN
    if [[ ! -f "$temp_config_file" ]]; then
        echo "Error: Failed to create temporary configuration file" >&2
        return 1
    fi

    # Save all configurations for this device to the temp file
    for key in "${!DEVICE_CONFIGS[@]}"; do
        if [[ "$key" == "$device_id:"* ]]; then
            local config_type="${key#*:}"
            local config_value="${DEVICE_CONFIGS[$key]}"
            echo "$config_type=$config_value" >> "$temp_config_file"
        fi
    done

    {
        local exit_code=0

        # Source configuration in subshell from the temp file
        local model_category=""
        local specific_model=""
        local test_type=""
        local model_path=""
        local smi_test_type=""
        local stress_test_hours=""
        local custom_test_params=""
        local reset_loop_count=""
        local sleep_wakeup_hours=""
        local total_traversal_models=""
        local traversal_loop_count=""
        local comm_mode=""

        # Validate temp_config_file path to prevent path traversal
        if [[ -n "$temp_config_file" && -f "$temp_config_file" ]]; then
            while IFS='=' read -r config_type config_value; do
                # Sanitize config_type and config_value to prevent injection
                config_type=$(printf '%s\n' "$config_type" | tr -d '\0\r\n\t')
                config_value=$(printf '%s\n' "$config_value" | tr -d '\0\r\n\t')

                case "$config_type" in
                    "model_category") model_category="$config_value" ;;
                    "specific_model") specific_model="$config_value" ;;
                    "test_type") test_type="$config_value" ;;
                    "model_path") model_path="$config_value" ;;
                    "smi_test_type") smi_test_type="$config_value" ;;
                    "stress_test_hours") stress_test_hours="$config_value" ;;
                    "custom_test_params") custom_test_params="$config_value" ;;
                    "reset_loop_count") reset_loop_count="$config_value" ;;
                    "sleep_wakeup_hours") sleep_wakeup_hours="$config_value" ;;
                    "total_traversal_models") total_traversal_models="$config_value" ;;
                    "traversal_loop_count") traversal_loop_count="$config_value" ;;
                    "comm_mode") comm_mode="$config_value" ;;
                esac
            done < "$temp_config_file"
        fi

        case "$test_category" in
            "Model Testing")
                # Handle model testing
                if [[ -n "$model_category" && -n "$test_type" ]]; then
                    echo "Executing model test on Device $device_id:"
                    echo "  - Communication Mode: ${comm_mode:-UNKNOWN}"
                    echo "  - Test Category: $test_category"
                    echo "  - Model Category: $model_category"
                    echo "  - Test Type: $test_type"

                    # Need to source the RKNN module in this subshell
                    if [[ -f "./aicp_rknn_test.sh" ]]; then
                        source "./aicp_rknn_test.sh" || { echo "Error: Failed to source aicp_rknn_test.sh"; exit_code=1; break; }
                    fi

                    case "$test_type" in
                        "Functional Test")
                            # Determine which demo executable to use based on model type
                            local demo_executable
                            demo_executable=$(get_demo_executable "$model_category") || {
                                echo "Unknown model type: $model_category"
                                exit_code=1
                            }

                            if [[ $exit_code -eq 0 ]]; then
                                if ! command -v "$demo_executable" &> /dev/null; then
                                    echo "Error: $demo_executable is not available in PATH"
                                    echo "Please make sure the demo executable is installed."
                                    exit_code=1
                                else
                                    echo "Executing: $demo_executable -f \"$model_path\" -id $device_id"
                                    stdbuf -oL "$demo_executable" -f "$model_path" -id "$device_id"
                                    exit_code=$?
                                fi
                            fi
                            ;;
                        "Stress Test")
                            # Retrieve stored stress test hours if available
                            if [[ -z "$stress_test_hours" ]]; then
                                # Fallback to default if no stored hours
                                stress_test_hours=1
                                echo "Warning: No stress test hours configured, using default value of 1 hour"
                            fi

                            # Override the function to accept stored parameters
                            echo "Executing stress test for Device $device_id with $stress_test_hours hours"
                            local demo_executable
                            demo_executable=$(get_demo_executable "$model_category") || {
                                echo "Unknown model type: $model_category"
                                exit_code=1
                                continue
                            }

                            if ! command -v "$demo_executable" &> /dev/null; then
                                echo "Error: $demo_executable is not available in PATH"
                                echo "Please make sure the demo executable is installed."
                                exit_code=1
                                continue
                            fi

                            # Validate stress_test_hours to prevent injection
                            if [[ ! "$stress_test_hours" =~ ^[0-9]+$ ]] || [ "$stress_test_hours" -le 0 ]; then
                                echo "Invalid stress test hours: $stress_test_hours, using default value of 1 hour"
                                stress_test_hours=1
                            fi

                            echo "Executing: $demo_executable -f \"$model_path\" -id $device_id -tl $stress_test_hours"
                            stdbuf -oL "$demo_executable" -f "$model_path" -id "$device_id" -tl "$stress_test_hours"
                            exit_code=$?
                            ;;
                        "Custom Test")
                            # Retrieve stored custom test parameters if available
                            if [[ -z "$custom_test_params" ]]; then
                                echo "Warning: No custom test parameters configured"
                                custom_test_params=""
                            fi

                            # Override the function to accept stored parameters
                            local demo_executable
                            demo_executable=$(get_demo_executable "$model_category") || {
                                echo "Unknown model type: $model_category"
                                exit_code=1
                                continue
                            }

                            if ! command -v "$demo_executable" &> /dev/null; then
                                echo "Error: $demo_executable is not available in PATH"
                                echo "Please make sure the demo executable is installed."
                                exit_code=1
                                continue
                            fi

                            # Build the command as an array to avoid injection issues
                            local cmd_array=("$demo_executable" "-f" "$model_path" "-id" "$device_id")

                            # Parse the parameters as space-separated arguments
                            if [ -n "$custom_test_params" ]; then
                                # Validate custom_test_params to prevent command injection
                                # Check for dangerous characters individually
                                local has_dangerous_chars=false
                                if [[ "$custom_test_params" =~ ";" ]] || \
                                   [[ "$custom_test_params" =~ "&" ]] || \
                                   [[ "$custom_test_params" =~ "|" ]] || \
                                   [[ "$custom_test_params" =~ "\$" ]] || \
                                   [[ "$custom_test_params" =~ "\`" ]] || \
                                   [[ "$custom_test_params" =~ "<" ]] || \
                                   [[ "$custom_test_params" =~ ">" ]] || \
                                   [[ "$custom_test_params" =~ "{" ]] || \
                                   [[ "$custom_test_params" =~ "}" ]]; then
                                    has_dangerous_chars=true
                                fi

                                if [[ "$has_dangerous_chars" == true ]]; then
                                    echo "Warning: Potentially unsafe characters detected in custom parameters, skipping dangerous parameters"
                                    custom_test_params=""
                                else
                                    # Use read to safely split the parameters into an array
                                    local params
                                    read -ra params <<< "$custom_test_params"

                                    # Append the parameters to the command
                                    for param in "${params[@]}"; do
                                        # Sanitize each parameter to prevent injection
                                        param=$(printf '%s\n' "$param" | tr -d '\0\r\n\t')
                                        cmd_array+=("$param")
                                    done
                                fi
                            fi

                            echo "Executing: ${cmd_array[*]}"
                            stdbuf -oL "${cmd_array[@]}"
                            exit_code=$?
                            ;;
                        "Model Traversal Test")
                            # Handle model traversal test - iterate through all model types and their directories
                            echo "Executing Model Traversal Test for Device $device_id"

                            # Get loop count from config, default to 1 if not set
                            local loop_count="${traversal_loop_count:-1}"
                            echo "Total loop count: $loop_count"

                            local model_types=("cnn" "llm" "vlm")
                            local model_type_names=("CNN" "LLM" "VLM")

                            # Outer loop for multiple iterations
                            for ((loop_idx=1; loop_idx<=loop_count; loop_idx++)); do
                                echo ""
                                echo "========== Loop $loop_idx of $loop_count =========="
                                echo ""

                                # Iterate through each model type directory
                                for i in "${!model_types[@]}"; do
                                    local model_type_dir="${model_types[$i]}"
                                    local model_type_name="${model_type_names[$i]}"

                                    local demo_executable="rknn3_${model_types[$i]}_demo"

                                    # Validate model_type_dir to prevent path traversal
                                    if [[ "$model_type_dir" =~ [^a-zA-Z0-9_.-] ]]; then
                                        echo "Warning: Invalid model type directory name: $model_type_dir, skipping..."
                                        continue
                                    fi

                                    # Check if demo executable exists
                                    if ! command -v "$demo_executable" &> /dev/null; then
                                        echo "Warning: $demo_executable is not available in PATH, skipping $model_type_name models"
                                        continue
                                    fi

                                    # Validate and check if the model directory exists
                                    local model_base_dir="../$model_type_dir"
                                    if [[ "$model_base_dir" =~ [^a-zA-Z0-9/_.-] ]]; then
                                        echo "Warning: Invalid model base directory path: $model_base_dir, skipping..."
                                        continue
                                    fi

                                    # Check if the model directory exists
                                    if [[ -d "$model_base_dir" ]]; then
                                        echo "Scanning $model_type_name models in $model_base_dir/"

                                        # Find all subdirectories in the model type directory
                                        for model_dir in "$model_base_dir"/*/; do
                                            # Validate model_dir to prevent path traversal
                                            if [[ -d "$model_dir" ]]; then
                                                local model_name=$(basename "$model_dir")

                                                # Validate model_name to prevent path traversal
                                                if [[ "$model_name" =~ [^a-zA-Z0-9_.-] ]]; then
                                                    echo "Warning: Invalid model name: $model_name, skipping..."
                                                    continue
                                                fi

                                                local full_model_path="$model_dir"

                                                echo "Executing $demo_executable -f \"$full_model_path\" -id $device_id"

                                                # Execute the model test
                                                stdbuf -oL "$demo_executable" -f "$full_model_path" -id "$device_id"
                                                local model_exit_code=$?

                                                if [[ $model_exit_code -ne 0 ]]; then
                                                    echo "Error: Model $model_name failed with exit code $model_exit_code"
                                                    echo "Terminating traversal test due to model failure"
                                                    exit_code=1
                                                    # Break out of all loops immediately
                                                    break 3
                                                else
                                                    echo "Success: Model $model_name completed successfully"
                                                fi
                                            fi
                                        done
                                    else
                                        echo "Info: $model_base_dir/ directory does not exist, skipping $model_type_name models"
                                    fi
                                done
                            done

                            echo ""
                            # Check if test was terminated early due to failure
                            if [[ $exit_code -ne 0 ]]; then
                                echo "========== Traversal Test Terminated (Model Failed) =========="
                            else
                                echo "========== Traversal Test Completed ($loop_count loops) =========="
                            fi
                            echo ""
                            ;;
                        *)
                            echo "Unknown test type: $test_type"
                            exit_code=1
                            ;;
                    esac
                else
                    echo "Warning: Device $device_id has incomplete model testing configuration."
                    exit_code=1
                fi
                ;;
            "SMI Testing")
                # Handle SMI testing
                if [[ -n "$smi_test_type" ]]; then
                    echo "Executing SMI test on Device $device_id:"
                    echo "  - Communication Mode: ${comm_mode:-UNKNOWN}"
                    echo "  - Test Category: $test_category"
                    echo "  - SMI Test Type: $smi_test_type"

                    # Source SMI test module
                    if [[ -f "./aicp_smi_test.sh" ]]; then
                        source "./aicp_smi_test.sh" || { echo "Error: Failed to source aicp_smi_test.sh"; exit_code=1; break; }
                    else
                        echo "Error: SMI test module (aicp_smi_test.sh) not found!"
                        exit_code=1
                    fi

                    case "$smi_test_type" in
                        "Comprehensive SMI Test")
                            if command -v rknn_smi_test_for_device &> /dev/null; then
                                rknn_smi_test_for_device "$device_id"
                                exit_code=$?  # Capture return value
                            else
                                echo "Comprehensive SMI test function not available"
                                exit_code=1
                            fi
                            ;;
                        "Reset Test")
                            local loop_count="$reset_loop_count"
                            if [[ -z "$loop_count" ]]; then
                                loop_count=1
                            fi

                            if command -v hardware_reset_test &> /dev/null; then
                                # Reset type will be determined automatically based on communication mode
                                hardware_reset_test "$device_id" "$loop_count"
                                exit_code=$?  # Capture return value
                            else
                                echo "Reset test function not available"
                                exit_code=1
                            fi
                            ;;
                        "Sleep Wake-up Test")
                            local test_hours="$sleep_wakeup_hours"
                            if [[ -z "$test_hours" ]]; then
                                test_hours=1
                            fi

                            if command -v sleep_wakeup_test &> /dev/null; then
                                sleep_wakeup_test "$device_id" "$test_hours"
                                exit_code=$?  # Capture return value
                            else
                                echo "Sleep wake-up test function not available"
                                exit_code=1
                            fi
                            ;;
                        *)
                            echo "Unknown SMI test type: $smi_test_type"
                            exit_code=1
                            ;;
                    esac
                else
                    echo "Warning: Device $device_id has SMI testing category but no specific test type configured."
                    exit_code=1
                fi
                ;;
            *)
                echo "Warning: Unknown test category for device $device_id: $test_category"
                exit_code=1
                ;;
        esac

        # Clean up temp config file
        rm -f "$temp_config_file"

        exit $exit_code
    }
}

# Function to check and update task statuses
update_task_statuses() {
    for i in "${!TASK_PIDS[@]}"; do
        local pid="${TASK_PIDS[$i]}"
        local current_time=$(date +%s)

        # Validate pid to prevent invalid kill commands
        if [[ ! "$pid" =~ ^[0-9]+$ ]]; then
            echo "Warning: Invalid PID found in task tracking: $pid" >&2
            continue
        fi

        # Check if process is still running
        if is_process_running "$pid"; then
            # Process is still running, check if log file has grown in last minute
            local log_file="${TASK_LOG_FILES[$i]}"

            # Validate log file path to prevent path traversal
            if [[ "$log_file" =~ [^a-zA-Z0-9/_.-] ]]; then
                echo "Warning: Invalid log file path: $log_file" >&2
                continue
            fi

            # Get current log file size
            local current_size=0
            if [[ -f "$log_file" ]]; then
                current_size=$(stat -c%s "$log_file" 2>/dev/null || echo 0)
            fi

            # Get the time elapsed since last check
            local time_since_last_check=$((current_time - TASK_LAST_UPDATE_TIMES[$i]))

            # Determine check interval based on config type
            local check_interval=60
            if [[ "${TASK_CONFIG_TYPES[$i]}" == "Model Testing" ]]; then
                local device_id="${TASK_DEVICE_IDS[$i]}"

                # Validate device_id
                if [[ ! "$device_id" =~ ^[0-9]+$ ]]; then
                    echo "Warning: Invalid device ID in task: $device_id" >&2
                    continue
                fi

                local test_category=$(get_device_config "$device_id" "test_category")
                local test_type=$(get_device_config "$device_id" "test_type")

                # Set longer interval for Model Traversal Test
                if [[ "$test_type" == "Model Traversal Test" ]]; then
                    check_interval=180
                fi

                # Add extra timeout for NET communication mode (network latency)
                local comm_mode=$(get_device_comm_mode "$device_id")
                if [[ "$comm_mode" =~ ^[Nn][Ee][Tt]$ ]]; then
                    if [[ "$test_type" == "Model Traversal Test" ]]; then
                        check_interval=$((check_interval + 360))
                    else
                        check_interval=$((check_interval + 180))
                    fi
                fi
            elif [[ "${TASK_CONFIG_TYPES[$i]}" == "SMI Testing" ]]; then
                local device_id="${TASK_DEVICE_IDS[$i]}"

                # Validate device_id
                if [[ ! "$device_id" =~ ^[0-9]+$ ]]; then
                    echo "Warning: Invalid device ID in task: $device_id" >&2
                    continue
                fi

                local smi_test_type=$(get_device_config "$device_id" "smi_test_type")

                # Set shorter interval for Sleep Wake-up Test for more responsive monitoring
                if [[ "$smi_test_type" == "Sleep Wake-up Test" ]]; then
                    check_interval=10
                fi
            fi

            # If it's been at least the check interval seconds since last check
            if [[ $time_since_last_check -ge $check_interval ]]; then
                # Check if the log file size has changed since the last check
                if [[ ${TASK_PREV_LOG_SIZES[$i]} -eq $current_size ]]; then
                    # Log file hasn't changed in the check interval, increment stuck counter
                    TASK_STUCK_COUNTS[$i]=$((TASK_STUCK_COUNTS[$i] + 1))

                    # Require 2 consecutive stuck detections before killing (tolerates timing misses)
                    local stuck_threshold=2
                    if [[ ${TASK_STUCK_COUNTS[$i]} -ge $stuck_threshold ]]; then
                        echo "Warning: Task $i (Device ${TASK_DEVICE_IDS[$i]}) confirmed stuck - log file size unchanged for $((check_interval * stuck_threshold)) seconds"
                        echo "Config type: ${TASK_CONFIG_TYPES[$i]}"

                        # Kill the process
                        kill -TERM "$pid" 2>/dev/null

                        # Update status to failed
                        update_task_status $i "$TASK_STATUS_FAILED"
                    else
                        echo "Info: Task $i (Device ${TASK_DEVICE_IDS[$i]}) - possible stuck detection (${TASK_STUCK_COUNTS[$i]}/${stuck_threshold}), waiting for confirmation"
                    fi
                else
                    # Log file has changed, reset stuck counter and update tracking
                    TASK_STUCK_COUNTS[$i]=0
                    TASK_PREV_LOG_SIZES[$i]=$current_size
                    TASK_LAST_UPDATE_TIMES[$i]=$current_time
                fi
            else
                # If it's been less than the check interval, just update the size if it changed
                if [[ ${TASK_PREV_LOG_SIZES[$i]} -ne $current_size ]]; then
                    TASK_STUCK_COUNTS[$i]=0  # Reset stuck counter when log changes
                    TASK_PREV_LOG_SIZES[$i]=$current_size
                    TASK_LAST_UPDATE_TIMES[$i]=$current_time
                fi
            fi
        else
            # Process has finished, check exit code
            # Only check exit code if status is still RUNNING (not already updated)
            if [[ "${TASK_STATUSES[$i]}" == "$TASK_STATUS_RUNNING" ]]; then
                local exit_code
                exit_code=$(wait "$pid" 2>/dev/null; echo $?)

                # Handle case where wait returns 127 (process not found)
                # This can happen if process was already reaped
                if [[ $exit_code -eq 127 ]]; then
                    # Process was likely killed by stuck detection, treat as failed
                    exit_code=1
                fi

                if [[ $exit_code -eq 0 ]]; then
                    update_task_status $i "$TASK_STATUS_SUCCESS"
                else
                    update_task_status $i "$TASK_STATUS_FAILED"
                fi
            fi
        fi
    done
}

# Function to print the current status table
print_status_table() {
    clear
    echo -e "${CYAN}=======================================${NC}"
    echo -e "${CYAN}    Concurrent Testing Process Status    ${NC}"
    echo -e "${CYAN}=======================================${NC}"
    echo
    printf "%-8s %-12s %-20s %-10s %-15s\n" "Task ID" "Device ID" "Config Type" "Status" "Run Time(s)"
    printf "%-8s %-12s %-20s %-10s %-15s\n" "-------" "---------" "-----------" "------" "---------"

    local current_time
    current_time=$(date +%s)

    for i in "${!TASK_PIDS[@]}"; do
        local device_id="${TASK_DEVICE_IDS[$i]}"
        local config_type="${TASK_CONFIG_TYPES[$i]}"
        local status="${TASK_STATUSES[$i]}"

        # Get start_time with safe array access
        local start_time=""
        if [[ $i -lt ${#TASK_START_TIMES[@]} ]]; then
            start_time="${TASK_START_TIMES[$i]}"
        fi

        # Calculate elapsed time with validation
        local elapsed_time="N/A"
        if [[ -n "$start_time" && "$start_time" =~ ^[0-9]+$ && "$current_time" =~ ^[0-9]+$ ]]; then
            local calculated=$((current_time - start_time))
            # Sanity check: elapsed time should be positive and reasonable (< 1 year)
            if [[ $calculated -ge 0 && $calculated -lt 31536000 ]]; then
                elapsed_time=$calculated
            fi
        fi

        printf "%-8s %-12s %-20s %-10s %-15s\n" "$i" "$device_id" "$config_type" "$status" "$elapsed_time"
    done
    echo
}

# Function to monitor tasks and update status display
monitor_tasks() {
    local all_completed=false

    while [[ "$all_completed" == false ]]; do
        update_task_statuses
        print_status_table

        # Check if all tasks are completed
        all_completed=true
        for status in "${TASK_STATUSES[@]}"; do
            if [[ "$status" == "$TASK_STATUS_RUNNING" ]]; then
                all_completed=false
                break
            fi
        done

        # If not all completed, wait a bit before next check
        if [[ "$all_completed" == false ]]; then
            sleep 2
        fi
    done

    # Final update and display
    update_task_statuses
    print_status_table

    echo -e "${GREEN}All testing tasks completed!${NC}"
    echo
    echo "Final Results Summary:"
    local total_tasks=${#TASK_PIDS[@]}
    local successful_tasks=0
    local failed_tasks=0

    for status in "${TASK_STATUSES[@]}"; do
        if [[ "$status" == "$TASK_STATUS_SUCCESS" ]]; then
            ((successful_tasks++))
        elif [[ "$status" == "$TASK_STATUS_FAILED" ]]; then
            ((failed_tasks++))
        fi
    done

    echo "  Total tasks: $total_tasks"
    echo "  Successful: $successful_tasks"
    echo "  Failed: $failed_tasks"

    # Print detailed results for each device
    echo
    echo "Detailed Results by Device:"
    echo "--------------------------"
    for i in "${!TASK_PIDS[@]}"; do
        local device_id="${TASK_DEVICE_IDS[$i]}"
        local config_type="${TASK_CONFIG_TYPES[$i]}"
        local status="${TASK_STATUSES[$i]}"
        local log_file="${TASK_LOG_FILES[$i]}"

        if [[ "$status" == "$TASK_STATUS_SUCCESS" ]]; then
            echo -e "  Device $device_id: ${GREEN}SUCCESS${NC} ($config_type)"
        elif [[ "$status" == "$TASK_STATUS_FAILED" ]]; then
            echo -e "  Device $device_id: ${RED}FAILED${NC} ($config_type)"
        else
            echo -e "  Device $device_id: ${YELLOW}${status}${NC} ($config_type)"
        fi
        echo "    Log file: $log_file"
    done

    if [[ $failed_tasks -gt 0 ]]; then
        echo
        echo "Failed task logs:"
        for i in "${!TASK_STATUSES[@]}"; do
            if [[ "${TASK_STATUSES[$i]}" == "$TASK_STATUS_FAILED" ]]; then
                echo "  - Task $i (Device ${TASK_DEVICE_IDS[$i]}, Config: ${TASK_CONFIG_TYPES[$i]})"
                echo "    Log file: ${TASK_LOG_FILES[$i]}"
            fi
        done
    fi

    echo
    echo -e "${GREEN}Press any key to return to main menu...${NC}"
    read -n 1 -s -r
}

# Function to load RKNN model testing module
load_rknn_module() {
    if [[ -f "./aicp_rknn_test.sh" ]]; then
        source "./aicp_rknn_test.sh"
    else
        echo -e "${RED}Error: RKNN test module (aicp_rknn_test.sh) not found!${NC}"
        return 1
    fi
}

# Function to load SMI testing module
load_smi_module() {
    if [[ -f "./aicp_smi_test.sh" ]]; then
        source "./aicp_smi_test.sh"
    else
        echo -e "${RED}Error: SMI test module (aicp_smi_test.sh) not found!${NC}"
        return 1
    fi
}


# Second Level Menu: Device-specific submenu
device_submenu() {
    local device_id="$1"
    local comm_mode=$(get_device_comm_mode "$device_id")

    # Load required modules
    load_rknn_module
    load_smi_module

    while true; do
        show_main_header
        echo "Device $device_id Menu"
        echo "Selected Device: $device_id"
        echo "Communication Mode: $comm_mode"
        echo
        echo "1. Model Testing"
        echo "2. SMI Testing"
        echo "3. Back to Device Selection"
        echo

        read -rp "Please select an option (1-3): " choice

        if [[ -z "$choice" ]]; then
            echo -e "${RED}No input received, please enter a number!${NC}"
            if [ -t 0 ]; then
                wait_for_user
            else
                echo -e "${YELLOW}Non-interactive mode detected, exiting...${NC}"
                return 1
            fi
            continue
        fi

        if [[ ! "$choice" =~ ^[0-9]+$ ]]; then
            echo -e "${RED}Invalid input, please enter a number!${NC}"
            if [ -t 0 ]; then
                wait_for_user
            else
                echo -e "${YELLOW}Non-interactive mode detected, exiting...${NC}"
                return 1
            fi
            continue
        fi

        case $choice in
            1)
                select_model_category "$device_id"

                # Check if the RETURN_TO_MAIN_MENU flag has been set and return to main menu if true
                if [[ "$RETURN_TO_MAIN_MENU" == "true" ]]; then
                    RETURN_TO_MAIN_MENU=false  # Reset the flag
                    return  # Return to main menu
                fi
                ;;
            2)
                # Load SMI module before calling its functions
                load_smi_module
                record_smi_config "$device_id"

                # Check if the RETURN_TO_MAIN_MENU flag has been set and return to main menu if true
                if [[ "$RETURN_TO_MAIN_MENU" == "true" ]]; then
                    RETURN_TO_MAIN_MENU=false  # Reset the flag
                    return  # Return to main menu
                fi
                ;;
            3)
                return
                ;;
            *)
                echo -e "${RED}Invalid selection, please enter 1-3${NC}"
                wait_for_user
                ;;
        esac

        # Check if the RETURN_TO_MAIN_MENU flag has been set and return to main menu if true
        if [[ "$RETURN_TO_MAIN_MENU" == "true" ]]; then
            RETURN_TO_MAIN_MENU=false  # Reset the flag
            return  # Return to main menu
        fi
    done
}


# Function to display stored configurations
display_configurations() {
    echo -e "${GREEN}Stored Configurations:${NC}"
    local has_configs=false

    for ((i=0; i<DEVICE_COUNT; i++)); do
        # Get actual Device ID from DEVICE_IDS array
        local actual_device_id="${DEVICE_IDS[$i]}"

        # Check for all types of configurations
        test_category=$(get_device_config "$actual_device_id" "test_category")
        model_category=$(get_device_config "$actual_device_id" "model_category")
        specific_model=$(get_device_config "$actual_device_id" "specific_model")
        model_type=$(get_device_config "$actual_device_id" "model_type")
        model_path=$(get_device_config "$actual_device_id" "model_path")
        test_type=$(get_device_config "$actual_device_id" "test_type")
        stress_test_hours=$(get_device_config "$actual_device_id" "stress_test_hours")
        custom_test_params=$(get_device_config "$actual_device_id" "custom_test_params")
        smi_test_type=$(get_device_config "$actual_device_id" "smi_test_type")
        reset_loop_count=$(get_device_config "$actual_device_id" "reset_loop_count")
        sleep_wakeup_hours=$(get_device_config "$actual_device_id" "sleep_wakeup_hours")
        total_traversal_models=$(get_device_config "$actual_device_id" "total_traversal_models")
        traversal_loop_count=$(get_device_config "$actual_device_id" "traversal_loop_count")
        comm_mode=$(get_device_comm_mode "$actual_device_id")

        # Display configurations if any exist for this device
        if [[ -n "$test_category" || -n "$model_category" || -n "$specific_model" || -n "$test_type" || -n "$smi_test_type" ]]; then
            has_configs=true
            echo "Device $actual_device_id (${GREEN}Comm Mode: ${comm_mode}${NC}):"

            # Validate device id
            if [[ ! "$actual_device_id" =~ ^[0-9]+$ ]]; then
                echo "Warning: Invalid device id: $actual_device_id" >&2
                continue
            fi

            # Display test category if set
            [[ -n "$test_category" ]] && echo "  - Test Category: $test_category"

            # Check if this is a model traversal test
            if [[ -n "$test_type" && "$test_type" == "Model Traversal Test" ]]; then
                echo "  - Model Category: $model_category"
                echo "  - Model Type: $model_type"
                echo "  - Test Type: $test_type"

                # Display loop count
                if [[ -n "$traversal_loop_count" && "$traversal_loop_count" =~ ^[0-9]+$ ]]; then
                    echo "  - Loop Count: $traversal_loop_count"
                else
                    echo "  - Loop Count: 1 (default)"
                fi

                # Display traversal test specific info
                if [[ -n "$total_traversal_models" && "$total_traversal_models" -gt 0 ]]; then
                    # Validate total_traversal_models is a number
                    if [[ "$total_traversal_models" =~ ^[0-9]+$ ]]; then
                        echo "  - Total Models to Traverse: $total_traversal_models"

                        # Display each model that will be traversed
                        for ((j=0; j<total_traversal_models; j++)); do
                            # Validate j is a number
                            if [[ "$j" =~ ^[0-9]+$ ]]; then
                                local model_key=$(get_device_config "$actual_device_id" "traversal_model_$j")
                                if [[ -n "$model_key" ]]; then
                                    # Sanitize model_key to prevent injection
                                    model_key=$(printf '%s\n' "$model_key" | tr -d '\0\r\n\t')
                                    echo "    * $model_key"
                                fi
                            fi
                        done
                    else
                        echo "  - Invalid model count: $total_traversal_models"
                    fi
                else
                    echo "  - Models: None found in cnn, llm, or vlm directories"
                fi
            else
                # Display model testing configurations if they exist
                [[ -n "$model_category" ]] && echo "  - Model Category: $model_category"
                [[ -n "$model_type" ]] && echo "  - Model Type: $model_type"
                [[ -n "$specific_model" ]] && echo "  - Specific Model: $specific_model"
                [[ -n "$model_path" ]] && echo "  - Model Path: $model_path"
                [[ -n "$test_type" ]] && echo "  - Test Type: $test_type"

                # Display stress test specific configurations if they exist
                [[ -n "$test_type" && "$test_type" == "Stress Test" && -n "$stress_test_hours" ]] && echo "  - Stress Test Hours: $stress_test_hours"
                # Display custom test specific configurations if they exist
                [[ -n "$test_type" && "$test_type" == "Custom Test" && -n "$custom_test_params" ]] && echo "  - Custom Test Parameters: $custom_test_params"
            fi

            # Display SMI testing configurations if they exist
            [[ -n "$smi_test_type" ]] && echo "  - SMI Test Type: $smi_test_type"
            [[ -n "$reset_loop_count" && -n "$smi_test_type" && "$smi_test_type" == "Reset Test" ]] && echo "  - Reset Loop Count: $reset_loop_count"
            [[ -n "$sleep_wakeup_hours" && -n "$smi_test_type" && "$smi_test_type" == "Sleep Wake-up Test" ]] && echo "  - Sleep Wake-up Hours: $sleep_wakeup_hours"

            echo
        fi
    done

    if [[ "$has_configs" == false ]]; then
        echo "No configurations stored yet."
    fi
    echo
}

# Main menu function
main_menu() {
    while true; do
        # Reset the return flag at the beginning of each menu cycle
        RETURN_TO_MAIN_MENU=false

        show_main_header
        echo -e "${CYAN}Main Menu${NC}"

        # Enumerate devices to get updated count
        enumerate_devices

        if [ $DEVICE_COUNT -gt 0 ]; then
            echo "Detected $DEVICE_COUNT device(s)"
            echo
            echo "ID   Device ID   Communication Mode"
            echo "---- ---------- --------------------"
            # Display available devices with actual Device ID and communication mode
            for ((i=0; i<DEVICE_COUNT; i++)); do
                local actual_device_id="${DEVICE_IDS[$i]}"
                local comm_mode=$(get_device_comm_mode "$actual_device_id")
                printf "%-4s %-10s %-20s\n" "$((i+1))." "$actual_device_id" "$comm_mode"
            done
            echo
        else
            echo -e "${YELLOW}No devices detected!${NC}"
            echo "1. Rescan for devices"
            echo "2. Exit"
            echo
            read -rp "Please select an option: " choice

            case $choice in
                1)
                    continue
                    ;;
                2)
                    exit 0
                    ;;
                *)
                    echo -e "${RED}Invalid selection${NC}"
                    wait_for_user
                    ;;
            esac
            continue
        fi

        # Add additional menu options
        local additional_options_start=$((DEVICE_COUNT + 1))
        echo "$additional_options_start. Start Testing Process"
        echo "$((additional_options_start + 1)). Show Stored Configurations"
        echo "$((additional_options_start + 2)). Exit"
        echo

        read -rp "Please select a device or option (1-$((additional_options_start + 2))): " choice

        if [[ -z "$choice" ]]; then
            echo -e "${RED}No input received, please enter a number!${NC}"
            if [ -t 0 ]; then
                wait_for_user
            else
                echo -e "${YELLOW}Non-interactive mode detected, exiting...${NC}"
                return 1
            fi
            continue
        fi

        if [[ ! "$choice" =~ ^[0-9]+$ ]]; then
            echo -e "${RED}Invalid input, please enter a number!${NC}"
            if [ -t 0 ]; then
                wait_for_user
            else
                echo -e "${YELLOW}Non-interactive mode detected, exiting...${NC}"
                return 1
            fi
            continue
        fi

        # Handle device selection
        if [[ $choice -ge 1 && $choice -le $DEVICE_COUNT ]]; then
            # Validate choice to ensure it's numeric
            if [[ ! "$choice" =~ ^[0-9]+$ ]]; then
                echo -e "${RED}Invalid choice, must be a number${NC}"
                wait_for_user
                continue
            fi

            # Get the actual Device ID from DEVICE_IDS array
            local menu_index=$((choice - 1))
            local selected_device_id="${DEVICE_IDS[$menu_index]}"
            device_submenu "$selected_device_id"

            # After returning from device submenu, reset the flag to ensure normal operation
            RETURN_TO_MAIN_MENU=false
        # Handle additional options
        elif [[ $choice -eq $additional_options_start ]]; then
            # Start Testing Process - execute tests on all devices based on stored configurations
            echo -e "${GREEN}Starting tests on all devices based on stored configurations...${NC}"

            # Clean up test results directory first
            if [[ -d "./test_results" ]]; then
                echo "Cleaning up old test result logs..."
                rm -f ./test_results/*.log
                echo "Old test result logs removed."
            fi

            # Initialize the task management system
            initialize_task_system

            # Load required modules
            load_rknn_module
            load_smi_module

            # Create test results directory if it doesn't exist
            mkdir -p "./test_results"

            # Check if all configured devices are Reset Test - use round-robin mode instead of parallel
            local reset_test_devices=()
            local reset_test_loop_counts=()
            local all_reset_test=true
            local has_other_test=false
            local configured_device_count=0

            for ((i=0; i<DEVICE_COUNT; i++)); do
                local actual_device_id="${DEVICE_IDS[$i]}"
                local test_category=$(get_device_config "$actual_device_id" "test_category")
                local smi_test_type=$(get_device_config "$actual_device_id" "smi_test_type")

                if [[ -n "$test_category" ]]; then
                    ((configured_device_count++))
                    if [[ "$test_category" == "SMI Testing" && "$smi_test_type" == "Reset Test" ]]; then
                        local loop_count=$(get_device_config "$actual_device_id" "reset_loop_count")
                        reset_test_devices+=("$actual_device_id:$loop_count")
                        reset_test_loop_counts+=("$loop_count")
                    else
                        all_reset_test=false
                        has_other_test=true
                    fi
                fi
            done

            # If all configured devices are Reset Test (and more than 1), use round-robin mode
            if [[ "$all_reset_test" == "true" && ${#reset_test_devices[@]} -gt 1 ]]; then
                echo
                echo -e "${CYAN}Detected ${#reset_test_devices[@]} devices configured for Reset Test${NC}"
                echo -e "${CYAN}Using round-robin execution mode to avoid multi-device conflicts${NC}"
                echo

                # Build device configs string
                local device_configs_str=""
                for config in "${reset_test_devices[@]}"; do
                    device_configs_str="$device_configs_str $config"
                done
                device_configs_str=$(echo "$device_configs_str" | xargs)  # Trim leading/trailing spaces

                # Create log file for round-robin test
                local log_file="./test_results/round_robin_reset_$(date +%s).log"

                echo -e "${GREEN}Starting round-robin reset test...${NC}"
                echo -e "${YELLOW}Log file: $log_file${NC}"
                echo

                # Execute round-robin test (foreground, not background)
                # Reset type will be determined automatically based on each device's communication mode
                {
                    multi_device_round_robin_reset_test "$device_configs_str"
                } | tee "$log_file"
                local round_robin_ret=${PIPESTATUS[0]}

                echo
                if [[ $round_robin_ret -eq 0 ]]; then
                    echo -e "${GREEN}Round-robin reset test completed successfully!${NC}"
                else
                    echo -e "${RED}Round-robin reset test failed${NC}"
                fi

                echo
                echo -e "${GREEN}Press any key to return to main menu...${NC}"
                read -n 1 -s -r

            else
                # Use original parallel execution mode for other test types or single device
                if [[ "$has_other_test" == "true" ]]; then
                    echo -e "${YELLOW}Mixed test types detected, using parallel execution mode${NC}"
                elif [[ ${#reset_test_devices[@]} -eq 1 ]]; then
                    echo -e "${YELLOW}Single device Reset Test, using normal execution mode${NC}"
                fi

                # Start a background process for each configured device
                for ((i=0; i<DEVICE_COUNT; i++)); do
                    # Get actual Device ID from DEVICE_IDS array
                    local actual_device_id="${DEVICE_IDS[$i]}"
                    test_category=$(get_device_config "$actual_device_id" "test_category")

                    if [[ -n "$test_category" ]]; then
                        echo "Starting test for Device $actual_device_id with configuration: $test_category"

                        # Create log file for this device's test
                        local log_file="./test_results/device_${actual_device_id}_$(date +%s).log"

                        # Execute test in background and capture PID with output redirection
                        execute_test_in_background "$actual_device_id" "$test_category" "$log_file" > "$log_file" 2>&1 &
                        local bg_pid=$!

                        # Add task to our tracking system
                        add_task "$bg_pid" "$actual_device_id" "$test_category" "$log_file"

                        echo "Started background test for Device $actual_device_id (PID: $bg_pid)"
                    else
                        echo "Warning: Device $actual_device_id has no test category configured. Please configure it first."
                    fi
                done

                # Start monitoring the background tasks
                if [[ ${#TASK_PIDS[@]} -gt 0 ]]; then
                    echo
                    echo -e "${GREEN}Background tasks started. Monitoring progress...${NC}"
                    echo "Press Ctrl+C to interrupt monitoring (tasks will continue running in background)"

                    # Monitor all tasks
                    monitor_tasks
                else
                    echo -e "${YELLOW}No configured devices found to test.${NC}"
                    wait_for_user
                fi
            fi
        elif [[ $choice -eq $((additional_options_start + 1)) ]]; then
            # Show stored configurations
            show_main_header
            display_configurations
            wait_for_user
        elif [[ $choice -eq $((additional_options_start + 2)) ]]; then
            echo "Exiting AICP Test Framework..."
            exit 0
        else
            echo -e "${RED}Invalid selection${NC}"
            wait_for_user
        fi
    done
}

# Main execution
main() {
    # Check if rknn-smi is available
    if ! command -v rknn-smi &> /dev/null; then
        echo -e "${RED}Error: rknn-smi command is not available.${NC}"
        echo "Please install RKNN toolkit and ensure rknn-smi is in your PATH."
        exit 1
    fi

    # Create sh directory if it doesn't exist
    if [[ ! -d "sh" ]]; then
        mkdir -p "sh"
    fi

    # Initialize and start the main menu
    enumerate_devices
    main_menu
}

# Run the main function
main "$@"
