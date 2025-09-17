#!/bin/bash
# Aeron C语言MediaDriver交叉编译脚本
# 使用Docker交叉编译环境构建AMD64和ARM64版本

set -e

# 配置
AERON_SOURCE_DIR="../aeron"
BUILD_BASE_DIR="./build"
DOCKER_IMAGE="xsyphon/cross-builder:2.0"

# 架构列表
ARCHITECTURES=("amd64" "arm64")

# 日志配置
LOG_DIR="${BUILD_BASE_DIR}/logs"
MAIN_LOG="${LOG_DIR}/build-$(date +%Y%m%d-%H%M%S).log"

# 清理旧的构建
echo "🧹 清理旧构建文件..."
rm -rf "${BUILD_BASE_DIR}"
mkdir -p "${BUILD_BASE_DIR}"
mkdir -p "${LOG_DIR}"

echo "📝 构建日志将保存到: ${MAIN_LOG}"

# 检查Docker镜像是否存在
if ! docker image inspect "${DOCKER_IMAGE}" > /dev/null 2>&1; then
    echo "❌ Docker镜像 ${DOCKER_IMAGE} 不存在" | tee -a "${MAIN_LOG}"
    echo "请先构建交叉编译环境镜像" | tee -a "${MAIN_LOG}"
    exit 1
fi

# 检查源码目录
if [ ! -d "${AERON_SOURCE_DIR}" ]; then
    echo "❌ Aeron源码目录不存在: ${AERON_SOURCE_DIR}" | tee -a "${MAIN_LOG}"
    exit 1
fi

echo "🚀 开始交叉编译Aeron C MediaDriver..." | tee -a "${MAIN_LOG}"
echo "源码目录: ${AERON_SOURCE_DIR}" | tee -a "${MAIN_LOG}"
echo "构建目录: ${BUILD_BASE_DIR}" | tee -a "${MAIN_LOG}"

