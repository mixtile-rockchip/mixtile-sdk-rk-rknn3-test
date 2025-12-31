#!/bin/bash

set -e

# Set default values
default_target_soc="rk3588"
default_target_arch="arm64-v8a"
default_build_type="Release"

# Initialize variables with defaults
TARGET_SOC="$default_target_soc"
TARGET_ARCH="$default_target_arch"
BUILD_TYPE="$default_build_type"

# Process command line options
echo "$0 $@"
while getopts ":t:a:d:b:m:r:j" opt; do
  case $opt in
    t)
      TARGET_SOC=$OPTARG
      ;;
    a)
      TARGET_ARCH=$OPTARG
      ;;
    d)
      BUILD_DEMO_NAME=$OPTARG
      ;;
    b)
      BUILD_TYPE=$OPTARG
      ;;
    m)
      ENABLE_ASAN=ON
      export ENABLE_ASAN=TRUE
      ;;
    r)
      DISABLE_RGA=ON
      ;;
    j)
      DISABLE_LIBJPEG=ON
      ;;
    :)
      echo "Option -$OPTARG requires an argument." 
      exit 1
      ;;
    ?)
      echo "Invalid option: -$OPTARG index:$OPTIND"
      ;;
  esac
done

# Check if demo name is provided
if [ -z ${BUILD_DEMO_NAME} ]; then
  echo "$0 [-t <target>] [-a <arch>] -d <build_demo_name> [-b <build_type>] [-m] [-r] [-j]"
  echo ""
  echo "Default values:"
  echo "    -t : target (default: $default_target_soc)"
  echo "    -a : arch (default: $default_target_arch)"
  echo "    -b : build_type (default: $default_build_type)"
  echo ""
  echo "Options:"
  echo "    -t : target (rk3588/rk3576)"
  echo "    -a : arch (arm64-v8a/armeabi-v7a)"
  echo "    -d : demo name (required, all for compile all demos)"
  echo "    -b : build_type (Debug/Release)"
  echo "    -m : enable address sanitizer, build_type need set to Debug"
  echo "    -r : disable rga, use cpu resize image"
  echo "    -j : disable libjpeg to avoid conflicts between libjpeg and opencv"
  echo ""
  echo "Examples:"
  echo "  $0 -d rknn3_vlm_test"
  echo "  $0 -d rknn3_vlm_test -b Debug"
  echo "  $0 -t rk3588 -a arm64-v8a -d rknn3_vlm_test -b Release"
  echo "  $0 -d all"
  echo "Note: 'if you want to use opencv to read or save jpg files, use the '-j' option to disable libjpeg"
  echo ""
  echo "Supported demos:"

  # List supported demos
  for demo_path in `find rknn3_stress_test tested_models -name cpp`
  do
      if [ -d "$demo_path" ]
      then
          dname=`dirname "$demo_path"`
          name=`basename $dname`
          echo "$name"
      fi
  done

  exit -1
fi

# Debug / Release / RelWithDebInfo

# Build with Address Sanitizer for memory check, BUILD_TYPE need set to Debug
if [[ -z ${ENABLE_ASAN} ]];then
    ENABLE_ASAN=OFF
fi

if [[ -z ${DISABLE_RGA} ]];then
    DISABLE_RGA=OFF
fi

if [[ -z ${DISABLE_LIBJPEG} ]];then
    DISABLE_LIBJPEG=OFF
fi

# 处理 -d all 参数，编译所有demo
if [ "${BUILD_DEMO_NAME}" = "all" ]; then
    # 收集所有demo路径
    ALL_DEMO_PATHS=()
    for demo_path in `find rknn3_stress_test tested_models -name cpp`
    do
        if [ -d "$demo_path" ]
        then
            ALL_DEMO_PATHS+=($demo_path)
        fi
    done
    
    if [ ${#ALL_DEMO_PATHS[@]} -eq 0 ]; then
        echo "No demos found!"
        exit 1
    fi
else
    # 处理单个demo
    for demo_path in `find rknn3_stress_test tested_models -name "${BUILD_DEMO_NAME}"`
    do
        if [ -d "$demo_path/cpp" ]
        then
            BUILD_DEMO_PATH="$demo_path/cpp"
            break;
        fi
    done

    if [[ -z "${BUILD_DEMO_PATH}" ]]
    then
        echo "Cannot find demo: ${BUILD_DEMO_NAME}, only support:"

        for demo_path in `find rknn3_stress_test tested_models -name cpp`
        do
            if [ -d "$demo_path" ]
            then
                dname=`dirname "$demo_path"`
                name=`basename $dname`
                echo "$name"
            fi
        done

        exit
    fi
    
    # 将单个demo路径添加到ALL_DEMO_PATHS数组中
    ALL_DEMO_PATHS=($BUILD_DEMO_PATH)
fi

case ${TARGET_SOC} in
    rk3588)
        ;;
    rk3576)
        ;;
    *)
        echo "Invalid target: ${TARGET_SOC}"
        echo "Valid target: rk3588,rk3576"
        exit -1
        ;;
