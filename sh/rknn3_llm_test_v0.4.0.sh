#!/bin/bash
# ------------------------------------------------------------------
#  run_power_loop.sh
#  用法：
#    ./run_power_loop.sh <prompt_len> <generation_len> <loop_cnt>
#  示例：
#    ./run_power_loop.sh 128 128 3
# ------------------------------------------------------------------
echo performance | tee $(find /sys/ -name *governor)

MAX_CONTEXT=1024
CORE_MASK=0xff


# 读取用户输入（如未传参则提示）
if [ $# -lt 5 ]; then
    echo "Usage: $0 <model_dir> <seq_len> <new_tokens> <loop_count> <loop_time> <device_id>"
    exit 1
fi
MODEL_DIR=$1
PROMPT_LEN=$2
GEN_LEN=$3
LOOP_CNT=$4
TIME_LOOP=$5
# 默认 device_id = 0
DEVICE_ID=${6:-0}



# 执行
rknn3_llm_demo \
    -m "${MODEL_DIR}.rknn" \
    -w "${MODEL_DIR}.weight" \
    -tk "${MODEL_DIR}.tokenizer.gguf" \
    -em "${MODEL_DIR}.embed.bin" \
    -ctx "$MAX_CONTEXT" \
    -ni "$PROMPT_LEN" \
    -no "$GEN_LEN" \
    -c "$CORE_MASK" \
    -cl "$LOOP_CNT" \
    -tl "$TIME_LOOP" \
    -id "$DEVICE_ID"

