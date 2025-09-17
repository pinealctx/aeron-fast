#!/bin/bash
# start-mediadriver-cpp-optimized.sh
# 
# 🚀 C++ 优化版MediaDriver - 对应Java版本的优化配置

# C++ MediaDriver可执行文件路径 (静态链接版本，避免依赖问题)
AERONMD_EXECUTABLE="./aeronmd_s-amd64"

echo "🚀 启动Aeron C++ MediaDriver (优化版)..."

# 检查可执行文件是否存在
if [ ! -f "$AERONMD_EXECUTABLE" ]; then
    echo "❌ MediaDriver可执行文件不存在: $AERONMD_EXECUTABLE"
    echo "请确保已将 aeronmd_s-amd64 部署到当前目录"
    exit 1
fi

# 检查是否已有C++ MediaDriver在运行
EXISTING_PID=$(pgrep -f "aeronmd")
if [ -n "$EXISTING_PID" ]; then
    echo "✅ C++ MediaDriver 已在运行 (PID: $EXISTING_PID)"
    echo "📊 进程信息:"
    echo "   - PID: $EXISTING_PID"
    echo "   - 优先级: $(ps -o pid,ni -p $EXISTING_PID --no-headers 2>/dev/null | awk '{print $2}' || echo 'N/A')"
    echo "   - 内存使用: $(ps -o pid,rss -p $EXISTING_PID --no-headers 2>/dev/null | awk '{print $2/1024 " MB"}' || echo 'N/A')"
    echo ""
    echo "🔍 监控命令:"
    echo "   检查进程: ps aux | grep aeronmd"
    echo "   查看日志: ls -la /dev/shm/aeron/"
    echo "   停止服务: ./stop-mediadriver-cpp.sh"
    echo ""
    echo "⚡ C++ MediaDriver 已经在运行中!"
    exit 0
fi

# 确保RAM磁盘存在并有正确权限
AERON_DIR="/dev/shm/aeron"
echo "📁 准备Aeron目录: $AERON_DIR"
if [ ! -d "$AERON_DIR" ]; then
    mkdir -p "$AERON_DIR"
elif [ ! -w "$AERON_DIR" ]; then
    echo "🔧 修复Aeron目录权限..."
    sudo chown $USER:$USER "$AERON_DIR" 2>/dev/null || true
    sudo chmod 755 "$AERON_DIR" 2>/dev/null || true
fi

echo "⚡ C++ MediaDriver 优化配置:"
echo "   - 可执行文件: $AERONMD_EXECUTABLE"
echo "   - 线程模式: DEDICATED (专用线程)"
echo "   - Socket缓冲区: 2MB"
echo "   - Term缓冲区: 2MB"
echo "   - MTU: 8KB"
echo "   - Aeron目录: $AERON_DIR"
echo ""

# 设置C++ MediaDriver环境变量 - 对应Java版本的配置
export AERON_DIR="$AERON_DIR"
export AERON_THREADING_MODE="DEDICATED"
export AERON_CONDUCTOR_IDLE_STRATEGY="spin"
export AERON_RECEIVER_IDLE_STRATEGY="spin"
export AERON_SENDER_IDLE_STRATEGY="spin"
export AERON_TERM_BUFFER_SPARSE_FILE="false"
export AERON_PRE_TOUCH_MAPPED_MEMORY="true"
export AERON_SOCKET_SO_SNDBUF="2097152"
export AERON_SOCKET_SO_RCVBUF="2097152"
export AERON_MTU_LENGTH="8192"
export AERON_IPC_MTU_LENGTH="8192"
export AERON_TERM_BUFFER_LENGTH="2097152"
export AERON_RCV_INITIAL_WINDOW_LENGTH="2097152"

# 启动C++ MediaDriver (后台进程)
echo "🚀 启动 C++ MediaDriver..."

$AERONMD_EXECUTABLE &
MEDIADRIVER_PID=$!
echo "✅ C++ MediaDriver 优化版已启动 (PID: $MEDIADRIVER_PID)"

# 等待一下确保启动成功
sleep 1

# 检查进程是否还在运行
if kill -0 $MEDIADRIVER_PID 2>/dev/null; then
    echo "📊 进程信息:"
    echo "   - PID: $MEDIADRIVER_PID"
    echo "   - 优先级: $(ps -o pid,ni -p $MEDIADRIVER_PID --no-headers | awk '{print $2}' 2>/dev/null || echo 'N/A')"
    echo "   - 可执行文件: $AERONMD_EXECUTABLE"
    echo ""
    echo "🔍 监控命令:"
    echo "   检查进程: ps aux | grep aeronmd"
    echo "   查看日志: ls -la $AERON_DIR/"
    echo "   停止服务: ./stop-mediadriver-cpp.sh"
    echo ""
    echo "⚡ C++ MediaDriver 优化版就绪!"
else
    echo "❌ C++ MediaDriver 启动失败！"
    echo "请检查:"
    echo "   1. 可执行文件是否有执行权限"
    echo "   2. 所需的动态库是否存在"
    echo "   3. 系统资源是否充足"
    exit 1
fi