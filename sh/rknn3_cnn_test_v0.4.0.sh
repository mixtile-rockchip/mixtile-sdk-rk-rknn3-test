#!/usr/bin/env bash
start_time=$(date +"%Y-%m-%d_%H-%M-%S")
set -uo pipefail

echo performance | tee $(find /sys/ -name *governor)

[ $# -lt 3 ] && { echo "用法: $0 <模型> <循环时间> <循环次数> "; exit 1; }
model=$1; time_loop=$2 cnt_loop=$3

echo "model:{model}"
echo "time_loop:${time_loop}"
model_dirname=$(basename "$(dirname "$model")")
pids=()               # 当前 shell 直接启动的 PID
echo "$model"
LOG_DIR="/tmp/rknn3_${model_dirname}_log"
echo "${LOG_DIR}"
rm -rf "$LOG_DIR"
mkdir -p "$LOG_DIR"
log_pre="${LOG_DIR}/rknn3_$$"   # 日志前缀，用 $$ 避免冲突

# 启动 8 个并行任务
for core in {1..8}; do
    mask=$((1 << (core - 1)))
    log="${log_pre}_core${core}.log"
    rknn3_cnn_demo \
        -m "${model}.rknn" \
		-w "${model}.weight" \
        -c "0x$(printf '%02x' $mask)" \
		-i "${model}.jpg" \
		-tl "${time_loop}" \
		-cl "${cnt_loop}" >"$log" 2>&1 &
    pids+=($!)        # 记录 PID
done

# 等待全部结束
for pid in "${pids[@]}"; do wait "$pid"; done

# 汇总结果
echo "===== 各核结果 ====="
for core in {1..8}; do
    log="${log_pre}_core${core}.log"
    last2=$(tail -1 "$log" | head -1)
    echo "$last2"
    if echo "$last2" | grep -q "rknn3_model_stress_test_done"; then
	echo "test1"
        echo "Core $core : 完成"
	rm -rf "${log}"
    else
	echo "test2"
        echo "Core $core : 失败"
    fi
    #rm -f "$log"      # 清理临时日志
done

# 2. 拷贝剩余日志（失败的）

# 目录里是否存在任意文件（含子目录）
if [ -n "$(ls -A "$LOG_DIR" 2>/dev/null)" ]; then
    dest="/data/rknn3_model_stress_test_log/rknn3_${model_dirname}_${start_time}"
    mkdir -p "$dest"
    cp "${log_pre}"_core*.log  "$dest"/  2>/dev/null || true
    for f in "${log_pre}"_core*.log; do
        [ -f "$f" ] && cat "$f"
    done
    echo "剩余日志已拷贝到：$dest"
    echo "[rknn3_model_stress_test_error] All processes done. have fail case,Please check."
else
    echo "[rknn3_model_stress_test_done] All processes finished successfully."
fi
rm -rf "$LOG_DIR"