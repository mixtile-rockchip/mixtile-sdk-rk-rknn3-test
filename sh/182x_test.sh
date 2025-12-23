#!/bin/bash

# 定义颜色代码，用于美化输出
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
PURPLE='\033[1;35m'
CYAN='\033[1;36m'
NC='\033[0m' # 恢复默认颜色

# 脚本信息
SCRIPT_VERSION="1.0"
TEST_RESULTS_DIR="./test_results"
mkdir -p "$TEST_RESULTS_DIR"
LOG_FILE="$TEST_RESULTS_DIR/rknn_test_$(date +%Y%m%d_%H%M%S).log"

# 全局变量
LOOP=1
DEVICES_NUM=1
SEQ_LEN=512
NEW_TOKENS=512

# ============================================================================
# 输入验证函数
# ============================================================================

# 通用输入验证函数
validate_number_input() {
    local prompt="$1"
    local variable_name="$2"
    local min_value="${3:-1}"  # 默认最小值为1
    local max_value="${4:-100000}"  # 默认最大值较大以适应不同参数
    
    while true; do
        read -p "$prompt" input
        
        # 验证是否为空
        if [[ -z "$input" ]]; then
            echo -e "${RED}错误：输入不能为空，请重新输入！${NC}"
            continue
        fi
        
        # 验证是否为正整数
        if [[ ! "$input" =~ ^[1-9][0-9]*$ ]]; then
            echo -e "${RED}错误：请输入有效的正整数！${NC}"
            continue
        fi
        
        # 验证范围
        if [[ "$input" -lt "$min_value" || "$input" -gt "$max_value" ]]; then
            echo -e "${RED}错误：请输入${min_value}-${max_value}之间的数字！${NC}"
            continue
        fi
        
        # 赋值给全局变量
        if [[ "$variable_name" == "LOOP" ]]; then
            LOOP="$input"
        elif [[ "$variable_name" == "DEVICES_NUM" ]]; then
            DEVICES_NUM="$input"
        elif [[ "$variable_name" == "SEQ_LEN" ]]; then
            SEQ_LEN="$input"
        elif [[ "$variable_name" == "NEW_TOKENS" ]]; then
            NEW_TOKENS="$input"
        fi
        
        break
    done
}

get_loop() {
    validate_number_input "请输入循环次数: " "LOOP" 1 100000
}

get_devices_num() {
    validate_number_input "请输入设备数量(1-64): " "DEVICES_NUM" 1 64
}

get_seq_len() {
    validate_number_input "请输入seq_len: " "SEQ_LEN" 1 65536
}

get_new_tokens() {
    validate_number_input "请输入new_tokens: " "NEW_TOKENS" 1 65536
}

# ============================================================================
# 通用测试函数框架
# ============================================================================

# 模型配置数组
declare -A MODEL_CONFIGS=(
    # CNN模型
    ["cnn_1"]="Dinov3 cnn ../Dinov3/Dinov3"
    ["cnn_2"]="Siglip2 cnn ../Siglip2/Siglip2" 
    ["cnn_3"]="YOLOv5s cnn ../YOLOv5s/YOLOv5s"
    ["cnn_4"]="YOLOv6s cnn ../YOLOv6s/YOLOv6s"
    ["cnn_5"]="YOLOv8s cnn ../YOLOv8s/YOLOv8s"
    ["cnn_6"]="MobilenetV1 cnn ../MobilenetV1/MobilenetV1"
    ["cnn_7"]="MobilenetV2 cnn ../MobilenetV2/MobilenetV2"
    ["cnn_8"]="Resnet50-v2 cnn ../Resnet50-v2/Resnet50-v2"
    
    # LLM模型
    ["llm_1"]="Qwen2.5-3B-Instruct llm ../Qwen2.5-3B-Instruct/Qwen2.5-3B-Instruct"
    ["llm_2"]="Qwen2.5-7B-Instruct llm ../Qwen2.5-7B-Instruct/Qwen2.5-7B-Instruct"
    
    # VLM模型
    ["vlm_1"]="FasterVLM-llm vlm ../FasterVLM-llm/FasterVLM-llm"
    ["vlm_2"]="InternVL3-2B vlm ../InternVL3-2B/InternVL3-2B"
    ["vlm_3"]="InternVL3_5-4B vlm ../InternVL3_5-4B/InternVL3_5-4B"
    ["vlm_4"]="Qwen2.5-VL-3B vlm ../Qwen2.5-VL-3B/Qwen2.5-VL-3B"
    ["vlm_5"]="Qwen2.5-VL-7B vlm ../Qwen2.5-VL-7B/Qwen2.5-VL-7B"
    ["vlm_6"]="Qwen3-VL-2B vlm ../Qwen3-VL-2B/Qwen3-VL-2B"
    ["vlm_7"]="Qwen3-VL-4B vlm ../Qwen3-VL-4B/Qwen3-VL-4B"
)