esac

ROOT_PWD=$( cd "$( dirname $0 )" && cd -P "$( dirname "$SOURCE" )" && pwd )
ANDROID_NDK_PATH=$(cd "$(dirname $0)/../../prebuilts/android-ndk/" && pwd)

# 遍历所有demo路径并构建
for demo_path in "${ALL_DEMO_PATHS[@]}"
do
    # 获取demo名称
    demo_name=$(basename $(dirname $demo_path))
    
    # 设置当前demo的构建参数
    TARGET_SDK="rknn_${demo_name}_demo"
    TARGET_PLATFORM=${TARGET_SOC}_android
    if [[ -n ${TARGET_ARCH} ]];then
        TARGET_PLATFORM=${TARGET_PLATFORM}_${TARGET_ARCH}
    fi
    
    INSTALL_DIR=${ROOT_PWD}/install/${TARGET_PLATFORM}/${TARGET_SDK}
    BUILD_DIR=${ROOT_PWD}/build/build_${TARGET_SDK}_${TARGET_PLATFORM}_${BUILD_TYPE}
    
    echo "==================================="
    echo "Building demo: ${demo_name}"
    echo "BUILD_DEMO_NAME=${demo_name}"
    echo "BUILD_DEMO_PATH=${demo_path}"
    echo "TARGET_SOC=${TARGET_SOC}"
    echo "TARGET_ARCH=${TARGET_ARCH}"
    echo "BUILD_TYPE=${BUILD_TYPE}"
    echo "ENABLE_ASAN=${ENABLE_ASAN}"
    echo "DISABLE_RGA=${DISABLE_RGA}"
    echo "DISABLE_LIBJPEG=${DISABLE_LIBJPEG}"
    echo "INSTALL_DIR=${INSTALL_DIR}"
    echo "BUILD_DIR=${BUILD_DIR}"
    echo "ANDROID_NDK_PATH=${ANDROID_NDK_PATH}"
    echo "==================================="
    
    # 创建构建目录
    if [[ ! -d "${BUILD_DIR}" ]]; then
      mkdir -p ${BUILD_DIR}
    fi
    
    # 清理安装目录
    if [[ -d "${INSTALL_DIR}" ]]; then
      rm -rf ${INSTALL_DIR}
    fi
    
    # 进入构建目录并执行构建
    cd ${BUILD_DIR}
    cmake ../../${demo_path} \
            -DTARGET_SOC=${TARGET_SOC} \
            -DCMAKE_SYSTEM_NAME=Android \
            -DCMAKE_SYSTEM_VERSION=23 \
            -DCMAKE_ANDROID_ARCH_ABI=${TARGET_ARCH} \
            -DCMAKE_ANDROID_STL_TYPE=c++_static \
            -DCMAKE_ANDROID_NDK=${ANDROID_NDK_PATH} \
            -DCMAKE_BUILD_TYPE=${BUILD_TYPE} \
            -DENABLE_ASAN=${ENABLE_ASAN} \
            -DDISABLE_RGA=${DISABLE_RGA} \
            -DDISABLE_LIBJPEG=${DISABLE_LIBJPEG} \
            -DCMAKE_INSTALL_PREFIX=${INSTALL_DIR}
    
    # 执行构建
    make -j4
    if [ $? -ne 0 ]; then
        echo "Build failed for demo: ${demo_name}"
        exit 1
    fi
    
    make install
    if [ $? -ne 0 ]; then
        echo "Install failed for demo: ${demo_name}"
        exit 1
    fi
    
    echo "Build completed for demo: ${demo_name}"
done

# Check if there is a rknn model in the install directory
suffix=".rknn"
shopt -s nullglob
if [ -d "$INSTALL_DIR" ]; then
    files=("$INSTALL_DIR/model/"/*"$suffix")
    shopt -u nullglob

    if [ ${#files[@]} -le 0 ]; then
        echo -e "\e[91mThe RKNN model can not be found in \"$INSTALL_DIR/model\", please check!\e[0m"
    fi
else
    echo -e "\e[91mInstall directory \"$INSTALL_DIR\" does not exist, please check!\e[0m"
fi
