#!/bin/bash
# Aeron C语言MediaDriver交叉编译脚本
# 使用Docker交叉编译环境构建AMD64和ARM64版本
# 支持详细日志记录和错误分析

set -e

# ==================== 配置区域 ====================
AERON_SOURCE_DIR="../aeron"
BUILD_BASE_DIR="./build"
DOCKER_IMAGE="xsyphon/cross-builder:2.0"

# 架构列表
ARCHITECTURES=("amd64" "arm64")

# 日志配置
LOG_DIR="${BUILD_BASE_DIR}/logs"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
MAIN_LOG="${LOG_DIR}/build-${TIMESTAMP}.log"

# ==================== 日志函数 ====================
setup_logging() {
    mkdir -p "${LOG_DIR}"
    
    # 创建主日志文件
    touch "${MAIN_LOG}"
    
    echo "🔨 Aeron C MediaDriver 交叉编译构建" > "${MAIN_LOG}"
    echo "📅 开始时间: $(date)" >> "${MAIN_LOG}"
    echo "🖥️  主机信息: $(uname -a)" >> "${MAIN_LOG}"
    echo "🐳 Docker镜像: ${DOCKER_IMAGE}" >> "${MAIN_LOG}"
    echo "========================================" >> "${MAIN_LOG}"
    echo "" >> "${MAIN_LOG}"
}

log_info() {
    local message="[$(date '+%H:%M:%S')] ℹ️  $1"
    echo "$message" | tee -a "${MAIN_LOG}"
}

log_success() {
    local message="[$(date '+%H:%M:%S')] ✅ $1"
    echo "$message" | tee -a "${MAIN_LOG}"
}

log_warning() {
    local message="[$(date '+%H:%M:%S')] ⚠️  $1"
    echo "$message" | tee -a "${MAIN_LOG}"
}

log_error() {
    local message="[$(date '+%H:%M:%S')] ❌ $1"
    echo "$message" | tee -a "${MAIN_LOG}" >&2
}

log_separator() {
    local sep="=========================================="
    echo "$sep" | tee -a "${MAIN_LOG}"
}

# ==================== 前置检查函数 ====================
check_prerequisites() {
    log_info "🔍 检查构建前置条件..."
    
    # 检查Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker未安装或不在PATH中"
        return 1
    fi
    
    # 检查Docker是否运行
    if ! docker info &> /dev/null; then
        log_error "Docker未运行，请启动Docker"
        return 1
    fi
    
    # 检查Docker镜像
    if ! docker image inspect "${DOCKER_IMAGE}" > /dev/null 2>&1; then
        log_error "Docker镜像 ${DOCKER_IMAGE} 不存在"
        log_error "请先构建交叉编译环境镜像"
        return 1
    fi
    
    # 检查源码目录
    if [ ! -d "${AERON_SOURCE_DIR}" ]; then
        log_error "Aeron源码目录不存在: ${AERON_SOURCE_DIR}"
        return 1
    fi
    
    # 检查CMakeLists.txt
    if [ ! -f "${AERON_SOURCE_DIR}/CMakeLists.txt" ]; then
        log_error "Aeron CMakeLists.txt不存在: ${AERON_SOURCE_DIR}/CMakeLists.txt"
        return 1
    fi
    
    log_success "前置条件检查通过"
    return 0
}

# ==================== 构建目录准备 ====================
prepare_build_dirs() {
    # 首先确保日志目录存在（避免在清理过程中丢失日志）
    mkdir -p "${LOG_DIR}"
    
    log_info "🧹 准备构建目录..."
    
    # 清理旧构建目录，但保留日志目录
    if [ -d "${BUILD_BASE_DIR}" ]; then
        # 保存日志目录
        if [ -d "${LOG_DIR}" ]; then
            mv "${LOG_DIR}" "${LOG_DIR}.backup"
        fi
        
        # 删除构建目录
        rm -rf "${BUILD_BASE_DIR}"
        log_info "已清理旧构建目录"
        
        # 恢复日志目录
        mkdir -p "${BUILD_BASE_DIR}"
        if [ -d "${LOG_DIR}.backup" ]; then
            mv "${LOG_DIR}.backup" "${LOG_DIR}"
        fi
    else
        # 如果构建目录不存在，直接创建
        mkdir -p "${BUILD_BASE_DIR}"
        mkdir -p "${LOG_DIR}"
    fi
    
    # 为每个架构创建目录
    for ARCH in "${ARCHITECTURES[@]}"; do
        mkdir -p "${BUILD_BASE_DIR}/${ARCH}"
    done
    
    # 创建输出目录
    mkdir -p "${BUILD_BASE_DIR}/dist"
    
    log_success "构建目录准备完成"
}

