#!/usr/bin/env bash

echo performance | tee $(find /sys/ -name *governor)

if [[ "${BASH_VERSION%%.*}" -ge 4 ]]; then
    set -uo pipefail
else
    set -u  # Old bash versions only use -u
fi

# Control whether to delete temporary log files (default: true)
CLEANUP_TEMP_LOG="${CLEANUP_TEMP_LOG:-true}"

if [ "${1:-}" == "-h" ] || [ "${1:-}" == "--help" ]; then
    echo "==========================================="
    echo "RKNN3 CNN Demo Multiple Device/Core Stress Test Tool"
    echo "==========================================="
    echo "Usage:"
    echo "  $0 <model_path> <loop_time_hours> <count_loop> <device_list> <core_list> [use_yuv] [save_result]"
    echo ""
    echo "Parameters:"
    echo "  model_path       Model file base path or directory (before .rknn extension)"
    echo "  loop_time_hours  Stress test duration (hours)"
    echo "  count_loop       Inference loop count"
    echo "  device_list      Device ID list (space-separated), e.g., '0 1' for devices 0 and 1"
    echo "  core_list        Core list (space-separated), e.g., '1 2 3 4' for cores 1-4"
    echo "  use_yuv          Use YUV input format (optional): 1=enable, 0=disable, default: 0"
    echo "  save_result      Save result to file (optional): 1=save, 0=no save, default: 0"
    echo ""
    echo "Environment Variables:"
    echo "  CLEANUP_TEMP_LOG  Delete temporary log files after test (default: true)"
    echo "                    Set to 'false' to keep logs for debugging"
    echo ""
    echo "Usage examples:"
    echo "  # RGB input, no save (default)"
    echo "  $0 mobilenet_v2 1 100 \"0 1\" \"1 2 3 4\""
    echo ""
    echo "  # YUV input with hardware acceleration"
    echo "  $0 mobilenet_v2 1 100 \"0 1\" \"1 2 3 4\" 1"
    echo ""
    echo "  # YUV input and save results to test_results/performance/cnn.log"
    echo "  $0 mobilenet_v2 1 100 \"0 1\" \"1 2 3 4\" 1 1"
    echo ""
    echo "  # Keep all logs for debugging"
    echo "  CLEANUP_TEMP_LOG=false $0 mobilenet_v2 1 100 \"0\" \"1 2\""
    echo ""
    echo "Note:"
    echo "  - This script starts an independent stress test process for each device and each core"
    echo "  - Core N corresponds to mask 0x(1<<(N-1)), for example:"
    echo "    Core 1 -> 0x01"
    echo "    Core 2 -> 0x02"
    echo "    Core 3 -> 0x04"
    echo "    Core 4 -> 0x08"
    echo "  - When save_result=0, results are not saved (useful for parallel tests)"
    echo "  - When save_result=1, each test saves results to cnn.log file"
    echo "  - On test failure, logs are copied to /data/rknn3_model_stress_test_log/"
    echo "  - Set CLEANUP_TEMP_LOG=false to keep temporary logs for debugging"
    echo ""
    echo "==========================================="
    exit 1
fi

