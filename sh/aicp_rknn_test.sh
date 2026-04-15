#!/bin/bash

# AICP RKNN Test Script - RKNN Model Testing Module

# Color variables for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Global variables
RETURN_TO_MAIN_MENU=false  # Flag to indicate if we should return to main menu

# NOTE: The following basic utility functions are expected to be available from the main script:
# store_device_config(), get_device_config(), clear_device_config(), show_main_header(), wait_for_user()

# Function for functional test
run_functional_test() {
    local model_name="$1"
    local model_type="$2"
    local model_path="$3"
    local device_id="$4"

    echo "Running functional test for $model_name (Type: $model_type) on device $device_id"
    echo "Model path: $model_path"
    echo

    # Determine which demo executable to use based on model type
    local demo_executable
    case "$model_type" in
        CNN)
            demo_executable="rknn3_cnn_demo"
            ;;
        LLM)
            demo_executable="rknn3_llm_demo"
            ;;
        VLM)
            demo_executable="rknn3_vlm_demo"
            ;;
        *)
            echo "Unknown model type: $model_type"
            return 1
            ;;
    esac

    if ! command -v "$demo_executable" &> /dev/null; then
        echo "Error: $demo_executable is not available in PATH"
        echo "Please make sure the demo executable is installed."
        return 1
    fi

    echo "Executing: $demo_executable -f \"$model_path\" -id $device_id"
    "$demo_executable" -f "$model_path" -id "$device_id"

    local exit_code=$?
    if [ $exit_code -eq 0 ]; then
        echo "Functional test completed successfully!"
    else
        echo "Functional test failed with exit code: $exit_code"
    fi

    return $exit_code
}

# Function for stress test
run_stress_test() {
    local model_name="$1"
    local model_type="$2"
    local model_path="$3"
    local device_id="$4"

    echo "Running stress test for $model_name (Type: $model_type) on device $device_id"
    echo "Model path: $model_path"
    echo

    # Determine which demo executable to use based on model type
    local demo_executable
    case "$model_type" in
        CNN)
            demo_executable="rknn3_cnn_demo"
            ;;
        LLM)
            demo_executable="rknn3_llm_demo"
            ;;
        VLM)
            demo_executable="rknn3_vlm_demo"
            ;;
        *)
            echo "Unknown model type: $model_type"
            return 1
            ;;
    esac

    if ! command -v "$demo_executable" &> /dev/null; then
        echo "Error: $demo_executable is not available in PATH"
        echo "Please make sure the demo executable is installed."
        return 1
    fi

    # Ask user for test duration in hours
    local hours
    read -rp "Enter test duration in hours: " hours

    if [[ ! "$hours" =~ ^[0-9]+$ ]] || [[ "$hours" -lt 1 ]]; then
        echo "Invalid input. Defaulting to 1 hour."
        hours=1
    fi

    echo "Executing: $demo_executable -f \"$model_path\" -id $device_id -tl $hours"
    "$demo_executable" -f "$model_path" -id "$device_id" -tl "$hours"

    local exit_code=$?
    if [ $exit_code -eq 0 ]; then
        echo "Stress test completed successfully!"
    else
        echo "Stress test failed with exit code: $exit_code"
    fi

    return $exit_code
}

