#!/bin/bash

# Import RKNN-SMI test module
if [[ -f "./aicp_smi_test.sh" ]]; then
    source ./aicp_smi_test.sh
else
    echo -e "${RED}Error: aicp_smi_test.sh not found!${NC}"
    echo "Please ensure aicp_smi_test.sh is in the same directory."
    exit 1
fi

# Import RKNN test module
if [[ -f "./aicp_rknn_test.sh" ]]; then
    source ./aicp_rknn_test.sh
else
    echo -e "${RED}Error: aicp_rknn_test.sh not found!${NC}"
    echo "Please ensure aicp_rknn_test.sh is in the same directory."
    exit 1
fi

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

# ============================================================================
# Menu functions
# ============================================================================

show_test_header() {
    clear
    echo -e "${GREEN}"
    echo "========================================"
    echo "      AI Coprocessor Test Script"
    echo "          Version $SCRIPT_VERSION"
    echo "========================================"
    echo -e "${NC}"
}

# Main menu
main_menu() {
    while true; do
        show_test_header
        echo -e "${GREEN}Main Menu Options:${NC}"
        echo "1. RKNN Test"
        echo "2. RKNN-SMI Test"
        echo "3. Exit"
        echo

        read -rp "Please select an operation: " choice

        case $choice in
            1) rknn_test_menu ;;
            2) rknn_smi_test_menu ;;
            3)
                echo -e "${GREEN}Thank you for using the AI Coprocessor test script, goodbye!${NC}"
                log_message "Script exited normally"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid selection, please enter 1-3${NC}"
                ;;
        esac
    done
}

# ============================================================================
# Script initialization
# ============================================================================

# Check if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Set signal handling for graceful exit
    trap 'echo -e "\n${RED}Script interrupted by user${NC}"; log_message "Script interrupted by user"; exit 1' INT TERM

    # Display welcome message
    ./install_rknn3_model_stress.sh
    echo -e "${GREEN}Script initialization completed${NC}"
    echo -e "Test results directory: $TEST_RESULTS_DIR"
    echo -e "Log file: $LOG_FILE"
    echo
    log_message "=== Test script started ==="

    # Enter main menu
    main_menu
fi