# 通用模型测试函数
test_model() {
    local model_name="$1"
    local model_type="$2"
    local model_path="$3"
    
    show_test_start "$model_type" "$model_name"
    echo "执行${model_name}模型测试..."
    
    # 获取用户输入
    get_loop
    get_devices_num
    echo "循环次数是: $LOOP"
    echo "设备数量: $DEVICES_NUM"
    
    # 根据模型类型执行不同的测试命令[2](@ref)
    case "$model_type" in
        "llm")
            # LLM模型需要额外的参数输入
            get_seq_len
            get_new_tokens
            echo "seq_len: $SEQ_LEN"
            echo "new_tokens: $NEW_TOKENS"
            
            # LLM模型测试命令
            echo -e "${CYAN}执行LLM测试命令: ./rknn3_llm_test.sh $model_path $SEQ_LEN $NEW_TOKENS 0 $LOOP $DEVICES_NUM${NC}"
            ./rknn3_llm_test.sh $model_path $SEQ_LEN $NEW_TOKENS 0 $LOOP $DEVICES_NUM
            ;;
        "cnn")
            # CNN模型测试命令
            echo -e "${CYAN}执行CNN测试命令: ./rknn3_cnn_test.sh $model_path 0 $LOOP $DEVICES_NUM${NC}"
            ./rknn3_cnn_test.sh $model_path 0 $LOOP $DEVICES_NUM
            ;;
        "vlm")
            # VLM模型测试命令
            echo -e "${CYAN}执行VLM测试命令: ./rknn3_vlm_test.sh $model_path 0 $LOOP $DEVICES_NUM${NC}"
            ./rknn3_vlm_test.sh $model_path 0 $LOOP $DEVICES_NUM
            ;;
        *)
            echo -e "${RED}未知的模型类型: $model_type${NC}"
            show_test_result 1 "$model_name"
            wait_return
            return 1
            ;;
    esac
    
    # 检查命令执行结果
    local test_result=$?
    if [ $test_result -eq 0 ]; then
        show_test_result 0 "$model_name"
        log_message "$model_name 测试完成 - 循环: $LOOP, 设备: $DEVICES_NUM, 序列长度: $SEQ_LEN, 新令牌数: $NEW_TOKENS"
    else
        show_test_result 1 "$model_name"
        log_message "$model_name 测试失败 - 退出码: $test_result"
    fi
    
    wait_return
}

# ============================================================================
# 菜单生成函数（保持不变）
# ============================================================================

# 通用菜单生成函数
generate_test_menu() {
    local menu_type="$1"
    local menu_title="$2"
    local color="$3"
    
    while true; do
        show_test_header
        echo -e "${color}${menu_title}选项：${NC}"
        
        # 动态生成菜单选项
        local count=1
        local menu_items=()
        
        for key in $(echo "${!MODEL_CONFIGS[@]}" | tr ' ' '\n' | grep "^${menu_type}_" | sort); do
            local model_info=(${MODEL_CONFIGS[$key]})
            echo "$count. ${model_info[0]}"
            menu_items[$count]="$key"
            ((count++))
        done
        
        local return_option=$count
        echo "$return_option. 返回上级菜单"
        echo
        
        read -rp "请选择要测试的模型 (1-$return_option): " choice
        
        # 验证输入[1](@ref)
        if [[ ! "$choice" =~ ^[0-9]+$ ]]; then
            echo -e "${RED}无效输入，请输入数字！${NC}"
            sleep 2
            continue
        fi
        
        if [[ "$choice" -eq "$return_option" ]]; then
            return
        elif [[ "$choice" -ge 1 && "$choice" -le $((return_option-1)) ]]; then
            local selected_key="${menu_items[$choice]}"
            local model_info=(${MODEL_CONFIGS[$selected_key]})
            test_model "${model_info[0]}" "${model_info[1]}" "${model_info[2]}"
        else
            echo -e "${RED}无效选择，请输入1-$return_option${NC}"
            sleep 2
        fi
    done
}