[ $# -lt 5 ] && { echo "Usage: $0 <model_path> <loop_time_hours> <count_loop> <device_list> <core_list> [use_yuv] [save_result]"; exit 1; }

model=$1
time_loop=$2
cnt_loop=$3
device_list=$4
core_list=$5
use_yuv="${6:-0}"      # Default: 0 (RGB input)
save_result="${7:-0}"  # Default: 0 (no save)

# Ensure absolute path and safely handle dirname
model_path_dir=$(dirname "$model")
model_dirname=$(basename "$model_path_dir")

# Find model directory
if [ -d "$model" ]; then
    model_dir="$model"
else
    model_dir=$(dirname "$model")
fi

# Auto-discover model files (compatible with new rknn3_cnn_test.sh)
RKNN_MODEL=$(find "$model_dir" -maxdepth 1 -type f -name "*.rknn" 2>/dev/null | head -n 1)
WEIGHT_MODEL=$(find "$model_dir" -maxdepth 1 -type f -name "*.weight" 2>/dev/null | head -n 1)
IMG_PATH="test.jpg"

# Check required files
for name in "RKNN_MODEL" "WEIGHT_MODEL" "IMG_PATH"; do
    eval file=\$$name
    if [ -z "$file" ] || [ ! -f "$file" ]; then
        echo "[ERROR] Missing file: $name"
        if [ "$name" = "RKNN_MODEL" ]; then
            echo "        Search location: $model_dir"
            echo "        Search pattern: *.rknn"
            echo "        Found: ${RKNN_MODEL:-none}"
        elif [ "$name" = "WEIGHT_MODEL" ]; then
            echo "        Search location: $model_dir"
            echo "        Search pattern: *.weight"
            echo "        Found: ${WEIGHT_MODEL:-none}"
        else
            echo "        Expected: test.jpg in current directory"
        fi
        exit 1
    fi
done

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CNN_TEST_SCRIPT="${SCRIPT_DIR}/rknn3_cnn_test.sh"

# Check if rknn3_cnn_test.sh exists
if [ ! -f "$CNN_TEST_SCRIPT" ]; then
    echo "[ERROR] rknn3_cnn_test.sh not found: $CNN_TEST_SCRIPT"
    exit 1
fi

echo "==========================================="
echo "Starting multiple device/core stress test..."
echo "Model: ${model}"
echo "Loop time: ${time_loop} hours"
echo "Loop count: ${cnt_loop}"
echo "Device list: ${device_list}"
echo "Core list: ${core_list}"
echo "Input format: $([ "$use_yuv" == "1" ] && echo "YUV enabled" || echo "RGB")"
echo "Save result: ${save_result}"
echo "Cleanup temp log: ${CLEANUP_TEMP_LOG}"
echo "==========================================="
echo ""

pids=()
start_time=$(date +%Y%m%d_%H%M%S)

# Double loop: outer devices, inner cores
for device_id in $device_list; do
    for core in $core_list; do
        # Calculate core mask: core N -> 0x(1<<(N-1))
        mask=$((1 << (core - 1)))
        core_mask=$(printf '0x%02x' $mask)

        echo ">>> Starting device ${device_id}, core ${core} (mask: ${core_mask})"

        # Call rknn3_cnn_test.sh with user-specified use_yuv and save_result parameters
        # Pass CLEANUP_TEMP_LOG environment variable to child process
        CLEANUP_TEMP_LOG="$CLEANUP_TEMP_LOG" "$CNN_TEST_SCRIPT" "$model" "$time_loop" "$cnt_loop" "$device_id" "$core_mask" "$use_yuv" "$save_result" &
        pids+=($!)
    done
done

echo ""
echo "Waiting for all processes to complete..."
failed_count=0
success_count=0

for pid in "${pids[@]}"; do
    if wait "$pid"; then
        success_count=$((success_count + 1))
    else
        failed_count=$((failed_count + 1))
    fi
done

echo "All processes completed."
echo ""

# Count devices and cores
device_count=$(echo "$device_list" | wc -w)
core_count=$(echo "$core_list" | wc -w)
total_tasks=$((device_count * core_count))

echo "==========================================="
echo "==================== Overall Statistics ===================="
echo "Device count: $device_count"
echo "Core count: $core_count"
echo "Total tasks: $total_tasks"
echo "Success tasks: $success_count"
echo "Failed tasks: $failed_count"
echo "=================================================="
echo ""

# Check failure status
if [ $failed_count -eq 0 ]; then
    echo "[SUCCESS] All device and core stress tests passed."
    echo "[rknn3_multiple_stress_test_done]"
    exit 0
else
    echo "[ERROR] $failed_count task(s) failed, please check logs."
    echo "[rknn3_multiple_stress_test_error]"
    exit 1
fi
