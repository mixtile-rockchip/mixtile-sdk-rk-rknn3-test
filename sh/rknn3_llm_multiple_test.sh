#!/usr/bin/env bash

echo performance | tee $(find /sys/ -name *governor) 2>/dev/null

if [[ "${BASH_VERSION%%.*}" -ge 4 ]]; then
    set -uo pipefail
else
    set -u  # Old bash versions only use -u
fi

# Control whether to delete temporary log files (default: true)
CLEANUP_TEMP_LOG="${CLEANUP_TEMP_LOG:-true}"

if [ "${1:-}" == "-h" ] || [ "${1:-}" == "--help" ]; then
    echo "==========================================="
    echo "RKNN3 LLM Multiple Device Test Tool"
    echo "==========================================="
    echo "Usage:"
    echo "  $0 <model_dir> <seq_len> <new_tokens> <loop_time> <loop_count> <device_list> <core_mask> [save_result]"
    echo ""
    echo "Parameters:"
    echo "  model_dir        Model directory path (e.g., /userdata/Qwen2.5-0.5B)"
    echo "  seq_len          Prompt length"
    echo "  new_tokens       Output length (if 1, indicates prefill mode)"
    echo "  loop_time        Stress test duration (hours), 0 to use loop_count"
    echo "  loop_count       Inference loop count"
    echo "  device_list      Device ID list (space-separated), e.g., '0 1' for devices 0 and 1"
    echo "  core_mask        Core mask (hex), e.g., '0xff' for all 8 cores"
    echo "  save_result      Save result to file (optional): 1=save, 0=no save, default: 0"
    echo ""
    echo "Core mask examples:"
    echo "  0xff   - All 8 cores (binary: 11111111)"
    echo "  0x0f   - Cores 0-3 (binary: 00001111)"
    echo "  0x03   - Cores 0-1 (binary: 00000011)"
    echo ""
    echo "Environment Variables:"
    echo "  CLEANUP_TEMP_LOG  Delete temporary log files after test (default: true)"
    echo "                    Set to 'false' to keep logs for debugging"
    echo ""
    echo "Usage examples:"
    echo "  # Run on devices 0 and 1 (prefill mode)"
    echo "  $0 /userdata/Qwen2.5-0.5B 512 1 1 100 \"0 1\" 0xff"
    echo ""
    echo "  # Run on device 0 only (decode mode)"
    echo "  $0 /userdata/Qwen2.5-0.5B 32 128 0 1000 \"0\" 0x0f"
    echo ""
    echo "  # Run on multiple devices and save results"
    echo "  $0 /userdata/Qwen2.5-0.5B 512 1 1 100 \"0 1 2\" 0xff 1"
    echo ""
    echo "  # Keep all logs for debugging"
    echo "  CLEANUP_TEMP_LOG=false $0 /userdata/Qwen2.5-0.5B 512 1 1 100 \"0 1\" 0xff"
    echo ""
    echo "Note:"
    echo "  - This script starts an independent stress test process for each device"
    echo "  - Each device runs the same model with the same parameters"
    echo "  - When save_result=0, results are not saved (default for parallel tests)"
    echo "  - When save_result=1, each test saves results to llm.log file"
    echo "  - On failure, logs are copied to /data/rknn3_model_stress_test_log/"
    echo "==========================================="
    exit 1
fi

[ $# -lt 7 ] && { echo "Usage: $0 <model_dir> <seq_len> <new_tokens> <loop_time> <loop_count> <device_list> <core_mask> [save_result]"; exit 1; }

MODEL_DIR="$1"
SEQ_LEN="$2"
NEW_TOKENS="$3"
LOOP_TIME="$4"
LOOP_COUNT="$5"
DEVICE_LIST="$6"
CORE_MASK="$7"
SAVE_RESULT="${8:-0}"  # Default: 0 (no save)

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LLM_TEST_SCRIPT="${SCRIPT_DIR}/rknn3_llm_test.sh"

# Check if rknn3_llm_test.sh exists
if [ ! -f "$LLM_TEST_SCRIPT" ]; then
    echo "[ERROR] rknn3_llm_test.sh not found: $LLM_TEST_SCRIPT"
    exit 1
fi

model_name=$(basename "$MODEL_DIR")

echo "==========================================="
echo "Starting LLM multiple device test..."
echo "Model: ${MODEL_DIR}"
echo "Seq length: ${SEQ_LEN}"
echo "New tokens: ${NEW_TOKENS}"
echo "Loop time: ${LOOP_TIME} hours"
echo "Loop count: ${LOOP_COUNT}"
echo "Device list: ${DEVICE_LIST}"
echo "Core mask: ${CORE_MASK}"
echo "Save result: ${SAVE_RESULT}"
echo "Cleanup temp log: ${CLEANUP_TEMP_LOG}"
echo "==========================================="
echo ""

pids=()
start_time=$(date +%Y%m%d_%H%M%S)

# Start one process for each device
for device_id in $DEVICE_LIST; do
    echo ">>> Starting device ${device_id} (core_mask: ${CORE_MASK})"

    # Call rknn3_llm_test.sh with specified parameters
    # Pass CLEANUP_TEMP_LOG environment variable to child process
    CLEANUP_TEMP_LOG="$CLEANUP_TEMP_LOG" "$LLM_TEST_SCRIPT" "$MODEL_DIR" "$SEQ_LEN" "$NEW_TOKENS" "$LOOP_TIME" "$LOOP_COUNT" "$device_id" "$CORE_MASK" "$SAVE_RESULT" &
    pids+=($!)
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

# Count devices
device_count=$(echo "$DEVICE_LIST" | wc -w)

echo "==========================================="
echo "==================== Overall Statistics ===================="
echo "Model: $model_name"
echo "Core mask: $CORE_MASK"
echo "Device count: $device_count"
echo "Total tasks: $device_count"
echo "Success tasks: $success_count"
echo "Failed tasks: $failed_count"
echo "=================================================="
echo ""

# Check failure status
if [ $failed_count -eq 0 ]; then
    echo "[SUCCESS] All device LLM stress tests passed."
    echo "[rknn3_multiple_stress_test_done]"
    exit 0
else
    echo "[ERROR] $failed_count task(s) failed, please check logs."
    echo "[rknn3_multiple_stress_test_error]"
    exit 1
fi
