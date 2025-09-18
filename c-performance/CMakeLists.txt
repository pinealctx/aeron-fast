cmake_minimum_required(VERSION 3.16)
project(aeron-c-performance VERSION 1.0.0 LANGUAGES C)

# 设置C标准
set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

# 编译选项
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wall -Wextra -O3 -fPIC")
set(CMAKE_C_FLAGS_DEBUG "${CMAKE_C_FLAGS_DEBUG} -g -O0 -DDEBUG")
set(CMAKE_C_FLAGS_RELEASE "${CMAKE_C_FLAGS_RELEASE} -O3 -DNDEBUG")

# 默认构建类型
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

# 查找线程库
find_package(Threads REQUIRED)

# 使用本地aeron-lib目录
set(AERON_LIB_DIR "${CMAKE_CURRENT_SOURCE_DIR}/aeron-lib")
set(AERON_INCLUDE_DIR "${AERON_LIB_DIR}/include")
set(AERON_STATIC_LIB "${AERON_LIB_DIR}/lib/libaeron_static.a")
set(AERON_CLIENT_LIB "${AERON_LIB_DIR}/lib/libaeron_client.a")

# 检查本地Aeron库是否存在
if(NOT EXISTS ${AERON_INCLUDE_DIR})
    message(FATAL_ERROR "Aeron include directory not found: ${AERON_INCLUDE_DIR}")
endif()

if(NOT EXISTS ${AERON_STATIC_LIB})
    message(FATAL_ERROR "Aeron static library not found: ${AERON_STATIC_LIB}")
endif()

if(NOT EXISTS ${AERON_CLIENT_LIB})
    message(FATAL_ERROR "Aeron client library not found: ${AERON_CLIENT_LIB}")
endif()

message(STATUS "Using local Aeron libraries:")
message(STATUS "  Include: ${AERON_INCLUDE_DIR}")
message(STATUS "  Static lib: ${AERON_STATIC_LIB}")
message(STATUS "  Client lib: ${AERON_CLIENT_LIB}")

# 设置为静态链接模式
set(CMAKE_FIND_LIBRARY_SUFFIXES ".a")
set(BUILD_SHARED_LIBS OFF)

# 包含目录
include_directories(${CMAKE_CURRENT_SOURCE_DIR}/include)
include_directories(${AERON_INCLUDE_DIR})
include_directories(${AERON_INCLUDE_DIR}/aeron)

# 定义源文件
set(COMMON_SOURCES
    src/time_utils.c
    src/binary_message.c
    src/performance_stats.c
    src/config_parser.c
)

# 创建静态库（可选，用于测试）
add_library(aeron-c-performance-common STATIC ${COMMON_SOURCES})

# 创建Publisher可执行文件
add_executable(binary_publisher
    src/binary_publisher.c
    ${COMMON_SOURCES}
)

target_link_libraries(binary_publisher
    ${AERON_STATIC_LIB}
    ${AERON_CLIENT_LIB}
    Threads::Threads
    m  # 数学库
    -static
)

# 创建Subscriber可执行文件
add_executable(binary_subscriber
    src/binary_subscriber.c
    ${COMMON_SOURCES}
)

target_link_libraries(binary_subscriber
    ${AERON_STATIC_LIB}
    ${AERON_CLIENT_LIB}
    Threads::Threads
    m  # 数学库
    -static
)

# 设置编译属性
set_target_properties(binary_publisher PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin
    LINK_SEARCH_START_STATIC 1
    LINK_SEARCH_END_STATIC 1
)

set_target_properties(binary_subscriber PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin
    LINK_SEARCH_START_STATIC 1
    LINK_SEARCH_END_STATIC 1
)

# 使用兼容性更好的优化选项，避免AVX2等高级指令集问题
# 替代 -march=native 以确保跨平台兼容性
if(CMAKE_BUILD_TYPE STREQUAL "Release")
    # 使用 x86-64 基本指令集，兼容性最佳
    target_compile_options(binary_publisher PRIVATE -march=x86-64 -mtune=generic)
    target_compile_options(binary_subscriber PRIVATE -march=x86-64 -mtune=generic)
    target_compile_options(aeron-c-performance-common PRIVATE -march=x86-64 -mtune=generic)
endif()

# 安装规则（可选）
install(TARGETS binary_publisher binary_subscriber
    RUNTIME DESTINATION bin
)

# 打印构建信息
message(STATUS "Build type: ${CMAKE_BUILD_TYPE}")
message(STATUS "C compiler: ${CMAKE_C_COMPILER}")
message(STATUS "C flags: ${CMAKE_C_FLAGS}")

if(CMAKE_BUILD_TYPE STREQUAL "Release")
    message(STATUS "Release flags: ${CMAKE_C_FLAGS_RELEASE}")
elseif(CMAKE_BUILD_TYPE STREQUAL "Debug")
    message(STATUS "Debug flags: ${CMAKE_C_FLAGS_DEBUG}")
endif()

# 添加自定义目标用于清理
add_custom_target(clean-all
    COMMAND ${CMAKE_COMMAND} -E remove_directory ${CMAKE_BINARY_DIR}/bin
    COMMAND ${CMAKE_COMMAND} -E remove_directory ${CMAKE_BINARY_DIR}/CMakeFiles
    COMMAND ${CMAKE_COMMAND} -E remove ${CMAKE_BINARY_DIR}/CMakeCache.txt
    COMMAND ${CMAKE_COMMAND} -E remove ${CMAKE_BINARY_DIR}/cmake_install.cmake
    COMMAND ${CMAKE_COMMAND} -E remove ${CMAKE_BINARY_DIR}/Makefile
    COMMENT "清理所有构建文件"
)