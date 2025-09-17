#!/bin/bash

# Aeron C语言延迟测试 - Docker交叉编译脚本
# 支持 Linux AMD64 和 ARM64 架构

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 显示用法
show_usage() {
    echo "用法: $0 [选项]"
    echo "选项:"
    echo "  -a ARCH     目标架构 (amd64|arm64|all) [默认: amd64]"
    echo "  -t TYPE     构建类型 (Debug|Release) [默认: Release]"
    echo "  -c          清理构建目录"
    echo "  -r          运行测试"
    echo "  -h          显示此帮助"
    echo ""
    echo "示例:"
    echo "  $0                    # 构建 AMD64 Release 版本"
    echo "  $0 -a arm64          # 构建 ARM64 版本"
    echo "  $0 -a all            # 构建所有架构"
    echo "  $0 -t Debug          # 构建 Debug 版本"
    echo "  $0 -c                # 清理构建目录"
    echo "  $0 -r                # 构建并运行测试"
}

# 检查Docker是否可用
check_docker() {
    if ! command -v docker &> /dev/null; then
        print_error "Docker 未安装或不可用"
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        print_error "Docker 守护进程未运行"
        exit 1
    fi
    
    print_info "Docker 检查通过"
}

# 创建Dockerfile
create_dockerfile() {
    local arch=$1
    local dockerfile_name="Dockerfile.${arch}"
    
    print_info "创建 ${dockerfile_name}"
    
    case $arch in
        amd64)
            base_image="ubuntu:24.04"
            cmake_arch="x86_64"
            ;;
        arm64)
            base_image="arm64v8/ubuntu:24.04"
            cmake_arch="aarch64"
            ;;
        *)
            print_error "不支持的架构: $arch"
            exit 1
            ;;
    esac
    
    cat > "$PROJECT_DIR/$dockerfile_name" << EOF
FROM ${base_image}

# 使用清华镜像源加速
RUN sed -i 's@//.*archive.ubuntu.com@//mirrors.tuna.tsinghua.edu.cn@g' /etc/apt/sources.list.d/ubuntu.sources

# 安装构建依赖
RUN apt-get update && apt-get install -y \\
    build-essential \\
    cmake \\
    git \\
    pkg-config \\
    libc6-dev \\
    linux-libc-dev \\
    wget \\
    curl \\
    && rm -rf /var/lib/apt/lists/*

# 安装较新版本的CMake（如果需要）
RUN cmake_version=\$(cmake --version | head -n1 | cut -d' ' -f3) && \\
    if [ "\$(printf '%s\\n3.16\\n' "\$cmake_version" | sort -V | head -n1)" != "3.16" ]; then \\
        echo "CMake 版本过低，安装新版本..." && \\
        wget -O - https://apt.kitware.com/keys/kitware-archive-latest.asc 2>/dev/null | gpg --dearmor - | tee /etc/apt/trusted.gpg.d/kitware.gpg >/dev/null && \\
        echo 'deb https://apt.kitware.com/ubuntu/ focal main' | tee /etc/apt/sources.list.d/kitware.list >/dev/null && \\
        apt-get update && apt-get install -y cmake; \\
    fi

# 设置工作目录
WORKDIR /workspace

# 复制源代码
COPY . .

# 构建参数
ARG BUILD_TYPE=Release
ARG CMAKE_ARCH=${cmake_arch}

# 创建构建目录
RUN mkdir -p build/\${CMAKE_ARCH}

# 配置和构建
RUN cd build/\${CMAKE_ARCH} && \\
    cmake ../.. \\
        -DCMAKE_BUILD_TYPE=\${BUILD_TYPE} \\
        -DCMAKE_INSTALL_PREFIX=/usr/local \\
        -DCMAKE_C_FLAGS="-march=native -mtune=native" \\
        && \\
    make -j\$(nproc) VERBOSE=1

# 安装
RUN cd build/\${CMAKE_ARCH} && make install

# 运行测试的入口点
CMD ["timestamp_stability", "-s", "10000"]
EOF
}

# 构建指定架构
build_arch() {
    local arch=$1
    local build_type=$2
    local dockerfile_name="Dockerfile.${arch}"
    local image_name="aeron-latency-test:${arch}-${build_type,,}"
    
    print_info "构建 ${arch} 架构，构建类型: ${build_type}"
    
    # 创建Dockerfile
    create_dockerfile $arch
    
    # 构建Docker镜像
    docker build \
        --platform linux/${arch} \
        -f "$dockerfile_name" \
        --build-arg BUILD_TYPE="$build_type" \
        -t "$image_name" \
        "$PROJECT_DIR"
    
    if [ $? -eq 0 ]; then
        print_success "${arch} 架构构建成功: $image_name"
        echo "$image_name" >> "$PROJECT_DIR/.built_images"
    else
        print_error "${arch} 架构构建失败"
        exit 1
    fi
}

# 运行测试
run_tests() {
    print_info "运行测试..."
    
    if [ ! -f "$PROJECT_DIR/.built_images" ]; then
        print_error "没有找到已构建的镜像，请先构建"
        exit 1
    fi
    
    while IFS= read -r image_name; do
        print_info "测试镜像: $image_name"
        docker run --rm "$image_name"
        echo ""
    done < "$PROJECT_DIR/.built_images"
}

# 清理
cleanup() {
    print_info "清理构建文件..."
    
    # 清理构建目录
    rm -rf "$PROJECT_DIR/build"
    
    # 清理Dockerfile
    rm -f "$PROJECT_DIR"/Dockerfile.*
    
    # 清理镜像记录
    if [ -f "$PROJECT_DIR/.built_images" ]; then
        while IFS= read -r image_name; do
            print_info "删除镜像: $image_name"
            docker rmi "$image_name" 2>/dev/null || true
        done < "$PROJECT_DIR/.built_images"
        rm -f "$PROJECT_DIR/.built_images"
    fi
    
    print_success "清理完成"
}

# 默认参数
ARCH="amd64"
BUILD_TYPE="Release"
CLEAN=false
RUN_TESTS=false

# 解析参数
while getopts "a:t:crh" opt; do
    case $opt in
        a)
            ARCH="$OPTARG"
            ;;
        t)
            BUILD_TYPE="$OPTARG"
            ;;
        c)
            CLEAN=true
            ;;
        r)
            RUN_TESTS=true
            ;;
        h)
            show_usage
            exit 0
            ;;
        ?)
            show_usage
            exit 1
            ;;
    esac
done

# 主程序
main() {
    print_info "Aeron C语言延迟测试 - Docker交叉编译"
    print_info "项目目录: $PROJECT_DIR"
    
    # 检查Docker
    check_docker
    
    # 清理（如果需要）
    if [ "$CLEAN" = true ]; then
        cleanup
        exit 0
    fi
    
    # 初始化构建镜像记录文件
    rm -f "$PROJECT_DIR/.built_images"
    touch "$PROJECT_DIR/.built_images"
    
    # 构建
    case $ARCH in
        amd64|arm64)
            build_arch "$ARCH" "$BUILD_TYPE"
            ;;
        all)
            build_arch "amd64" "$BUILD_TYPE"
            build_arch "arm64" "$BUILD_TYPE"
            ;;
        *)
            print_error "不支持的架构: $ARCH"
            print_info "支持的架构: amd64, arm64, all"
            exit 1
            ;;
    esac
    
    # 运行测试（如果需要）
    if [ "$RUN_TESTS" = true ]; then
        run_tests
    fi
    
    print_success "构建完成！"
    print_info "运行测试: $0 -r"
    print_info "清理: $0 -c"
}

# 执行主程序
main "$@"
