#!/bin/bash

# ============================================================================
# AI Coprocessor Test Script - RKNN-SMI Test Module (Integrated Version)
# ============================================================================

# Define color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[1;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script information
SCRIPT_VERSION="1.0"
TEST_RESULTS_DIR="./test_results"
mkdir -p "$TEST_RESULTS_DIR"

# ============================================================================
# RKNN-SMI Test Core Functions
# ============================================================================

# Use main script's store_device_config and get_device_config functions instead of defining new ones
# These functions should be available from the main script

# Check if rknn-smi command exists
check_rknn_smi() {
    if ! command -v rknn-smi &> /dev/null; then
        echo -e "${RED}rknn-smi command not found, please ensure RKNN driver is properly installed${NC}"
        return 1
    fi
    return 0
}

# Execute reset command based on reset type
# Usage: execute_reset <device_id> <reset_type>
#   reset_type: "hw" for hardware reset, empty for normal reset
execute_reset() {
    local device_id="$1"
    local reset_type="$2"

    if [[ "$reset_type" == "hw" ]]; then
        rknn-smi reset -d "$device_id" -t hw 2>/dev/null
    else
        rknn-smi reset -d "$device_id" 2>/dev/null
    fi
}

# Get device list
get_device_list() {
    rknn-smi info -l 2>/dev/null | grep "Device ID" | awk '{print $NF}' | sort -n
}

# Get chip list for specific device
get_chip_list() {
    local device_id=$1
    rknn-smi info -t cpu_freq -d "$device_id" 2>/dev/null | grep "Chip ID" | awk '{print $NF}' | sort -n
}

# Get available CPU frequencies
get_available_cpu_freq() {
    local device_id=$1
    local chip_id=$2
    rknn-smi info -t cpu_freq -d "$device_id" -c "$chip_id" 2>/dev/null | grep "Available CPU Freq" | awk -F':' '{print $2}' | xargs
}

# Get available NPU frequencies
get_available_npu_freq() {
    local device_id=$1
    local chip_id=$2
    rknn-smi info -t npu_freq -d "$device_id" -c "$chip_id" 2>/dev/null | grep "Available NPU Freq" | awk -F':' '{print $2}' | xargs
}

# Basic information query
query_basic_info() {
    local device_id="$1"

    echo -e "${CYAN}=== Basic RKNN Device Information Query for Device $device_id ===${NC}"

    echo -e "${BLUE}1. Query version information:${NC}"
    rknn-smi -v
    echo

    echo -e "${BLUE}2. Query specific device information:${NC}"
    rknn-smi info -d "$device_id"
    echo

    echo -e "${BLUE}3. Query device detailed information:${NC}"
    rknn-smi info -t board -d "$device_id"
    echo
}

# Detailed status query for specific device
query_detailed_status() {
    local device_id="$1"

    echo -e "${CYAN}=== Detailed RKNN Device Status Query for Device $device_id ===${NC}"

    local info_types=("memory" "fan" "temp" "voltage" "health" "sys_time" "reset_reason" "pcie_err")
    local type_names=("Memory Information" "Fan Speed Ratio" "Temperature Information" "Voltage Information" "Health Status" "System Time" "Last Reset Time" "PCIe Error Count")

    for i in "${!info_types[@]}"; do
        echo -e "${GREEN}$((i+5)). Query device $device_id ${type_names[i]}:${NC}"
        rknn-smi info -t "${info_types[i]}" -d "$device_id"
        echo
        sleep 1
    done
}

# Query frequency and work mode information for specific device
query_frequency_mode_info() {
    local device_id="$1"

    echo -e "${CYAN}=== Frequency and Work Mode Information Query for Device $device_id ===${NC}"

    echo -e "${BLUE}Querying device $device_id:${NC}"

    echo -e "${GREEN}  CPU frequency information:${NC}"
    rknn-smi info -t cpu_freq -d "$device_id"
    echo

    echo -e "${GREEN}  NPU frequency information:${NC}"
    rknn-smi info -t npu_freq -d "$device_id"
    echo

    echo -e "${GREEN}  Work mode information:${NC}"
    rknn-smi info -t work_mode -d "$device_id"
    echo

    sleep 1
}

# CPU frequency setting test
test_cpu_freq_settings() {
    echo -e "${CYAN}=== Starting CPU Frequency Setting Test ===${NC}"

    local devices=$(get_device_list)

    if [ -z "$devices" ]; then
        echo -e "${YELLOW}No RKNN devices found for CPU frequency test${NC}"
        return 1
    fi

    for device in $devices; do
        echo -e "${BLUE}Processing device $device${NC}"
        local chips=$(get_chip_list $device)

        if [ -z "$chips" ]; then
            echo -e "${YELLOW}  No chips found for device $device${NC}"
            continue
        fi

        for chip in $chips; do
            echo -e "${GREEN}  Processing chip $chip${NC}"
            local freq_list=$(get_available_cpu_freq $device $chip)

            if [ -z "$freq_list" ]; then
                echo -e "${YELLOW}    No available CPU frequency information for device $device chip $chip, skipping${NC}"
                continue
            fi

            echo -e "${YELLOW}    Available CPU frequencies: $freq_list${NC}"

            for freq in $freq_list; do
                echo -e "${GREEN}    Setting device ${device} chip ${chip} CPU frequency to: ${freq}MHz${NC}"
                echo -e "${YELLOW}Execute the command: rknn-smi set -t cpu_freq -d $device -c $chip -s $freq${NC}"
                rknn-smi set -t cpu_freq -d "$device" -c "$chip" -s "$freq" 2>/dev/null
                echo -e "${GREEN}    Setting successful${NC}"
                # Verify setting
                sleep 1
                local current_freq=$(rknn-smi info -t cpu_freq -d "$device" -c "$chip" 2>/dev/null | grep "Current CPU Freq" | awk '{print $5}')
                echo -e "${BLUE}    Current CPU frequency: ${current_freq}MHz${NC}"
                echo
                sleep 1
            done
        done
    done
}

# NPU frequency setting test
test_npu_freq_settings() {
    echo -e "${CYAN}=== Starting NPU Frequency Setting Test ===${NC}"

    local devices=$(get_device_list)

    if [ -z "$devices" ]; then
        echo -e "${YELLOW}No RKNN devices found for NPU frequency test${NC}"
        return 1
    fi

    for device in $devices; do
        echo -e "${BLUE}Processing device $device${NC}"
        local chips=$(get_chip_list $device)

        if [ -z "$chips" ]; then
            echo -e "${YELLOW}  No chips found for device $device${NC}"
            continue
        fi

        for chip in $chips; do
            echo -e "${GREEN}  Processing chip $chip${NC}"
            local freq_list=$(get_available_npu_freq $device $chip)

            if [ -z "$freq_list" ]; then
                echo -e "${YELLOW}    No available NPU frequency information for device $device chip $chip, skipping${NC}"
                continue
            fi

            echo -e "${YELLOW}    Available NPU frequencies: $freq_list${NC}"

            for freq in $freq_list; do
                echo -e "${GREEN}    Setting device ${device} chip ${chip} NPU frequency to: ${freq}MHz${NC}"
                echo -e "${YELLOW}Execute the command: rknn-smi set -t npu_freq -d $device -c $chip -s $freq${NC}"
                rknn-smi set -t npu_freq -d "$device" -c "$chip" -s "$freq" 2>/dev/null
                # Verify setting
                sleep 1
                local current_freq=$(rknn-smi info -t npu_freq -d "$device" -c "$chip" 2>/dev/null | grep "Current NPU Freq" | awk '{print $5}')
                echo -e "${BLUE}    Current NPU frequency: ${current_freq}MHz${NC}"
                echo
                sleep 1
            done
        done
    done
}

