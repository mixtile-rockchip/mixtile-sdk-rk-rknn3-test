#!/bin/bash

echo performance | tee $(find /sys/ -name *governor)

# Source common utility functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/rknn3_model_utils.sh"

MAX_CONTEXT=1024
CORE_MASK=0xff

# Control whether to delete temporary log files (default: true)
CLEANUP_TEMP_LOG="${CLEANUP_TEMP_LOG:-true}"

if [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
    echo "==========================================="
    echo "RKNN3 LLM Demo Stress Test Tool"
    echo "==========================================="
    echo "Usage:"
    echo "  $0 <model_dir> <seq_len> <new_tokens> <loop_time> <loop_count> <device_id> [core_mask] [use_yuv] [save_result]"
    echo ""
    echo "Parameters:"
    echo "  model_dir       Model file base path (before .rknn extension), e.g., /userdata/Qwen2.5-0.5B/Qwen2.5-0.5B"
    echo "  seq_len         Prompt length"
    echo "  new_tokens      Output length, if 1 indicates prefill mode"
    echo "  loop_time       Stress test duration (hours), if 0, use loop count"
    echo "  loop_count      Inference loop count, time loop takes priority"
    echo "  device_id       Device ID (typically 0)"
    echo "  core_mask       Core mask (optional, hex), e.g., '0xff' for all 8 cores, '0x0f' for cores 0-3, default: 0xff"
    echo "  use_yuv         Use YUV format (optional, reserved parameter): 0=RGB, 1=YUV, default: 0"
    echo "  save_result     Save result to file (optional): 1=save, 0=no save, default: 1"
    echo ""
    echo "Core mask examples:"
    echo "  0xff   - All 8 cores (binary: 11111111)"
    echo "  0x0f   - Cores 0-3 (binary: 00001111)"
    echo "  0xf0   - Cores 4-7 (binary: 11110000)"
    echo "  0x03   - Cores 0-1 (binary: 00000011)"
    echo ""
    echo ""
    echo "==========================================="
    exit 1
fi

if [ $# -lt 6 ]; then
    echo "Usage: $0 <model_dir> <seq_len> <new_tokens> <loop_time> <loop_count> <device_id> [core_mask] [use_yuv] [save_result]"
    exit 1
fi
MODEL_DIR=$1
PROMPT_LEN=$2
GEN_LEN=$3
TIME_LOOP=$4
LOOP_CNT=$5
DEVICE_ID=$6
CORE_MASK="${7:-0xff}"  # Default: all 8 cores
USE_YUV="${8:-0}"       # Default: RGB (reserved parameter)
SAVE_RESULT="${9:-1}"   # Default: save to file

model_name=$(basename "$MODEL_DIR")

# Find model files in the directory (any files with required extensions)
model_dir=$(dirname "$MODEL_DIR")
if [ -d "$MODEL_DIR" ]; then
    model_dir="$MODEL_DIR"
fi

RKNN_MODEL=$(find "$model_dir" -maxdepth 1 -type f -name "*.rknn" 2>/dev/null | head -n 1)
WEIGHT_MODEL=$(find "$model_dir" -maxdepth 1 -type f -name "*.weight" 2>/dev/null | head -n 1)
TOKENIZER=$(find "$model_dir" -maxdepth 1 -type f -name "*.tokenizer.gguf" 2>/dev/null | head -n 1)
EMBEDDING=$(find "$model_dir" -maxdepth 1 -type f -name "*.embed.bin" 2>/dev/null | head -n 1)

# Check if all required files exist
declare -A required_files=(
    ["RKNN_MODEL"]="$RKNN_MODEL"
    ["WEIGHT_MODEL"]="$WEIGHT_MODEL"
    ["TOKENIZER"]="$TOKENIZER"
    ["EMBEDDING"]="$EMBEDDING"
)

# Define file patterns for error messages
declare -A file_patterns=(
    ["RKNN_MODEL"]="*.rknn"
    ["WEIGHT_MODEL"]="*.weight"
    ["TOKENIZER"]="*.tokenizer.gguf"
    ["EMBEDDING"]="*.embed.bin"
)

for name in "${!required_files[@]}"; do
    file="${required_files[$name]}"
    if [ -z "$file" ] || [ ! -f "$file" ]; then
        pattern="${file_patterns[$name]}"
        echo "[ERROR] Missing file for $name"
        echo "        Search directory: $model_dir"
        echo "        Search pattern: $pattern"
        echo "        Found: ${file:-none}"
        exit 1
    fi
done

echo "Starting rknn3_llm_demo..."
echo "Model directory: $MODEL_DIR"
echo "Loop time: ${TIME_LOOP} hours"
echo "Use YUV: $USE_YUV (reserved)"
echo "Loop count: ${LOOP_CNT}"
echo "Device ID: ${DEVICE_ID}"
echo "Core mask: $CORE_MASK"

pids=()
start_time=$(date +%Y%m%d_%H%M%S)
model_dirname=$(basename "$MODEL_DIR")
LOG_DIR="/tmp"
echo "Log directory: ${LOG_DIR}"
mkdir -p "$LOG_DIR"
log_pre="${LOG_DIR}/rknn3_$$"

current_log="${log_pre}_${model_dirname}_${start_time}_device${DEVICE_ID}_${CORE_MASK}.log"
log_files+=("$current_log")

rknn3_llm_demo \
    -m "$RKNN_MODEL" \
    -w "$WEIGHT_MODEL" \
    -tk "$TOKENIZER" \
    -em "$EMBEDDING" \
    -ctx "$MAX_CONTEXT" \
    -ni "$PROMPT_LEN" \
    -no "$GEN_LEN" \
    -c "$CORE_MASK" \
    -cl "$LOOP_CNT" \
    -tl "$TIME_LOOP" \
    -id "${DEVICE_ID}" >"$current_log" 2>&1 &
    pids+=($!)

echo "Waiting for all processes to complete..."
for pid in "${pids[@]}"; do wait "$pid"; done
echo "All processes completed."

echo "==================== Stress Test Results Summary ===================="

# Check execution status and print logs after specified keyword
error_found=0
ttft=""
tpot=""
prefill_tps=""
tps=""
total_time=""
total_runs=""
avg_memory=""
npu_util=""

for log in "${log_files[@]}"; do
    echo "$log"
    if grep -q "rknn3_model_stress_test_done" "$log"; then
        # echo "--- Log file: $(basename "$log") (Success) ---"
        # Use sed to print all content after matching line
        sed -n '/rknn3_model_stress_test_done/,$p' "$log"


        ttft=$(grep '^TTFT:' "$log" 2>/dev/null | tail -n 1 | awk '{for(i=2;i<=NF;i++) printf "%s%s",$i,(i==NF?"\n":" ")}')
        tpot=$(grep '^TPOT:' "$log" 2>/dev/null | tail -n 1 | awk '{for(i=2;i<=NF;i++) printf "%s%s",$i,(i==NF?"\n":" ")}')
        prefill_tps=$(grep '^Prefill:' "$log" 2>/dev/null | tail -n 1 | awk '{for(i=2;i<=NF;i++) printf "%s%s",$i,(i==NF?"\n":" ")}')
        tps=$(grep '^TPS:' "$log" 2>/dev/null | tail -n 1 | awk '{for(i=2;i<=NF;i++) printf "%s%s",$i,(i==NF?"\n":" ")}')
        total_time=$(grep '^TotalTime:' "$log" 2>/dev/null | tail -n 1 | awk '{for(i=2;i<=NF;i++) printf "%s%s",$i,(i==NF?"\n":" ")}')
        total_runs=$(grep '^TotalRuns:' "$log" 2>/dev/null | tail -n 1 | awk '{for(i=2;i<=NF;i++) printf "%s%s",$i,(i==NF?"\n":" ")}')
        avg_memory=$(grep '^AvgMemoryUsage:' "$log" 2>/dev/null | tail -n 1 | awk '{for(i=2;i<=NF;i++) printf "%s%s",$i,(i==NF?"\n":" ")}')
        npu_util=$(grep '^AvgNpuUtilization:' "$log" 2>/dev/null | tail -n 1 | awk '{for(i=2;i<=NF;i++) printf "%s%s",$i,(i==NF?"\n":" ")}')

        # Validate that critical data was extracted successfully
        if [ -z "$total_runs" ] || [ "$total_runs" = "0" ] || [ -z "$total_time" ]; then
            echo "  [ERROR] Failed to extract critical data from log"
            echo "  total_runs: ${total_runs:-empty}, total_time: ${total_time:-empty}"
            tail -n 20 "$log"
            error_found=1
        fi
    else
        echo "--- Log file: $(basename "$log") ([ERROR] Abnormal) ---"
        tail -n 20 "$log" # If success marker not found, print last 20 lines of error
        error_found=1
    fi
    echo ""
done

# Save results to test_results/performance in script run directory (key information)
SCRIPT_RUN_DIR="$(pwd)"
RESULT_DIR="${SCRIPT_RUN_DIR}/test_results/performance"
mkdir -p "$RESULT_DIR"
RESULT_FILE="${RESULT_DIR}/llm.log"
LOCK_FILE="${RESULT_FILE}.lock"

# Prepare content to append
APPEND_CONTENT=$(cat <<EOF
llm:
model: ${model_name}
core: ${CORE_MASK}
seq_len: ${PROMPT_LEN}
token: ${GEN_LEN}
TTFT: ${ttft}
TPOT: ${tpot}
Prefill: ${prefill_tps}
TPS: ${tps}
TotalTime: ${total_time}
TotalRuns: ${total_runs}
AvgMemoryUsage: ${avg_memory}
AvgNpuUtilization: ${npu_util}
EOF
)

# Save results to file if enabled
if [ "$SAVE_RESULT" == "1" ]; then
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
else
    echo "Result saving disabled (save_result=$SAVE_RESULT)"
fi

if [ $error_found -eq 0 ]; then
    # Delete temporary log file on success
    if [ "$CLEANUP_TEMP_LOG" = "true" ]; then
        rm -f "$current_log"
    fi
    echo "[SUCCESS] All device stress tests passed."
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
    echo "[ERROR] Some device stress tests have abnormalities, please check the above log."
    echo "Log copied to: $dest/$(basename $current_log)"
    echo "[rknn3_model_stress_test_error]"
    exit 1
fi
