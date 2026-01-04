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
    echo "  $0 <model_path> <loop_time_hours> <count_loop> <device_id> [core_mask(optional)]"
    echo ""
    echo "参数说明:"
    echo "  model_path       指定模型文件的基础路径,要指定到.rknn之前的路径"
    echo "  loop_time_hours  压测持续时间 (小时)"
    echo "  count_loop       推理循环次数"
    echo "  device_id        指定设备ID (通常为0)"
    echo "  core_mask        核心掩码(可选,16进制),如'0xff'表示全8核,'0x0f'表示核心0-3"
    echo ""
    echo "核心掩码示例:"
    echo "  0xff   - 全8核 (二进制: 11111111)"
    echo "  0x0f   - 核心0-3 (二进制: 00001111)"
    echo "  0xf0   - 核心4-7 (二进制: 11110000)"
    echo "  0x01   - 仅核心0 (二进制: 00000001)"
    echo ""
    echo "使用示例:"
    echo "  $0 mobilenet_v2 1 100 0 0x01"
    echo ""
    echo "==========================================="
    exit 1
fi

[ $# -lt 4 ] && { echo "用法: $0 <model_path> <loop_time_hours> <count_loop> <device_id> [core_mask(optional)]"; exit 1; }

model=$1
time_loop=$2
cnt_loop=$3
DEVICE_ID=$4
CORE_MASK="${5:-0x01}"  # 默认全1核

# 确保使用绝对路径，并安全处理 dirname
model_path_dir=$(dirname "$model")
model_dirname=$(basename "$model_path_dir")

pids=()
start_time=$(date +%Y%m%d_%H%M%S)

LOG_DIR="/tmp"
echo "日志目录: ${LOG_DIR}"
mkdir -p "$LOG_DIR"
log_pre="${LOG_DIR}/rknn3_$$"
log_files=()

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
echo "循环时间: ${time_loop} 小时"
echo "循环次数: ${cnt_loop}"
echo "指定设备ID: ${DEVICE_ID}"
echo "核心掩码: ${CORE_MASK}"

current_log="${log_pre}_${model_dirname}_${start_time}_device${DEVICE_ID}_${CORE_MASK}.log"
log_files+=("$current_log")

# 构建完整命令
cmd="rknn3_cnn_demo -m \"$RKNN_MODEL\" -w \"$WEIGHT_MODEL\" -c \"$CORE_MASK\" -i \"$IMG_PATH\" -tl \"${time_loop}\" -id \"${DEVICE_ID}\" -cl \"${cnt_loop}\""

# 输出执行的命令
echo ">>> 执行命令: $cmd > $current_log"

rknn3_cnn_demo \
    -m "$RKNN_MODEL" \
    -w "$WEIGHT_MODEL" \
    -c "$CORE_MASK" \
    -i "$IMG_PATH" \
    -tl "${time_loop}" \
    -id "${DEVICE_ID}" \
    -cl "${cnt_loop}" >"$current_log" 2>&1 &
pids+=($!)
echo "等待所有进程完成..."
for pid in "${pids[@]}"; do wait "$pid"; done
echo "所有进程已完成。"

echo "==================== 压测结果汇总 ===================="

model_name=$(basename "$1")
error_found=0
total_fps=0
total_frames=0
tot_time=0
avg_cost=0
run_cnt=0
device_id_mac=""

echo ""
echo "--- 设备 ${DEVICE_ID} 统计 ---"

for log in "${log_files[@]}"; do
    # 检查日志文件是否存在
    if [ ! -f "$log" ]; then
        echo "  日志文件不存在"
        error_found=1
        continue
    fi

    # 获取设备ID MAC
    device_id_line=$(grep 'device_id' "$log" 2>/dev/null | tail -n 1)
    device_id_mac=$(echo "$device_id_line" | awk -F': ' '{print $2}')

    # 检查是否成功完成
    if ! grep -q "rknn3_model_stress_test_done" "$log"; then
        echo "  ❌ 异常"
        tail -n 20 "$log"
        error_found=1
        continue
    fi

    fps_line=$(grep 'avgFPS' "$log" 2>/dev/null | tail -n 1)
    if [[ -z "$fps_line" ]]; then
        echo "  无 FPS 信息"
        error_found=1
        continue
    fi

    fps=$(echo "$fps_line" | awk -F'avgFPS:' '{print $NF}' | awk '{print $1}')
    run_cnt=$(echo "$fps_line" | awk '{print $2}')
    tot_time=$(echo "$fps_line" | awk -F'tot_time:' '{print $2}' | awk -F',' '{print $1}')
    avg_cost=$(echo "$fps_line" | awk -F'avgCost:' '{print $NF}' | awk '{print $1}')

    if [[ -n "$fps" ]]; then
        echo "  核心掩码 $CORE_MASK: FPS = $fps, loop_cnt = $run_cnt, avgCost = $avg_cost ms"
        total_fps=$(awk "BEGIN {printf \"%.2f\", $total_fps + $fps}")
        total_frames=$(awk "BEGIN {printf \"%.2f\", $total_frames + $fps * $run_cnt}")
    else
        echo "  提取FPS失败"
        error_found=1
    fi
done

# 打印设备小结
echo "  [$model_name] 设备ID: $device_id_mac"
echo "  [$model_name] 核心掩码: $CORE_MASK"
echo "  [$model_name] 总帧数: $total_frames"
echo "  [$model_name] 总耗时: $tot_time ms"
echo "  [$model_name] 平均耗时: $avg_cost ms"
echo "  [$model_name] 总帧率: $total_fps"

if [ $error_found -eq 0 ]; then
    echo "  状态: ✅ 通过"
else
    echo "  状态: ❌ 失败"
fi

echo ""
echo "==================== 总体统计 ===================="
echo "总帧率: $total_fps"
echo "总帧数: $total_frames"
echo "=================================================="

# 处理日志保存
dest="/data/rknn3_model_stress_test_log"
mkdir -p "$dest"
cp "$current_log" "$dest/" 2>/dev/null || true
echo "日志拷贝到：$dest/$(basename $current_log)"
# 只删除自己的临时日志文件，不删除整个目录（可能被其他进程使用）
rm -f "$current_log"

if [ $error_found -eq 0 ]; then
    echo ""
    echo "✅ [SUCCESS] 设备压测通过。"
    echo "[rknn3_model_stress_test_done]"
    exit 0
else
    echo ""
    echo "❌ [ERROR] 设备压测存在异常，请检查上述日志。"
    echo "[rknn3_model_stress_test_error]"
    exit 1
fi