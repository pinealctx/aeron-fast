#!/bin/bash
# Aeron C Performance Test 交叉编译脚本
# 使用本地aeron-lib库进行编译

set -e

# 配置
PROJECT_SOURCE_DIR="."
BUILD_BASE_DIR="./build"
DOCKER_IMAGE="xsyphon/cross-builder:1.0"

# 清理旧的构建
echo "🧹 清理旧构建文件..."
rm -rf "${BUILD_BASE_DIR}"
mkdir -p "${BUILD_BASE_DIR}"

# 检查Docker镜像是否存在
if ! docker image inspect "${DOCKER_IMAGE}" > /dev/null 2>&1; then
    echo "❌ Docker镜像 ${DOCKER_IMAGE} 不存在"
    echo "请先构建交叉编译环境镜像"
    exit 1
fi

# 检查源码目录
if [ ! -d "${PROJECT_SOURCE_DIR}" ]; then
    echo "❌ 项目源码目录不存在: ${PROJECT_SOURCE_DIR}"
    exit 1
fi

# 检查本地aeron-lib目录
if [ ! -d "${PROJECT_SOURCE_DIR}/aeron-lib" ]; then
    echo "❌ 本地Aeron库目录不存在: ${PROJECT_SOURCE_DIR}/aeron-lib"
    echo "请确保aeron-lib目录存在并包含lib和include子目录"
    exit 1
fi

echo "🚀 开始交叉编译Aeron C Performance Test (使用本地库)..."
echo "项目源码目录: ${PROJECT_SOURCE_DIR}"
echo "本地Aeron库: ${PROJECT_SOURCE_DIR}/aeron-lib"
echo "构建目录: ${BUILD_BASE_DIR}"

ARCH="amd64"
echo ""
echo "🔨 构建架构: ${ARCH}"
echo "==========================================="

BUILD_DIR="${BUILD_BASE_DIR}/${ARCH}"
mkdir -p "${BUILD_DIR}"

COMPILER_PREFIX="x86_64-linux-gnu"

# 运行Docker容器进行编译
echo "📦 启动Docker容器编译 ${ARCH}..."

docker run --rm -it \
    -v "${PROJECT_SOURCE_DIR}:/source" \
    -v "${BUILD_DIR}:/build" \
    -w /build \
    "${DOCKER_IMAGE}" \
    bash -c "
    set -e
    echo '🔧 配置CMake for ${ARCH}...'
    
    # 设置环境变量
    export CC=${COMPILER_PREFIX}-gcc
    export CXX=${COMPILER_PREFIX}-g++
    export AR=${COMPILER_PREFIX}-ar
    export STRIP=${COMPILER_PREFIX}-strip
    export RANLIB=${COMPILER_PREFIX}-ranlib
    
    echo '🔍 检查编译器版本...'
    echo \"编译器: \${CC}\"
    \${CC} --version || echo \"\${CC} 命令不可用\"
    \${CXX} --version || echo \"\${CXX} 命令不可用\"
    
    # 获取CPU核心数用于并行编译
    NPROC=\$(nproc || echo '4')
    echo \"使用CPU核心数: \$NPROC\"
    
    # 设置优化参数
    ARCH_FLAGS=\"-march=x86-64 -mtune=generic\"
    echo \"x86_64交叉编译: 使用通用优化\"
    
    echo '� 检查本地Aeron库...'
    if [ ! -d '/source/aeron-lib/lib' ]; then
        echo '❌ 本地Aeron库目录不存在: /source/aeron-lib/lib'
        exit 1
    fi
    
    if [ ! -d '/source/aeron-lib/include' ]; then
        echo '❌ 本地Aeron头文件目录不存在: /source/aeron-lib/include'
        exit 1
    fi
    
    echo '✅ 找到本地Aeron库:'
    ls -la /source/aeron-lib/lib/ || echo '无法列出lib目录'
    
    echo '🔧 配置C Performance Test...'
    cd /build
    
    # 配置我们的项目CMake，使用本地aeron-lib
    cmake /source \\
        -DCMAKE_BUILD_TYPE=Release \\
        -DCMAKE_INSTALL_PREFIX=/build/install \\
        -DCMAKE_C_FLAGS=\"-O3 -DNDEBUG -ffunction-sections -fdata-sections \$ARCH_FLAGS\" \\
        -DCMAKE_EXE_LINKER_FLAGS=\"-Wl,--gc-sections -static-libgcc -static-libstdc++\" \\
        -DCMAKE_VERBOSE_MAKEFILE=ON
    
    echo '🔨 开始编译C Performance Test...'
    make -j\$NPROC
    
    echo '📦 安装到指定目录...'
    make install
    
    echo '📏 检查生成的可执行文件...'
    find /build -name 'binary_*' -type f 2>/dev/null || echo '未找到可执行文件'
    
    echo '🔍 检查文件信息...'
    if [ -f /build/bin/binary_publisher ]; then
        echo '找到 binary_publisher:'
        file /build/bin/binary_publisher
        ls -lh /build/bin/binary_publisher
    fi
    
    if [ -f /build/bin/binary_subscriber ]; then
        echo '找到 binary_subscriber:'
        file /build/bin/binary_subscriber
        ls -lh /build/bin/binary_subscriber
    fi
    
    if [ -f /build/install/bin/binary_publisher ]; then
        echo '找到 install/bin/binary_publisher:'
        file /build/install/bin/binary_publisher
        ls -lh /build/install/bin/binary_publisher
    fi
    
    if [ -f /build/install/bin/binary_subscriber ]; then
        echo '找到 install/bin/binary_subscriber:'
        file /build/install/bin/binary_subscriber
        ls -lh /build/install/bin/binary_subscriber
    fi
    "