# ==================== 单架构构建函数 ====================
build_architecture() {
    local ARCH="$1"
    local ARCH_LOG="${LOG_DIR}/build-${ARCH}-${TIMESTAMP}.log"
    
    log_separator
    log_info "🔨 开始构建架构: ${ARCH}"
    log_info "📋 架构日志: ${ARCH_LOG}"
    
    local BUILD_DIR="${BUILD_BASE_DIR}/${ARCH}"
    local DIST_DIR="${BUILD_BASE_DIR}/dist/${ARCH}"
    mkdir -p "${DIST_DIR}"
    
    # 根据架构设置编译器工具链
    local CMAKE_TOOLCHAIN=""
    local COMPILER_PREFIX=""
    
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
            log_error "不支持的架构: ${ARCH}"
            return 1
            ;;
    esac
    
    log_info "🛠️  编译器前缀: ${COMPILER_PREFIX}"
    log_info "⚙️  CMake工具链: ${CMAKE_TOOLCHAIN:-"默认"}"
    
    # 创建Docker构建脚本
    local DOCKER_BUILD_SCRIPT=$(cat << 'EOF'
set -e

echo "[$(date '+%H:%M:%S')] 🚀 开始Docker容器内构建..."

# 显示环境信息
echo "[$(date '+%H:%M:%S')] 📊 构建环境信息:"
echo "  操作系统: $(cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '"')"
echo "  编译器: ${COMPILER_PREFIX}-gcc $(${COMPILER_PREFIX}-gcc --version | head -1 | cut -d')' -f2)"
echo "  CMake: $(cmake --version | head -1)"
echo "  CPU核心: $(nproc)"
echo "  可用内存: $(free -h | grep Mem | awk '{print $7}')"
echo ""

# 设置环境变量
export CC=${COMPILER_PREFIX}-gcc
export CXX=${COMPILER_PREFIX}-g++
export AR=${COMPILER_PREFIX}-ar
export STRIP=${COMPILER_PREFIX}-strip
export RANLIB=${COMPILER_PREFIX}-ranlib
export PKG_CONFIG_PATH=/usr/lib/${COMPILER_PREFIX}/pkgconfig

# 获取CPU核心数用于并行优化
NPROC=$(nproc)

echo "[$(date '+%H:%M:%S')] ⚙️  配置CMake..."
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

echo "[$(date '+%H:%M:%S')] 🔨 开始编译 (使用 ${NPROC} 个并行作业)..."
make -j${NPROC} aeronmd aeronmd_s

echo "[$(date '+%H:%M:%S')] 📦 安装到指定目录..."
make install

echo "[$(date '+%H:%M:%S')] � 检查生成的文件..."
echo "=== 构建目录中的aeronmd文件 ==="
find . -name 'aeronmd*' -type f -executable -ls

echo "=== 安装目录中的文件 ==="
find /build/install -type f -executable -ls

echo "[$(date '+%H:%M:%S')] � 检查可执行文件信息..."
for exe in aeronmd aeronmd_s; do
    if [ -f "$exe" ]; then
        echo "=== $exe ==="
        file "$exe"
        ls -lh "$exe"
        ldd "$exe" 2>/dev/null || echo "静态链接或无动态依赖"
        echo ""
    fi
done

echo "[$(date '+%H:%M:%S')] ✅ Docker容器内构建完成"
EOF
)

    # 执行Docker构建
    log_info "📦 启动Docker容器进行构建..."
    
    # 使用环境变量传递参数，避免shell转义问题
    if docker run --rm \
        -v "${AERON_SOURCE_DIR}:/source:ro" \
        -v "${BUILD_DIR}:/build" \
        -w /build \
        -e "ARCH=${ARCH}" \
        -e "COMPILER_PREFIX=${COMPILER_PREFIX}" \
        -e "CMAKE_TOOLCHAIN=${CMAKE_TOOLCHAIN}" \
        "${DOCKER_IMAGE}" \
        bash -c "${DOCKER_BUILD_SCRIPT}" 2>&1 | tee "${ARCH_LOG}" | tee -a "${MAIN_LOG}"; then
        
        log_success "Docker构建成功"
        
        # 检查和复制生成的文件
        copy_build_artifacts "${BUILD_DIR}" "${DIST_DIR}" "${ARCH}"
        
        return 0
    else
        log_error "Docker构建失败，详细信息请查看: ${ARCH_LOG}"
        return 1
    fi
}

# ==================== 构建产物复制函数 ====================
copy_build_artifacts() {
    local BUILD_DIR="$1"
    local DIST_DIR="$2"
    local ARCH="$3"
    
    log_info "📁 复制构建产物..."
    
    local FOUND_FILES=0
    
    # 查找并复制aeronmd文件
    while IFS= read -r -d '' file; do
        if [ -f "$file" ]; then
            local filename=$(basename "$file")
            local dest_file="${DIST_DIR}/${filename}-${ARCH}"
            
            cp "$file" "$dest_file"
            chmod +x "$dest_file"
            
            local size=$(ls -lh "$dest_file" | awk '{print $5}')
            local file_info=$(file "$dest_file" | cut -d: -f2-)
            
            log_success "复制: ${filename} -> ${dest_file} (${size})"
            log_info "  文件信息:${file_info}"
            
            FOUND_FILES=$((FOUND_FILES + 1))
        fi
    done < <(find "${BUILD_DIR}" -name 'aeronmd*' -type f -executable -print0)
    
    if [ $FOUND_FILES -eq 0 ]; then
        log_warning "未找到任何aeronmd可执行文件"
        return 1
    else
        log_success "成功复制 ${FOUND_FILES} 个文件"
        return 0
    fi
}

