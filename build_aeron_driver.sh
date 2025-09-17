#!/bin/bash
# Aeron C语言MediaDriver交叉编译脚本
# 使用Docker交叉编译环境构建AMD64和ARM64版本

set -e

# 配置
AERON_SOURCE_DIR="../aeron"
BUILD_BASE_DIR="./build"
DOCKER_IMAGE="xsyphon/cross-builder:1.0"

# 架构列表
ARCHITECTURES=("amd64" "arm64")

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
if [ ! -d "${AERON_SOURCE_DIR}" ]; then
    echo "❌ Aeron源码目录不存在: ${AERON_SOURCE_DIR}"
    exit 1
fi

echo "🚀 开始交叉编译Aeron C MediaDriver..."
echo "源码目录: ${AERON_SOURCE_DIR}"
echo "构建目录: ${BUILD_BASE_DIR}"

# 为每个架构构建
for ARCH in "${ARCHITECTURES[@]}"; do
    echo ""
    echo "🔨 构建架构: ${ARCH}"
    echo "==========================================="
    
    BUILD_DIR="${BUILD_BASE_DIR}/${ARCH}"
    mkdir -p "${BUILD_DIR}"
    
    # 根据架构设置编译器工具链
    case "${ARCH}" in
        "amd64")
            CMAKE_TOOLCHAIN=""
            COMPILER_PREFIX="x86_64-linux-gnu"
            ;;
        "arm64")
            CMAKE_TOOLCHAIN=""
            COMPILER_PREFIX="aarch64-linux-gnu"
            ;;
        *)
            echo "❌ 不支持的架构: ${ARCH}"
            continue
            ;;
    esac
    
    # 运行Docker容器进行编译
    echo "📦 启动Docker容器编译 ${ARCH}..."
    
    docker run --rm -it \
        -v "${AERON_SOURCE_DIR}:/source" \
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
        export PKG_CONFIG_PATH=/usr/lib/${COMPILER_PREFIX}/pkgconfig
        
        echo '🔍 检查编译器版本...'
        echo \"编译器: \${CC}\"
        \${CC} --version || echo \"\${CC} 命令不可用\"
        \${CXX} --version || echo \"\${CXX} 命令不可用\"
        \${AR} --version || echo \"\${AR} 命令不可用\"
        \${STRIP} --version || echo \"\${STRIP} 命令不可用\"
        \${RANLIB} --version || echo \"\${RANLIB} 命令不可用\"
        
        echo '📦 检查pkg-config路径...'
        pkg-config --version || echo 'pkg-config不可用'
        pkg-config --cflags aeron-client || echo 'aeron-client未找到'
        pkg-config --libs aeron-client || echo 'aeron-client未找到'
        
        # CPU核心数和内存
        echo \"  CPU核心数: \$(nproc || echo '不可用')\"
        echo \"  可用内存: \$(free -h | grep Mem | awk '{print \$2}' 2>/dev/null || echo '内存信息不可用')\"

        # 获取CPU核心数用于并行LTO
        NPROC=\$(nproc || echo '4')
        echo \"使用CPU核心数: \$NPROC\"

        # 配置CMake
        cmake /source \\
            ${CMAKE_TOOLCHAIN} \\
            -DCMAKE_BUILD_TYPE=Release \\
            -DBUILD_AERON_DRIVER=ON \\
            -DBUILD_AERON_ARCHIVE_API=OFF \\
            -DAERON_TESTS=OFF \\
            -DCMAKE_INSTALL_PREFIX=/build/install \\
            -DCMAKE_C_FLAGS=\"-O3 -DNDEBUG -flto=\$NPROC -ffunction-sections -fdata-sections\" \\
            -DCMAKE_CXX_FLAGS=\"-O3 -DNDEBUG -flto=\$NPROC -ffunction-sections -fdata-sections\" \\
            -DCMAKE_EXE_LINKER_FLAGS=\"-Wl,--gc-sections -static-libgcc -static-libstdc++\" \\
            -DCMAKE_VERBOSE_MAKEFILE=ON
        
        echo '🔨 开始编译...'
        make -j\$(nproc) aeronmd aeronmd_s
        
        echo '📦 安装到指定目录...'
        make install
        
        echo '📏 检查生成的可执行文件...'
        ls -la aeronmd* || echo '在当前目录未找到aeronmd'
        echo '查找所有aeronmd文件...'
        find /build -name 'aeronmd*' -type f 2>/dev/null || echo '未找到可执行文件'
        echo '查找install目录中的可执行文件...'
        find /build/install -name 'aeronmd*' -type f 2>/dev/null || echo 'install目录中未找到'
        echo '查找bin目录中的可执行文件...'
        find /build -path '*/bin/*' -name 'aeronmd*' 2>/dev/null || echo 'bin目录中未找到'
        
        echo '🔍 检查文件信息...'
        # 检查install目录中的可执行文件
        if [ -f /build/install/bin/aeronmd ]; then
            echo '找到 aeronmd (动态链接):'
            file /build/install/bin/aeronmd
            ldd /build/install/bin/aeronmd || echo '静态链接或ldd不可用'
            ls -lh /build/install/bin/aeronmd
        fi
        
        if [ -f /build/install/bin/aeronmd_s ]; then
            echo '找到 aeronmd_s (静态链接):'
            file /build/install/bin/aeronmd_s
            ldd /build/install/bin/aeronmd_s || echo '静态链接'
            ls -lh /build/install/bin/aeronmd_s
        fi
        
        # 检查binaries目录中的可执行文件
        if [ -f /build/binaries/aeronmd ]; then
            echo '找到 binaries/aeronmd:'
            file /build/binaries/aeronmd
            ls -lh /build/binaries/aeronmd
        fi
        
        if [ -f /build/binaries/aeronmd_s ]; then
            echo '找到 binaries/aeronmd_s:'
            file /build/binaries/aeronmd_s
            ls -lh /build/binaries/aeronmd_s
        fi
        "
    
    if [ $? -eq 0 ]; then
        echo "✅ ${ARCH} 架构编译成功"
        
        # 复制可执行文件到更易访问的位置
        DIST_DIR="${BUILD_BASE_DIR}/dist/${ARCH}"
        mkdir -p "${DIST_DIR}"
        
        # 从install目录复制
        if [ -f "${BUILD_DIR}/install/bin/aeronmd" ]; then
            cp "${BUILD_DIR}/install/bin/aeronmd" "${DIST_DIR}/aeronmd-${ARCH}"
            echo "📁 动态链接版本: ${DIST_DIR}/aeronmd-${ARCH}"
        fi
        
        if [ -f "${BUILD_DIR}/install/bin/aeronmd_s" ]; then
            cp "${BUILD_DIR}/install/bin/aeronmd_s" "${DIST_DIR}/aeronmd_s-${ARCH}"
            echo "📁 静态链接版本: ${DIST_DIR}/aeronmd_s-${ARCH}"
        fi
        
        # 从binaries目录复制
        if [ -f "${BUILD_DIR}/binaries/aeronmd" ]; then
            cp "${BUILD_DIR}/binaries/aeronmd" "${DIST_DIR}/aeronmd-binaries-${ARCH}"
            echo "📁 binaries动态版本: ${DIST_DIR}/aeronmd-binaries-${ARCH}"
        fi
        
        if [ -f "${BUILD_DIR}/binaries/aeronmd_s" ]; then
            cp "${BUILD_DIR}/binaries/aeronmd_s" "${DIST_DIR}/aeronmd_s-binaries-${ARCH}"
            echo "📁 binaries静态版本: ${DIST_DIR}/aeronmd_s-binaries-${ARCH}"
        fi
        
        # 查找安装目录中的文件
        echo '复制所有找到的可执行文件到dist目录...'
        find "${BUILD_DIR}" -name "aeronmd" -type f 2>/dev/null -exec cp {} "${DIST_DIR}/aeronmd-found-${ARCH}" \; 2>/dev/null || true
        find "${BUILD_DIR}" -name "aeronmd_s" -type f 2>/dev/null -exec cp {} "${DIST_DIR}/aeronmd_s-found-${ARCH}" \; 2>/dev/null || true
    else
        echo "❌ ${ARCH} 架构编译失败"
    fi
done

echo ""
echo "🎉 构建完成！"
echo "================================================="
echo ""

# 显示最终结果
DIST_BASE="${BUILD_BASE_DIR}/dist"
if [ -d "${DIST_BASE}" ]; then
    echo "📦 生成的可执行文件:"
    find "${DIST_BASE}" -type f 2>/dev/null | while read -r file; do
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
echo "  1. 选择静态链接版本 (aeronmd_s-*) 以减少依赖"
echo "  2. 部署到目标Linux机器后赋予执行权限: chmod +x aeronmd_s-*"
echo "  3. 运行: ./aeronmd_s-amd64 或 ./aeronmd_s-arm64"
echo ""
echo "📚 参数说明:"
echo "  -v               显示版本信息"
echo "  -Dname=value     设置系统属性"
echo "  config_file      指定配置文件"