# Work mode setting test
test_work_mode_settings() {
    echo -e "${CYAN}=== Starting Work Mode Setting Test ===${NC}"

    local devices=$(get_device_list)

    if [ -z "$devices" ]; then
        echo -e "${YELLOW}No RKNN devices found for work mode test${NC}"
        return 1
    fi

    local modes=("0" "1" "2")
    local mode_names=("EFFICIENT" "NORMAL" "PERFORMANCE")

    for device in $devices; do
        echo -e "${BLUE}Processing device $device${NC}"
        local chips=$(get_chip_list $device)

        if [ -z "$chips" ]; then
            echo -e "${YELLOW}  No chips found for device $device${NC}"
            continue
        fi

        for chip in $chips; do
            echo -e "${GREEN}  Processing chip $chip${NC}"

            for i in "${!modes[@]}"; do
                echo -e "${YELLOW}    Setting device ${device} chip ${chip} work mode to: ${mode_names[i]} (${modes[i]})${NC}"
                echo -e "${YELLOW}Execute the command: rknn-smi set -t work_mode -d $device -c $chip -s ${modes[i]}${NC}"
                rknn-smi set -t work_mode -d "$device" -c "$chip" -s "${modes[i]}" 2>/dev/null
                # Verify setting
                sleep 1
                local current_mode=$(rknn-smi info -t work_mode -d "$device" -c "$chip" 2>/dev/null | grep "Chip Work Mode" | awk '{print $NF}')
                echo -e "${BLUE}    Current work mode: $current_mode${NC}"
                echo
                sleep 1
            done
        done
    done
}

# Final status summary
final_status_summary() {
    echo -e "${CYAN}=== Final Status Summary ===${NC}"

    echo -e "${BLUE}Device list:${NC}"
    rknn-smi info -l
    echo

    local devices=$(get_device_list)

    echo -e "${BLUE}Current frequency status:${NC}"
    for device in $devices; do
        echo -e "${GREEN}Device $device CPU frequency:${NC}"
        rknn-smi info -t cpu_freq -d "$device" | grep -E "(Current|Available)" || true
        echo -e "${GREEN}Device $device NPU frequency:${NC}"
        rknn-smi info -t npu_freq -d "$device" | grep -E "(Current|Available)" || true
        echo -e "${GREEN}Device $device work mode:${NC}"
        rknn-smi info -t work_mode -d "$device" | grep "Chip Work Mode" || true
        echo
    done
}

