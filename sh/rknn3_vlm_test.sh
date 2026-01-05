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
    echo "  $0 <model_dir> <loop_time_hours> <count_loop> <device_id> [core_mask(optional)]"
    echo ""
    echo "参数说明:"
    echo "  model_dir        指定模型文件的基础路径,要指定到.rknn之前的路径例如:/userdata/Qwen2.5-VL-3B/Qwen2.5-VL-3B"
    echo "  loop_time_hours  压测持续时间 (小时)"
    echo "  count_loop       推理循环次数"
    echo "  device_id        指定设备ID (通常为0)"
    echo "  core_mask        核心掩码(可选,16进制),如'0xff'表示全8核,'0x0f'表示核心0-3"
    echo ""
    echo "核心掩码示例:"
    echo "  0xff   - 全8核 (二进制: 11111111)"
    echo "  0x0f   - 核心0-3 (二进制: 00001111)"
    echo "  0xf0   - 核心4-7 (二进制: 11110000)"
    echo "  0x03   - 核心0-1 (二进制: 00000011)"
    echo ""
    echo "当前支持的模型系列:Qwen2.5-VL/Qwen3-VL/FastVLM/InternVL3_5-4B"
    echo ""
    echo "==========================================="
    exit 1
fi

if [ $# -lt 4 ]; then
    echo "用法: $0 <模型目录> <loop_time_hours> <count_loop> <device_id> [core_mask(optional)]"
    exit 1
fi

# 参数读取
MODEL_DIR="$1"
LOOP_TIME="$2"
COUNT_LOOP="$3"
DEVICE_ID="$4"
CORE_MASK="${5:-0xff}"  # 默认全8核

model_name=$(basename "$MODEL_DIR")

# 将CORE_MASK赋值给Vision和LLM
VISION_CORE_MASK="$CORE_MASK"
LLM_CORE_MASK="$CORE_MASK"

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
    -id "${DEVICE_ID}" >"$current_log" 2>&1 &
    pids+=($!)

echo "等待所有进程完成..."
for pid in "${pids[@]}"; do wait "$pid"; done
echo "所有进程已完成。"

echo "==================== 压测结果汇总 ===================="

# 检查执行状态并打印指定关键词后的日志
error_found=0
vision=""
gen_len=""
ttft=""
tps=""
total_time=""
total_runs=""
input_width=""
input_height=""

for log in "${log_files[@]}"; do
    echo "$log"
    if grep -q "rknn3_model_stress_test_done" "$log"; then
        echo "--- 日志文件: $(basename "$log") (成功) ---"
        sed -n '/rknn3_model_stress_test_done/,$p' "$log"

        vision=$(grep '| Vision' "$log" 2>/dev/null | tail -n 1 | awk -F'|' '{print $3}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        gen_len=$(grep '| GenLen' "$log" 2>/dev/null | tail -n 1 | awk -F'|' '{print $3}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        ttft=$(grep '| TTFT' "$log" 2>/dev/null | tail -n 1 | awk -F'|' '{print $3}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        tps=$(grep '| TPS' "$log" 2>/dev/null | tail -n 1 | awk -F'|' '{print $3}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        total_time=$(grep '总耗时：' "$log" 2>/dev/null | tail -n 1 | awk '{for(i=3;i<=NF;i++) printf "%s%s",$i,(i==NF?"\n":" ")}')
        total_runs=$(grep '总推理次数:' "$log" 2>/dev/null | tail -n 1 | awk '{print $NF}')

        # 提取 vision 模型输入分辨率信息
        model_size_line=$(grep 'model_width=' "$log" 2>/dev/null | tail -n 1)
        if [[ -n "$model_size_line" ]]; then
            input_width=$(echo "$model_size_line" | awk -F'model_width=' '{print $2}' | awk '{print $1}')
            input_height=$(echo "$model_size_line" | awk -F'model_height=' '{print $2}' | awk '{print $1}')
            input_channel=3  # VLM vision 模型输入固定为 RGB888 格式（3通道）
        else
            input_width="unknown"
            input_height="unknown"
            input_channel="unknown"
        fi
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

# 2. 保存到脚本运行目录的 test_results/performance/vlm.log（追加模式，带锁）
SCRIPT_RUN_DIR="$(pwd)"
RESULT_DIR="${SCRIPT_RUN_DIR}/test_results/performance"
mkdir -p "$RESULT_DIR"
RESULT_FILE="${RESULT_DIR}/vlm.log"
LOCK_FILE="${RESULT_FILE}.lock"

# 准备要追加的内容
APPEND_CONTENT=$(cat <<EOF
vlm:
model: ${model_name}
core: ${CORE_MASK}
input_width: ${input_width}
input_height: ${input_height}
Vision: ${vision}
GenLen: ${gen_len}
TTFT: ${ttft}
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
    exit 0
else
    # dest="/data/rknn3_model_stress_test_log/rknn3_${model_dirname}_${start_time}"
    # mkdir -p "$dest"
    # cp "${LOG_DIR}"/* "$dest/" 2>/dev/null || true
    echo "❌ [ERROR] 部分设备压测存在异常，请检查上述日志。"
    echo "日志拷贝到：$dest"
    echo "[rknn3_model_stress_test_error]"
    exit 1
fi