# ============================================================================
# 核心功能函数（保持不变）
# ============================================================================

# 记录日志函数
log_message() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" | tee -a "$LOG_FILE"
}

# 显示测试头信息
show_test_header() {
    clear
    echo -e "${GREEN}"
    echo "========================================"
    echo "          182X算力卡 测试脚本"
    echo "                版本 $SCRIPT_VERSION"
    echo "========================================"
    echo -e "${NC}"
}

# 等待用户按键返回
wait_return() {
    echo
    echo -e "${YELLOW}按 Enter 键返回菜单...${NC}"
    read -r
}

# 显示测试开始信息
show_test_start() {
    local model_type="$1"
    local model_name="$2"
    echo
    echo -e "${BLUE}========================================${NC}"
    echo -e "${GREEN}开始 $model_type 测试${NC}"
    echo -e "${GREEN}模型: $model_name${NC}"
    echo -e "${BLUE}========================================${NC}"
    log_message "开始测试: $model_type - $model_name"
}

# 显示测试结果
show_test_result() {
    local success="$1"
    local model_name="$2"
    
    if [ "$success" -eq 0 ]; then
        echo -e "${GREEN}✓ $model_name 测试完成${NC}"
        log_message "$model_name 测试结果: 完成"
    else
        echo -e "${RED}✗ $model_name 测试失败${NC}"
        log_message "$model_name 测试结果: 失败"
    fi
}

# ============================================================================
# 菜单函数（简化版）
# ============================================================================

# 主菜单
main_menu() {
    while true; do
        show_test_header
        echo -e "${GREEN}主菜单选项：${NC}"
        echo "1. RKNN Test"
        echo "2. 查看测试日志"
        echo "3. Exit"
        echo
        
        read -rp "请选择操作 (1-3): " choice
        
        case $choice in
            1) rknn_test_menu ;;
            2) view_test_logs ;;
            3) 
                echo -e "${GREEN}感谢使用182x测试脚本，再见！${NC}"
                log_message "脚本正常退出"
                exit 0 
                ;;
            *) 
                echo -e "${RED}无效选择，请输入1-3${NC}"
                sleep 2
                ;;
        esac
    done
}

# RKNN测试主菜单
rknn_test_menu() {
    while true; do
        show_test_header
        echo -e "${BLUE}RKNN测试选项：${NC}"
        echo "1. CNN模型验证测试"
        echo "2. LLM模型验证测试" 
        echo "3. VLM模型验证测试"
        echo "4. 返回主菜单"
        echo
        
        read -rp "请选择测试类型 (1-4): " choice
        
        case $choice in
            1) cnn_test_menu ;;
            2) llm_test_menu ;;
            3) vlm_test_menu ;;
            4) return ;;
            *) 
                echo -e "${RED}无效选择，请输入1-4${NC}"
                sleep 2
                ;;
        esac
    done
}

# 使用通用菜单函数
cnn_test_menu() {
    generate_test_menu "cnn" "CNN模型验证测试" "${CYAN}"
}

llm_test_menu() {
    generate_test_menu "llm" "LLM模型验证测试" "${PURPLE}"
}

vlm_test_menu() {
    generate_test_menu "vlm" "VLM模型验证测试" "${YELLOW}"
}

# ============================================================================
# 日志查看功能
# ============================================================================

view_test_logs() {
    show_test_header
    echo -e "${CYAN}测试日志内容：${NC}"
    echo "=========================================="
    
    if [ -f "$LOG_FILE" ]; then
        if [ -s "$LOG_FILE" ]; then
            tail -20 "$LOG_FILE"
        else
            echo "日志文件为空"
        fi
    else
        echo "日志文件不存在"
    fi
    
    echo "=========================================="
    wait_return
}

# ============================================================================
# 脚本初始化
# ============================================================================

# 检查脚本是否直接运行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # 设置信号处理，确保优雅退出
    trap 'echo -e "\n${RED}脚本被用户中断${NC}"; log_message "脚本被用户中断"; exit 1' INT TERM
    
    # 显示欢迎信息
    show_test_header
    ./install_rknn3_model_stress.sh
    echo -e "${GREEN}脚本初始化完成${NC}"
    echo -e "测试结果目录: $TEST_RESULTS_DIR"
    echo -e "日志文件: $LOG_FILE"
    echo
    log_message "=== 测试脚本启动 ==="
    
    # 进入主菜单
    main_menu
fi