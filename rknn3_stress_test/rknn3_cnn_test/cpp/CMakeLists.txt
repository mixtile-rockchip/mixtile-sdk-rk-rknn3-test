cmake_minimum_required(VERSION 3.10)

project(rknn3_cnn_demo)

set(CMAKE_CXX_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

if (ENABLE_ASAN)
	message(STATUS "BUILD WITH ADDRESS SANITIZER")
	set (CMAKE_C_FLAGS_DEBUG "${CMAKE_C_FLAGS_DEBUG} -fno-omit-frame-pointer -fsanitize=address")
	set (CMAKE_CXX_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG} -fno-omit-frame-pointer -fsanitize=address")
	set (CMAKE_LINKER_FLAGS_DEBUG "${CMAKE_LINKER_FLAGS_DEBUG} -fno-omit-frame-pointer -fsanitize=address")
endif ()

add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/../../../../../rknn/rknn3-model-zoo/3rdparty/ 3rdparty.out)
add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/../../../../../rknn/rknn3-model-zoo/utils/ utils.out)

# Add rknn-smi path
set(RKNNSMI_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/../../../../rknn-smi-host)
set(RKNNSMI_INCLUDE_DIR ${RKNNSMI_ROOT}/include)
set(RKNNSMI_LIB_DIR ${RKNNSMI_ROOT}/out/linux/aarch64/target/lib)

# Add chips-connect path
set(CHIPS_CONNECT_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/../../../../chips_connect)
set(CHIPS_CONNECT_INCLUDE_DIR ${CHIPS_CONNECT_ROOT}/build/linux/install/rc/include)
set(CHIPS_CONNECT_LIB_DIR ${CHIPS_CONNECT_ROOT}/build/linux/install/rc/lib)

set(CMAKE_INSTALL_RPATH "$ORIGIN/lib")

file(GLOB SRCS ${CMAKE_CURRENT_SOURCE_DIR}/*.cpp)

# include_directories(${CMAKE_SOURCE_DIR}/llm)
# include_directories(${CMAKE_SOURCE_DIR}/vision/)

# set(llm_file llm/rknn_fastvlm_llm.cc)
# set(vision_file vision/rknn_fastvlm_vision.cc)

message(STATUS "LIBRKNNAPI = ${LIBRKNNAPI}")
message(STATUS "LIBRKNNAPI_INCLUDES = ${LIBRKNNAPI_INCLUDES}")
message(STATUS "TARGET_LIB_ARCH = ${TARGET_LIB_ARCH}")

add_executable(${PROJECT_NAME}
    main.cpp
    rknn3_cnn_test.cpp
    cnpy.cpp
    ../../rknn3_test_monitor/MemoryMonitor.cpp
)

target_include_directories(${PROJECT_NAME} PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/../../rknn3_test_monitor
    ${LIBRKNNAPI_INCLUDES}
    ${LIBTOKENIZER_INCLUDES}
    ${RKNNSMI_INCLUDE_DIR}
    ${CHIPS_CONNECT_INCLUDE_DIR}
)

target_link_directories(${PROJECT_NAME} PRIVATE
    ${RKNNSMI_LIB_DIR}
    ${CHIPS_CONNECT_LIB_DIR}
)

target_link_libraries(${PROJECT_NAME}
	imageutils
    fileutils
    ${LIBRKNNAPI}
    ${LIBTOKENIZER}
    dl
    rknnsmi
    chips_connect_rc_static
)

if (CMAKE_SYSTEM_NAME STREQUAL "Android")
    target_link_libraries(${PROJECT_NAME}
    log
)
endif()

if (CMAKE_SYSTEM_NAME STREQUAL "Linux")
    target_link_libraries(${PROJECT_NAME}
        pthread
        atomic
    )
endif()

install(TARGETS ${PROJECT_NAME} DESTINATION .)
# install(FILES ${CMAKE_CURRENT_SOURCE_DIR}/../data/demo.jpg DESTINATION ./model)

