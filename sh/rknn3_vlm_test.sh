#!/usr/bin/env bash

# ===========================================
# RKNN3 VLM Demo Launch Script
# Usage:
#   ./rknn3_vlm_demo.sh <model_path> [loop_time_hours] [count_loop]
#
# Example:
#   ./rknn3_vlm_demo.sh ./Qwen2.5-VL-3B 1 10
# ===========================================

echo performance | tee $(find /sys/ -name *governor)

# Control whether to delete temporary log files (default: true)
CLEANUP_TEMP_LOG="${CLEANUP_TEMP_LOG:-true}"

if [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
    echo "==========================================="
    echo "RKNN3 VLM Demo Stress Test Tool"
    echo "==========================================="
    echo "Usage:"
    echo "  $0 <model_dir> <loop_time_hours> <count_loop> <device_id> [core_mask(optional)]"
    echo ""
    echo "Parameters:"
    echo "  model_dir        Model file base path (before .rknn extension), e.g., /userdata/Qwen2.5-VL-3B/Qwen2.5-VL-3B"
    echo "  loop_time_hours  Stress test duration (hours)"
    echo "  count_loop       Inference loop count"
    echo "  device_id        Device ID (typically 0)"
    echo "  core_mask        Core mask (optional, hex), e.g., '0xff' for all 8 cores, '0x0f' for cores 0-3"
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

if [ $# -lt 4 ]; then
    echo "Usage: $0 <model_dir> <loop_time_hours> <count_loop> <device_id> [core_mask(optional)]"
    exit 1
fi

# Parameter reading
MODEL_DIR="$1"
LOOP_TIME="$2"
COUNT_LOOP="$3"
DEVICE_ID="$4"
CORE_MASK="${5:-0xff}"  # Default: all 8 cores

model_name=$(basename "$MODEL_DIR")

# Assign CORE_MASK to Vision and LLM
VISION_CORE_MASK="$CORE_MASK"
LLM_CORE_MASK="$CORE_MASK"

echo "${MODEL_DIR}"
# Model file definitions
VISION_MODEL="${MODEL_DIR}-vision.rknn"
VISION_WEIGHT="${MODEL_DIR}-vision.weight"
LLM_MODEL="${MODEL_DIR}-llm.rknn"
LLM_WEIGHT="${MODEL_DIR}-llm.weight"
TOKENIZER="${MODEL_DIR}-llm.tokenizer.gguf"
EMBEDDING="${MODEL_DIR}-llm.embed.bin"
IMAGE_PATH="test.jpg"
PROMPT_FILE="${MODEL_DIR}.ini"

# Check if key files exist
for f in "$VISION_MODEL" "$LLM_MODEL" "$TOKENIZER" "$EMBEDDING" "$IMAGE_PATH" "$PROMPT_FILE"; do
    if [ ! -f "$f" ]; then
        echo "[ERROR] Missing file: $f"
        exit 1
    fi
done

echo "Starting rknn3_vlm_demo..."
echo "Model directory: $MODEL_DIR"
echo "Loop time: ${LOOP_TIME} hours"
echo "Loop count: ${COUNT_LOOP}"
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
# Execute inference command
rknn3_vlm_demo \
    -vm "$VISION_MODEL" \
    -vw "$VISION_WEIGHT" \
    -lm "$LLM_MODEL" \
    -lw "$LLM_WEIGHT" \
    -tk "$TOKENIZER" \
    -em "$EMBEDDING" \
    -vc "$VISION_CORE_MASK" \
    -lc "$LLM_CORE_MASK" \
    -im "$IMAGE_PATH" \
    -pi "$PROMPT_FILE" \
    -vl "$COUNT_LOOP" \
    -ll "$COUNT_LOOP" \
    -tl "$LOOP_TIME" \
    -id "${DEVICE_ID}" >"$current_log" 2>&1 &
    pids+=($!)

echo "Waiting for all processes to complete..."
for pid in "${pids[@]}"; do wait "$pid"; done
echo "All processes completed."

echo "==================== Stress Test Results Summary ===================="

# Check execution status and print logs after specified keyword
error_found=0
vision=""
gen_len=""
ttft=""
tps=""
total_time=""
total_runs=""
input_width=""
input_height=""

for log in "${log_files[@]}"; do
    echo "$log"
    if grep -q "rknn3_model_stress_test_done" "$log"; then
        echo "--- Log file: $(basename "$log") (Success) ---"
        sed -n '/rknn3_model_stress_test_done/,$p' "$log"

        vision=$(grep '| Vision' "$log" 2>/dev/null | tail -n 1 | awk -F'|' '{print $3}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        gen_len=$(grep '| GenLen' "$log" 2>/dev/null | tail -n 1 | awk -F'|' '{print $3}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        ttft=$(grep '| TTFT' "$log" 2>/dev/null | tail -n 1 | awk -F'|' '{print $3}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        tps=$(grep '| TPS' "$log" 2>/dev/null | tail -n 1 | awk -F'|' '{print $3}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        total_time=$(grep 'Total time:' "$log" 2>/dev/null | tail -n 1 | awk '{for(i=3;i<=NF;i++) printf "%s%s",$i,(i==NF?"\n":" ")}')
        total_runs=$(grep 'Total runs:' "$log" 2>/dev/null | tail -n 1 | awk '{print $NF}')

        # Extract vision model input resolution information
        model_size_line=$(grep 'model_width=' "$log" 2>/dev/null | tail -n 1)
        if [[ -n "$model_size_line" ]]; then
            input_width=$(echo "$model_size_line" | awk -F'model_width=' '{print $2}' | awk '{print $1}')
            input_height=$(echo "$model_size_line" | awk -F'model_height=' '{print $2}' | awk '{print $1}')
            input_channel=3  # VLM vision model input is fixed to RGB888 format (3 channels)
        else
            input_width="unknown"
            input_height="unknown"
            input_channel="unknown"
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
RESULT_FILE="${RESULT_DIR}/vlm.log"
LOCK_FILE="${RESULT_FILE}.lock"

# Prepare content to append
APPEND_CONTENT=$(cat <<EOF
vlm:
model: ${model_name}
core: ${CORE_MASK}
input_width: ${input_width}
input_height: ${input_height}
Vision: ${vision}
GenLen: ${gen_len}
TTFT: ${ttft}
TPS: ${tps}
TotalTime: ${total_time}
TotalRuns: ${total_runs}
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
    echo "[SUCCESS] All device stress tests passed."
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
