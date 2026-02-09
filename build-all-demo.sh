#!/bin/bash

set -e

# --- Default parameter Settings ---
TARGET_SOC=""
TARGET_ARCH=""
BUILD_TYPE="Release"
ENABLE_ASAN=OFF
DISABLE_RGA=OFF
DISABLE_LIBJPEG=OFF

# Only compile these tests when executing this script
DEMO_LIST=("rknn3_cnn_test" "rknn3_llm_test" "rknn3_vlm_test" "rknn3_audio_encoder_test")

echo "$0 $@"
while getopts ":t:a:b:m:r:j:g:" opt; do
  case $opt in
    t) TARGET_SOC=$OPTARG ;;
    a) TARGET_ARCH=$OPTARG ;;
    b) BUILD_TYPE=$OPTARG ;;
    m) ENABLE_ASAN=ON; export ENABLE_ASAN=TRUE ;;
    r) DISABLE_RGA=ON ;;
    j) DISABLE_LIBJPEG=ON ;;
    g) GCC_COMPILER=$OPTARG ;;
    ?) echo "Invalid option: -$OPTARG"; exit 1 ;;
  esac
done

if [ -z ${TARGET_SOC} ]; then
  echo "Usage: $0 -t <target> -a <arch> [-b <build_type>] [-m] [-r] [-j]"
  echo "Example: $0 -t rk3588 -a aarch64"
  exit -1
fi

# --- Compiler Settings ---
if [ "${TARGET_SOC}" = "x86" ]; then
    export CC=gcc
    export CXX=g++
    TARGET_PLATFORM="x86_64"
    DISABLE_RGA=ON
else
    # Use parameter GCC_COMPILER if provided, otherwise use environment variable
    if [ -z "$GCC_COMPILER" ]; then
        echo "No compiler specified: Please use the -g parameter or export GCC_COMPILER"
        exit 1
    fi

    export CC=${GCC_COMPILER}-gcc
    export CXX=${GCC_COMPILER}-g++
    TARGET_PLATFORM=${TARGET_SOC}_linux_${TARGET_ARCH}

    if ! command -v ${CC} >/dev/null 2>&1; then
        echo "The compiler was not found: ${CC}"
        exit 1
    fi
fi

ROOT_PWD=$( cd "$( dirname $0 )" && pwd )
# Modify the installation root directory: Consolidate it under the same install/ platform name
FINAL_INSTALL_DIR=${ROOT_PWD}/install/aicp_test_${TARGET_ARCH}

echo "==========================================="
echo "Start batch compilation: ${DEMO_LIST[*]}"
echo "Target platform: ${TARGET_PLATFORM}"
echo "Installation directory: ${FINAL_INSTALL_DIR}"
echo "==========================================="

# Clear the old summary directory
[ -d "${FINAL_INSTALL_DIR}" ] && rm -rf "${FINAL_INSTALL_DIR}"
mkdir -p "${FINAL_INSTALL_DIR}"

# --- Enter loop compilation ---
for DEMO_NAME in "${DEMO_LIST[@]}"
do
    echo ">>>> Being processed: ${DEMO_NAME} ...."

    # Automatically find the path (match your directory structure)
    BUILD_DEMO_PATH=""
    for search_path in "rknn3_stress_test" "tested_models" "examples"; do
        if [ -d "${ROOT_PWD}/${search_path}/${DEMO_NAME}/cpp" ]; then
            BUILD_DEMO_PATH="${search_path}/${DEMO_NAME}/cpp"
            break
        fi
    done

    if [ -z "${BUILD_DEMO_PATH}" ]; then
        echo "Skip: The cpp source code directory for ${DEMO_NAME} cannot be found"
        continue
    fi

    # Create an independent build directory for each Demo
    CURRENT_BUILD_DIR=${ROOT_PWD}/build/build_${DEMO_NAME}_${TARGET_PLATFORM}
    mkdir -p "${CURRENT_BUILD_DIR}"

    cd "${CURRENT_BUILD_DIR}"

    # Execute CMake
    # Note: CMAKE_INSTALL_PREFIX points to a subfolder in the main directory
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
    echo "${DEMO_NAME} has been compiled and installed successfully."
    cd "${ROOT_PWD}"
done

echo "==========================================="
echo "All compilation tasks have been completed!"
echo "The package is located at: ${FINAL_INSTALL_DIR}"
ls -l "${FINAL_INSTALL_DIR}"
echo "==========================================="