if [ $? -eq 0 ]; then
    echo "✅ ${ARCH} 架构编译成功"
    
    # 复制可执行文件到更易访问的位置
    DIST_DIR="${BUILD_BASE_DIR}/dist"
    mkdir -p "${DIST_DIR}"
    
    # 从构建目录复制
    if [ -f "${BUILD_DIR}/bin/binary_publisher" ]; then
        cp "${BUILD_DIR}/bin/binary_publisher" "${DIST_DIR}/binary_publisher-${ARCH}"
        echo "📁 Publisher: ${DIST_DIR}/binary_publisher-${ARCH}"
    fi
    
    if [ -f "${BUILD_DIR}/bin/binary_subscriber" ]; then
        cp "${BUILD_DIR}/bin/binary_subscriber" "${DIST_DIR}/binary_subscriber-${ARCH}"
        echo "📁 Subscriber: ${DIST_DIR}/binary_subscriber-${ARCH}"
    fi
    
    # 从install目录复制
    if [ -f "${BUILD_DIR}/install/bin/binary_publisher" ]; then
        cp "${BUILD_DIR}/install/bin/binary_publisher" "${DIST_DIR}/binary_publisher-install-${ARCH}"
        echo "📁 Publisher (install): ${DIST_DIR}/binary_publisher-install-${ARCH}"
    fi
    
    if [ -f "${BUILD_DIR}/install/bin/binary_subscriber" ]; then
        cp "${BUILD_DIR}/install/bin/binary_subscriber" "${DIST_DIR}/binary_subscriber-install-${ARCH}"
        echo "📁 Subscriber (install): ${DIST_DIR}/binary_subscriber-install-${ARCH}"
    fi
    
    # 查找所有找到的可执行文件
    echo '复制所有找到的可执行文件到dist目录...'
    find "${BUILD_DIR}" -name "binary_publisher" -type f 2>/dev/null -exec cp {} "${DIST_DIR}/binary_publisher-found-${ARCH}" \; 2>/dev/null || true
    find "${BUILD_DIR}" -name "binary_subscriber" -type f 2>/dev/null -exec cp {} "${DIST_DIR}/binary_subscriber-found-${ARCH}" \; 2>/dev/null || true
    
else
    echo "❌ ${ARCH} 架构编译失败"
    exit 1
fi

echo ""
echo "🎉 构建完成！"
echo "================================================="
echo ""

# 显示最终结果
if [ -d "${DIST_DIR}" ]; then
    echo "📦 生成的可执行文件:"
    find "${DIST_DIR}" -type f 2>/dev/null | while read -r file; do
        if [ -x "$file" ]; then
            echo "  $(basename "$file"): $(file "$file" 2>/dev/null | cut -d: -f2-)"
            echo "    路径: $file"
            echo "    大小: $(ls -lh "$file" | awk '{print $5}')"
            echo ""
        fi
    done
else
    echo "⚠️ 未找到生成的可执行文件"
fi

echo "💡 使用建议:"
echo "  1. 部署到目标Linux机器后赋予执行权限: chmod +x binary_*-amd64"
echo "  2. 启动Subscriber: ./binary_subscriber-amd64"
echo "  3. 启动Publisher: ./binary_publisher-amd64"
echo ""
echo "📚 参数说明:"
echo "  --help           显示帮助信息"
echo "  -t IPC           使用IPC模式 (超低延迟)"
echo "  -c 10000000      指定消息数量"