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
    echo "  - This script directly calls rknn3_cnn_demo program for each device and core"
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
model_name=$(basename "$model")

# Find model directory
if [ -d "$model" ]; then
    model_dir="$model"
else
    model_dir=$(dirname "$model")
fi

# Auto-discover model files
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

# Check if rknn3_cnn_demo exists in PATH
if ! command -v rknn3_cnn_demo &> /dev/null; then
    echo "[ERROR] rknn3_cnn_demo not found in PATH"
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

# Setup log directory
LOG_DIR="/tmp"
mkdir -p "$LOG_DIR"
start_time=$(date +%Y%m%d_%H%M%S)

# Arrays to store process info
declare -a pids=()
declare -a log_files=()
declare -a device_ids=()
declare -a core_masks=()

# Function to run single test process
run_single_test() {
    local device_id=$1
    local core_mask=$2
    local log_file=$3

    # Build command arguments
    local CMD_ARGS=(
        "-m" "$RKNN_MODEL"
        "-w" "$WEIGHT_MODEL"
        "-c" "$core_mask"
        "-i" "$IMG_PATH"
        "-tl" "$time_loop"
        "-id" "$device_id"
        "-cl" "$cnt_loop"
    )

    # Add optional flags
    if [ "$use_yuv" == "1" ]; then
        CMD_ARGS+=("--yuv")
    fi

    # Execute rknn3_cnn_demo and redirect output to log file
    rknn3_cnn_demo "${CMD_ARGS[@]}" >"$log_file" 2>&1
    local ret=$?

    # Parse results and save to file if enabled
    if [ "$save_result" == "1" ] && [ $ret -eq 0 ]; then
        parse_and_save_results "$log_file" "$device_id" "$core_mask"
    fi

    # Handle log cleanup or archiving
    if [ $ret -eq 0 ]; then
        # Success: cleanup if enabled
        if [ "$CLEANUP_TEMP_LOG" = "true" ]; then
            rm -f "$log_file"
        fi
    else
        # Failure: copy to archive directory
        local dest="/data/rknn3_model_stress_test_log"
        mkdir -p "$dest"
        cp "$log_file" "$dest/" 2>/dev/null || true
        if [ "$CLEANUP_TEMP_LOG" = "true" ]; then
            rm -f "$log_file"
        fi
    fi

    return $ret
}

# Function to parse log and save results
parse_and_save_results() {
    local log=$1
    local device_id=$2
    local core_mask=$3

    # Check if log file exists and completed successfully
    if [ ! -f "$log" ] || ! grep -q "rknn3_model_stress_test_done" "$log"; then
        return 1
    fi

    # Parse results from log file
    local device_id_mac=$(grep '^DeviceId:' "$log" 2>/dev/null | tail -n 1 | awk '{for(i=2;i<=NF;i++) printf "%s%s",$i,(i==NF?"\n":" ")}')
    local run_cnt=$(grep '^RunCount:' "$log" 2>/dev/null | tail -n 1 | awk '{for(i=2;i<=NF;i++) printf "%s%s",$i,(i==NF?"\n":" ")}')
    local tot_time=$(grep '^TotalTime:' "$log" 2>/dev/null | tail -n 1 | awk '{for(i=2;i<=NF;i++) printf "%s%s",$i,(i==NF?"\n":" ")}' | sed 's/ ms$//')
    local fps=$(grep '^AvgFPS:' "$log" 2>/dev/null | tail -n 1 | awk '{for(i=2;i<=NF;i++) printf "%s%s",$i,(i==NF?"\n":" ")}')
    local avg_cost=$(grep '^AvgCost:' "$log" 2>/dev/null | tail -n 1 | awk '{for(i=2;i<=NF;i++) printf "%s%s",$i,(i==NF?"\n":" ")}' | sed 's/ ms$//')
    local input_format=$(grep '^InputFormat:' "$log" 2>/dev/null | tail -n 1 | awk '{for(i=2;i<=NF;i++) printf "%s%s",$i,(i==NF?"\n":" ")}')

    # Extract input resolution from log
    local input_res_line=$(grep 'input image height' "$log" 2>/dev/null | tail -n 1)
    local input_height input_width input_channel
    if [[ -n "$input_res_line" ]]; then
        input_height=$(echo "$input_res_line" | awk -F'height=' '{print $2}' | awk -F',' '{print $1}')
        input_width=$(echo "$input_res_line" | awk -F'width=' '{print $2}' | awk -F',' '{print $1}')
        input_channel=$(echo "$input_res_line" | awk -F'channel=' '{print $2}' | awk '{print $1}')
    else
        input_height="unknown"
        input_width="unknown"
        input_channel="unknown"
    fi

    # Calculate total frames
    local total_frames=$(awk "BEGIN {printf \"%.2f\", $fps * $tot_time / 1000}")

    # Save to temporary result file using simple format
    local TEMP_RESULT_DIR="/tmp/rknn3_cnn_results_$$"
    mkdir -p "$TEMP_RESULT_DIR"
    local TEMP_RESULT_FILE="${TEMP_RESULT_DIR}/result_device${device_id}_${core_mask}.txt"

    cat > "$TEMP_RESULT_FILE" <<EOF
device_id=${device_id}
device_id_mac=${device_id_mac}
core_mask=${core_mask}
input_format=${input_format}
input_width=${input_width}
input_height=${input_height}
input_channel=${input_channel}
total_frames=${total_frames}
total_time=${tot_time}
fps=${fps}
avg_cost=${avg_cost}
EOF
}

