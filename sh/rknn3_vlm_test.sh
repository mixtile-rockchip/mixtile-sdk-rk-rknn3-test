#!/usr/bin/env bash

# ===========================================
# RKNN3 VLM Demo 启动脚本
# 用法:
#   ./rknn3_vlm_demo_v0.4.0.sh <模型路径> [loop_time_hours] [count_loop]
#
# 示例:
#   ./rknn3_vlm_demo_v0.4.0.sh ./Qwen2.5-VL-3B 1 10
# ===========================================

echo performance | tee $(find /sys/ -name *governor)

if [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
    echo "==========================================="
    echo "RKNN3 VLM Demo 压测工具"
    echo "==========================================="
    echo "用法:"
    echo "  $0 <model_dir> <loop_time_hours> <count_loop> <device_num> "
    echo ""
    echo "参数说明:"
    echo "  model_dir        指定模型文件的基础路径,要指定到.rknn之前的路径例如:/userdata/Qwen2.5-VL-3B/Qwen2.5-VL-3B"
    echo "  loop_time_hours 压测持续时间 (小时)"
    echo "  count_loop      推理循环次数"
    echo "  device_num      设备数量 (1-N)"
    echo ""
    echo "当前支持的模型系列:Qwen2.5-VL/Qwen3-VL/FastVLM/InternVL3_5-4B"
    echo ""
    echo "==========================================="
    exit 0
fi

if [ $# -ne 4 ]; then
    echo "用法: $0 <模型目录> [loop_time_hours] [count_loop] [device_num]"
    exit 1
fi

# 参数读取
MODEL_DIR="$1"
LOOP_TIME="${2:-1}"          # 默认 loop_time = 1 小时
COUNT_LOOP="${3:-1}"         # 默认 count_loop = 1 次
DEVICE_NUM="$4"

echo "${MODEL_DIR}"
# 模型文件定义
VISION_MODEL="${MODEL_DIR}-vision.rknn"
VISION_WEIGHT="${MODEL_DIR}-vision.weight"
LLM_MODEL="${MODEL_DIR}-llm.rknn"
LLM_WEIGHT="${MODEL_DIR}-llm.weight"
TOKENIZER="${MODEL_DIR}-llm.tokenizer.gguf"
EMBEDDING="${MODEL_DIR}-llm.embed.bin"
IMAGE_PATH="test.jpg"
PROMPT_FILE="${MODEL_DIR}.ini"

# 核心掩码（根据平台可修改）
VISION_CORE_MASK="0xff"
LLM_CORE_MASK="0xff"

# 检查关键文件是否存在
for f in "$VISION_MODEL" "$LLM_MODEL" "$TOKENIZER" "$EMBEDDING" "$IMAGE_PATH" "$PROMPT_FILE"; do
    if [ ! -f "$f" ]; then
        echo "❌ miss file: $f"
        exit 1
    fi
done

echo "✅ 启动 rknn3_vlm_demo..."
echo "模型目录: $MODEL_DIR"
echo "Loop 时间: ${LOOP_TIME} 小时"
echo "循环次数: ${COUNT_LOOP}"

pids=()
start_time=$(date +%Y%m%d_%H%M%S)

model_dirname=$(basename "$MODEL_DIR")
LOG_DIR="/tmp/rknn3_${model_dirname}_log"
echo "日志目录: ${LOG_DIR}"
rm -rf "$LOG_DIR"
mkdir -p "$LOG_DIR"
log_pre="${LOG_DIR}/rknn3_$$"

echo "DEVICE_NUM:$DEVICE_NUM"
for id in $(seq 1 $DEVICE_NUM)
do 
    # log="${log_pre}_device${id}.log"
    current_log="${log_pre}_device${id}.log"
    echo "current_log:$current_log"
    log_files+=("$current_log")
    # 执行推理命令
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
        -id "$id-1" >"$current_log" 2>&1 &
        pids+=($!)
done

echo "等待所有进程完成..."
for pid in "${pids[@]}"; do wait "$pid"; done
echo "所有进程已完成。"

echo "==================== 压测结果汇总 ===================="

# 检查执行状态并打印指定关键词后的日志
error_found=0
for log in "${log_files[@]}"; do
    echo "$log"
    if grep -q "rknn3_model_stress_test_done" "$log"; then
        echo "--- 日志文件: $(basename "$log") (成功) ---"
        # 使用 sed 打印匹配行之后的所有内容
        sed -n '/rknn3_model_stress_test_done/,$p' "$log"
    else
        echo "--- 日志文件: $(basename "$log") (❌ 异常) ---"
        tail -n 20 "$log" # 如果没找到成功标志，打印最后20行报错
        error_found=1
    fi
    echo ""
done

if [ $error_found -eq 0 ]; then
    rm -rf ${LOG_DIR}
    echo "✅ [SUCCESS] 所有设备压测通过。"
else
    dest="/data/rknn3_model_stress_test_log/rknn3_${model_dirname}_${start_time}"
    mkdir -p "$dest"
    cp "${LOG_DIR}"/* "$dest/" 2>/dev/null || true
    echo "❌ [ERROR] 部分设备压测存在异常，请检查上述日志。"
    echo "日志拷贝到：$dest"
    echo "[rknn3_model_stress_test_error]"
    exit 1
fi
