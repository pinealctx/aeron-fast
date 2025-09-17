#!/bin/bash

# 保守配置的C++ MediaDriver启动脚本
# 专门用于调试4秒延迟问题

# 检查可执行文件
AERONMD_EXECUTABLE="./aeronmd_s-amd64"
if [ ! -f "$AERONMD_EXECUTABLE" ]; then
    AERONMD_EXECUTABLE="./aeronmd-amd64"
    if [ ! -f "$AERONMD_EXECUTABLE" ]; then
        echo "❌ 错误: 找不到C++ MediaDriver可执行文件"
        echo "请确保 aeronmd_s-amd64 或 aeronmd-amd64 在当前目录"
        exit 1
    fi
fi

echo "🩺 C++ MediaDriver 保守配置启动 (调试高延迟问题)"
echo "=================================="

# 检查是否已运行
EXISTING_PID=$(pgrep -f "aeronmd")
if [ -n "$EXISTING_PID" ]; then
    echo "⚠️  检测到C++ MediaDriver正在运行 (PID: $EXISTING_PID)"
    echo "建议先停止: ./stop-mediadriver-cpp.sh"
    read -p "是否强制继续? [y/N]: " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# 确保RAM磁盘存在
AERON_DIR="/dev/shm/aeron"
echo "📁 准备Aeron目录: $AERON_DIR"
mkdir -p "$AERON_DIR"

echo "🐌 使用保守配置以避免高延迟:"
echo "   - 使用Yielding策略替代BusySpin"
echo "   - 减小缓冲区大小"
echo "   - 启用详细日志"
echo ""

# 设置保守的环境变量配置
export AERON_DIR="$AERON_DIR"
export AERON_THREADING_MODE="DEDICATED"

# 关键变更：使用yield策略而不是spin
export AERON_CONDUCTOR_IDLE_STRATEGY="yield"
export AERON_RECEIVER_IDLE_STRATEGY="yield"  
export AERON_SENDER_IDLE_STRATEGY="yield"

# 保守的缓冲区设置
export AERON_TERM_BUFFER_SPARSE_FILE="false"
export AERON_PRE_TOUCH_MAPPED_MEMORY="true"
export AERON_SOCKET_SO_SNDBUF="1048576"     # 减小到1MB
export AERON_SOCKET_SO_RCVBUF="1048576"     # 减小到1MB
export AERON_MTU_LENGTH="1408"              # 标准MTU
export AERON_IPC_MTU_LENGTH="1408"
export AERON_TERM_BUFFER_LENGTH="1048576"   # 减小到1MB
export AERON_RCV_INITIAL_WINDOW_LENGTH="1048576"

# 启用详细日志以便调试
export AERON_EVENT_LOG_ENABLED="true"
export AERON_EVENT_LOG="admin"

echo "🚀 启动保守配置的C++ MediaDriver..."

# 启动并显示详细信息
$AERONMD_EXECUTABLE &
MEDIADRIVER_PID=$!

echo "✅ C++ MediaDriver 已启动 (PID: $MEDIADRIVER_PID)"
echo "📊 配置概览:"
echo "   - 可执行文件: $AERONMD_EXECUTABLE"
echo "   - 线程策略: DEDICATED"
echo "   - 空闲策略: YIELD (保守)"
echo "   - 缓冲区: 1MB (保守)"
echo "   - 事件日志: 启用"
echo ""

# 等待启动
sleep 2

# 验证启动状态
if kill -0 $MEDIADRIVER_PID 2>/dev/null; then
    echo "✅ 进程运行正常"
    echo "🔍 监控建议:"
    echo "   实时监控: ./diagnose-cpp-mediadriver.sh"
    echo "   性能测试: ./binary-performance-publisher-ipc.sh -size 256 -count 100000"
    echo "   停止服务: ./stop-mediadriver-cpp.sh"
else
    echo "❌ 进程启动失败，请检查日志"
    echo "日志位置: $AERON_DIR/"
    exit 1
fi

echo ""
echo "🎯 调试目标: 解决4.66秒延迟问题"
echo "预期结果: 延迟应降至毫秒级别"