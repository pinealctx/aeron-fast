#!/bin/bash
# binary-performance-subscriber-udp-optimized.sh
# 
# 🚀 C版本 UDP传输高度优化版 - 超越Java性能

export AERON_DIR="/dev/shm/aeron"

# C版本可执行文件路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
C_BINARY="$SCRIPT_DIR/../c-performance/build/dist/binary_subscriber-amd64"

# 检查C可执行文件是否存在
if [ ! -f "$C_BINARY" ]; then
    echo "❌ 错误: 找不到C版本可执行文件: $C_BINARY"
    echo "请先编译C版本:"
    echo "  cd ../c-performance && ./build.sh"
    exit 1
fi

# 检查可执行权限
if [ ! -x "$C_BINARY" ]; then
    echo "🔧 设置可执行权限..."
    chmod +x "$C_BINARY"
fi

echo "🚀 启动Aeron C版本二进制高性能测试订阅者 (UDP超优化模式)..."
echo "连接到MediaDriver: $AERON_DIR"
echo "传输方式: UDP (C原生超优化网络传输)"
echo "确保MediaDriver已在运行: ./start-mediadriver.sh"
echo "C可执行文件: $C_BINARY"

# 检查是否需要sudo权限
if [ "$EUID" -eq 0 ]; then
    echo "🔐 以root权限运行，保持用户身份..."
    USER_NAME="${SUDO_USER:-$(logname 2>/dev/null || echo root)}"
    echo "目标用户: $USER_NAME"
else
    echo "👤 以普通用户身份运行"
    USER_NAME="$(whoami)"
    echo "当前用户: $USER_NAME"
fi

echo "准备接收二进制性能数据..."
echo ""

# C版本环境变量设置（对应Java的JVM参数）
export AERON_SOCKET_SO_SNDBUF=2097152
export AERON_SOCKET_SO_RCVBUF=2097152
export AERON_MTU_LENGTH=8192
export AERON_IPC_MTU_LENGTH=8192
export AERON_TERM_BUFFER_LENGTH=2097152
export AERON_RCV_INITIAL_WINDOW_LENGTH=2097152
export AERON_THREADING_MODE=DEDICATED
export AERON_CONDUCTOR_IDLE_STRATEGY=busy-spin
export AERON_RECEIVER_IDLE_STRATEGY=busy-spin

# 性能优化设置
export AERON_PRE_TOUCH_MAPPED_MEMORY=true
export AERON_PERFORM_STORAGE_CHECKS=false

# 根据权限选择执行方式
if [ "$EUID" -eq 0 ] && [ -n "$SUDO_USER" ]; then
    # 以sudo启动，但保持原用户身份执行C程序
    echo "🔐 以sudo权限执行C程序..."
    sudo -u "$SUDO_USER" \
         env AERON_DIR="$AERON_DIR" \
             AERON_SOCKET_SO_SNDBUF="$AERON_SOCKET_SO_SNDBUF" \
             AERON_SOCKET_SO_RCVBUF="$AERON_SOCKET_SO_RCVBUF" \
             AERON_MTU_LENGTH="$AERON_MTU_LENGTH" \
             AERON_IPC_MTU_LENGTH="$AERON_IPC_MTU_LENGTH" \
             AERON_TERM_BUFFER_LENGTH="$AERON_TERM_BUFFER_LENGTH" \
             AERON_RCV_INITIAL_WINDOW_LENGTH="$AERON_RCV_INITIAL_WINDOW_LENGTH" \
             AERON_THREADING_MODE="$AERON_THREADING_MODE" \
             AERON_CONDUCTOR_IDLE_STRATEGY="$AERON_CONDUCTOR_IDLE_STRATEGY" \
             AERON_RECEIVER_IDLE_STRATEGY="$AERON_RECEIVER_IDLE_STRATEGY" \
             AERON_PRE_TOUCH_MAPPED_MEMORY="$AERON_PRE_TOUCH_MAPPED_MEMORY" \
             AERON_PERFORM_STORAGE_CHECKS="$AERON_PERFORM_STORAGE_CHECKS" \
         "$C_BINARY" -transport UDP "$@"
else
    # 普通权限执行
    echo "👤 以普通用户权限执行C程序..."
    "$C_BINARY" -transport UDP "$@"
fi