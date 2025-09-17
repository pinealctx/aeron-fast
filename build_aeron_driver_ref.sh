#!/bin/bash
# Aeron C语言MediaDriver交叉编译脚本
# 使用Docker交叉编译环境构建AMD64和ARM64版本

set -e

# 配置
AERON_SOURCE_DIR="/Users/kunzhang/work/source/aeron-project/aeron"
BUILD_BASE_DIR="/Users/kunzhang/work/source/aeron-project/aeron-c/build"
DOCKER_IMAGE="xsyphon/cross-builder:2.0"

# 日志配置
LOG_DIR="${BUILD_BASE_DIR}/logs"
MAIN_LOG="${LOG_DIR}/build-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "${LOG_DIR}"

# 架构列表
ARCHITECTURES=("amd64" "arm64")

# 日志函数
log_info() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1"
    echo "$message" | tee -a "${MAIN_LOG}"
}

log_error() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1"
    echo "$message" | tee -a "${MAIN_LOG}" >&2
}

log_warning() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1"
    echo "$message" | tee -a "${MAIN_LOG}"
}

# 执行命令并记录日志
run_with_log() {
    local cmd="$1"
    local desc="$2"
    log_info "执行: $desc"
    log_info "命令: $cmd"
    
    # 使用script命令捕获所有输出(包括颜色)到日志文件，同时显示在终端
    script -q -c "$cmd" /dev/null 2>&1 | tee -a "${MAIN_LOG}"
    local exit_code=${PIPESTATUS[0]}
    
    if [ $exit_code -eq 0 ]; then
        log_info "$desc 成功完成"
    else
        log_error "$desc 失败，退出码: $exit_code"
        return $exit_code
    fi
}

# 开始构建
log_info "🔨 开始构建Aeron C MediaDriver..."
log_info "主日志文件: ${MAIN_LOG}"

# 清理旧的构建
log_info "🧹 清理旧构建文件..."
rm -rf "${BUILD_BASE_DIR}"
mkdir -p "${BUILD_BASE_DIR}"

# 检查Docker镜像是否存在
log_info "🔍 检查Docker镜像: ${DOCKER_IMAGE}"
if ! docker image inspect "${DOCKER_IMAGE}" > /dev/null 2>&1; then
    log_error "❌ Docker镜像 ${DOCKER_IMAGE} 不存在"
    log_error "请先构建交叉编译环境镜像"
    exit 1
fi

# 检查源码目录
log_info "🔍 检查Aeron源码目录: ${AERON_SOURCE_DIR}"
if [ ! -d "${AERON_SOURCE_DIR}" ]; then
    log_error "❌ Aeron源码目录不存在: ${AERON_SOURCE_DIR}"
    exit 1
fi

log_info "🚀 开始交叉编译Aeron C MediaDriver..."
log_info "源码目录: ${AERON_SOURCE_DIR}"
log_info "构建目录: ${BUILD_BASE_DIR}"

