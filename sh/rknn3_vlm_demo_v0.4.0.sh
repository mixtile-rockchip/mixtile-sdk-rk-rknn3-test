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

if [ $# -lt 1 ]; then
    echo "用法: $0 <模型目录> [loop_time_hours] [count_loop]"
    exit 1
fi

# 参数读取
MODEL_DIR="$1"
LOOP_TIME="${2:-1}"          # 默认 loop_time = 1 小时
COUNT_LOOP="${3:-1}"         # 默认 count_loop = 1 次

# 模型文件定义
VISION_MODEL="${MODEL_DIR}-vision.rknn"
VISION_WEIGHT="${MODEL_DIR}-vision.weight"
LLM_MODEL="${MODEL_DIR}-llm.rknn"
LLM_WEIGHT="${MODEL_DIR}-llm.weight"
TOKENIZER="${MODEL_DIR}-llm.tokenizer.gguf"
EMBEDDING="${MODEL_DIR}-llm.embed.bin"
IMAGE_PATH="${MODEL_DIR}.jpg"
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
    -tl "$LOOP_TIME"

# 检查执行状态
if [ $? -eq 0 ]; then
    echo "rknn3_model_stress_test_done"
else
    echo "rknn3_model_stress_test_error"
    exit 1
fi
