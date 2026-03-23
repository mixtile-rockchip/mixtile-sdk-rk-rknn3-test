cmake_minimum_required(VERSION 3.15)

project(rknn_model_zoo_utils)

add_definitions(-D_POSIX_C_SOURCE=199309L)
add_definitions(-D_GNU_SOURCE)
add_library(fileutils STATIC
  file_utils.c
)
target_include_directories(fileutils PUBLIC
  ${CMAKE_CURRENT_SOURCE_DIR}
)

add_library(timeutils STATIC
  time_utils.c
)
target_include_directories(timeutils PUBLIC
  ${CMAKE_CURRENT_SOURCE_DIR}
)

add_library(imagedrawing STATIC
  image_drawing.c
)
target_include_directories(imagedrawing PUBLIC
  ${CMAKE_CURRENT_SOURCE_DIR}
)

if(DISABLE_RGA)
  add_definitions(-DDISABLE_RGA)
endif ()

# only RGA on rk3588 support handle
if (TARGET_SOC STREQUAL "rk3588")
  add_definitions(-DLIBRGA_IM2D_HANDLE)
endif()

# Disable RGA on RK3572 due to hardware issues
if (TARGET_SOC STREQUAL "rk3572")
  add_definitions(-DDISABLE_RGA_ON_RK3572)
endif()

add_library(imageutils STATIC
  image_utils.c
)

target_include_directories(imageutils PUBLIC
  ${CMAKE_CURRENT_SOURCE_DIR}
  ${STB_INCLUDES}
  ${LIBRGA_INCLUDES}
)

target_link_libraries(imageutils
  ${LIBRGA}
)

if (DISABLE_LIBJPEG)
  add_definitions(-DDISABLE_LIBJPEG)
else()
  target_link_libraries(imageutils
    ${LIBJPEG}
  )
  target_include_directories(imageutils PUBLIC
    ${LIBJPEG_INCLUDES}
  )
endif()

add_library(audioutils STATIC
  audio_utils.cc
)
target_include_directories(audioutils PUBLIC
  ${CMAKE_CURRENT_SOURCE_DIR}
  ${MINIAUDIO_INCLUDES}
  ${LIBFFTW_INCLUDES}
)
target_link_libraries(audioutils
  ${LIBFFTW}
)

add_library(cmdlineparser STATIC
  cmdline_parser.c
)
target_include_directories(cmdlineparser PUBLIC
  ${CMAKE_CURRENT_SOURCE_DIR}
)