# Function for custom test
run_custom_test() {
    local model_name="$1"
    local model_type="$2"
    local model_path="$3"
    local device_id="$4"

    echo "Running custom test for $model_name (Type: $model_type) on device $device_id"
    echo "Model path: $model_path"
    echo

    # Determine which demo executable to use based on model type
    local demo_executable
    case "$model_type" in
        CNN)
            demo_executable="rknn3_cnn_demo"
            ;;
        LLM)
            demo_executable="rknn3_llm_demo"
            ;;
        VLM)
            demo_executable="rknn3_vlm_demo"
            ;;
        *)
            echo "Unknown model type: $model_type"
            return 1
            ;;
    esac

    if ! command -v "$demo_executable" &> /dev/null; then
        echo "Error: $demo_executable is not available in PATH"
        echo "Please make sure the demo executable is installed."
        return 1
    fi

    echo "Enter custom parameters for the test (without -f and -id):"
    echo "Example: -c 0xff -cl 10"
    read -rp "Parameters: " raw_params

    # Sanitize input to prevent command injection
    # Use whitelist policy to only allow safe characters
    if [[ ! "$raw_params" =~ ^[-a-zA-Z0-9_./[:space:]]*$ ]]; then
        echo "Error: Potentially dangerous characters detected in parameters. Please enter valid parameters only."
        return 1
    fi

    # Build the command as an array to avoid injection issues
    local cmd_array=("$demo_executable" "-f" "$model_path" "-id" "$device_id")

    # Parse the parameters as space-separated arguments
    if [ -n "$raw_params" ]; then
        # Use read to safely split the parameters into an array
        local params
        read -ra params <<< "$raw_params"

        # Append the parameters to the command
        for param in "${params[@]}"; do
            cmd_array+=("$param")
        done
    fi

    echo "Executing: ${cmd_array[*]}"
    "${cmd_array[@]}"

    local exit_code=$?
    if [ $exit_code -eq 0 ]; then
        echo "Custom test completed successfully!"
    else
        echo "Custom test failed with exit code: $exit_code"
    fi

    return $exit_code
}

# Function to scan model directories
scan_model_directories() {
    local model_type="$1"
    local -n found_models_ref="$2"

    # For "Traversal" type, we need to scan all directories (cnn, llm, vlm)
    if [[ "$model_type" == "Traversal" ]]; then
        local all_model_types=("cnn" "llm" "vlm")
        local count=0

        for mt in "${all_model_types[@]}"; do
            local model_dir="../$mt"

            if [[ -d "$model_dir" ]]; then
                for dir in "$model_dir"/*/; do
                    if [[ -d "$dir" ]]; then
                        local dir_name=$(basename "$dir")
                        found_models_ref[$((count++))]="$mt/$dir_name"
                    fi
                done
            fi
        done

        if [[ $count -eq 0 ]]; then
            return 1
        fi

        return 0
    else
        # Original functionality for specific model types
        local model_dir="../$model_type"

        if [[ ! -d "$model_dir" ]]; then
            return 1
        fi

        local count=0
        for dir in "$model_dir"/*/; do
            if [[ -d "$dir" ]]; then
                local dir_name=$(basename "$dir")
                found_models_ref[$((count++))]="$dir_name"
            fi
        done

        if [[ $count -eq 0 ]]; then
            return 1
        fi

        return 0
    fi
}

