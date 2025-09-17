#!/bin/bash

# Aeron C++ MediaDriver同步脚本 - 同步C++可执行文件和Linux脚本到服务器
# 使用方法: ./sync-to-linux.sh user@hostname:/path/to/destination

if [ $# -eq 0 ]; then
    echo "使用方法: $0 user@hostname:/remote/path"
    echo "示例: $0 root@192.168.1.100:/opt/aeron-cpp"
    exit 1
fi

REMOTE_TARGET=$1
LOCAL_BINARY_DIR="./build/dist/amd64"
APP_BINARY_NAME="./c-performance/build/dist"
LOCAL_SCRIPT_DIR="./linux-script"

echo "🚀 同步Aeron C++ MediaDriver到Linux服务器..."
echo "可执行文件源目录: $LOCAL_BINARY_DIR"
echo "脚本源目录: $LOCAL_SCRIPT_DIR"
echo "目标: $REMOTE_TARGET"

# 检查本地目录是否存在
if [ ! -d "$LOCAL_BINARY_DIR" ]; then
    echo "❌ 可执行文件目录不存在: $LOCAL_BINARY_DIR"
    echo "请先运行 ./build_aeron_driver.sh 构建C++ MediaDriver"
    exit 1
fi

# 检查可执行文件目录是否存在
if [ ! -d "$APP_BINARY_NAME" ]; then
    echo "❌ 可执行文件目录不存在: $APP_BINARY_NAME"
    exit 1
fi

# 检查脚本目录是否存在
if [ ! -d "$LOCAL_SCRIPT_DIR" ]; then
    echo "❌ 脚本目录不存在: $LOCAL_SCRIPT_DIR"
    exit 1
fi

# 检查关键文件
if [ ! -f "$LOCAL_BINARY_DIR/aeronmd_s-amd64" ]; then
    echo "❌ 静态链接MediaDriver不存在: $LOCAL_BINARY_DIR/aeronmd_s-amd64"
    echo "请检查构建是否成功"
    exit 1
fi

echo ""
echo "📦 同步C++ MediaDriver可执行文件..."
rsync -avz --progress \
    --include="aeronmd_s-amd64" \
    --include="aeronmd-amd64" \
    --exclude="*" \
    $LOCAL_BINARY_DIR/ \
    $REMOTE_TARGET/

echo ""
echo "📦 同步C++ App可执行文件..."
rsync -avz --progress \
    --include="binary_publisher-amd64" \
    --include="binary_publisher-install-amd64" \
    --include="binary_subscriber-amd64" \
    --include="binary_subscriber-install-amd64" \
    --exclude="*" \
    $APP_BINARY_NAME/ \
    $REMOTE_TARGET/
  
echo ""
echo "📜 同步Linux脚本..."
rsync -avz --progress \
    $LOCAL_SCRIPT_DIR/ \
    $REMOTE_TARGET/

echo ""
echo "✅ 同步完成！"
echo ""
echo "🔧 在Linux服务器上运行:"
echo "cd $REMOTE_TARGET"
echo "chmod +x aeronmd* *.sh"
echo ""
echo "📋 可用脚本和文件:"
echo "  ./aeronmd_s-amd64                      # C++ MediaDriver (静态链接，推荐)"
echo "  ./aeronmd-amd64                        # C++ MediaDriver (动态链接)"
echo "  ./start-mediadriver-cpp-optimized.sh  # 启动C++ MediaDriver"
echo "  ./stop-mediadriver-cpp.sh             # 停止C++ MediaDriver"
echo ""
echo "🚀 快速启动:"
echo "  ./start-mediadriver-cpp-optimized.sh  # 启动MediaDriver"
echo "  ps aux | grep aeronmd                 # 检查运行状态"
echo "  ./stop-mediadriver-cpp.sh             # 停止MediaDriver"
echo ""
echo "📊 监控命令:"
echo "  ls -la /dev/shm/aeron/                 # 查看Aeron工作目录"
echo "  netstat -ulnp | grep 4050             # 检查UDP端口"
echo "  top -p \$(pgrep aeronmd)                # 查看资源使用"
echo ""
echo "📚 详细说明请查看: README-deployment.md"