#!/bin/bash
# Aeron C语言MediaDriver启动脚本 - Linux版本
# 对应Java版本的 start-mediadriver.sh

# 设置Aeron目录 (使用RAM磁盘以获得最佳性能)
export AERON_DIR="/dev/shm/aeron"

# 确保目录存在且权限正确
if [ ! -d "$AERON_DIR" ]; then
    mkdir -p "$AERON_DIR"
elif [ ! -w "$AERON_DIR" ]; then
    echo "⚠️  Aeron目录权限不足，尝试修复..."
    if sudo chown $USER:$USER "$AERON_DIR" 2>/dev/null; then
        echo "✅ 权限修复成功"
    else
        echo "❌ 权限修复失败，请手动执行:"
        echo "   sudo chown $USER:$USER $AERON_DIR"
        echo "   sudo chmod 755 $AERON_DIR"
        exit 1
    fi
fi

# 检测架构并选择对应的可执行文件
ARCH=$(uname -m)
case "$ARCH" in
    "x86_64")
        BINARY_SUFFIX="amd64"
        ;;
    "aarch64" | "arm64")
        BINARY_SUFFIX="arm64"
        ;;
    *)
        echo "❌ 不支持的架构: $ARCH"
        exit 1
        ;;
esac

# 优先使用静态链接版本
AERONMD_BINARY="./aeronmd_s-${BINARY_SUFFIX}"
if [ ! -f "$AERONMD_BINARY" ]; then
    # 回退到动态链接版本
    AERONMD_BINARY="./aeronmd-${BINARY_SUFFIX}"
    if [ ! -f "$AERONMD_BINARY" ]; then
        echo "❌ 找不到对应架构的MediaDriver可执行文件"
        echo "期望文件: aeronmd_s-${BINARY_SUFFIX} 或 aeronmd-${BINARY_SUFFIX}"
        echo "当前目录: $(pwd)"
        echo "可用文件:"
        ls -la aeronmd* 2>/dev/null || echo "  无aeronmd*文件"
        exit 1
    fi
fi

# 检查可执行权限
if [ ! -x "$AERONMD_BINARY" ]; then
    echo "🔧 修复执行权限..."
    chmod +x "$AERONMD_BINARY"
fi

echo "🚀 启动Aeron C语言MediaDriver..."
echo "架构: $ARCH ($BINARY_SUFFIX)"
echo "可执行文件: $AERONMD_BINARY"
echo "Aeron目录: $AERON_DIR"
echo "使用RAM磁盘以获得最佳性能"
echo ""

# 显示版本信息
echo "📋 MediaDriver版本信息:"
"$AERONMD_BINARY" -v
echo ""

# 设置C语言MediaDriver的环境变量 (对应Java版本的系统属性)
export AERON_DRIVER_TERMINATION_HOOK=true
export AERON_TERM_BUFFER_SPARSE_FILE=false
export AERON_PRE_TOUCH_MAPPED_MEMORY=true
export AERON_SOCKET_SO_SNDBUF=2097152
export AERON_SOCKET_SO_RCVBUF=2097152
export AERON_RCV_INITIAL_WINDOW_LENGTH=2097152

# 设置性能优化参数
export AERON_THREADING_MODE=DEDICATED  # 专用线程模式
export AERON_CONDUCTOR_IDLE_STRATEGY=SPIN  # 自旋等待策略
export AERON_SENDER_IDLE_STRATEGY=NOOP     # 发送器空闲策略
export AERON_RECEIVER_IDLE_STRATEGY=NOOP   # 接收器空闲策略

# 可选：绑定到特定CPU核心以减少上下文切换
# taskset -c 0-3 "$AERONMD_BINARY"

echo "🔧 环境变量配置:"
echo "  AERON_DIR=$AERON_DIR"
echo "  AERON_THREADING_MODE=$AERON_THREADING_MODE"
echo "  AERON_CONDUCTOR_IDLE_STRATEGY=$AERON_CONDUCTOR_IDLE_STRATEGY"
echo ""

# 启动MediaDriver
echo "▶️  启动MediaDriver (Ctrl+C 停止)..."
"$AERONMD_BINARY" "$@"

echo "MediaDriver已停止"