# Function to select specific model based on type
select_specific_model() {
    local model_type="$1"
    local model_subtype="$2"
    local device_id="$3"

    # Clear previous configuration for this device before storing new one
    clear_device_config "$device_id"

    # Store the test category and model category selections
    store_device_config "$device_id" "test_category" "Model Testing"
    store_device_config "$device_id" "model_category" "$model_subtype"
    store_device_config "$device_id" "model_type" "$model_type"

    while true; do
        show_main_header
        echo -e "${CYAN}Select Specific Model for $model_subtype ($model_type)${NC}"
        echo "Model Type: $model_type"
        echo "Subtype: $model_subtype"
        echo "Current Device: $device_id"
        echo

        declare -A found_models

        if ! scan_model_directories "$model_type" found_models; then
            echo -e "${YELLOW}No $model_type models found in ../ directory!${NC}"
            echo
            echo "1. Rescan directories"
            echo "2. Back to Model Category Selection"
            echo

            read -rp "Please select an option (1-2): " retry_choice

            case $retry_choice in
                1) continue ;;
                2) return ;;
                *) echo -e "${RED}Invalid selection!${NC}"; wait_for_user; continue ;;
            esac
        fi

        local count=0
        for index in $(echo "${!found_models[@]}" | tr ' ' '\n' | sort -n); do
            ((count++))
            echo "$count. ${found_models[$index]}"
        done

        local return_option=$((count + 1))
        echo "$return_option. Back to Model Category Selection"
        echo

        read -rp "Please select a model to test (1-$return_option): " choice

        if [[ -z "$choice" ]]; then
            echo -e "${RED}No input received, please enter a number!${NC}"
            if [ -t 0 ]; then
                wait_for_user
            else
                echo -e "${YELLOW}Non-interactive mode detected, exiting...${NC}"
                break
            fi
            continue
        fi

        if [[ ! "$choice" =~ ^[0-9]+$ ]]; then
            echo -e "${RED}Invalid input, please enter a number!${NC}"
            if [ -t 0 ]; then
                wait_for_user
            else
                echo -e "${YELLOW}Non-interactive mode detected, exiting...${NC}"
                break
            fi
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
                    local model_path="../$model_type/$model_name"

                    if [[ ! -e "$model_path" ]] && [[ ! -e "$model_path.rknn" ]] && [[ -z "$(ls "$model_path"/*.rknn 2>/dev/null)" ]]; then
                        echo -e "${RED}Model files not found for $model_name!${NC}"
                        echo "Expected path: $model_path"
                        wait_for_user
                        continue
                    fi

                    echo -e "${GREEN}Selected model: $model_name${NC}"

                    # Save the specific model name and path for later use during testing
                    store_device_config "$device_id" "specific_model" "$model_name"
                    store_device_config "$device_id" "model_path" "$model_path"

                    select_test_type "$model_name" "$model_type" "$model_path" "$device_id"

                    # Check if the RETURN_TO_MAIN_MENU flag has been set and return if true
                    if [[ "$RETURN_TO_MAIN_MENU" == "true" ]]; then
                        return  # Return to device_submenu which will return to main menu
                    fi
                    break
                fi
            done
        else
            echo -e "${RED}Invalid selection, please enter 1-$return_option${NC}"
            wait_for_user
        fi
    done
}