# Start tests for all device/core combinations
for device_id in $device_list; do
    for core in $core_list; do
        # Calculate core mask: core N -> 0x(1<<(N-1))
        mask=$((1 << (core - 1)))
        core_mask=$(printf '0x%02x' $mask)

        # Create log file name
        log_file="${LOG_DIR}/rknn3_$$_${model_dirname}_${start_time}_device${device_id}_${core_mask}.log"

        echo ">>> Starting device ${device_id}, core ${core} (mask: ${core_mask})"

        # Run test in background
        run_single_test "$device_id" "$core_mask" "$log_file" &

        # Store process info
        pids+=($!)
        log_files+=("$log_file")
        device_ids+=("$device_id")
        core_masks+=("$core_mask")
    done
done

echo ""
echo "Waiting for all processes to complete..."
failed_count=0
success_count=0

# Wait for all processes and collect results
for i in "${!pids[@]}"; do
    pid="${pids[$i]}"
    if wait "$pid"; then
        success_count=$((success_count + 1))
    else
        failed_count=$((failed_count + 1))
        echo "[ERROR] Test failed: device ${device_ids[$i]}, core mask ${core_masks[$i]}"
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

# Aggregate results and generate summary report
if [ "$save_result" == "1" ]; then
    TEMP_RESULT_DIR="/tmp/rknn3_cnn_results_$$"

    if [ -d "$TEMP_RESULT_DIR" ] && [ "$(ls -A $TEMP_RESULT_DIR 2>/dev/null)" ]; then
        # Read all result files and aggregate data
        first_result=true
        common_model=""
        common_input_format=""
        common_input_width=""
        common_input_height=""
        common_input_channel=""

        agg_total_fps=0
        agg_total_frames=0
        agg_max_time=0
        agg_sum_avg_cost=0
        core_results=""

        for result_file in "$TEMP_RESULT_DIR"/result_*.txt; do
            [ -f "$result_file" ] || continue

            # Initialize variables
            device_id=""
            device_id_mac=""
            core_mask=""
            input_format=""
            input_width=""
            input_height=""
            input_channel=""
            total_frames=""
            total_time=""
            fps=""
            avg_cost=""

            # Source the result file to get variables
            source "$result_file"

            # Get common info from first result
            if [ "$first_result" = true ]; then
                common_model="$RKNN_MODEL"
                common_input_format="${input_format:-unknown}"
                common_input_width="${input_width:-unknown}"
                common_input_height="${input_height:-unknown}"
                common_input_channel="${input_channel:-unknown}"
                first_result=false
            fi

            # Set default values for empty variables
            fps="${fps:-0}"
            total_frames="${total_frames:-0}"
            avg_cost="${avg_cost:-0}"
            total_time="${total_time:-0}"

            # Accumulate statistics (only if values are numeric)
            if [[ "$fps" =~ ^[0-9]+\.?[0-9]*$ ]]; then
                agg_total_fps=$(awk "BEGIN {printf \"%.2f\", $agg_total_fps + $fps}")
            fi

            if [[ "$total_frames" =~ ^[0-9]+\.?[0-9]*$ ]]; then
                agg_total_frames=$(awk "BEGIN {printf \"%.2f\", $agg_total_frames + $total_frames}")
            fi

            if [[ "$avg_cost" =~ ^[0-9]+\.?[0-9]*$ ]]; then
                agg_sum_avg_cost=$(awk "BEGIN {printf \"%.2f\", $agg_sum_avg_cost + $avg_cost}")
            fi

            # Track maximum time
            if [[ "$total_time" =~ ^[0-9]+\.?[0-9]*$ ]]; then
                if (( $(awk "BEGIN {print ($total_time > $agg_max_time)}") )); then
                    agg_max_time=$total_time
                fi
            fi

            # Collect per-core results
            core_results="${core_results}  Core ${core_mask}: fps=${fps}, avg_cost=${avg_cost} ms
"
        done

        # Prepare final result file
        SCRIPT_RUN_DIR="$(pwd)"
        RESULT_DIR="${SCRIPT_RUN_DIR}/test_results/performance"
        mkdir -p "$RESULT_DIR"
        RESULT_FILE="${RESULT_DIR}/cnn.log"
        LOCK_FILE="${RESULT_FILE}.lock"

        # Calculate average cost (avoid division by zero)
        final_avg_cost="0.00"
        if [ "$success_count" -gt 0 ]; then
            final_avg_cost=$(awk "BEGIN {printf \"%.2f\", $agg_sum_avg_cost / $success_count}")
        fi

        # Generate final report content
        FINAL_REPORT=$(cat <<EOF
==================================================
Test Summary
==================================================
RKNN3 Model: ${common_model}
Input Format: ${common_input_format}
Input Resolution: ${common_input_width}x${common_input_height}x${common_input_channel}
Successful Cores: ${success_count} / ${total_tasks}

Per-Core Results:
${core_results}
Overall Summary:
Total Frames: ${agg_total_frames}
Total Time: ${agg_max_time} ms
Total FPS: ${agg_total_fps}
Avg Cost: ${final_avg_cost} ms
==================================================
EOF
)

        # Write to result file with lock
        (
            flock -x 200
            if [ -s "$RESULT_FILE" ]; then
                echo "" >> "$RESULT_FILE"
            fi
            echo "$FINAL_REPORT" >> "$RESULT_FILE"
        ) 200>"$LOCK_FILE"

        echo "Test results saved to: ${RESULT_FILE}"
        echo ""
        echo "$FINAL_REPORT"

        # Cleanup temporary result files
        rm -rf "$TEMP_RESULT_DIR"
    fi
fi

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
