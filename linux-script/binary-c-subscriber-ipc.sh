#!/bin/bash
# binary-performance-subscriber-ipc-optimized.sh
# 
# 🚀 C版本 IPC传输极限优化版 - 最高性能模式

export AERON_DIR="/dev/shm/aeron"

# C版本可执行文件路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
C_BINARY="./binary_subscriber-amd64"

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

echo "🚀 启动Aeron C版本二进制高性能测试订阅者 (IPC极限优化模式)..."
echo "连接到MediaDriver: $AERON_DIR"
echo "传输方式: IPC (C原生进程间通信 - 最高性能)"
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

echo "准备接收二进制性能数据 (IPC模式)..."
echo ""

# C版本环境变量设置（IPC优化）
export AERON_IPC_MTU_LENGTH=8192
export AERON_TERM_BUFFER_LENGTH=2097152
export AERON_THREADING_MODE=DEDICATED
export AERON_CONDUCTOR_IDLE_STRATEGY=busy-spin
export AERON_RECEIVER_IDLE_STRATEGY=busy-spin

# IPC专用优化设置
export AERON_PRE_TOUCH_MAPPED_MEMORY=true
export AERON_PERFORM_STORAGE_CHECKS=false
export AERON_IPC_PUBLICATION_TERM_WINDOW_LENGTH=2097152

# 根据权限选择执行方式
if [ "$EUID" -eq 0 ] && [ -n "$SUDO_USER" ]; then
    # 以sudo启动，但保持原用户身份执行C程序
    echo "🔐 以sudo权限执行C程序 (IPC模式)..."
    sudo -u "$SUDO_USER" \
         env AERON_DIR="$AERON_DIR" \
             AERON_IPC_MTU_LENGTH="$AERON_IPC_MTU_LENGTH" \
             AERON_TERM_BUFFER_LENGTH="$AERON_TERM_BUFFER_LENGTH" \
             AERON_THREADING_MODE="$AERON_THREADING_MODE" \
             AERON_CONDUCTOR_IDLE_STRATEGY="$AERON_CONDUCTOR_IDLE_STRATEGY" \
             AERON_RECEIVER_IDLE_STRATEGY="$AERON_RECEIVER_IDLE_STRATEGY" \
             AERON_PRE_TOUCH_MAPPED_MEMORY="$AERON_PRE_TOUCH_MAPPED_MEMORY" \
             AERON_PERFORM_STORAGE_CHECKS="$AERON_PERFORM_STORAGE_CHECKS" \
             AERON_IPC_PUBLICATION_TERM_WINDOW_LENGTH="$AERON_IPC_PUBLICATION_TERM_WINDOW_LENGTH" \
         "$C_BINARY" -t IPC "$@"
else
    # 普通权限执行
    echo "👤 以普通用户权限执行C程序 (IPC模式)..."
    "$C_BINARY" -t IPC "$@"
fi