# ==================== 构建总结函数 ====================
print_build_summary() {
    local SUCCESSFUL_ARCHS="$1"
    local FAILED_ARCHS="$2"
    
    log_separator
    log_info "📊 构建总结报告"
    log_info "📅 完成时间: $(date)"
    
    if [ -n "$SUCCESSFUL_ARCHS" ]; then
        log_success "成功构建的架构: ${SUCCESSFUL_ARCHS}"
    fi
    
    if [ -n "$FAILED_ARCHS" ]; then
        log_error "失败构建的架构: ${FAILED_ARCHS}"
    fi
    
    # 显示生成的文件
    local DIST_BASE="${BUILD_BASE_DIR}/dist"
    if [ -d "$DIST_BASE" ] && [ "$(find "$DIST_BASE" -type f -executable | wc -l)" -gt 0 ]; then
        log_separator
        log_info "🎁 生成的可执行文件:"
        
        find "$DIST_BASE" -type f -executable | sort | while read -r file; do
            local arch_dir=$(basename "$(dirname "$file")")
            local filename=$(basename "$file")
            local size=$(ls -lh "$file" | awk '{print $5}')
            local file_type=$(file "$file" | cut -d: -f2- | sed 's/^[[:space:]]*//')
            
            echo "  [$arch_dir] $filename"
            echo "    大小: $size"
            echo "    类型: $file_type"
            echo "    路径: $file"
            echo ""
        done | tee -a "${MAIN_LOG}"
    else
        log_warning "未找到任何生成的可执行文件"
    fi
    
    # 显示日志文件
    log_separator
    log_info "📋 详细日志文件:"
    log_info "  主日志: ${MAIN_LOG}"
    
    for ARCH in "${ARCHITECTURES[@]}"; do
        local ARCH_LOG="${LOG_DIR}/build-${ARCH}-${TIMESTAMP}.log"
        if [ -f "$ARCH_LOG" ]; then
            log_info "  ${ARCH}日志: ${ARCH_LOG}"
        fi
    done
    
    # 使用建议
    log_separator
    log_info "💡 使用建议:"
    log_info "  1. 优先选择静态链接版本 (aeronmd_s-*) 以减少部署依赖"
    log_info "  2. 部署到目标Linux机器:"
    log_info "     scp aeronmd_s-amd64 user@target:/opt/aeron/"
    log_info "     chmod +x /opt/aeron/aeronmd_s-amd64"
    log_info "  3. 运行MediaDriver:"
    log_info "     ./aeronmd_s-amd64 [config_file]"
    log_info "  4. 常用参数:"
    log_info "     -Daeron.dir=/dev/shm/aeron    # 指定工作目录"
    log_info "     -Daeron.threading.mode=SHARED # 线程模式"
    log_info "     -Daeron.term.buffer.length=64k # 缓冲区大小"
}

# ==================== 主函数 ====================
main() {
    # 设置日志
    setup_logging
    
    log_info "🚀 开始Aeron C MediaDriver交叉编译构建"
    log_info "🎯 目标架构: ${ARCHITECTURES[*]}"
    log_info "📁 源码目录: ${AERON_SOURCE_DIR}"
    log_info "📁 构建目录: ${BUILD_BASE_DIR}"
    log_info "� Docker镜像: ${DOCKER_IMAGE}"
    
    # 前置检查
    if ! check_prerequisites; then
        log_error "前置条件检查失败，退出构建"
        exit 1
    fi
    
    # 准备构建目录
    prepare_build_dirs
    
    # 构建各个架构
    local SUCCESSFUL_ARCHS=""
    local FAILED_ARCHS=""
    
    for ARCH in "${ARCHITECTURES[@]}"; do
        if build_architecture "$ARCH"; then
            SUCCESSFUL_ARCHS="${SUCCESSFUL_ARCHS} ${ARCH}"
        else
            FAILED_ARCHS="${FAILED_ARCHS} ${ARCH}"
        fi
    done
    
    # 显示构建总结
    print_build_summary "$SUCCESSFUL_ARCHS" "$FAILED_ARCHS"
    
    # 确定退出状态
    if [ -n "$FAILED_ARCHS" ]; then
        log_error "🚨 部分或全部架构构建失败"
        log_error "请检查相应的架构日志文件进行问题排查"
        exit 1
    else
        log_success "🎉 所有架构构建成功完成！"
        exit 0
    fi
}

# 执行主函数
main "$@"