# Reboot test function
reboot_test() {
    echo -e "${CYAN}=== Starting Reboot Test ===${NC}"

    # Check if required commands exist
    if ! command -v rknn-smi &> /dev/null; then
        echo -e "${RED}rknn-smi command not found${NC}"
        return 1
    fi

    # Get available devices
    local devices=$(get_device_list)
    if [ -z "$devices" ]; then
        echo -e "${RED}No RKNN devices found${NC}"
        return 1
    fi

    # Display available devices
    echo -e "${YELLOW}Available devices:${NC}"
    local device_array=()
    local idx=0
    for dev in $devices; do
        device_array[$idx]=$dev
        local comm_mode=$(rknn-smi info -t board -d "$dev" 2>/dev/null | grep "Communication mode" | sed 's/.*Communication mode[[:space:]]*:[[:space:]]*//' | tr -d '[:space:]')
        echo "  $((idx+1)). Device ID: $dev (${comm_mode:-UNKNOWN})"
        ((idx++))
    done

    # Ask user to select device
    local device_choice
    read -p "Select device to test (1-$idx): " device_choice
    if [[ ! "$device_choice" =~ ^[0-9]+$ ]] || [[ "$device_choice" -lt 1 ]] || [[ "$device_choice" -gt $idx ]]; then
        echo -e "${RED}Invalid device selection${NC}"
        return 1
    fi

    local device_id="${device_array[$((device_choice-1))]}"

    # Get device communication mode
    local board_info=$(rknn-smi info -t board -d "$device_id" 2>/dev/null)
    local comm_mode=""
    local bus_addr_or_sn=""

    if echo "$board_info" | grep -q "Communication mode"; then
        comm_mode=$(echo "$board_info" | grep "Communication mode" | sed 's/.*Communication mode[[:space:]]*:[[:space:]]*//' | tr -d '[:space:]')
    fi

    # Get BusAddr/SN for proxy process identification
    if [[ "$comm_mode" == "PCIe" ]]; then
        if echo "$board_info" | grep -q "PCIe Bus Info"; then
            bus_addr_or_sn=$(echo "$board_info" | grep "PCIe Bus Info" | sed 's/.*PCIe Bus Info[[:space:]]*:[[:space:]]*//' | tr -d '[:space:]')
        fi
    elif [[ "$comm_mode" == "USB" ]]; then
        if echo "$board_info" | grep -q "Chip CPUID"; then
            local full_cpuid=$(echo "$board_info" | grep "Chip CPUID" | sed 's/.*Chip CPUID[[:space:]]*:[[:space:]]*//' | tr -d '[:space:]')
            bus_addr_or_sn="${full_cpuid:0:16}"
        fi
    fi

    echo -e "${YELLOW}Device $device_id Communication Mode: ${comm_mode:-UNKNOWN}${NC}"
    if [[ -n "$bus_addr_or_sn" ]]; then
        echo -e "${YELLOW}Device BusAddr/SN: $bus_addr_or_sn${NC}"
    fi
    echo

    # Get number of loops - support 0 for infinite loop and higher maximum
    while true; do
        read -p "Enter number of reboot loops (0=infinite, 1-99999): " loop_count
        if [[ -z "$loop_count" ]]; then
            echo -e "${RED}Error: Input cannot be empty, please re-enter!${NC}"
            continue
        fi

        if [[ ! "$loop_count" =~ ^[0-9]+$ ]]; then
            echo -e "${RED}Error: Please enter a valid non-negative integer!${NC}"
            continue
        fi

        loop_count=$((10#$loop_count))

        if [[ "$loop_count" -eq 0 ]]; then
            echo -e "${YELLOW}Infinite loop mode selected${NC}"
            break
        elif [[ "$loop_count" -ge 1 && "$loop_count" -le 99999 ]]; then
            break
        else
            echo -e "${RED}Error: Please enter 0 for infinite loops or a number between 1-99999!${NC}"
        fi
    done

    if [[ "$loop_count" -eq 0 ]]; then
        echo -e "${YELLOW}Reboot test will run indefinitely until manually stopped${NC}"
    else
        echo -e "${YELLOW}Reboot test will run $loop_count times${NC}"
    fi
    echo

    # Determine reset type based on communication mode
    local reset_type
    local reset_type_display
    if [[ "$comm_mode" == "PCIe" ]]; then
        reset_type="hw"
        reset_type_display="hardware reset (hw)"
        echo -e "${YELLOW}PCIe mode detected: using hardware reset${NC}"
    elif [[ "$comm_mode" == "USB" ]]; then
        reset_type=""
        reset_type_display="normal reset"
        echo -e "${YELLOW}USB mode detected: using normal reset${NC}"
    else
        reset_type=""
        reset_type_display="normal reset"
        echo -e "${YELLOW}Unknown mode: using normal reset for safety${NC}"
    fi

    echo -e "${GREEN}Reset type: $reset_type_display${NC}"
    echo

    # Confirm test execution
    if [[ "$loop_count" -eq 0 ]]; then
        echo -e "${RED}WARNING: This will reboot device $device_id indefinitely until manually stopped!${NC}"
    else
        echo -e "${RED}WARNING: This will reboot device $device_id $loop_count times.${NC}"
    fi
    echo -e "${YELLOW}Reset type: $reset_type_display${NC}"

    read -p "Continue? (y/n): " confirm_choice

    if [[ "$confirm_choice" != "y" ]] && [[ "$confirm_choice" != "Y" ]]; then
        echo -e "${YELLOW}Reboot test cancelled${NC}"
        return
    fi

    local successful_reboots=0
    local failed_reboots=0
    local current_iteration=0

    echo -e "${GREEN}Starting reboot test sequence...${NC}"
    echo -e "${YELLOW}Press Ctrl+C to stop the test at any time${NC}"
    echo

    trap 'echo -e "\n${YELLOW}Test interrupted by user${NC}"; break' INT

    # Main loop
    while true; do
        ((current_iteration++))
        if [[ "$loop_count" -ne 0 ]] && [[ "$current_iteration" -gt "$loop_count" ]]; then
            break
        fi

        if [[ "$loop_count" -eq 0 ]]; then
            echo -e "${BLUE}=== Reboot Test Iteration $current_iteration (Infinite Mode) for Device $device_id ===${NC}"
        else
            echo -e "${BLUE}=== Reboot Test Iteration $current_iteration of $loop_count for Device $device_id ===${NC}"
        fi

        # Step 1: Clean up processes (per documentation)
        echo -e "${GREEN}1. Cleaning up processes for device $device_id...${NC}"
        killall rknn3_llm_demo 2>/dev/null || true
        killall rknn3_cnn_demo 2>/dev/null || true
        killall rknn3_vlm_demo 2>/dev/null || true

        if [[ -n "$bus_addr_or_sn" ]]; then
            echo -e "${YELLOW}   Killing proxy process (BusAddr/SN: $bus_addr_or_sn)...${NC}"
            pkill -f "rknn3_transfer_proxy.*-s.*$bus_addr_or_sn" 2>/dev/null || true
        else
            pkill -f "rknn3_transfer_proxy" 2>/dev/null || true
        fi
        sleep 1

        # Step 2: Reset
        echo -e "${GREEN}2. Executing $reset_type_display for device $device_id...${NC}"
        execute_reset "$device_id" "$reset_type"

        # Step 3: Sleep for device to stabilize
        echo -e "${GREEN}3. Waiting for device to stabilize (5 seconds)...${NC}"
        sleep 5

        # Step 4: Service recovery (per documentation)
        echo -e "${GREEN}4. Service recovery...${NC}"
        if [[ "$comm_mode" == "PCIe" ]]; then
            echo -e "${YELLOW}   PCIe mode: executing rknn3_startup start${NC}"
            rknn3_startup start 2>/dev/null
        elif [[ "$comm_mode" == "USB" ]]; then
            echo -e "${YELLOW}   USB mode: executing rknn3_startup start${NC}"
            rknn3_startup start 2>/dev/null
        else
            echo -e "${YELLOW}   Unknown mode: executing rknn3_startup start${NC}"
            rknn3_startup start 2>/dev/null
        fi

        # Additional wait for system to stabilize
        echo -e "${GREEN}5. Waiting 5 seconds for system to stabilize...${NC}"
        sleep 5

        # Step 6: Verify reboot success
        echo -e "${GREEN}6. Verifying reboot success for device $device_id...${NC}"
        local version_output
        version_output=$(rknn-smi --version 2>/dev/null)

        if echo "$version_output" | grep -q "rknn-smi version"; then
            echo -e "${GREEN}Reboot iteration $current_iteration for device $device_id completed successfully${NC}"
            ((successful_reboots++))
        else
            echo -e "${RED}Reboot iteration $current_iteration for device $device_id failed${NC}"
            ((failed_reboots++))
            echo -e "${RED}Stopping test due to failure${NC}"
            break
        fi

        if [[ "$loop_count" -eq 0 ]] || [[ "$current_iteration" -lt "$loop_count" ]]; then
            echo
            if [[ "$loop_count" -eq 0 ]]; then
                echo -e "${YELLOW}Infinite loop mode - Press Ctrl+C to stop, continuing in 2 seconds...${NC}"
            else
                echo -e "${YELLOW}Preparing for next iteration...${NC}"
            fi
            sleep 2
            echo
        fi
    done

    # Reset signal capture
    trap - INT

    # Display test summary
    echo
    echo -e "${CYAN}=== Reboot Test Summary ===${NC}"

    if [[ "$loop_count" -eq 0 ]]; then
        echo -e "Test mode: Infinite (manually stopped or failure)"
    else
        echo -e "Total iterations requested: $loop_count"
    fi

    echo -e "Device ID: $device_id"
    echo -e "Communication Mode: $comm_mode"
    echo -e "Completed iterations: $((current_iteration - 1))"
    echo -e "${GREEN}Successful reboots: $successful_reboots${NC}"
    echo -e "Reset type used: $reset_type_display"

    if [[ $failed_reboots -gt 0 ]]; then
        echo -e "${RED}Failed reboots: $failed_reboots${NC}"
    else
        echo -e "${GREEN}All reboot tests completed successfully!${NC}"
    fi

    # Final verification
    echo
    echo -e "${CYAN}Final system status verification:${NC}"
    rknn-smi --version

    return $((failed_reboots > 0 ? 1 : 0))
}

# Sleep wake-up test for specific device with duration parameter
sleep_wakeup_test() {
    local device_id="$1"
    local test_hours="${2:-1}"  # Default to 1 hour if not specified

    echo -e "${CYAN}=== Starting Sleep Wake-up Test for Device $device_id ===${NC}"
    # Force flush - print a large amount of text to trigger buffer flush
    echo "================================================================"
    echo "Sleep wake-up test will run for $test_hours hour(s)"
    echo "Testing suspend and wakeup functionality continuously"
    echo "================================================================"
    echo

    # Validate inputs
    if [[ ! "$test_hours" =~ ^[0-9]+$ ]] || [[ "$test_hours" -lt 1 ]]; then
        echo -e "${RED}Error: Test hours must be a positive integer${NC}"
        return 1
    fi

    # Check if required commands exist
    if ! command -v rknn-smi &> /dev/null; then
        echo -e "${RED}rknn-smi command not found${NC}"
        return 1
    fi

    # Calculate test duration in seconds
    local test_duration_seconds=$((test_hours * 3600))
    echo -e "${YELLOW}Sleep wake-up test will run for $test_hours hour(s) ($test_duration_seconds seconds) for device $device_id${NC}"
    echo
    # Force flush with more output
    for i in {1..20}; do echo "========================================"; done

    local successful_cycles=0
    local failed_cycles=0
    local start_time
    start_time=$(date +%s)
    local current_iteration=0
    local test_stopped_for_failure=false  # Track if test stopped due to failure

    # Retry settings
    local max_retries=3      # Max retries when output is empty/unclear
    local retry_delay=2      # Seconds to wait between retries

    echo -e "${GREEN}Starting sleep wake-up test sequence...${NC}"
    echo -e "${YELLOW}Press Ctrl+C to stop the test at any time${NC}"
    echo -e "${YELLOW}Test will retry up to $max_retries times if output is unclear${NC}"
    echo -e "${RED}Test will stop immediately if 'failed' appears in output${NC}"
    echo
    # More flush padding
    for i in {1..10}; do echo "."; done

    # Capture both SIGINT and SIGTERM for graceful shutdown
    trap 'echo -e "\n${YELLOW}Test interrupted by signal${NC}"; break' INT TERM

    # Helper function to execute command with retry
    execute_with_retry() {
        local cmd="$1"
        local operation="$2"  # "suspend" or "wakeup"
        local retry_count=0
        local output=""
        local result=""

        while [[ $retry_count -lt $max_retries ]]; do
            output=$(eval "$cmd" 2>&1)

            # Check for "failed" in output - immediate failure, no retry
            if echo "$output" | grep -qi "failed"; then
                result="FAILED"
                echo "   Output: $output"
                return 1
            # Check for "Successfully" in output - success
            elif echo "$output" | grep -qi "Successfully"; then
                result="SUCCESS"
                echo "   Output: $output"
                return 0
            # Output is empty or unclear - retry
            else
                ((retry_count++))
                if [[ $retry_count -lt $max_retries ]]; then
                    echo "   Output: $output (empty/unclear, retrying...)"
                    echo -e "${YELLOW}   $operation output unclear, waiting $retry_delay seconds and retrying ($retry_count/$max_retries)${NC}"
                    sleep $retry_delay
                else
                    echo "   Output: $output"
                    echo -e "${RED}   $operation FAILED after $max_retries retries (no valid output)${NC}"
                    result="FAILED"
                    return 1
                fi
            fi
        done

        return 1
    }

    # Main loop - run until time expires or failure detected
    while true; do
        ((current_iteration++))

        local current_time
        current_time=$(date +%s)
        local elapsed_time=$((current_time - start_time))

        # Check if test duration has been reached
        if [[ $elapsed_time -ge $test_duration_seconds ]]; then
            echo -e "${GREEN}Test duration of $test_hours hour(s) reached. Ending test.${NC}"
            break
        fi

        local remaining_time=$((test_duration_seconds - elapsed_time))
        local remaining_hours=$((remaining_time / 3600))
        local remaining_minutes=$(( (remaining_time % 3600) / 60 ))
        local remaining_seconds=$((remaining_time % 60))

        echo -e "${BLUE}=== Sleep Wake-up Test Iteration $current_iteration ===${NC}"
        echo -e "${YELLOW}Elapsed: ${elapsed_time}s | Remaining: ${remaining_hours}h ${remaining_minutes}m ${remaining_seconds}s${NC}"

        # Step 1: Suspend device with retry
        echo -e "${GREEN}1. Executing suspend for device $device_id: rknn-smi suspend${NC}"
        if execute_with_retry "rknn-smi suspend" "Suspend"; then
            echo -e "${GREEN}   Suspend successful${NC}"
        else
            echo -e "${RED}   Suspend FAILED${NC}"
            ((failed_cycles++))
            test_stopped_for_failure=true
            break
        fi

        # Step 2: Sleep for a short interval
        echo -e "${GREEN}2. Waiting for 2 seconds...${NC}"
        sleep 2

        # Step 3: Wakeup device with retry
        echo -e "${GREEN}3. Executing wakeup for device $device_id: rknn-smi wakeup${NC}"
        if execute_with_retry "rknn-smi wakeup" "Wakeup"; then
            echo -e "${GREEN}   Wakeup successful${NC}"
            ((successful_cycles++))
        else
            echo -e "${RED}   Wakeup FAILED${NC}"
            ((failed_cycles++))
            test_stopped_for_failure=true
            break
        fi

        # Step 4: Short wait before next cycle
        echo -e "${GREEN}4. Waiting 3 seconds before next cycle...${NC}"
        sleep 3

        # Heartbeat output to keep log file growing and prevent stuck detection
        echo -e "${CYAN}[Heartbeat] Iteration $current_iteration done, test continuing...${NC}"
        echo "........................................"
        echo
    done

    # Reset signal capture
    trap - INT TERM

    # Display test summary
    echo
    echo -e "${CYAN}=== Sleep Wake-up Test Summary for Device $device_id ===${NC}"
    echo -e "Test duration: $test_hours hour(s)"
    echo -e "Total iterations: $current_iteration"
    echo -e "${GREEN}Successful cycles: $successful_cycles${NC}"
    echo -e "${RED}Failed cycles: $failed_cycles${NC}"

    # Determine final status
    local exit_code=0

    if [[ $failed_cycles -gt 0 ]]; then
        exit_code=1
        echo -e "${RED}Test result: FAILED (detected failures during test)${NC}"
    elif [[ "$test_stopped_for_failure" == "true" ]]; then
        exit_code=1
        echo -e "${RED}Test result: FAILED (test stopped due to failure detection)${NC}"
    else
        echo -e "${GREEN}Test result: SUCCESS (all tests passed)${NC}"
    fi

    # Final verification with more padding
    echo
    echo "Final system status:"
    rknn-smi info -d "$device_id" | head -10
    for i in {1..10}; do echo "========================================"; done

    return $exit_code
}

# Hardware reset test for specific device with parameters
hardware_reset_test() {
    local device_id="$1"
    local loop_count="${2:-1}"  # Default to 1 if not specified
    local reset_type="${3:-}"   # Default to empty (will be determined by communication mode)

    echo -e "${CYAN}=== Starting Hardware Reset Test for Device $device_id ===${NC}"

    # Validate inputs - support 0 for infinite loop
    if [[ ! "$loop_count" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Error: Loop count must be a non-negative integer${NC}"
        return 1
    fi

    loop_count=$((10#$loop_count))  # Ensure base-10 interpretation

    if [[ "$loop_count" -eq 0 ]]; then
        echo -e "${YELLOW}Infinite loop mode selected - test will run until manually stopped or failure${NC}"
    elif [[ "$loop_count" -lt 1 ]] || [[ "$loop_count" -gt 99999 ]]; then
        echo -e "${RED}Error: Loop count must be 0 (infinite) or between 1 and 99999${NC}"
        return 1
    fi

    # Check if required commands exist
    if ! command -v rknn-smi &> /dev/null; then
        echo -e "${RED}rknn-smi command not found${NC}"
        return 1
    fi

    # Get device communication mode and BusAddr/SN for identifying proxy processes
    local comm_mode=""
    local bus_addr_or_sn=""

    # Get communication mode from rknn-smi info -t board
    local board_info=$(rknn-smi info -t board -d "$device_id" 2>/dev/null)

    # Check for communication mode
    if echo "$board_info" | grep -q "Communication mode"; then
        comm_mode=$(echo "$board_info" | grep "Communication mode" | sed 's/.*Communication mode[[:space:]]*:[[:space:]]*//' | tr -d '[:space:]')
    fi

    # Get BusAddr (PCIe) or Chip CPUID (USB) for identifying proxy process
    if [[ "$comm_mode" == "PCIe" ]]; then
        # PCIe mode: get PCIe Bus Info
        if echo "$board_info" | grep -q "PCIe Bus Info"; then
            bus_addr_or_sn=$(echo "$board_info" | grep "PCIe Bus Info" | sed 's/.*PCIe Bus Info[[:space:]]*:[[:space:]]*//' | tr -d '[:space:]')
        fi
    elif [[ "$comm_mode" == "USB" ]]; then
        # USB mode: get Chip CPUID (first 16 chars)
        if echo "$board_info" | grep -q "Chip CPUID"; then
            local full_cpuid=$(echo "$board_info" | grep "Chip CPUID" | sed 's/.*Chip CPUID[[:space:]]*:[[:space:]]*//' | tr -d '[:space:]')
            bus_addr_or_sn="${full_cpuid:0:16}"
        fi
    fi

    # Determine reset type based on communication mode if not explicitly specified
    if [[ -z "$reset_type" ]]; then
        if [[ "$comm_mode" == "PCIe" ]]; then
            reset_type="hw"
            echo -e "${YELLOW}PCIe mode detected: using hardware reset (hw)${NC}"
        elif [[ "$comm_mode" == "USB" ]]; then
            reset_type=""
            echo -e "${YELLOW}USB mode detected: using normal reset (no hw parameter)${NC}"
        else
            # Unknown mode: default to normal reset for safety
            reset_type=""
            echo -e "${YELLOW}Unknown communication mode: using normal reset for safety${NC}"
        fi
    fi

    # Display reset type in a readable format
    local reset_type_display
    if [[ "$reset_type" == "hw" ]]; then
        reset_type_display="hardware reset (hw)"
    else
        reset_type_display="normal reset"
    fi

    echo -e "${YELLOW}Device $device_id Communication Mode: ${comm_mode:-UNKNOWN}${NC}"
    echo -e "${YELLOW}Reset type: $reset_type_display${NC}"
    if [[ -n "$bus_addr_or_sn" ]]; then
        echo -e "${YELLOW}Device BusAddr/SN: $bus_addr_or_sn${NC}"
    fi

    if [[ "$loop_count" -eq 0 ]]; then
        echo -e "${YELLOW}Reset test will run indefinitely until manually stopped or failure for device $device_id${NC}"
    else
        echo -e "${YELLOW}Reset test will run $loop_count times for device $device_id${NC}"
    fi
    echo

    local successful_resets=0
    local failed_resets=0
    local current_iteration=0

    echo -e "${GREEN}Starting reset test sequence...${NC}"
    echo -e "${YELLOW}Press Ctrl+C to stop the test at any time${NC}"
    echo -e "${RED}Test will stop immediately if a reset fails${NC}"
    echo

    trap 'echo -e "\n${YELLOW}Test interrupted by user${NC}"; break' INT

    # Main loop - support infinite loop when loop_count is 0
    while true; do
        ((current_iteration++))
        if [[ "$loop_count" -ne 0 ]] && [[ "$current_iteration" -gt "$loop_count" ]]; then
            break
        fi

        if [[ "$loop_count" -eq 0 ]]; then
            echo -e "${BLUE}=== Reset Test Iteration $current_iteration (Infinite Mode) for Device $device_id ===${NC}"
        else
            echo -e "${BLUE}=== Reset Test Iteration $current_iteration of $loop_count for Device $device_id ===${NC}"
        fi

        # Step 1: Clean up processes using this device (per documentation)
        echo -e "${GREEN}1. Cleaning up processes for device $device_id...${NC}"

        # Kill user application processes (rknn3_llm_demo, rknn3_cnn_demo, etc.)
        echo -e "${YELLOW}   Killing user application processes...${NC}"
        killall rknn3_llm_demo 2>/dev/null || true
        killall rknn3_cnn_demo 2>/dev/null || true
        killall rknn3_vlm_demo 2>/dev/null || true

        # Kill specific proxy process for this device
        # The proxy process name format: rknn3_transfer_proxy_xxxxxxxx -s [BusAddr/SN]
        if [[ -n "$bus_addr_or_sn" ]]; then
            echo -e "${YELLOW}   Killing proxy process for device $device_id (BusAddr/SN: $bus_addr_or_sn)...${NC}"
            pkill -f "rknn3_transfer_proxy.*-s.*$bus_addr_or_sn" 2>/dev/null || true
        else
            # Fallback: kill all transfer proxy processes if we can't identify specific one
            echo -e "${YELLOW}   Killing all rknn3_transfer_proxy processes (BusAddr/SN not available)...${NC}"
            pkill -f "rknn3_transfer_proxy" 2>/dev/null || true
        fi

        sleep 1

        # Step 2: Reset
        local reset_type_display
        if [[ "$reset_type" == "hw" ]]; then
            reset_type_display="hardware reset (hw)"
        else
            reset_type_display="normal reset"
        fi
        echo -e "${GREEN}2. Executing $reset_type_display for device $device_id...${NC}"

        execute_reset "$device_id" "$reset_type"

        # Step 3: Sleep for device to stabilize
        echo -e "${GREEN}3. Waiting for device to stabilize (5 seconds)...${NC}"
        sleep 5

        # Step 4: Service recovery (per documentation)
        echo -e "${GREEN}4. Service recovery...${NC}"

        if [[ "$comm_mode" == "PCIe" ]]; then
            # PCIe mode: manually restart service using rknn3_startup start
            echo -e "${YELLOW}   PCIe mode: executing rknn3_startup start${NC}"
            rknn3_startup start 2>/dev/null
        elif [[ "$comm_mode" == "USB" ]]; then
            # USB mode: manually restart service using rknn3_startup start
            echo -e "${YELLOW}   USB mode: executing rknn3_startup start${NC}"
            rknn3_startup start 2>/dev/null
        else
            # Unknown mode: try rknn3_startup start as fallback
            echo -e "${YELLOW}   Unknown communication mode, executing rknn3_startup start${NC}"
            rknn3_startup start 2>/dev/null
        fi

        # Additional wait for system to stabilize
        echo -e "${GREEN}5. Waiting 5 seconds for system to stabilize...${NC}"
        sleep 5

        # Step 6: Verify reset success
        echo -e "${GREEN}6. Verifying reset success for device $device_id...${NC}"
        local version_output
        version_output=$(rknn-smi --version 2>/dev/null)

        if echo "$version_output" | grep -q "rknn-smi version"; then
            echo -e "${GREEN}Reset iteration $current_iteration for device $device_id completed successfully${NC}"
            ((successful_resets++))
        else
            echo -e "${RED}Reset iteration $current_iteration for device $device_id failed${NC}"
            ((failed_resets++))
            # Stop immediately on failure for safety
            echo -e "${RED}Stopping test due to reset failure${NC}"
            break
        fi

        if [[ "$loop_count" -eq 0 ]] || [[ "$current_iteration" -lt "$loop_count" ]]; then
            echo
            if [[ "$loop_count" -eq 0 ]]; then
                echo -e "${YELLOW}Infinite loop mode - Press Ctrl+C to stop, continuing in 2 seconds...${NC}"
            else
                echo -e "${YELLOW}Preparing for next iteration...${NC}"
            fi
            sleep 2
            echo
        fi
    done

    # Reset signal capture
    trap - INT

    # Display test summary
    echo
    echo -e "${CYAN}=== Reset Test Summary for Device $device_id ===${NC}"

    if [[ "$loop_count" -eq 0 ]]; then
        echo -e "Test mode: Infinite (manually stopped or failure detected)"
    else
        echo -e "Total iterations requested: $loop_count"
    fi

    echo -e "Completed iterations: $((current_iteration - 1))"
    echo -e "${GREEN}Successful resets: $successful_resets${NC}"
    echo -e "Reset type used: $reset_type_display"

    if [[ $failed_resets -gt 0 ]]; then
        echo -e "${RED}Failed resets: $failed_resets${NC}"
        echo -e "${RED}Test stopped due to failure${NC}"
    else
        echo -e "${GREEN}All reset tests for device $device_id completed successfully!${NC}"
    fi

    # Final verification
    echo
    echo -e "${CYAN}Final system status verification for device $device_id:${NC}"
    rknn-smi info -d "$device_id" | head -10

    return $((failed_resets > 0 ? 1 : 0))
}

# Main RKNN-SMI test function for a specific device
rknn_smi_test_for_device() {
    local device_id="$1"

    echo -e "${PURPLE}=== Starting Comprehensive RKNN-SMI Test for Device $device_id ===${NC}"
    echo

    # Check if rknn-smi command exists
    if ! check_rknn_smi; then
        return 1
    fi

    # Basic information query
    query_basic_info "$device_id"
    sleep 1

    # Detailed status query
    query_detailed_status "$device_id"
    sleep 1

    # Frequency and work mode information query
    query_frequency_mode_info "$device_id"
    sleep 1

    # CPU frequency setting test
    test_cpu_freq_settings "$device_id"
    sleep 1

    # NPU frequency setting test
    test_npu_freq_settings "$device_id"
    sleep 1

    # Work mode setting test
    test_work_mode_settings "$device_id"

    # Final status summary
    final_status_summary "$device_id"

    echo -e "${GREEN}RKNN-SMI Comprehensive Test for Device $device_id Completed Successfully${NC}"
    return 0
}

# Perform SMI test on a specific device (to be called from main script)
perform_smi_test() {
    local device_id="$1"
    local test_type="${2:-comprehensive}"  # Default to comprehensive if not specified
    local loop_count="${3:-1}"             # Default to 1 for reset tests
    local reset_type="${4:-}"              # Default to empty, will be determined by communication mode

    case "$test_type" in
        "comprehensive")
            rknn_smi_test_for_device "$device_id"
            ;;
        "reset")
            hardware_reset_test "$device_id" "$loop_count" "$reset_type"
            ;;
        *)
            echo -e "${RED}Unknown test type: $test_type${NC}"
            echo "Supported test types: comprehensive, reset"
            return 1
            ;;
    esac
}

# Main RKNN-SMI test function (preserving original functionality)
rknn_smi_test() {
    echo -e "${PURPLE}=== Starting Comprehensive RKNN-SMI Test ===${NC}"
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

    echo -e "${GREEN}RKNN-SMI Comprehensive Test Completed Successfully${NC}"
    return 0
}

# RKNN-SMI Test Menu
rknn_smi_test_menu() {
    while true; do
        clear
        echo -e "${PURPLE}========================================${NC}"
        echo -e "${GREEN}          AI Coprocessor Test Script${NC}"
        echo -e "${GREEN}          RKNN-SMI Test Module${NC}"
        echo -e "${PURPLE}========================================${NC}"
        echo
        echo -e "${CYAN}RKNN-SMI Test Menu${NC}"
        echo "========================================"
        echo "1. Run Comprehensive RKNN-SMI Test"
        echo "2. Reboot Test"
        echo "3. Sleep Wake-up Test"
        echo "4. Return to Main Menu"
        echo

        read -p "Please select an option (1-4): " choice

        case $choice in
            1)
                echo -e "${YELLOW}Starting comprehensive RKNN-SMI test...${NC}"
                rknn_smi_test
                echo
                read -p "Press Enter to continue..."
                ;;
            2)
                echo -e "${YELLOW}Starting Reboot Test...${NC}"
                reboot_test
                echo
                read -p "Press Enter to continue..."
                ;;
            3)
                echo -e "${YELLOW}Starting Sleep Wake-up Test...${NC}"
                # Ask for test duration in hours
                local test_hours
                read -p "Enter test duration in hours (default: 1): " test_hours
                if [[ -z "$test_hours" ]]; then
                    test_hours=1
                elif [[ ! "$test_hours" =~ ^[0-9]+$ ]] || [[ "$test_hours" -lt 1 ]]; then
                    echo "Invalid input. Defaulting to 1 hour."
                    test_hours=1
                fi
                sleep_wakeup_test 0 "$test_hours"
                echo
                read -p "Press Enter to continue..."
                ;;
            4)
                return
                ;;
            *)
                echo -e "${RED}Invalid selection, please enter 1-4${NC}"
                echo
                read -p "Press Enter to continue..."
                ;;
        esac
    done
}