# 为每个架构构建
for ARCH in "${ARCHITECTURES[@]}"; do
    echo ""
    echo "🔨 构建架构: ${ARCH}"
    echo "==========================================="
    
    BUILD_DIR="${BUILD_BASE_DIR}/${ARCH}"
    mkdir -p "${BUILD_DIR}"
    
    # 设置架构特定日志文件
    ARCH_LOG="${LOG_DIR}/build_${ARCH}_$(date +%Y%m%d_%H%M%S).log"
    
    # 根据架构设置编译器工具链
    case "${ARCH}" in
        "amd64")
            CMAKE_TOOLCHAIN=""
            COMPILER_PREFIX="x86_64-linux-gnu"
            ;;
        "arm64")
            CMAKE_TOOLCHAIN="-DCMAKE_TOOLCHAIN_FILE=/opt/toolchain/aarch64-linux-gnu.cmake"
            COMPILER_PREFIX="aarch64-linux-gnu"
            ;;
        *)
            echo "❌ 不支持的架构: ${ARCH}"
            continue
            ;;
    esac
    
    # 运行Docker容器进行编译
    echo "📦 启动Docker容器编译 ${ARCH}..." | tee -a "${MAIN_LOG}"
    echo "📝 详细日志: ${ARCH_LOG}" | tee -a "${MAIN_LOG}"
    
    docker run --rm -it \
        -v "${AERON_SOURCE_DIR}:/source" \
        -v "${BUILD_DIR}:/build" \
        -v "${LOG_DIR}:/logs" \
        -w /build \
        "${DOCKER_IMAGE}" \
        bash -c "
        set -e
        
        # 创建日志文件
        touch '/logs/build_${ARCH}_$(date +%Y%m%d_%H%M%S).log'
        CONTAINER_LOG='/logs/build_${ARCH}_$(date +%Y%m%d_%H%M%S).log'
        
        echo '🔧 配置CMake for ${ARCH}...' | tee -a \"\$CONTAINER_LOG\"
        
        # 设置环境变量
        export CC=${COMPILER_PREFIX}-gcc
        export CXX=${COMPILER_PREFIX}-g++
        export AR=${COMPILER_PREFIX}-ar
        export STRIP=${COMPILER_PREFIX}-strip
        export RANLIB=${COMPILER_PREFIX}-ranlib
        export PKG_CONFIG_PATH=/usr/lib/${COMPILER_PREFIX}/pkgconfig
        
        echo \"[$(date '+%Y-%m-%d %H:%M:%S')] 📊 编译环境信息:\" | tee -a \"\$CONTAINER_LOG\"
        echo \"  编译器: \$CC\" | tee -a \"\$CONTAINER_LOG\"
        echo \"  C++编译器: \$CXX\" | tee -a \"\$CONTAINER_LOG\"
        echo \"  CPU核心数: \$(nproc)\" | tee -a \"\$CONTAINER_LOG\"
        echo \"  内存: \$(free -h | grep Mem | awk '{print \$2}')\" | tee -a \"\$CONTAINER_LOG\"

        # 获取CPU核心数用于并行LTO
        NPROC=\$(nproc)

        # 配置CMake
        cmake /source \\
            ${CMAKE_TOOLCHAIN} \\
            -DCMAKE_BUILD_TYPE=Release \\
            -DBUILD_AERON_DRIVER=ON \\
            -DBUILD_AERON_ARCHIVE_API=OFF \\
            -DAERON_TESTS=OFF \\
            -DCMAKE_INSTALL_PREFIX=/build/install \\
            -DCMAKE_C_FLAGS='-O3 -DNDEBUG -flto=\${NPROC} -ffunction-sections -fdata-sections' \\
            -DCMAKE_CXX_FLAGS='-O3 -DNDEBUG -flto=\${NPROC} -ffunction-sections -fdata-sections' \\
            -DCMAKE_EXE_LINKER_FLAGS='-Wl,--gc-sections -static-libgcc -static-libstdc++' \\
            -DCMAKE_VERBOSE_MAKEFILE=ON 2>&1 | tee -a \"\$CONTAINER_LOG\"
        
        echo '🔨 开始编译...' | tee -a \"\$CONTAINER_LOG\"
        make -j\$(nproc) aeronmd aeronmd_s 2>&1 | tee -a \"\$CONTAINER_LOG\"
        
        echo '📦 安装到指定目录...' | tee -a \"\$CONTAINER_LOG\"
        make install 2>&1 | tee -a \"\$CONTAINER_LOG\"
        
        echo '📏 检查生成的可执行文件...' | tee -a \"\$CONTAINER_LOG\"
        ls -la aeronmd* 2>&1 | tee -a \"\$CONTAINER_LOG\" || echo '在当前目录未找到aeronmd' | tee -a \"\$CONTAINER_LOG\"
        find /build -name 'aeronmd*' -type f -perm +111 2>&1 | tee -a \"\$CONTAINER_LOG\"
        
        echo '🔍 检查文件信息...' | tee -a \"\$CONTAINER_LOG\"
        if [ -f aeronmd ]; then
            file aeronmd 2>&1 | tee -a \"\$CONTAINER_LOG\"
            ldd aeronmd 2>&1 | tee -a \"\$CONTAINER_LOG\" || echo '静态链接或ldd不可用' | tee -a \"\$CONTAINER_LOG\"
            ls -lh aeronmd 2>&1 | tee -a \"\$CONTAINER_LOG\"
        fi
        
        if [ -f aeronmd_s ]; then
            file aeronmd_s 2>&1 | tee -a \"\$CONTAINER_LOG\"
            ldd aeronmd_s 2>&1 | tee -a \"\$CONTAINER_LOG\" || echo '静态链接' | tee -a \"\$CONTAINER_LOG\"
            ls -lh aeronmd_s 2>&1 | tee -a \"\$CONTAINER_LOG\"
        fi
        " 2>&1 | tee -a "${ARCH_LOG}"
    
    if [ $? -eq 0 ]; then
        echo "✅ ${ARCH} 架构编译成功" | tee -a "${MAIN_LOG}" "${ARCH_LOG}"
        
        # 复制可执行文件到更易访问的位置
        DIST_DIR="${BUILD_BASE_DIR}/dist/${ARCH}"
        mkdir -p "${DIST_DIR}"
        
        if [ -f "${BUILD_DIR}/aeronmd" ]; then
            cp "${BUILD_DIR}/aeronmd" "${DIST_DIR}/aeronmd-${ARCH}"
            echo "📁 动态链接版本: ${DIST_DIR}/aeronmd-${ARCH}" | tee -a "${MAIN_LOG}" "${ARCH_LOG}"
        fi
        
        if [ -f "${BUILD_DIR}/aeronmd_s" ]; then
            cp "${BUILD_DIR}/aeronmd_s" "${DIST_DIR}/aeronmd_s-${ARCH}"
            echo "📁 静态链接版本: ${DIST_DIR}/aeronmd_s-${ARCH}" | tee -a "${MAIN_LOG}" "${ARCH_LOG}"
        fi
        
        # 查找安装目录中的文件
        find "${BUILD_DIR}" -name "aeronmd*" -type f -perm +111 -exec cp {} "${DIST_DIR}/" \;
    else
        echo "❌ ${ARCH} 架构编译失败" | tee -a "${MAIN_LOG}" "${ARCH_LOG}"
    fi
done

echo ""
echo "🎉 构建完成！" | tee -a "${MAIN_LOG}"
echo "=================================================" | tee -a "${MAIN_LOG}"
echo ""

# 显示最终结果
DIST_BASE="${BUILD_BASE_DIR}/dist"
if [ -d "${DIST_BASE}" ]; then
    echo "📦 生成的可执行文件:" | tee -a "${MAIN_LOG}"
    find "${DIST_BASE}" -type f -perm +111 | while read -r file; do
        echo "  $(basename "$file"): $(file "$file" | cut -d: -f2-)" | tee -a "${MAIN_LOG}"
        echo "    路径: $file" | tee -a "${MAIN_LOG}"
        echo "    大小: $(ls -lh "$file" | awk '{print $5}')" | tee -a "${MAIN_LOG}"
        echo "" | tee -a "${MAIN_LOG}"
    done
else
    echo "⚠️ 未找到生成的可执行文件" | tee -a "${MAIN_LOG}"
fi

echo "💡 使用建议:" | tee -a "${MAIN_LOG}"
echo "  1. 选择静态链接版本 (aeronmd_s-*) 以减少依赖" | tee -a "${MAIN_LOG}"
echo "  2. 部署到目标Linux机器后赋予执行权限: chmod +x aeronmd_s-*" | tee -a "${MAIN_LOG}"
echo ""
echo "📝 构建日志已保存到:" | tee -a "${MAIN_LOG}"
echo "  主日志: ${MAIN_LOG}"
echo "  详细日志目录: ${LOG_DIR}"
echo "  3. 运行: ./aeronmd_s-amd64 或 ./aeronmd_s-arm64"
echo ""
echo "📚 参数说明:"
echo "  -v               显示版本信息"
echo "  -Dname=value     设置系统属性"
echo "  config_file      指定配置文件"