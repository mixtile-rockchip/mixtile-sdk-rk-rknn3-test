#!/bin/sh

echo performance | tee $(find /sys/ -name *governor) 2>/dev/null

set -u  # Old bash versions only use -u

# Source common utility functions
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "${SCRIPT_DIR}/rknn3_model_utils.sh"

# Control whether to delete temporary log files (default: true)
CLEANUP_TEMP_LOG="${CLEANUP_TEMP_LOG:-true}"

if [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
    echo "==========================================="
    echo "RKNN3 Audio Encoder Stress Test Tool"
    echo "==========================================="
    echo "Usage:"
    echo "  $0 <model_dir> <loop_time_hours> <count_loop> <device_id> [core_mask] [save_result]"
    echo ""
    echo "Parameters:"
    echo "  model_dir        Model directory"
    echo "                   e.g., /userdata/Qwen2.5-Omni-3B (directory)"
    echo "  loop_time_hours  Stress test duration (hours), 0 to use count_loop"
    echo "  count_loop       Inference loop count"
    echo "  device_id        Device ID (typically 0)"
    echo "  core_mask        Core mask (optional, hex), default: 0xff"
    echo "  save_result      Save result to file (optional): 1=save + enable memory monitor, 0=no save, default: 1"
    echo ""
    echo "Core mask examples:"
    echo "  0xff   - All 8 cores (binary: 11111111) [default]"
    echo "  0x07   - Cores 0-2 (binary: 00000111)"
    echo "  0x01   - Core 0 only (binary: 00000001)"
    echo ""
    echo "Required files in current directory:"
    echo "  - demo.wav"
    echo "  - mel_128_filters.txt"
    echo ""
    echo "Required files in model directory:"
    echo "  - <model>-audio.rknn"
    echo "  - <model>-audio.weight"
    echo ""
    echo "Examples:"
    echo "  # Using directory path"
    echo "  $0 /userdata/Qwen2.5-Omni-3B 0 100 0 0xff"
    echo "==========================================="
    exit 1
fi

[ $# -lt 4 ] && { echo "Usage: $0 <model_dir> <loop_time_hours> <count_loop> <device_id> [core_mask] [save_result]"; exit 1; }

MODEL_DIR="$1"
TIME_LOOP="$2"
COUNT_LOOP="$3"
DEVICE_ID="$4"
CORE_MASK="${5:-0xff}"  # Default: all 8 cores
SAVE_RESULT="${6:-1}"  # Default: save to file

model_name=$(basename "$MODEL_DIR")

# Determine search directory (same logic as VLM script)
search_dir=$(dirname "$MODEL_DIR")
if [ -d "$MODEL_DIR" ]; then
    search_dir="$MODEL_DIR"
fi

# Model file definitions with flexible pattern matching
AUDIO_MODEL=$(find "$search_dir" -maxdepth 1 -type f -iname "*audio*.rknn" 2>/dev/null | head -n 1)
AUDIO_WEIGHT=$(find "$search_dir" -maxdepth 1 -type f -iname "*audio*.weight" 2>/dev/null | head -n 1)
AUDIO_PATH="demo.wav"

# Check if key files exist using indexed arrays
required_files_names=("AUDIO_MODEL" "AUDIO_WEIGHT" "AUDIO_PATH" "MEL_FILTERS")
required_files_values=("$AUDIO_MODEL" "$AUDIO_WEIGHT" "$AUDIO_PATH" "mel_128_filters.txt")
file_patterns=("*audio*.rknn" "*audio*.weight" "demo.wav" "mel_128_filters.txt")
search_locations=("$search_dir" "$search_dir" "current directory" "current directory")

for i in 0 1 2 3; do
    name="${required_files_names[i]}"
    file="${required_files_values[i]}"
    pattern="${file_patterns[i]}"
    location="${search_locations[i]}"

    if [ -z "$file" ] || [ ! -f "$file" ]; then
        echo "[ERROR] Missing file for $name"
        echo "        Search location: $location"
        echo "        Search pattern: $pattern"
        echo "        Found: ${file:-none}"
        exit 1
    fi
done

echo "Starting rknn3_audio_encoder_test..."
echo "Model directory: $MODEL_DIR"
echo "Loop time: ${TIME_LOOP} hours"
echo "Loop count: ${COUNT_LOOP}"
echo "Device ID: ${DEVICE_ID}"
echo "Core mask: $CORE_MASK"

pids=()
start_time=$(date +%Y%m%d_%H%M%S)

model_dirname=$(basename "$MODEL_DIR")
LOG_DIR="/tmp"
if [ -d "/tmp" ]; then
    LOG_DIR="/tmp"
else
    LOG_DIR="/data/tmp"
    mkdir -p "$LOG_DIR"
fi
echo "Log directory: ${LOG_DIR}"
mkdir -p "$LOG_DIR"
log_pre="${LOG_DIR}/rknn3_$$"
log_files=()

current_log="${log_pre}_${model_dirname}_${start_time}_device${DEVICE_ID}_${CORE_MASK}.log"
log_files+=("$current_log")

# Build command arguments
CMD_ARGS=(
    "-am" "$AUDIO_MODEL"
    "-aw" "$AUDIO_WEIGHT"
    "-ac" "$CORE_MASK"
    "-a" "$AUDIO_PATH"
    "-al" "$COUNT_LOOP"
    "-tl" "$TIME_LOOP"
    "-id" "${DEVICE_ID}"
)

# Enable memory monitor if save_result is enabled
if [ "$SAVE_RESULT" == "1" ]; then
    CMD_ARGS+=("-mm")
fi

# Output executed command
echo ">>> Executing command: rknn3_audio_encoder_test ${CMD_ARGS[*]} > $current_log"

# Execute inference command
rknn3_audio_encoder_test "${CMD_ARGS[@]}" >"$current_log" 2>&1 &
pids+=($!)

echo "Waiting for all processes to complete..."
for pid in "${pids[@]}"; do wait "$pid"; done
echo "All processes completed."

echo "==================== Stress Test Results Summary ===================="

error_found=0
avgCost=0
tot_time=0
run_cnt=0
min_lat=0
max_lat=0
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

    # Check if completed successfully
    if ! grep -q "rknn3_model_stress_test_done" "$log"; then
        echo "  [ERROR] Abnormal"
        tail -n 20 "$log"
        error_found=1
        continue
    fi

    # Extract information using multi-line key-value format
    device_id_mac=$(grep '^DeviceID:' "$log" 2>/dev/null | tail -n 1 | awk -F': ' '{print $2}')
    avgCost=$(grep '^AvgLatency:' "$log" 2>/dev/null | tail -n 1 | awk '{print $2}')
    min_lat=$(grep '^MinLatency:' "$log" 2>/dev/null | tail -n 1 | awk '{print $2}')
    max_lat=$(grep '^MaxLatency:' "$log" 2>/dev/null | tail -n 1 | awk '{print $2}')
    tot_time=$(grep '^TotalTime:' "$log" 2>/dev/null | tail -n 1 | awk '{print $2}')
    run_cnt=$(grep '^TotalRuns:' "$log" 2>/dev/null | tail -n 1 | awk '{print $2}')
    avg_memory=$(grep '^AvgMemoryUsage:' "$log" 2>/dev/null | tail -n 1 | awk '{for(i=2;i<=NF;i++) printf "%s%s",$i,(i==NF?"\n":" ")}')
    avg_npu_util=$(grep '^AvgNpuUtilization:' "$log" 2>/dev/null | tail -n 1 | awk '{for(i=2;i<=NF;i++) printf "%s%s",$i,(i==NF?"\n":" ")}')

    # Validate that critical data was extracted successfully
    # if [ -z "$run_cnt" ] || [ "$run_cnt" = "0" ] || [ -z "$tot_time" ] || [ -z "$avgCost" ]; then
    #     echo "  [ERROR] Failed to extract critical data from log"
    #     echo "  run_cnt: ${run_cnt:-empty}, tot_time: ${tot_time:-empty}, avgCost: ${avgCost:-empty}"
    #     tail -n 20 "$log"
    #     error_found=1
    # fi

done


echo "  [$model_name] Device ID: $device_id_mac"
echo "  [$model_name] Core mask: $CORE_MASK"
echo "  [$model_name] Total runs: $run_cnt"
echo "  [$model_name] Total time: $tot_time ms"
echo "  [$model_name] Average latency: $avgCost ms"
echo "  [$model_name] Min latency: $min_lat ms"
echo "  [$model_name] Max latency: $max_lat ms"
echo "  [$model_name] Avg Memory Usage: $avg_memory"
echo "  [$model_name] Avg NPU Utilization: $avg_npu_util"

if [ $error_found -eq 0 ]; then
    echo "  Status: [PASS]"
else
    echo "  Status: [FAIL]"
fi

# Save results to test_results/performance in script run directory
SCRIPT_RUN_DIR="$(pwd)"
RESULT_DIR="${SCRIPT_RUN_DIR}/test_results/performance"
mkdir -p "$RESULT_DIR"
RESULT_FILE="${RESULT_DIR}/audio_encoder.log"
LOCK_FILE="${RESULT_FILE}.lock"

# Prepare content to append
APPEND_CONTENT=$(cat <<EOF
audio_encoder:
model: ${model_name}
core: ${CORE_MASK}
total_runs: ${run_cnt}
total_time: ${tot_time} ms
avg_latency: ${avgCost} ms
min_latency: ${min_lat} ms
max_latency: ${max_lat} ms
avg_memory_usage: ${avg_memory}
avg_npu_utilization: ${avg_npu_util}
EOF
)

# Save results to file if enabled
if [ "$SAVE_RESULT" == "1" ]; then
    # Use mkdir to implement lock mechanism (compatible with Android Toybox)
    MAX_RETRIES=100
    RETRY_COUNT=0
    while ! mkdir "$LOCK_FILE" 2>/dev/null; do
        RETRY_COUNT=$((RETRY_COUNT + 1))
        if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
            echo "Warning: Lock acquisition timeout, forcing write"
            rm -rf "$LOCK_FILE" 2>/dev/null
            mkdir "$LOCK_FILE" 2>/dev/null || true
            break
        fi
        sleep 0.1
    done

    # If file exists and is not empty, append a blank line first
    if [ -s "$RESULT_FILE" ]; then
        echo "" >> "$RESULT_FILE"
    fi
    # Append new content
    echo "$APPEND_CONTENT" >> "$RESULT_FILE"

    # Release lock
    rm -rf "$LOCK_FILE"

    echo "Test results appended to: ${RESULT_FILE}"
else
    echo "Result saving disabled (save_result=$SAVE_RESULT)"
fi

if [ $error_found -eq 0 ]; then
    # Delete temporary log file on success
    if [ "$CLEANUP_TEMP_LOG" = "true" ]; then
        rm -f "$current_log"
    fi
    echo ""
    echo "[SUCCESS] Audio encoder stress test passed."
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
    echo "[ERROR] Audio encoder stress test has abnormalities, please check the above log."
    echo "Log copied to: $dest/$(basename $current_log)"
    echo "[rknn3_model_stress_test_error]"
    exit 1
fi