# Function to store SMI test configuration - placeholder in case it's not defined elsewhere
# SMI test configuration recording - Records configuration only, does not execute tests
record_smi_config() {
    local device_id="$1"

    # Clear previous configuration for this device before storing new one
    clear_device_config "$device_id"

    echo "Recording SMI test configuration for device $device_id"
    echo

    if ! command -v rknn-smi &> /dev/null; then
        echo "Error: rknn-smi command not found"
        wait_for_user
        return 1
    fi

    # Always ask user what type of SMI test they want to configure
    echo "Select SMI test type for device $device_id:"
    echo "1. Comprehensive SMI Test (Information Query and Settings)"
    echo "2. Reset Test"
    echo "3. Sleep Wake-up Test"
    echo "4. Back to Device Menu"
    echo

    read -rp "Please select a test type (1-4): " choice

    case $choice in
        1)
            # Record the SMI test configuration - NO ACTUAL TEST EXECUTION HERE
            store_device_config "$device_id" "test_category" "SMI Testing"
            store_device_config "$device_id" "smi_test_type" "Comprehensive SMI Test"

            # Inform user that test is scheduled but not executed yet
            echo "Comprehensive SMI test scheduled for device $device_id."
            echo "Will be executed during 'Start Testing Process'."
            read -rp "Press Enter to return to main menu..." dummy
            RETURN_TO_MAIN_MENU=true
            return
            ;;
        2)
            # Record the reset test configuration - NO ACTUAL TEST EXECUTION HERE
            store_device_config "$device_id" "test_category" "SMI Testing"
            store_device_config "$device_id" "smi_test_type" "Reset Test"

            # Ask for reset loop count but don't execute yet
            read -rp "Enter number of reset loops (0=infinite, 1-99999) for scheduled test: " loop_count
            if [[ ! "$loop_count" =~ ^[0-9]+$ ]]; then
                echo "Invalid loop count. Defaulting to 1."
                loop_count=1
            fi
            loop_count=$((10#$loop_count))  # Ensure base-10 interpretation
            if [[ "$loop_count" -gt 99999 ]]; then
                echo "Loop count exceeds maximum 99999. Defaulting to 99999."
                loop_count=99999
            fi

            # Store the reset configuration
            store_device_config "$device_id" "reset_loop_count" "$loop_count"

            # Inform user that test is scheduled but not executed yet
            echo "Reset test scheduled for device $device_id with $loop_count loops."
            echo "Will be executed during 'Start Testing Process'."
            read -rp "Press Enter to return to main menu..." dummy
            RETURN_TO_MAIN_MENU=true
            return
            ;;
        3)
            # Record the sleep wake-up test configuration - NO ACTUAL TEST EXECUTION HERE
            store_device_config "$device_id" "test_category" "SMI Testing"
            store_device_config "$device_id" "smi_test_type" "Sleep Wake-up Test"

            # Ask for test duration in hours
            read -rp "Enter test duration in hours (default: 1): " sleep_wakeup_hours
            if [[ -z "$sleep_wakeup_hours" ]]; then
                echo "No input. Defaulting to 1 hour."
                sleep_wakeup_hours=1
            elif [[ ! "$sleep_wakeup_hours" =~ ^[0-9]+$ ]] || [[ "$sleep_wakeup_hours" -lt 1 ]]; then
                echo "Invalid input. Defaulting to 1 hour."
                sleep_wakeup_hours=1
            fi

            # Store the sleep wake-up configuration
            store_device_config "$device_id" "sleep_wakeup_hours" "$sleep_wakeup_hours"

            # Inform user that test is scheduled but not executed yet
            echo "Sleep wake-up test scheduled for device $device_id with $sleep_wakeup_hours hour(s)."
            echo "Will be executed during 'Start Testing Process'."
            read -rp "Press Enter to return to main menu..." dummy
            RETURN_TO_MAIN_MENU=true
            return
            ;;
        4)
            # User wants to go back to device menu
            return
            ;;
        *)
            echo -e "${RED}Invalid selection, please enter 1-4${NC}"
            wait_for_user
            ;;
    esac
}


