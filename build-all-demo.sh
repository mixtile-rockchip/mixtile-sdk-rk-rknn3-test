#!/bin/bash

set -e

# --- 默认参数设置 ---
TARGET_SOC=""
TARGET_ARCH=""
BUILD_TYPE="Release"
ENABLE_ASAN=OFF
DISABLE_RGA=OFF
DISABLE_LIBJPEG=OFF

# 只要执行该脚本，就同时编译这三个
DEMO_LIST=("rknn3_cnn_test" "rknn3_llm_test" "rknn3_vlm_test")

echo "$0 $@"
while getopts ":t:a:b:m:r:j" opt; do
  case $opt in
    t) TARGET_SOC=$OPTARG ;;
    a) TARGET_ARCH=$OPTARG ;;
    b) BUILD_TYPE=$OPTARG ;;
    m) ENABLE_ASAN=ON; export ENABLE_ASAN=TRUE ;;
    r) DISABLE_RGA=ON ;;
    j) DISABLE_LIBJPEG=ON ;;
    ?) echo "Invalid option: -$OPTARG"; exit 1 ;;
  esac
done

if [ -z ${TARGET_SOC} ]; then
  echo "用法: $0 -t <target> -a <arch> [-b <build_type>] [-m] [-r] [-j]"
  echo "示例: $0 -t rk3588 -a aarch64"
  exit -1
fi

# --- 编译器设置 ---
if [ "${TARGET_SOC}" = "x86" ]; then
    export CC=gcc
    export CXX=g++
    TARGET_PLATFORM="x86_64"
    DISABLE_RGA=ON
else
    export CC=${GCC_COMPILER}-gcc
    export CXX=${GCC_COMPILER}-g++
    TARGET_PLATFORM=${TARGET_SOC}_linux_${TARGET_ARCH}
    
    if ! command -v ${CC} >/dev/null 2>&1; then
        echo "❌ 未找到编译器: ${CC}, 请先 export GCC_COMPILER"
        exit 1
    fi
fi

ROOT_PWD=$( cd "$( dirname $0 )" && pwd )
# 修改安装根目录：汇总到同一个 install/平台名 下
FINAL_INSTALL_DIR=${ROOT_PWD}/install/${TARGET_PLATFORM}_rk1820_stress_test

echo "==========================================="
echo "开始批量编译: ${DEMO_LIST[*]}"
echo "目标平台: ${TARGET_PLATFORM}"
echo "安装目录: ${FINAL_INSTALL_DIR}"
echo "==========================================="

# 清理旧的汇总目录
[ -d "${FINAL_INSTALL_DIR}" ] && rm -rf "${FINAL_INSTALL_DIR}"
mkdir -p "${FINAL_INSTALL_DIR}"

# --- 进入循环编译 ---
for DEMO_NAME in "${DEMO_LIST[@]}"
do
    echo ">>>> 正在处理: ${DEMO_NAME} ...."
    
    # 自动寻找路径 (匹配你的目录结构)
    BUILD_DEMO_PATH=""
    for search_path in "rknn3_stress_test" "tested_models" "examples"; do
        if [ -d "${ROOT_PWD}/${search_path}/${DEMO_NAME}/cpp" ]; then
            BUILD_DEMO_PATH="${search_path}/${DEMO_NAME}/cpp"
            break
        fi
    done

    if [ -z "${BUILD_DEMO_PATH}" ]; then
        echo "⚠️ 跳过: 找不到 ${DEMO_NAME} 的 cpp 源码目录"
        continue
    fi

    # 为每个 Demo 创建独立的 build 目录
    CURRENT_BUILD_DIR=${ROOT_PWD}/build/build_${DEMO_NAME}_${TARGET_PLATFORM}
    mkdir -p "${CURRENT_BUILD_DIR}"
    
    cd "${CURRENT_BUILD_DIR}"
    
    # 执行 CMake
    # 注意：CMAKE_INSTALL_PREFIX 指向总目录下的子文件夹
    cmake ../../${BUILD_DEMO_PATH} \
        -DTARGET_SOC=${TARGET_SOC} \
        -DCMAKE_SYSTEM_NAME=Linux \
        -DCMAKE_SYSTEM_PROCESSOR=${TARGET_ARCH} \
        -DCMAKE_BUILD_TYPE=${BUILD_TYPE} \
        -DENABLE_ASAN=${ENABLE_ASAN} \
        -DDISABLE_RGA=${DISABLE_RGA} \
        -DDISABLE_LIBJPEG=${DISABLE_LIBJPEG} \
        -DCMAKE_INSTALL_PREFIX=${FINAL_INSTALL_DIR}

    make -j$(nproc)
    make install
    cp ${ROOT_PWD}/sh/* ${FINAL_INSTALL_DIR}/
    echo "✅ ${DEMO_NAME} 编译并安装完成。"
    cd "${ROOT_PWD}"
done

echo "==========================================="
echo "所有编译任务已完成！"
echo "程序包位于: ${FINAL_INSTALL_DIR}"
ls -l "${FINAL_INSTALL_DIR}"
echo "==========================================="