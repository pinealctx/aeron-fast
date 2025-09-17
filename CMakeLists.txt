cmake_minimum_required(VERSION 3.16)
project(aeron-latency-test C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

# 性能优化编译选项
set(CMAKE_C_FLAGS_RELEASE "-O3 -march=native -mtune=native -DNDEBUG")
set(CMAKE_C_FLAGS_DEBUG "-O0 -g -DDEBUG")

# 如果没有指定构建类型，默认为Release
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

# 查找线程库
find_package(Threads REQUIRED)

# 查找Aeron C库
find_path(AERON_INCLUDE_DIR
    NAMES aeron/aeron.h
    PATHS
        /usr/local/include
        /usr/include
        /opt/aeron/include
        ${CMAKE_SOURCE_DIR}/../aeron/aeron-client/src/main/c
    DOC "Aeron C header files"
)

find_library(AERON_LIBRARY
    NAMES aeron
    PATHS
        /usr/local/lib
        /usr/lib
        /opt/aeron/lib
        ${CMAKE_SOURCE_DIR}/../aeron/cppbuild/Release/lib
    DOC "Aeron C library"
)

# 如果找不到系统安装的Aeron，使用源码构建
if(NOT AERON_INCLUDE_DIR OR NOT AERON_LIBRARY)
    message(STATUS "System Aeron not found, using embedded source")
    
    # 下载并构建Aeron
    include(FetchContent)
    FetchContent_Declare(
        aeron
        GIT_REPOSITORY https://github.com/real-logic/aeron.git
        GIT_TAG        1.46.7
        GIT_SHALLOW    TRUE
    )
    
    set(BUILD_AERON_DRIVER OFF)
    set(BUILD_AERON_ARCHIVE_API OFF)
    FetchContent_MakeAvailable(aeron)
    
    set(AERON_INCLUDE_DIR ${aeron_SOURCE_DIR}/aeron-client/src/main/c)
    set(AERON_LIBRARY aeron)
else()
    message(STATUS "Found Aeron: ${AERON_LIBRARY}")
    message(STATUS "Aeron headers: ${AERON_INCLUDE_DIR}")
endif()

# 包含目录
include_directories(${AERON_INCLUDE_DIR})
include_directories(src)

# 高精度时间库
add_library(hires_time STATIC src/hires_time.c)
target_link_libraries(hires_time PRIVATE Threads::Threads)

# 延迟测试发布者
add_executable(latency_publisher src/latency_publisher.c)
target_link_libraries(latency_publisher 
    PRIVATE 
    ${AERON_LIBRARY} 
    hires_time 
    Threads::Threads
    m  # 数学库
)

# 延迟测试订阅者
add_executable(latency_subscriber src/latency_subscriber.c)
target_link_libraries(latency_subscriber 
    PRIVATE 
    ${AERON_LIBRARY} 
    hires_time 
    Threads::Threads
    m  # 数学库
)

# 时间戳稳定性测试
add_executable(timestamp_stability src/timestamp_stability.c)
target_link_libraries(timestamp_stability 
    PRIVATE 
    hires_time 
    Threads::Threads
    m  # 数学库
)

# HdrHistogram C库 (简化版实现)
add_library(hdr_histogram STATIC src/hdr_histogram.c)
target_link_libraries(hdr_histogram PRIVATE m)

target_link_libraries(latency_subscriber PRIVATE hdr_histogram)

# 编译器特定优化
if(CMAKE_C_COMPILER_ID STREQUAL "GNU" OR CMAKE_C_COMPILER_ID STREQUAL "Clang")
    target_compile_options(latency_publisher PRIVATE 
        -Wall -Wextra -Wpedantic
        -ffast-math
        -funroll-loops
        -finline-functions
    )
    target_compile_options(latency_subscriber PRIVATE 
        -Wall -Wextra -Wpedantic
        -ffast-math
        -funroll-loops
        -finline-functions
    )
    target_compile_options(timestamp_stability PRIVATE 
        -Wall -Wextra -Wpedantic
        -ffast-math
    )
endif()

# 安装目标
install(TARGETS latency_publisher latency_subscriber timestamp_stability
    RUNTIME DESTINATION bin
)

# 交叉编译支持
if(CMAKE_CROSSCOMPILING)
    message(STATUS "Cross-compiling for ${CMAKE_SYSTEM_PROCESSOR}")
endif()
