#!/usr/bin/env bash

echo performance | tee $(find /sys/ -name *governor)

if [[ "${BASH_VERSION%%.*}" -ge 4 ]]; then
    set -uo pipefail
else
    set -u  # 旧版 bash 只使用 -u
fi

[ $# -lt 4 ] && { echo "用法: $0 <RK1820模型>  [loop_time_hours] [count_loop] [device_num]"; exit 1; }

model=$1
time_loop=$2
cnt_loop=$3
device_num=$4

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
echo "device_num: ${device_num}"

for id in $(seq 1 $device_num)
do
    for core in {1..8}; do
        mask=$((1 << (core - 1)))
        log="${log_pre}_device${id}_core${core}.log"
        # echo "$log"
        rknn3_cnn_demo \
            -m "$RKNN_MODEL" \
            -w "$WEIGHT_MODEL" \
            -c "0x$(printf '%02x' $mask)" \
            -i "$IMG_PATH" \
            -tl "${time_loop}" \
            -id "${id-1}" \
            -cl "${cnt_loop}" >"$log" 2>&1 &
        pids+=($!)
    # echo "设备ID:$id,NPU核心：$core"
    done
done
# 启动 8 个并行任务
# 等待全部结束
echo "等待所有进程完成..."
for pid in "${pids[@]}"; do wait "$pid"; done
echo "所有进程已完成。"

error_found=0
for id in $(seq 1 $device_num)
do
    echo ""
    echo "===== 各核结果与总帧率 ====="

    total_fps=0
    success_cores=0
    all_fps=0
    tot_time=0

    for core in {1..8}; do
        # echo "$device_id"
        log="${log_pre}_device${id}_core${core}.log"
        device_id_line=$(grep 'device_id' "$log" 2>/dev/null | tail -n 1)
        device_id=$(echo "$device_id_line" | awk -F': ' '{print $2}')

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


    #all_fps=$(awk "BEGIN { print $all_fps + $total_fps }")

    model_name=$(basename "$1")
    echo "---------------------测试情况小结---------------------"
    echo "RKNN3模型： $1"
    echo -e "$model_name 设备ID: $device_id"
    echo -e "$model_name 成功核心数:       $success_cores / 8"
    echo -e "$model_name 成功核心总帧数:   $all_fps"
    echo -e "$model_name 总耗时:        $tot_time ms"
    echo -e "$model_name 总帧率:           $total_fps"
    echo "---------------------------------------------------"

done
    # 检查失败情况
    if [ -n "$(ls -A "$LOG_DIR" 2>/dev/null)" ]; then
        dest="/data/rknn3_model_stress_test_log/rknn3_${model_dirname}_${start_time}"
        mkdir -p "$dest"
        for id in $(seq 1 $device_num) 
        do
            cp "${log_pre}_device${id}_core"*.log "$dest/" 2>/dev/null || true
        done
        echo ""
        echo "❌ [ERROR] 部分设备压测存在异常，请检查上述日志。"
        echo "日志已拷贝到: $dest"
        # echo "[rknn3_model_stress_test_error] 存在失败用例"#    echo "日志已拷贝到: $dest"
    else
        echo ""
        echo "✅ [SUCCESS] 所有设备压测通过。"
        # echo "[rknn3_model_stress_test_done] 所有进程成功完成"
    fi
    rm -rf "$LOG_DIR"


