#!/usr/bin/env bash

echo performance | tee $(find /sys/ -name *governor)

if [[ "${BASH_VERSION%%.*}" -ge 4 ]]; then
    set -uo pipefail
else
    set -u  # Old bash versions only use -u
fi

# Source common utility functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/rknn3_model_utils.sh"

# Control whether to delete temporary log files (default: true)
CLEANUP_TEMP_LOG="${CLEANUP_TEMP_LOG:-true}"

if [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
    echo "==========================================="
    echo "RKNN3 CNN Demo Stress Test Tool"
    echo "==========================================="
    echo "Usage:"
    echo "  $0 <model_path> <loop_time_hours> <count_loop> <device_id> [core_mask(optional)]"
    echo ""
    echo "Parameters:"
    echo "  model_path       Model file base path (before .rknn extension)"
    echo "  loop_time_hours  Stress test duration (hours)"
    echo "  count_loop       Inference loop count"
    echo "  device_id        Device ID (typically 0)"
    echo "  core_mask        Core mask (optional, hex), e.g., '0xff' for all 8 cores, '0x0f' for cores 0-3"
    echo ""
    echo "Core mask examples:"
    echo "  0xff   - All 8 cores (binary: 11111111)"
    echo "  0x0f   - Cores 0-3 (binary: 00001111)"
    echo "  0xf0   - Cores 4-7 (binary: 11110000)"
    echo "  0x01   - Core 0 only (binary: 00000001)"
    echo ""
    echo "Usage example:"
    echo "  $0 mobilenet_v2 1 100 0 0x01"
    echo ""
    echo "==========================================="
    exit 1
fi

[ $# -lt 4 ] && { echo "Usage: $0 <model_path> <loop_time_hours> <count_loop> <device_id> [core_mask(optional)]"; exit 1; }

MODEL=$1
TIME_LOOP=$2
COUNT_LOOP=$3
DEVICE_ID=$4
CORE_MASK="${5:-0x01}"  # Default: single core

# Ensure absolute path and safely handle dirname
model_path_dir=$(dirname "$MODEL")
model_dirname=$(basename "$model_path_dir")

pids=()
start_time=$(date +%Y%m%d_%H%M%S)

LOG_DIR="/tmp"
echo "Log directory: ${LOG_DIR}"
mkdir -p "$LOG_DIR"
log_pre="${LOG_DIR}/rknn3_$$"
log_files=()

# Find model files in the directory (any .rknn and .weight files)
model_dir=$(dirname "$MODEL")
if [ -d "$MODEL" ]; then
    model_dir="$MODEL"
fi

RKNN_MODEL=$(find "$model_dir" -maxdepth 1 -type f -name "*.rknn" 2>/dev/null | head -n 1)
WEIGHT_MODEL=$(find "$model_dir" -maxdepth 1 -type f -name "*.weight" 2>/dev/null | head -n 1)

IMG_PATH="test.jpg"

# Check if all required files exist
declare -A required_files=(
    ["RKNN_MODEL"]="$RKNN_MODEL"
    ["WEIGHT_MODEL"]="$WEIGHT_MODEL"
    ["IMG_PATH"]="$IMG_PATH"
)

# Define file patterns and search locations for error messages
declare -A file_patterns=(
    ["RKNN_MODEL"]="*.rknn"
    ["WEIGHT_MODEL"]="*.weight"
    ["IMG_PATH"]="test.jpg"
)

declare -A search_locations=(
    ["RKNN_MODEL"]="$model_dir"
    ["WEIGHT_MODEL"]="$model_dir"
    ["IMG_PATH"]="current directory"
)

for name in "${!required_files[@]}"; do
    file="${required_files[$name]}"
    if [ -z "$file" ] || [ ! -f "$file" ]; then
        pattern="${file_patterns[$name]}"
        location="${search_locations[$name]}"
        echo "[ERROR] Missing file for $name"
        echo "        Search location: $location"
        echo "        Search pattern: $pattern"
        echo "        Found: ${file:-none}"
        exit 1
    fi
done

echo "Starting rknn3_cnn_demo..."
echo "Model: ${MODEL}"
echo "Loop time: ${TIME_LOOP} hours"
echo "Loop count: ${COUNT_LOOP}"
echo "Device ID: ${DEVICE_ID}"
echo "Core mask: ${CORE_MASK}"

current_log="${log_pre}_${model_dirname}_${start_time}_device${DEVICE_ID}_${CORE_MASK}.log"
log_files+=("$current_log")

# Build complete command
cmd="rknn3_cnn_demo -m \"$RKNN_MODEL\" -w \"$WEIGHT_MODEL\" -c \"$CORE_MASK\" -i \"$IMG_PATH\" -tl \"${TIME_LOOP}\" -id \"${DEVICE_ID}\" -cl \"${COUNT_LOOP}\""

# Output executed command
echo ">>> Executing command: $cmd > $current_log"

rknn3_cnn_demo \
    -m "$RKNN_MODEL" \
    -w "$WEIGHT_MODEL" \
    -c "$CORE_MASK" \
    -i "$IMG_PATH" \
    -tl "${TIME_LOOP}" \
    -id "${DEVICE_ID}" \
    -cl "${COUNT_LOOP}" >"$current_log" 2>&1 &
pids+=($!)
echo "Waiting for all processes to complete..."
for pid in "${pids[@]}"; do wait "$pid"; done
echo "All processes completed."

echo "==================== Stress Test Results Summary ===================="

model_name=$(basename "$1")
error_found=0
total_fps=0
total_frames=0
tot_time=0
avg_cost=0
run_cnt=0
device_id_mac=""

echo ""
echo "--- Device ${DEVICE_ID} Statistics ---"

for log in "${log_files[@]}"; do
    # Check if log file exists
    if [ ! -f "$log" ]; then
        echo "  Log file does not exist"
        error_found=1
        continue
    fi

    # Get device ID MAC
    device_id_line=$(grep 'device_id' "$log" 2>/dev/null | tail -n 1)
    device_id_mac=$(echo "$device_id_line" | awk -F': ' '{print $2}')

    # Check if completed successfully
    if ! grep -q "rknn3_model_stress_test_done" "$log"; then
        echo "  [ERROR] Abnormal"
        tail -n 20 "$log"
        error_found=1
        continue
    fi

    fps_line=$(grep 'avgFPS' "$log" 2>/dev/null | tail -n 1)
    if [[ -z "$fps_line" ]]; then
        echo "  No FPS information"
        error_found=1
        continue
    fi

    fps=$(echo "$fps_line" | awk -F'avgFPS:' '{print $NF}' | awk '{print $1}')
    run_cnt=$(echo "$fps_line" | awk '{print $2}')
    tot_time=$(echo "$fps_line" | awk -F'tot_time:' '{print $2}' | awk -F',' '{print $1}')
    avg_cost=$(echo "$fps_line" | awk -F'avgCost:' '{print $NF}' | awk '{print $1}')

    # Extract input resolution information (model input)
    input_res_line=$(grep 'input image height' "$log" 2>/dev/null | tail -n 1)
    if [[ -n "$input_res_line" ]]; then
        input_height=$(echo "$input_res_line" | awk -F'height=' '{print $2}' | awk -F',' '{print $1}')
        input_width=$(echo "$input_res_line" | awk -F'width=' '{print $2}' | awk -F',' '{print $1}')
        input_channel=$(echo "$input_res_line" | awk -F'channel=' '{print $2}' | awk '{print $1}')
    else
        input_height="unknown"
        input_width="unknown"
        input_channel="unknown"
    fi

    if [[ -n "$fps" ]]; then
        echo "  Core mask $CORE_MASK: FPS = $fps, loop_cnt = $run_cnt, avgCost = $avg_cost ms"
        total_fps=$(awk "BEGIN {printf \"%.2f\", $total_fps + $fps}")
        total_frames=$(awk "BEGIN {printf \"%.2f\", $total_frames + $fps * $tot_time / 1000}")
    else
        echo "  Failed to extract FPS"
        error_found=1
    fi
done

# Print device summary
echo "  [$model_name] Device ID: $device_id_mac"
echo "  [$model_name] Core mask: $CORE_MASK"
echo "  [$model_name] Total frames: $total_frames"
echo "  [$model_name] Total time: $tot_time ms"
echo "  [$model_name] Average cost: $avg_cost ms"
echo "  [$model_name] Total FPS: $total_fps"

if [ $error_found -eq 0 ]; then
    echo "  Status: [PASS]"
else
    echo "  Status: [FAIL]"
fi

echo ""
echo "==================== Overall Statistics ===================="
echo "Total FPS: $total_fps"
echo "Total frames: $total_frames"
echo "=================================================="

# Save results to test_results/performance in script run directory
SCRIPT_RUN_DIR="$(pwd)"
RESULT_DIR="${SCRIPT_RUN_DIR}/test_results/performance"
mkdir -p "$RESULT_DIR"
RESULT_FILE="${RESULT_DIR}/cnn.log"
LOCK_FILE="${RESULT_FILE}.lock"

# Prepare content to append
APPEND_CONTENT=$(cat <<EOF
cnn:
model: ${model_name}
core: ${CORE_MASK}
input_width: ${input_width}
input_height: ${input_height}
input_channel: ${input_channel}
total_frames: ${total_frames}
total_time: ${tot_time} ms
fps: ${total_fps}
avg_cost: ${avg_cost} ms
EOF
)

# Use flock for locking to avoid concurrent write conflicts
(
    flock -x 200  # Acquire exclusive lock
    # If file exists and is not empty, append blank line first
    if [ -s "$RESULT_FILE" ]; then
        echo "" >> "$RESULT_FILE"
    fi
    # Append new content
    echo "$APPEND_CONTENT" >> "$RESULT_FILE"
) 200>"$LOCK_FILE"

echo "Test results appended to: ${RESULT_FILE}"

if [ $error_found -eq 0 ]; then
    # Delete temporary log file on success
    if [ "$CLEANUP_TEMP_LOG" = "true" ]; then
        rm -f "$current_log"
    fi
    echo ""
    echo "[SUCCESS] Device stress test passed."
    echo "[rknn3_model_stress_test_done]"
    exit 0
else
    # Copy log to /data directory on error
    dest="/data/rknn3_model_stress_test_log"
    mkdir -p "$dest"
    cp "$current_log" "$dest/" 2>/dev/null || true
    # Delete temporary log file after copying
    if [ "$CLEANUP_TEMP_LOG" = "true" ]; then
        rm -f "$current_log"
    fi
    echo ""
    echo "[ERROR] Device stress test has abnormalities, please check the above log."
    echo "Log copied to: $dest/$(basename $current_log)"
    echo "[rknn3_model_stress_test_error]"
    exit 1
fi
