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

# 强制静态链接
set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -static")
set(CMAKE_FIND_LIBRARY_SUFFIXES ".a")
set(BUILD_SHARED_LIBS OFF)

# 查找Aeron库
find_path(AERON_INCLUDE_DIR
    NAMES aeronc.h
    HINTS
        ${CMAKE_SOURCE_DIR}/build/amd64/aeron-install/include
        /build/aeron-install/include
        /usr/include
        /usr/local/include
        /opt/aeron/include
        ${CMAKE_PREFIX_PATH}/include
        ${CMAKE_SOURCE_DIR}/../../../build/install/include
        ${CMAKE_SOURCE_DIR}/../../build/install/include
        ${CMAKE_SOURCE_DIR}/../build/install/include
    PATH_SUFFIXES aeron
)

find_library(AERON_LIBRARY
    NAMES aeron_static aeron libaeron_static.a libaeron.a
    HINTS
        ${CMAKE_SOURCE_DIR}/build/amd64/aeron-install/lib
        /build/aeron-install/lib
        /usr/lib
        /usr/local/lib
        /opt/aeron/lib
        ${CMAKE_PREFIX_PATH}/lib
        ${CMAKE_SOURCE_DIR}/../../../build/install/lib
        ${CMAKE_SOURCE_DIR}/../../build/install/lib
        ${CMAKE_SOURCE_DIR}/../build/install/lib
    PATH_SUFFIXES aeron
)

# 检查是否找到Aeron
if(NOT AERON_INCLUDE_DIR OR NOT AERON_LIBRARY)
    # 尝试直接指定本地构建的静态库
    set(AERON_INCLUDE_DIR "${CMAKE_SOURCE_DIR}/build/amd64/aeron-install/include")
    set(AERON_LIBRARY "${CMAKE_SOURCE_DIR}/build/amd64/aeron-install/lib/libaeron_static.a")
    
    if(NOT EXISTS ${AERON_INCLUDE_DIR}/aeron/aeronc.h OR NOT EXISTS ${AERON_LIBRARY})
        message(FATAL_ERROR "Aeron library not found. Please ensure Aeron is built and installed.
        
        Expected paths:
        Header: ${AERON_INCLUDE_DIR}/aeron/aeronc.h
        Library: ${AERON_LIBRARY}
        
        To build Aeron:
        1. cd to aeron source directory
        2. ./gradlew clean build publishToMavenLocal
        
        Or set AERON_ROOT environment variable to point to Aeron installation.")
    endif()
endif()

message(STATUS "Found Aeron include: ${AERON_INCLUDE_DIR}")
message(STATUS "Found Aeron library: ${AERON_LIBRARY}")

# 设置包含目录
include_directories(
    ${CMAKE_SOURCE_DIR}/include
    ${AERON_INCLUDE_DIR}
)

# 定义源文件
set(COMMON_SOURCES
    src/time_utils.c
    src/binary_message.c
    src/performance_stats.c
    src/config_parser.c
)

# 创建静态库（可选，用于测试）
add_library(aeron-c-performance-common STATIC ${COMMON_SOURCES})
target_link_libraries(aeron-c-performance-common
    ${AERON_LIBRARY}
    Threads::Threads
    m  # 数学库
)

# 创建Publisher可执行文件
add_executable(binary_publisher
    src/binary_publisher.c
    ${COMMON_SOURCES}
)

target_link_libraries(binary_publisher
    ${AERON_LIBRARY}
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
    ${AERON_LIBRARY}
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

# 添加编译选项
if(CMAKE_BUILD_TYPE STREQUAL "Release")
    target_compile_options(binary_publisher PRIVATE -march=native -mtune=native)
    target_compile_options(binary_subscriber PRIVATE -march=native -mtune=native)
    target_compile_options(aeron-c-performance-common PRIVATE -march=native -mtune=native)
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