# Function to select test type (Functional, Stress, Custom)
select_test_type() {
    local model_name="$1"
    local model_type="$2"
    local model_path="$3"
    local device_id="$4"

    while true; do
        show_main_header
        echo -e "${CYAN}Select Test Type for $model_name${NC}"
        echo "Model Type: $model_type"
        echo "Model Path: $model_path"
        echo "Device ID: $device_id"
        echo
        echo "1. Functional Test"
        echo "2. Stress Test"
        echo "3. Custom Test"
        echo "4. Back to Model Selection"
        echo

        read -rp "Please select a test type (1-4): " choice

        if [[ -z "$choice" ]]; then
            echo -e "${RED}No input received, please enter a number!${NC}"
            if [ -t 0 ]; then
                wait_for_user
            else
                echo -e "${YELLOW}Non-interactive mode detected, exiting...${NC}"
                break
            fi
            continue
        fi

        if [[ ! "$choice" =~ ^[0-9]+$ ]]; then
            echo -e "${RED}Invalid input, please enter a number!${NC}"
            if [ -t 0 ]; then
                wait_for_user
            else
                echo -e "${YELLOW}Non-interactive mode detected, exiting...${NC}"
                break
            fi
            continue
        fi

        case $choice in
            1)
                echo -e "${GREEN}Selected functional test for $model_name on device $device_id${NC}"

                # Store the test type selection - NO ACTUAL TEST EXECUTION HERE
                store_device_config "$device_id" "test_type" "Functional Test"

                # Inform user that test is scheduled but not executed yet
                echo "Test scheduled for device $device_id. Will be executed during 'Start Testing Process'."
                read -rp "Press Enter to return to main menu..." dummy
                RETURN_TO_MAIN_MENU=true
                return
                ;;
            2)
                echo -e "${GREEN}Selected stress test for $model_name on device $device_id${NC}"

                # Ask user for test duration in hours
                local hours
                read -rp "Enter test duration in hours: " hours

                if [[ ! "$hours" =~ ^[0-9]+$ ]] || [[ "$hours" -lt 1 ]]; then
                    echo "Invalid input. Defaulting to 1 hour."
                    hours=1
                fi

                # Store the test type and stress test specific parameters - NO ACTUAL TEST EXECUTION HERE
                store_device_config "$device_id" "test_type" "Stress Test"
                store_device_config "$device_id" "stress_test_hours" "$hours"

                # Inform user that test is scheduled but not executed yet
                echo "Stress test scheduled for device $device_id with $hours hour(s). Will be executed during 'Start Testing Process'."
                read -rp "Press Enter to return to main menu..." dummy
                RETURN_TO_MAIN_MENU=true
                return
                ;;
            3)
                echo -e "${GREEN}Selected custom test for $model_name on device $device_id${NC}"

                echo "Enter custom parameters for the test (without -f and -id):"
                echo "Example: -c 0xff -cl 10"
                read -rp "Parameters: " raw_params

                # Sanitize input to prevent command injection
                # Use whitelist policy to only allow safe characters
                if [[ ! "$raw_params" =~ ^[-a-zA-Z0-9_./[:space:]]*$ ]]; then
                    echo "Error: Potentially dangerous characters detected in parameters. Please enter valid parameters only."
                    wait_for_user
                    continue
                fi

                # Store the test type and custom test parameters - NO ACTUAL TEST EXECUTION HERE
                store_device_config "$device_id" "test_type" "Custom Test"
                store_device_config "$device_id" "custom_test_params" "$raw_params"

                # Inform user that test is scheduled but not executed yet
                echo "Custom test scheduled for device $device_id with parameters: $raw_params. Will be executed during 'Start Testing Process'."
                read -rp "Press Enter to return to main menu..." dummy
                RETURN_TO_MAIN_MENU=true
                return
                ;;
            4)
                return
                ;;
            *)
                echo -e "${RED}Invalid selection, please enter 1-4${NC}"
                wait_for_user
                ;;
        esac
    done
}