# 为每个架构构建
for ARCH in "${ARCHITECTURES[@]}"; do
    ARCH_LOG="${LOG_DIR}/build-${ARCH}-$(date +%Y%m%d-%H%M%S).log"
    
    log_info ""
    log_info "🔨 构建架构: ${ARCH}"
    log_info "==========================================="
    log_info "架构专用日志: ${ARCH_LOG}"
    
    BUILD_DIR="${BUILD_BASE_DIR}/${ARCH}"
    mkdir -p "${BUILD_DIR}"
    
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
    log_info "📦 启动Docker容器编译 ${ARCH}..."
    
    # 创建详细的Docker构建脚本
    DOCKER_BUILD_SCRIPT=$(cat << 'EOF'
set -e

echo "[$(date '+%Y-%m-%d %H:%M:%S')] 🔧 配置CMake for ${ARCH}..."

# 设置环境变量
export CC=${COMPILER_PREFIX}-gcc
export CXX=${COMPILER_PREFIX}-g++
export AR=${COMPILER_PREFIX}-ar
export STRIP=${COMPILER_PREFIX}-strip
export RANLIB=${COMPILER_PREFIX}-ranlib
export PKG_CONFIG_PATH=/usr/lib/${COMPILER_PREFIX}/pkgconfig

echo "[$(date '+%Y-%m-%d %H:%M:%S')] 📊 编译环境信息:"
echo "  编译器: $CC"
echo "  C++编译器: $CXX"
echo "  CPU核心数: $(nproc)"
echo "  内存: $(free -h | grep Mem | awk '{print $2}')"

# 获取CPU核心数用于并行LTO
NPROC=$(nproc)

echo "[$(date '+%Y-%m-%d %H:%M:%S')] ⚙️ 配置CMake..."
cmake /source \
    ${CMAKE_TOOLCHAIN} \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_AERON_DRIVER=ON \
    -DBUILD_AERON_ARCHIVE_API=OFF \
    -DAERON_TESTS=OFF \
    -DCMAKE_INSTALL_PREFIX=/build/install \
    -DCMAKE_C_FLAGS="-O3 -DNDEBUG -flto=${NPROC} -ffunction-sections -fdata-sections" \
    -DCMAKE_CXX_FLAGS="-O3 -DNDEBUG -flto=${NPROC} -ffunction-sections -fdata-sections" \
    -DCMAKE_EXE_LINKER_FLAGS="-Wl,--gc-sections -flto=${NPROC} -static-libgcc -static-libstdc++" \
    -DCMAKE_VERBOSE_MAKEFILE=ON

echo "[$(date '+%Y-%m-%d %H:%M:%S')] 🔨 开始编译..."
make -j${NPROC} aeronmd aeronmd_s

echo "[$(date '+%Y-%m-%d %H:%M:%S')] 📦 安装到指定目录..."
make install

echo "[$(date '+%Y-%m-%d %H:%M:%S')] 📏 检查生成的可执行文件..."
ls -la aeronmd* || echo '在当前目录未找到aeronmd'
find /build -name 'aeronmd*' -type f -executable

echo "[$(date '+%Y-%m-%d %H:%M:%S')] 🔍 检查文件信息..."
if [ -f aeronmd ]; then
    echo "=== aeronmd (动态链接版) ==="
    file aeronmd
    ldd aeronmd || echo '静态链接或ldd不可用'
    ls -lh aeronmd
fi

if [ -f aeronmd_s ]; then
    echo "=== aeronmd_s (静态链接版) ==="
    file aeronmd_s
    ldd aeronmd_s || echo '静态链接'
    ls -lh aeronmd_s
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ 编译完成"
EOF
)

    # 执行Docker构建，将所有输出重定向到架构专用日志
    docker run --rm \
        -v "${AERON_SOURCE_DIR}:/source" \
        -v "${BUILD_DIR}:/build" \
        -w /build \
        -e "ARCH=${ARCH}" \
        -e "COMPILER_PREFIX=${COMPILER_PREFIX}" \
        -e "CMAKE_TOOLCHAIN=${CMAKE_TOOLCHAIN}" \
        "${DOCKER_IMAGE}" \
        bash -c "${DOCKER_BUILD_SCRIPT}" 2>&1 | tee -a "${ARCH_LOG}" | tee -a "${MAIN_LOG}"
    
    BUILD_EXIT_CODE=${PIPESTATUS[0]}
    
    # 检查构建结果
    if [ $BUILD_EXIT_CODE -eq 0 ]; then
        log_info "✅ ${ARCH} 编译成功"
        
        # 检查和复制生成的文件
        if [ -d "${ARCH_BUILD_DIR}" ]; then
            cd "${ARCH_BUILD_DIR}"
            
            # 查找生成的可执行文件
            AERONMD_FILES=$(find . -name 'aeronmd*' -type f -executable)
            
            if [ -n "$AERONMD_FILES" ]; then
                log_info "📋 ${ARCH} 生成的文件:"
                echo "$AERONMD_FILES" | while read file; do
                    if [ -f "$file" ]; then
                        FILE_INFO=$(file "$file")
                        FILE_SIZE=$(ls -lh "$file" | awk '{print $5}')
                        log_info "  $file - $FILE_SIZE - $FILE_INFO"
                    fi
                done | tee -a "${ARCH_LOG}" | tee -a "${MAIN_LOG}"
                
                # 复制到输出目录
                mkdir -p "${OUTPUT_DIR}/${ARCH}"
                cp aeronmd* "${OUTPUT_DIR}/${ARCH}/" 2>/dev/null || log_warning "复制文件时出现问题"
                
                log_info "📁 文件已复制到: ${OUTPUT_DIR}/${ARCH}/"
            else
                log_error "❌ ${ARCH}: 未找到aeronmd可执行文件"
                return 1
            fi
        else
            log_error "❌ ${ARCH}: 构建目录不存在: ${ARCH_BUILD_DIR}"
            return 1
        fi
    else
        log_error "❌ ${ARCH} 编译失败 (退出码: $BUILD_EXIT_CODE)"
        log_error "查看详细日志: ${ARCH_LOG}"
        return 1
    fi
}