# ============================================================================
# Multi-Device Round-Robin Reset Test
# ============================================================================
# This function performs reset tests on multiple devices in a round-robin fashion.
# Instead of parallel execution, it resets devices sequentially: device0 -> device1 -> device2 -> ...
# This avoids the problems of:
#   1. killall killing processes on all devices
#   2. Lock contention causing stuck detection
#
# Reset type is automatically determined based on communication mode:
#   - PCIe devices: use hardware reset (hw)
#   - USB devices: use normal reset (no hw parameter)
#
# Usage: multi_device_round_robin_reset_test <device_configs>
#   device_configs format: "device_id:loop_count" for each device, space-separated
#   Example: "0:100 1:100 2:50"
#
multi_device_round_robin_reset_test() {
    local device_configs="$1"

    echo -e "${CYAN}=== Starting Multi-Device Round-Robin Reset Test ===${NC}"
    echo

    # Check if required commands exist
    if ! command -v rknn-smi &> /dev/null; then
        echo -e "${RED}rknn-smi command not found${NC}"
        return 1
    fi

    # Parse device configurations
    declare -a DEVICE_IDS
    declare -a LOOP_COUNTS
    declare -a CURRENT_COUNTS
    declare -a SUCCESSFUL_COUNTS
    declare -a FAILED_COUNTS
    declare -a COMM_MODES
    declare -a BUS_ADDR_SN
    declare -a COMPLETED_FLAGS
    declare -a RESET_TYPES  # Store reset type for each device based on comm mode

    local device_count=0
    local max_rounds=0
    local has_infinite=false

    for config in $device_configs; do
        # Parse each config: "device_id:loop_count"
        local device_id=$(echo "$config" | cut -d':' -f1)
        local loop_count=$(echo "$config" | cut -d':' -f2)

        # Validate device_id
        if [[ ! "$device_id" =~ ^[0-9]+$ ]]; then
            echo -e "${RED}Invalid device ID in config: $config${NC}"
            return 1
        fi

        # Validate loop_count (support 0 for infinite)
        if [[ ! "$loop_count" =~ ^[0-9]+$ ]]; then
            echo -e "${RED}Invalid loop count in config: $config${NC}"
            return 1
        fi

        loop_count=$((10#$loop_count))  # Ensure base-10 interpretation

        DEVICE_IDS[$device_count]=$device_id
        LOOP_COUNTS[$device_count]=$loop_count
        CURRENT_COUNTS[$device_count]=0
        SUCCESSFUL_COUNTS[$device_count]=0
        FAILED_COUNTS[$device_count]=0
        COMPLETED_FLAGS[$device_count]=false

        # Track maximum rounds needed (for finite loops)
        if [[ "$loop_count" -eq 0 ]]; then
            has_infinite=true
        elif [[ "$loop_count" -gt "$max_rounds" ]]; then
            max_rounds=$loop_count
        fi

        # Get device info (communication mode and BusAddr/SN)
        local board_info=$(rknn-smi info -t board -d "$device_id" 2>/dev/null)
        local comm_mode=""
        local bus_addr_or_sn=""

        if echo "$board_info" | grep -q "Communication mode"; then
            comm_mode=$(echo "$board_info" | grep "Communication mode" | sed 's/.*Communication mode[[:space:]]*:[[:space:]]*//' | tr -d '[:space:]')
        fi

        if [[ "$comm_mode" == "PCIe" ]]; then
            if echo "$board_info" | grep -q "PCIe Bus Info"; then
                bus_addr_or_sn=$(echo "$board_info" | grep "PCIe Bus Info" | sed 's/.*PCIe Bus Info[[:space:]]*:[[:space:]]*//' | tr -d '[:space:]')
            fi
        elif [[ "$comm_mode" == "USB" ]]; then
            if echo "$board_info" | grep -q "Chip CPUID"; then
                local full_cpuid=$(echo "$board_info" | grep "Chip CPUID" | sed 's/.*Chip CPUID[[:space:]]*:[[:space:]]*//' | tr -d '[:space:]')
                bus_addr_or_sn="${full_cpuid:0:16}"
            fi
        fi

        COMM_MODES[$device_count]="$comm_mode"
        BUS_ADDR_SN[$device_count]="$bus_addr_or_sn"

        # Determine reset type based on communication mode
        local device_reset_type
        if [[ "$comm_mode" == "PCIe" ]]; then
            device_reset_type="hw"
        elif [[ "$comm_mode" == "USB" ]]; then
            device_reset_type=""  # Normal reset for USB
        else
            device_reset_type=""  # Default to normal reset for unknown modes
        fi
        RESET_TYPES[$device_count]="$device_reset_type"

        ((device_count++))
    done

    # Display test configuration
    echo -e "${YELLOW}Test Configuration:${NC}"
    echo -e "${YELLOW}  Total devices: $device_count${NC}"
    for i in "${!DEVICE_IDS[@]}"; do
        local loop_str="${LOOP_COUNTS[$i]}"
        if [[ "${LOOP_COUNTS[$i]}" -eq 0 ]]; then
            loop_str="infinite"
        fi
        local reset_type_str
        if [[ "${RESET_TYPES[$i]}" == "hw" ]]; then
            reset_type_str="hardware reset (hw)"
        else
            reset_type_str="normal reset"
        fi
        echo -e "${YELLOW}  Device ${DEVICE_IDS[$i]}: ${loop_str} iterations, Communication: ${COMM_MODES[$i]:-UNKNOWN}, Reset: ${reset_type_str}${NC}"
    done
    echo

    if [[ "$has_infinite" == "true" ]]; then
        echo -e "${YELLOW}Test will run indefinitely for some devices until manually stopped or failure${NC}"
    fi

    echo -e "${GREEN}Starting round-robin reset test sequence...${NC}"
    echo -e "${YELLOW}Press Ctrl+C to stop the test at any time${NC}"
    echo -e "${RED}Test will stop immediately if any device reset fails${NC}"
    echo

    # Trap Ctrl+C
    trap 'echo -e "\n${YELLOW}Test interrupted by user${NC}"; break' INT

    # Main round-robin loop
    local current_round=0
    local all_completed=false
    local test_failed=false

    while [[ "$all_completed" == "false" && "$test_failed" == "false" ]]; do
        ((current_round++))

        echo -e "${PURPLE}========== Round $current_round ==========${NC}"
        echo

        # Iterate through each device in order
        for i in "${!DEVICE_IDS[@]}"; do
            local device_id="${DEVICE_IDS[$i]}"
            local loop_count="${LOOP_COUNTS[$i]}"
            local current_count="${CURRENT_COUNTS[$i]}"
            local comm_mode="${COMM_MODES[$i]}"
            local bus_addr_or_sn="${BUS_ADDR_SN[$i]}"
            local reset_type="${RESET_TYPES[$i]}"  # Use device-specific reset type

            # Check if this device has completed its iterations
            if [[ "${COMPLETED_FLAGS[$i]}" == "true" ]]; then
                echo -e "${GREEN}[Device $device_id] Already completed (${SUCCESSFUL_COUNTS[$i]}/${loop_count}), skipping...${NC}"
                continue
            fi

            # Check if this device has reached its target
            if [[ "$loop_count" -ne 0 ]] && [[ "$current_count" -ge "$loop_count" ]]; then
                COMPLETED_FLAGS[$i]=true
                echo -e "${GREEN}[Device $device_id] Target reached (${current_count}/${loop_count}), marking as completed${NC}"
                continue
            fi

            # Display reset type being used
            local reset_type_display
            if [[ "$reset_type" == "hw" ]]; then
                reset_type_display="hardware reset (hw)"
            else
                reset_type_display="normal reset"
            fi

            echo -e "${BLUE}--- [Device $device_id] Reset iteration $((current_count + 1)) (${reset_type_display}) ---${NC}"

            # Step 1: Clean up processes for this device
            echo -e "${GREEN}1. Cleaning up processes for device $device_id...${NC}"
            killall rknn3_llm_demo 2>/dev/null || true
            killall rknn3_cnn_demo 2>/dev/null || true
            killall rknn3_vlm_demo 2>/dev/null || true

            if [[ -n "$bus_addr_or_sn" ]]; then
                echo -e "${YELLOW}   Killing proxy process (BusAddr/SN: $bus_addr_or_sn)...${NC}"
                pkill -f "rknn3_transfer_proxy.*-s.*$bus_addr_or_sn" 2>/dev/null || true
            else
                pkill -f "rknn3_transfer_proxy" 2>/dev/null || true
            fi
            sleep 1

            # Step 2: Execute reset with device-specific reset type
            echo -e "${GREEN}2. Executing reset for device $device_id (${reset_type_display})...${NC}"
            local reset_ret=0
            execute_reset "$device_id" "$reset_type"
            reset_ret=$?

            if [[ $reset_ret -ne 0 ]]; then
                echo -e "${RED}Reset command failed for device $device_id (return: $reset_ret)${NC}"
                ((FAILED_COUNTS[$i]++))
                test_failed=true
                break
            fi

            # Step 3: Wait for device to stabilize
            echo -e "${GREEN}3. Waiting for device to stabilize (2 seconds)...${NC}"
            sleep 2

            # Step 4: Service recovery
            echo -e "${GREEN}4. Service recovery...${NC}"
            if [[ "$comm_mode" == "PCIe" ]]; then
                echo -e "${YELLOW}   PCIe mode: executing rknn3_startup start${NC}"
                rknn3_startup start 2>/dev/null
            elif [[ "$comm_mode" == "USB" ]]; then
                echo -e "${YELLOW}   USB mode: executing rknn3_startup start${NC}"
                rknn3_startup start 2>/dev/null
            else
                echo -e "${YELLOW}   Unknown mode: executing rknn3_startup start${NC}"
                rknn3_startup start 2>/dev/null
            fi

            # Step 5: Additional stabilization wait
            echo -e "${GREEN}5. Waiting 2 seconds for system stabilization...${NC}"
            sleep 2

            # Step 6: Verify reset success
            echo -e "${GREEN}6. Verifying reset success for device $device_id...${NC}"
            local version_output=$(rknn-smi --version 2>/dev/null)

            if echo "$version_output" | grep -q "rknn-smi version"; then
                echo -e "${GREEN}Reset for device $device_id completed successfully${NC}"
                ((SUCCESSFUL_COUNTS[$i]++))
                ((CURRENT_COUNTS[$i]++))
            else
                echo -e "${RED}Reset verification failed for device $device_id${NC}"
                ((FAILED_COUNTS[$i]++))
                test_failed=true
                break
            fi

            echo
        done

        # Check if all devices have completed
        all_completed=true
        for i in "${!DEVICE_IDS[@]}"; do
            if [[ "${COMPLETED_FLAGS[$i]}" == "false" ]]; then
                all_completed=false
                break
            fi
        done

        # For infinite mode, check if any device has infinite loop
        if [[ "$has_infinite" == "true" && "$test_failed" == "false" ]]; then
            all_completed=false
        fi

        if [[ "$all_completed" == "false" && "$test_failed" == "false" ]]; then
            echo -e "${YELLOW}Preparing for next round...${NC}"
            sleep 2
        fi
    done

    # Reset signal capture
    trap - INT

    # Display final summary
    echo
    echo -e "${CYAN}==========================================${NC}"
    echo -e "${CYAN}=== Multi-Device Round-Robin Reset Test Summary ===${NC}"
    echo -e "${CYAN}==========================================${NC}"
    echo

    echo -e "${YELLOW}Total rounds executed: $current_round${NC}"
    echo

    local overall_success=true
    for i in "${!DEVICE_IDS[@]}"; do
        local device_id="${DEVICE_IDS[$i]}"
        local loop_count="${LOOP_COUNTS[$i]}"
        local successful="${SUCCESSFUL_COUNTS[$i]}"
        local failed="${FAILED_COUNTS[$i]}"
        local reset_type="${RESET_TYPES[$i]}"
        local comm_mode="${COMM_MODES[$i]}"

        # Display reset type in readable format
        local reset_type_display
        if [[ "$reset_type" == "hw" ]]; then
            reset_type_display="hardware reset (hw)"
        else
            reset_type_display="normal reset"
        fi

        echo -e "${CYAN}Device $device_id:${NC}"
        if [[ "$loop_count" -eq 0 ]]; then
            echo -e "  Target: Infinite"
        else
            echo -e "  Target: $loop_count iterations"
        fi
        echo -e "  Communication Mode: ${comm_mode:-UNKNOWN}"
        echo -e "  Reset Type Used: $reset_type_display"
        echo -e "  Completed: ${CURRENT_COUNTS[$i]} iterations"
        echo -e "${GREEN}  Successful: $successful${NC}"

        if [[ $failed -gt 0 ]]; then
            echo -e "${RED}  Failed: $failed${NC}"
            overall_success=false
        fi
        echo
    done

    if [[ "$overall_success" == "true" ]]; then
        echo -e "${GREEN}All reset tests completed successfully!${NC}"
        return 0
    else
        echo -e "${RED}Some reset tests failed${NC}"
        return 1
    fi
}


# ============================================================================
# Standalone execution support
# ============================================================================

# If script is executed directly, run the test menu
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo -e "${GREEN}RKNN-SMI Test Module - Standalone Execution${NC}"
    rknn_smi_test_menu
fi
