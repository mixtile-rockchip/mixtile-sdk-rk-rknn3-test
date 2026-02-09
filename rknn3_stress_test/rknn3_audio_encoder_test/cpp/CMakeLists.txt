cmake_minimum_required(VERSION 3.10)

project(rknn3_audio_encoder_test)

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
add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/../../utils/ utils.out)

set(CMAKE_INSTALL_RPATH "$ORIGIN/lib")

set(PREBUILDS_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/../../prebuilds)
set(RKNNSMI_INCLUDE_DIR ${PREBUILDS_ROOT}/include)
set(RKNNSMI_LIB_DIR ${PREBUILDS_ROOT}/lib)

message(STATUS "LIBRKNNAPI = ${LIBRKNNAPI}")
message(STATUS "LIBRKNNAPI_INCLUDES = ${LIBRKNNAPI_INCLUDES}")
message(STATUS "TARGET_LIB_ARCH = ${TARGET_LIB_ARCH}")

add_executable(${PROJECT_NAME}
    main.cc
    rknn3_audio_encoder_test.cc
    audio/rknn3_audio_encoder.cc
)

target_link_directories(${PROJECT_NAME} PRIVATE
    ${RKNNSMI_LIB_DIR}
)

target_link_libraries(${PROJECT_NAME}
    audioutils
    fileutils
    cmdlineparser
    ${LIBRKNNAPI}
    dl
)

if (CMAKE_SYSTEM_NAME STREQUAL "Android")
    target_link_libraries(${PROJECT_NAME}
        log
    )
endif()

if (CMAKE_SYSTEM_NAME STREQUAL "Linux")
    target_link_libraries(${PROJECT_NAME}
        pthread
)
endif()

target_include_directories(${PROJECT_NAME} PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/audio
    ${CMAKE_CURRENT_SOURCE_DIR}/llm
    ${LIBRKNNAPI_INCLUDES}
    ${LIBTOKENIZER_INCLUDES}
    ${RKNNSMI_INCLUDE_DIR}
)

install(TARGETS ${PROJECT_NAME} DESTINATION .)

