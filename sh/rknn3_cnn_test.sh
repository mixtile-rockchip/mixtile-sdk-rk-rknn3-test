#!/usr/bin/env bash

echo performance | tee $(find /sys/ -name *governor)

if [[ "${BASH_VERSION%%.*}" -ge 4 ]]; then
    set -uo pipefail
else
    set -u  # 旧版 bash 只使用 -u
fi

if [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
    echo "==========================================="
    echo "RKNN3 CNN Demo 压测工具"
    echo "==========================================="
    echo "用法:"
    echo "  $0 <model_path> <loop_time_hours> <count_loop> <device_id> <devices_core>"
    echo ""
    echo "参数说明:"
    echo "  model_path       指定模型文件的基础路径,要指定到.rknn之前的路径"
    echo "  loop_time_hours  压测持续时间 (小时)"
    echo "  count_loop       推理循环次数"
    echo "  device_id        设备ID (通常为0)"
    echo "  devices_core     核心列表,空格分隔,如'1 2 3 4'表示使用核心1-4"
    echo ""
    echo "使用示例:"
    echo "  $0 mobilenet_v2 1 100 0 \"1 2 3 4\""
    echo ""
    echo "==========================================="
    exit 1
fi

[ $# -lt 5 ] && { echo "用法: $0 <model_path> <loop_time_hours> <count_loop> <device_id> <devices_core>"; exit 1; }

model=$1
time_loop=$2
cnt_loop=$3
device_id=$4
devices_core=$5

# 确保使用绝对路径，并安全处理 dirname
model_path_dir=$(dirname "$model")
model_dirname=$(basename "$model_path_dir")

pids=()
start_time=$(date +%Y%m%d_%H%M%S)

LOG_DIR="/tmp/rknn3_${model_dirname}_log"
echo "日志目录: ${LOG_DIR}"
rm -rf "$LOG_DIR"
mkdir -p "$LOG_DIR"
log_pre="${LOG_DIR}/rknn3_$$"

echo "--- 启动并行任务 (8 核心) ---"

RKNN_MODEL=${model}.rknn
WEIGHT_MODEL=${model}.weight
IMG_PATH="test.jpg"
for f in "$RKNN_MODEL" "$WEIGHT_MODEL" "$IMG_PATH"; do
    if [ ! -f "$f" ]; then
        echo "❌ miss file: $f"
        exit 1
    fi
done

echo "✅ 启动 rknn3_cnn_demo..."
echo "模型: ${model}"
echo "循环时间: ${time_loop}"
echo "循环次数: ${cnt_loop}"
echo "指定设备ID: ${device_id}"
echo "指定核心: ${devices_core}"

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 核心列表
core_list="$devices_core"

for core in $core_list; do
    mask=$((1 << (core - 1)))
    log="${log_pre}_device${device_id}_core${core}.log"

    # 构建完整命令
    cmd="rknn3_cnn_demo -m \"$RKNN_MODEL\" -w \"$WEIGHT_MODEL\" -c \"0x$(printf '%02x' $mask)\" -i \"$IMG_PATH\" -tl \"${time_loop}\" -id \"${device_id}\" -cl \"${cnt_loop}\""

    # 输出执行的命令
    echo ">>> 执行命令: $cmd > $log"

    "rknn3_cnn_demo" \
        -m "$RKNN_MODEL" \
        -w "$WEIGHT_MODEL" \
        -c "0x$(printf '%02x' $mask)" \
        -i "$IMG_PATH" \
        -tl "${time_loop}" \
        -id "${device_id}" \
        -cl "${cnt_loop}" >"$log" 2>&1 &
    pids+=($!)
done
# 启动 8 个并行任务
# 等待全部结束
echo "等待所有进程完成..."
for pid in "${pids[@]}"; do wait "$pid"; done
echo "所有进程已完成。"

error_found=0
# 统计核心数
total_cores=$(echo "$devices_core" | wc -w)

echo ""
echo "===== 各核结果与总帧率 ====="

total_fps=0
success_cores=0
all_fps=0
tot_time=0

# 核心列表
core_list="$devices_core"

for core in $core_list; do
    log="${log_pre}_device${device_id}_core${core}.log"

    # 检查日志文件是否存在
    if [ ! -f "$log" ]; then
        echo "Core $core: 日志文件不存在 ($log)"
        error_found=$((error_found + 1))
        continue
    fi

    device_id_line=$(grep 'device_id' "$log" 2>/dev/null | tail -n 1)
    device_id_mac=$(echo "$device_id_line" | awk -F': ' '{print $2}')

        fps_line=$(grep 'avgFPS' "$log" 2>/dev/null | tail -n 1)
        # echo "$fps_line"
        if [[ -z "$fps_line" ]]; then
            echo "Core $core: 无效日志或无 FPS 信息"
            continue
        fi

        fps=$(echo "$fps_line" | awk -F'avgFPS:' '{print $NF}' | awk '{print $1}')
        # 假设变量 $log_line 是你的日志行
        run_cnt=$(echo "$fps_line" | awk '{print $2}')
        # 先用冒号切分取最后一段，再用逗号切分取第一段
        tot_time=$(echo "$fps_line" | awk -F'tot_time:' '{print $2}' | awk -F',' '{print $1}')
        if [[ -n "$fps" ]]; then
            echo "Core $core: FPS = $fps loop_cnt = $run_cnt"
            # 使用 awk 进行浮点数加法，保留两位小数
            total_fps=$(awk "BEGIN {printf \"%.2f\", $total_fps + $fps}")
            all_fps=$(awk "BEGIN {printf \"%.2f\", $all_fps + $fps *$run_cnt}")
            success_cores=$((success_cores + 1))

            # 检查是否成功完成
            if grep -q "rknn3_model_stress_test_done" "$log"; then
                # 成功且有结束标记，删除临时日志文件
                # echo $log
                rm -f "$log"
            else
                error_found=error_found+1
            fi
        else
            # 虽然找到了 avgFPS 的行，但提取数字失败，可能是日志格式不完全符合
            echo "Core $core: 提取FPS失败 (日志行: ${fps_line})"
        fi
    done

model_name=$(basename "$1")
echo "---------------------测试情况小结---------------------"
echo "RKNN3模型： $1"
device_id_mac=$(echo "$device_id_line" | awk -F': ' '{print $2}')
echo -e "$model_name 设备ID: $device_id_mac"
echo -e "$model_name 成功核心数:       $success_cores / $total_cores"
echo -e "$model_name 成功核心总帧数:   $all_fps"
echo -e "$model_name 总耗时:        $tot_time ms"
echo -e "$model_name 总帧率:           $total_fps"
echo "---------------------------------------------------"

# 检查失败情况
if [ -n "$(ls -A "$LOG_DIR" 2>/dev/null)" ]; then
    dest="/data/rknn3_model_stress_test_log/rknn3_${model_dirname}_${start_time}"
    mkdir -p "$dest"
    cp "${log_pre}_device${device_id}_core"*.log "$dest/" 2>/dev/null || true
    echo ""
    echo "❌ [ERROR] 部分设备压测存在异常，请检查上述日志。"
    echo "日志已拷贝到: $dest"
    rm -rf "$LOG_DIR"
    exit 1
else
    echo ""
    echo "✅ [SUCCESS] 所有设备压测通过。"
    rm -rf "$LOG_DIR"
    exit 0
fi


