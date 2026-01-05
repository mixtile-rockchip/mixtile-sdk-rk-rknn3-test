#!/bin/bash

echo performance | tee $(find /sys/ -name *governor)

MAX_CONTEXT=1024
CORE_MASK=0xff

if [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
    echo "==========================================="
    echo "RKNN3 LLM Demo 压测工具"
    echo "==========================================="
    echo "用法:"
    echo "  $0 <model_dir> <seq_len> <new_tokens> <loop_time> <loop_count> <device_id> [core_mask(optional)]"
    echo ""
    echo "参数说明:"
    echo "  model_dir       指定模型文件的基础路径,要指定到.rknn之前的路径例如:/userdata/Qwen2.5-0.5B/Qwen2.5-0.5B"
    echo "  seq_len         指定prompt长度"
    echo "  new_tokens      指定输出长度，如果为1则表示prefill模式"
    echo "  loop_time       压测持续时间 (小时),如果为0，则循环次数"
    echo "  loop_count      推理循环次数，时间循环优先"
    echo "  device_id       指定设备ID (通常为0)"
    echo "  core_mask       核心掩码(可选,16进制),如'0xff'表示全8核,'0x0f'表示核心0-3"
    echo ""
    echo "核心掩码示例:"
    echo "  0xff   - 全8核 (二进制: 11111111)"
    echo "  0x0f   - 核心0-3 (二进制: 00001111)"
    echo "  0xf0   - 核心4-7 (二进制: 11110000)"
    echo "  0x03   - 核心0-1 (二进制: 00000011)"
    echo ""
    echo "当前支持的模型系列:Qwen2.5/Qwen3"
    echo ""
    echo "==========================================="
    exit 1
fi

if [ $# -lt 6 ]; then
    echo "Usage: $0 <model_dir> <seq_len> <new_tokens> <loop_time> <loop_count> <device_id> [core_mask(optional)]"
    exit 1
fi
MODEL_DIR=$1
PROMPT_LEN=$2
GEN_LEN=$3
TIME_LOOP=$4
LOOP_CNT=$5
DEVICE_ID=$6
CORE_MASK="${7:-0xff}"  # 默认全8核

model_name=$(basename "$MODEL_DIR")

RKNN_MODEL=${MODEL_DIR}.rknn
WEIGHT_MODEL=${MODEL_DIR}.weight
for f in "$RKNN_MODEL" "$WEIGHT_MODEL"; do
    if [ ! -f "$f" ]; then
        echo "❌ miss file: $f"
        exit 1
    fi
done

echo "✅ 启动 rknn3_llm_demo..."
echo "模型目录: $MODEL_DIR"
echo "Loop 时间: ${TIME_LOOP} 小时"
echo "循环次数: ${LOOP_CNT}"
echo "指定设备ID: ${DEVICE_ID}"
echo "核心掩码: $CORE_MASK"

pids=()
start_time=$(date +%Y%m%d_%H%M%S)
model_dirname=$(basename "$MODEL_DIR")
LOG_DIR="/tmp"
echo "日志目录: ${LOG_DIR}"
mkdir -p "$LOG_DIR"
log_pre="${LOG_DIR}/rknn3_$$"

current_log="${log_pre}_${model_dirname}_${start_time}_device${DEVICE_ID}_${CORE_MASK}.log"
log_files+=("$current_log")

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
    -id "${DEVICE_ID}" >"$current_log" 2>&1 &
    pids+=($!)

echo "等待所有进程完成..."
for pid in "${pids[@]}"; do wait "$pid"; done
echo "所有进程已完成。"

echo "==================== 压测结果汇总 ===================="

# 检查执行状态并打印指定关键词后的日志
error_found=0
ttft=""
tpot=""
prefill_tps=""
tps=""
total_time=""
total_runs=""

for log in "${log_files[@]}"; do
    echo "$log"
    if grep -q "rknn3_model_stress_test_done" "$log"; then
        # echo "--- 日志文件: $(basename "$log") (成功) ---"
        # 使用 sed 打印匹配行之后的所有内容
        sed -n '/rknn3_model_stress_test_done/,$p' "$log"


        ttft=$(grep 'TTFT:' "$log" 2>/dev/null | tail -n 1 | awk '{for(i=3;i<=NF;i++) printf "%s%s",$i,(i==NF?"\n":" ")}')
        tpot=$(grep 'TPOT:' "$log" 2>/dev/null | tail -n 1 | awk -F'=' '{print $NF}' | sed 's/^[[:space:]]*//')
        prefill_tps=$(grep 'Prefill:' "$log" 2>/dev/null | tail -n 1 | awk -F'=' '{print $NF}' | sed 's/^[[:space:]]*//')
        tps=$(grep 'TPS:' "$log" 2>/dev/null | tail -n 1 | awk -F'=' '{print $NF}' | sed 's/^[[:space:]]*//')
        total_time=$(grep '总耗时：' "$log" 2>/dev/null | tail -n 1 | awk '{for(i=3;i<=NF;i++) printf "%s%s",$i,(i==NF?"\n":" ")}')
        total_runs=$(grep '总推理次数:' "$log" 2>/dev/null | tail -n 1 | awk '{print $NF}')
    else
        echo "--- 日志文件: $(basename "$log") (❌ 异常) ---"
        tail -n 20 "$log" # 如果没找到成功标志，打印最后20行报错
        error_found=1
    fi
    echo ""
done

# 处理日志保存
# 1. 保存到 /data 目录（完整日志）
dest="/data/rknn3_model_stress_test_log"
mkdir -p "$dest"
cp "$current_log" "$dest/" 2>/dev/null || true
echo "日志拷贝到：$dest/$(basename $current_log)"

# 2. 保存到脚本运行目录的 test_results/performance/llm.log（追加模式，带锁）
SCRIPT_RUN_DIR="$(pwd)"
RESULT_DIR="${SCRIPT_RUN_DIR}/test_results/performance"
mkdir -p "$RESULT_DIR"
RESULT_FILE="${RESULT_DIR}/llm.log"
LOCK_FILE="${RESULT_FILE}.lock"

# 准备要追加的内容
APPEND_CONTENT=$(cat <<EOF
llm:
model: ${model_name}
core: ${CORE_MASK}
seq_len: ${PROMPT_LEN}
token: ${GEN_LEN}
TTFT: ${ttft}
TPOT: ${tpot}
Prefill: ${prefill_tps}
TPS: ${tps}
TotalTime: ${total_time}
TotalRuns: ${total_runs}
EOF
)

# 使用 flock 加锁，避免并发写入冲突
(
    flock -x 200  # 获取独占锁
    # 如果文件存在且非空，先追加空行
    if [ -s "$RESULT_FILE" ]; then
        echo "" >> "$RESULT_FILE"
    fi
    # 追加新内容
    echo "$APPEND_CONTENT" >> "$RESULT_FILE"
) 200>"$LOCK_FILE"

echo "测试结果追加到：${RESULT_FILE}"

# 只删除自己的临时日志文件，不删除整个目录（可能被其他进程使用）
rm -f "$current_log"

if [ $error_found -eq 0 ]; then
    # rm -rf ${LOG_DIR}
    echo "✅ [SUCCESS] 所有设备压测通过。"
    echo "[rknn3_model_stress_test_done]"
    exit 0
else
    dest="/data/rknn3_model_stress_test_log/rknn3_${model_dirname}_${start_time}"
    # mkdir -p "$dest"
    # cp "${LOG_DIR}"/* "$dest/" 2>/dev/null || true
    echo "❌ [ERROR] 部分设备压测存在异常，请检查上述日志。"
    # echo "日志拷贝到：$dest"
    echo "[rknn3_model_stress_test_error]"
    exit 1
fi