# 主函数
main() {
    setup_logging
    
    log_info "🚀 开始Aeron C MediaDriver交叉编译"
    log_info "📅 时间: $(date)"
    log_info "🖥️  主机: $(uname -a)"
    log_info "📁 源码目录: ${AERON_SOURCE_DIR}"
    log_info "📁 构建目录: ${BUILD_DIR}"
    log_info "📁 输出目录: ${OUTPUT_DIR}"
    log_info "📁 日志目录: ${LOG_DIR}"
    
    # 检查前置条件
    if ! check_prerequisites; then
        log_error "❌ 前置条件检查失败"
        exit 1
    fi
    
    # 准备构建目录
    prepare_build_dirs
    
    # 编译各个架构
    FAILED_ARCHS=""
    SUCCESSFUL_ARCHS=""
    
    for ARCH in "${ARCHITECTURES[@]}"; do
        log_info ""
        log_info "🏗️  开始构建架构: $ARCH"
        
        if build_architecture "$ARCH"; then
            SUCCESSFUL_ARCHS="$SUCCESSFUL_ARCHS $ARCH"
            log_info "✅ $ARCH 构建成功"
        else
            FAILED_ARCHS="$FAILED_ARCHS $ARCH"
            log_error "❌ $ARCH 构建失败"
        fi
    done
    
    # 总结
    log_info ""
    log_info "📊 构建总结:"
    if [ -n "$SUCCESSFUL_ARCHS" ]; then
        log_info "✅ 成功的架构:$SUCCESSFUL_ARCHS"
    fi
    if [ -n "$FAILED_ARCHS" ]; then
        log_error "❌ 失败的架构:$FAILED_ARCHS"
    fi
    
    # 显示生成的文件
    if [ -d "$OUTPUT_DIR" ]; then
        log_info ""
        log_info "� 生成的文件:"
        find "$OUTPUT_DIR" -type f -executable | while read file; do
            SIZE=$(ls -lh "$file" | awk '{print $5}')
            ARCH=$(basename $(dirname "$file"))
            NAME=$(basename "$file")
            log_info "  [$ARCH] $NAME - $SIZE"
        done
    fi
    
    log_info ""
    log_info "📋 完整日志文件:"
    log_info "  主日志: ${MAIN_LOG}"
    for ARCH in "${ARCHITECTURES[@]}"; do
        ARCH_LOG="${LOG_DIR}/build_${ARCH}.log"
        if [ -f "$ARCH_LOG" ]; then
            log_info "  ${ARCH}日志: ${ARCH_LOG}"
        fi
    done
    
    if [ -n "$FAILED_ARCHS" ]; then
        log_error "🚨 部分架构构建失败，请查看相应日志文件"
        exit 1
    else
        log_info "🎉 所有架构构建成功！"
        
        log_info ""
        log_info "💡 使用建议:"
        log_info "  1. 选择静态链接版本 (aeronmd_s) 以减少依赖"
        log_info "  2. 部署到目标Linux机器后赋予执行权限: chmod +x aeronmd_s"
        log_info "  3. 运行配置: ./aeronmd_s [config_file]"
        log_info ""
        log_info "📚 参数说明:"
        log_info "  -v               显示版本信息"
        log_info "  -Dname=value     设置系统属性"
        log_info "  config_file      指定配置文件"
        
        exit 0
    fi
}

# 执行主函数
main "$@"