# Function to perform model traversal test
perform_model_traversal_test() {
    local device_id="$1"

    # Clear previous configuration for this device before storing new one
    clear_device_config "$device_id"

    echo "Setting up Model Traversal Test for device $device_id"
    echo

    # Scan for all models across cnn, llm, and vlm directories
    declare -A all_found_models
    local all_model_types=("cnn" "llm" "vlm")
    local model_type_names=("CNN" "LLM" "VLM")

    echo "Models that will be tested in traversal mode:"
    local total_models=0

    for i in "${!all_model_types[@]}"; do
        local model_type_dir="${all_model_types[$i]}"
        local model_type_name="${model_type_names[$i]}"

        if [[ -d "../$model_type_dir" ]]; then
            echo "$model_type_name Models:"

            for model_dir in "../$model_type_dir"/*/; do
                if [[ -d "$model_dir" ]]; then
                    local model_name=$(basename "$model_dir")
                    local model_key="$model_type_dir/$model_name"

                    all_found_models[$total_models]="$model_key"
                    echo "  - $model_key"
                    ((total_models++))
                fi
            done
        else
            echo "$model_type_name directory (../$model_type_dir/) does not exist."
        fi
    done

    if [[ $total_models -eq 0 ]]; then
        echo "No models found in cnn, llm, or vlm directories."
    else
        echo "Total models to test: $total_models"
    fi

    echo

    # Ask user for loop count
    local loop_count
    read -rp "Enter total loop count for traversal test (default: 1): " loop_count

    if [[ -z "$loop_count" ]]; then
        loop_count=1
        echo "Using default loop count: 1"
    elif [[ ! "$loop_count" =~ ^[0-9]+$ ]] || [[ "$loop_count" -lt 1 ]]; then
        echo "Invalid input. Defaulting to 1 loop."
        loop_count=1
    else
        echo "Loop count set to: $loop_count"
    fi

    echo

    # Store the test category and model traversal test type
    store_device_config "$device_id" "test_category" "Model Testing"
    store_device_config "$device_id" "model_category" "Model Traversal Test"
    store_device_config "$device_id" "model_type" "Traversal"
    store_device_config "$device_id" "test_type" "Model Traversal Test"
    store_device_config "$device_id" "total_traversal_models" "$total_models"
    store_device_config "$device_id" "traversal_loop_count" "$loop_count"

    # Store each model that will be tested for display purposes
    for i in "${!all_found_models[@]}"; do
        store_device_config "$device_id" "traversal_model_$i" "${all_found_models[$i]}"
    done

    # Inform user that test is scheduled but not executed yet
    echo "Model Traversal Test scheduled for device $device_id."
    echo "Will be executed during 'Start Testing Process'."

    # Simply return to the select_model_category function which will handle asking the user about returning to main menu
    return
}

# Third Level Menu: Model Category Selection
select_model_category() {
    local device_id="$1"

    while true; do
        show_main_header
        echo -e "${CYAN}Select Model Category for Device $device_id${NC}"
        echo "Current Device: $device_id"
        echo
        echo "1. CNN Models"
        echo "2. LLM Models"
        echo "3. VLM Models"
        echo "4. Audio Models"
        echo "5. Model traversal test"
        echo "6. Special Scenario 1"
        echo "7. Special Scenario 2"
        echo "8. Back to Device Menu"
        echo

        read -rp "Please select a model category (1-8): " choice

        if [[ -z "$choice" ]]; then
            echo -e "${RED}No input received, please enter a number!${NC}"
            if [ -t 0 ]; then
                wait_for_user
            else
                echo -e "${YELLOW}Non-interactive mode detected, exiting...${NC}"
                break
            fi
            continue
        fi

        if [[ ! "$choice" =~ ^[0-9]+$ ]]; then
            echo -e "${RED}Invalid input, please enter a number!${NC}"
            if [ -t 0 ]; then
                wait_for_user
            else
                echo -e "${YELLOW}Non-interactive mode detected, exiting...${NC}"
                break
            fi
            continue
        fi

        case $choice in
            1|2|3|4)
                local model_types=("cnn" "llm" "vlm" "audio")
                local model_subtypes=("CNN" "LLM" "VLM" "Audio")
                local selected_type="${model_types[$((choice-1))]}"
                local selected_subtype="${model_subtypes[$((choice-1))]}"

                select_specific_model "$selected_type" "$selected_subtype" "$device_id"

                # Check if the RETURN_TO_MAIN_MENU flag has been set and return if true
                if [[ "$RETURN_TO_MAIN_MENU" == "true" ]]; then
                    return  # Return to device_submenu which will return to main menu
                fi
                ;;
            5)
                # Model traversal test
                perform_model_traversal_test "$device_id"

                # After setting up model traversal test, ask user if they want to return to main menu
                echo
                read -rp "Model Traversal Test has been configured. Would you like to return to the main menu? (y/n): " return_choice
                if [[ "$return_choice" =~ ^[Yy]$ ]]; then
                    RETURN_TO_MAIN_MENU=true
                fi
                return  # Return to device submenu
                ;;
            6|7)
                local model_types=("special1" "special2")
                local model_subtypes=("Special Scenario 1" "Special Scenario 2")
                local selected_type="${model_types[$((choice-6))]}"
                local selected_subtype="${model_subtypes[$((choice-6))]}"

                echo -e "${YELLOW}Special scenario testing would be implemented here${NC}"
                echo "Special scenario testing for device $device_id"
                # Additional logic for special scenarios can be added here
                wait_for_user
                ;;
            8)
                return
                ;;
            *)
                echo -e "${RED}Invalid selection, please enter 1-8${NC}"
                wait_for_user
                ;;
        esac
    done
}
