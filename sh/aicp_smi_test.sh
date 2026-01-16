#!/bin/bash

# ============================================================================
# AI Coprocessor Test Script - RKNN-SMI Test Module
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

# ============================================================================
# RKNN-SMI Test Core Functions
# ============================================================================

# Check if rknn-smi command exists
check_rknn_smi() {
    if ! command -v rknn-smi &> /dev/null; then
        echo -e "${RED}rknn-smi command not found, please ensure RKNN driver is properly installed${NC}"
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
    echo -e "${CYAN}=== Basic RKNN Device Information Query ===${NC}"

    echo -e "${BLUE}1. Query version information:${NC}"
    rknn-smi -v
    echo

    echo -e "${BLUE}2. Query device information:${NC}"
    rknn-smi info
    echo

    echo -e "${BLUE}3. Query topology information:${NC}"
    rknn-smi info -l
    echo

    echo -e "${BLUE}4. Query all devices and chips detailed information:${NC}"
    rknn-smi info -t board
    echo
}

# Detailed status query
query_detailed_status() {
    echo -e "${CYAN}=== Detailed RKNN Device Status Query ===${NC}"

    local info_types=("memory" "fan" "temp" "voltage" "health" "sys_time" "reset_reason" "pcie_err")
    local type_names=("Memory Information" "Fan Speed Ratio" "Temperature Information" "Voltage Information" "Health Status" "System Time" "Last Reset Time" "PCIe Error Count")

    for i in "${!info_types[@]}"; do
        echo -e "${GREEN}$((i+5)). Query all devices ${type_names[i]}:${NC}"
        rknn-smi info -t ${info_types[i]}
        echo
        sleep 1
    done
}

# Query frequency and work mode information
query_frequency_mode_info() {
    echo -e "${CYAN}=== Frequency and Work Mode Information Query ===${NC}"

    local devices=$(get_device_list)

    if [ -z "$devices" ]; then
        echo -e "${YELLOW}No RKNN devices found${NC}"
        return 1
    fi

    for device in $devices; do
        echo -e "${BLUE}Querying device $device:${NC}"

        echo -e "${GREEN}  CPU frequency information:${NC}"
        rknn-smi info -t cpu_freq -d $device
        echo

        echo -e "${GREEN}  NPU frequency information:${NC}"
        rknn-smi info -t npu_freq -d $device
        echo

        echo -e "${GREEN}  Work mode information:${NC}"
        rknn-smi info -t work_mode -d $device
        echo

        sleep 1
    done
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
                echo -e "${YELLOW}Execute the command: rknn-smi set -t cpu_freq -d $device -c $chip -s $freq ${NC}"
                rknn-smi set -t cpu_freq -d $device -c $chip -s $freq 2>/dev/null
                echo -e "${GREEN}    Setting successful${NC}"
                # Verify setting
                sleep 1
                local current_freq=$(rknn-smi info -t cpu_freq -d $device -c $chip 2>/dev/null | grep "Current CPU Freq" | awk '{print $5}')
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
                echo -e "${YELLOW}Execute the command: rknn-smi set -t npu_freq -d $device -c $chip -s $freq ${NC}"
                rknn-smi set -t npu_freq -d $device -c $chip -s $freq 2>/dev/null
                # Verify setting
                sleep 1
                local current_freq=$(rknn-smi info -t npu_freq -d $device -c $chip 2>/dev/null | grep "Current NPU Freq" | awk '{print $5}')
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
                echo -e "${YELLOW}Execute the command: rknn-smi set -t work_mode -d $device -c $chip -s ${modes[i]} ${NC}"
                rknn-smi set -t work_mode -d $device -c $chip -s ${modes[i]} 2>/dev/null
                # Verify setting
                sleep 1
                local current_mode=$(rknn-smi info -t work_mode -d $device -c $chip 2>/dev/null | grep "Chip Work Mode" | awk '{print $NF}')
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
        rknn-smi info -t cpu_freq -d $device | grep -E "(Current|Available)" || true
        echo -e "${GREEN}Device $device NPU frequency:${NC}"
        rknn-smi info -t npu_freq -d $device | grep -E "(Current|Available)" || true
        echo -e "${GREEN}Device $device work mode:${NC}"
        rknn-smi info -t work_mode -d $device | grep "Chip Work Mode" || true
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

    if ! command -v rknn3_startup &> /dev/null; then
        echo -e "${RED}rknn3_startup command not found${NC}"
        return 1
    fi

    # Get number of loops - 修改为支持0表示无限循环
    while true; do
        read -p "Enter number of reboot loops (0=infinite, 1-100): " loop_count
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
        elif [[ "$loop_count" -ge 1 && "$loop_count" -le 100 ]]; then
            break
        else
            echo -e "${RED}Error: Please enter 0 for infinite loops or a number between 1-100!${NC}"
        fi
    done

    if [[ "$loop_count" -eq 0 ]]; then
        echo -e "${YELLOW}Reboot test will run indefinitely until manually stopped${NC}"
    else
        echo -e "${YELLOW}Reboot test will run $loop_count times${NC}"
    fi
    echo

    # 询问是否使用硬件重启
    while true; do
        read -p "Use hardware reset? (y/n): " use_hw_reset
        if [[ -z "$use_hw_reset" ]]; then
            echo -e "${RED}Error: Input cannot be empty, please re-enter!${NC}"
            continue
        fi

        use_hw_reset_lower=$(echo "$use_hw_reset" | tr '[:upper:]' '[:lower:]')
        if [[ "$use_hw_reset_lower" == "y" || "$use_hw_reset_lower" == "n" ]]; then
            break
        else
            echo -e "${RED}Error: Please enter y or n!${NC}"
        fi
    done

    # 根据用户选择设置重启命令
    if [[ "$use_hw_reset_lower" == "y" ]]; then
        reset_command="rknn-smi reset -t hw"
        reset_type="hardware reset"
    else
        reset_command="rknn-smi reset"
        reset_type="normal reset"
    fi

    echo -e "${GREEN}Selected reset type: $reset_type${NC}"
    echo

    # Confirm test execution
    if [[ "$loop_count" -eq 0 ]]; then
        echo -e "${RED}WARNING: This will reboot the RKNN device indefinitely until manually stopped!${NC}"
    else
        echo -e "${RED}WARNING: This will reboot the RKNN device $loop_count times.${NC}"
    fi
    echo -e "${YELLOW}Reset type: $reset_type${NC}"

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

    # 主循环
    while true; do
        ((current_iteration++))
        if [[ "$loop_count" -ne 0 ]] && [[ $current_iteration -gt $loop_count ]]; then
            break
        fi

        if [[ "$loop_count" -eq 0 ]]; then
            echo -e "${BLUE}=== Reboot Test Iteration $current_iteration (Infinite Mode) ===${NC}"
        else
            echo -e "${BLUE}=== Reboot Test Iteration $current_iteration of $loop_count ===${NC}"
        fi

        # The background program of npu needs to be closed first
        pkill -f "rknn3_transfer_proxy"

        # Step 1: Reset
        echo -e "${GREEN}1. Executing $reset_type: $reset_command${NC}"
        eval "$reset_command" 2>/dev/null

        # Step 2: Sleep for 1 second
        echo -e "${GREEN}2. Waiting for 1 second...${NC}"
        sleep 2

        # Step 3: Restart rknn3 startup
        echo -e "${GREEN}3. Restarting rknn3 startup: rknn3_startup restart${NC}"
        rknn3_startup restart 2>/dev/null

        # Additional wait for system to stabilize
        echo -e "${GREEN}Waiting 3 seconds for system to stabilize...${NC}"
        sleep 2

        # Step 4: Verify reboot success
        echo -e "${GREEN}4. Verifying reboot success...${NC}"
        local version_output
        version_output=$(rknn-smi --version 2>/dev/null)

        if echo "$version_output" | grep -q "rknn-smi version"; then
            echo -e "${GREEN}Reboot iteration $current_iteration completed successfully${NC}"
            ((successful_reboots++))
        else
            echo -e "${RED}Reboot iteration $current_iteration failed${NC}"
            ((failed_reboots++))
        fi

        if [[ "$loop_count" -eq 0 ]] || [[ $current_iteration -lt $loop_count ]]; then
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

    # 重置信号捕获
    trap - INT

    # Display test summary
    echo
    echo -e "${CYAN}=== Reboot Test Summary ===${NC}"

    if [[ "$loop_count" -eq 0 ]]; then
        echo -e "Test mode: Infinite (manually stopped)"
    else
        echo -e "Total iterations: $loop_count"
    fi

    echo -e "Completed iterations: $((current_iteration - 1))"
    echo -e "${GREEN}Successful reboots: $successful_reboots${NC}"
    echo -e "Reset type used: $reset_type"

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

# Main RKNN-SMI test function
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
        echo "3. Return to Main Menu"
        echo

        read -p "Please select an option (1-3): " choice

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
                return
                ;;
            *)
                echo -e "${RED}Invalid selection, please enter 1-3${NC}"
                echo
                read -p "Press Enter to continue..."
                ;;
        esac
    done
}

# ============================================================================
# Standalone execution support
# ============================================================================

# If script is executed directly, run the test menu
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo -e "${GREEN}RKNN-SMI Test Module - Standalone Execution${NC}"
    rknn_smi_test_menu
fi