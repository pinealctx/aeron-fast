#!/bin/bash

echo "🔍 C++ MediaDriver 性能诊断工具"
echo "=================================="
echo ""

# 检查C++ MediaDriver进程
MEDIADRIVER_PID=$(pgrep -f "aeronmd")
if [ -z "$MEDIADRIVER_PID" ]; then
    echo "❌ 未找到C++ MediaDriver进程"
    echo "请先启动MediaDriver: ./start-mediadriver-cpp-optimized.sh"
    exit 1
fi

echo "📊 基本进程信息:"
echo "PID: $MEDIADRIVER_PID"
ps -o pid,ppid,start,time,%cpu,%mem,nice,pri,command -p $MEDIADRIVER_PID
echo ""

echo "💾 内存使用详情:"
cat /proc/$MEDIADRIVER_PID/status | grep -E "(VmPeak|VmSize|VmRSS|VmData|VmStk|VmLck)"
echo ""

echo "🔧 CPU亲和性:"
taskset -cp $MEDIADRIVER_PID 2>/dev/null || echo "未设置CPU亲和性"
echo ""

echo "📁 Aeron目录状态:"
AERON_DIR="/dev/shm/aeron"
ls -la $AERON_DIR/ 2>/dev/null || echo "目录不存在或无权限访问"
echo ""
df -h /dev/shm | grep -v "Filesystem"
echo ""

echo "🌡️ 系统资源情况:"
echo "Load Average: $(uptime | awk -F'load average:' '{print $2}')"
echo "Available Memory: $(free -h | grep 'Mem:' | awk '{print $7}')"
echo ""

echo "⚡ 环境变量检查:"
echo "AERON_DIR: ${AERON_DIR}"
echo "AERON_THREADING_MODE: ${AERON_THREADING_MODE:-未设置}"
echo "AERON_CONDUCTOR_IDLE_STRATEGY: ${AERON_CONDUCTOR_IDLE_STRATEGY:-未设置}"
echo ""

echo "🔍 实时性能监控 (按Ctrl+C停止):"
echo "时间戳                CPU%   内存(MB)  状态"
echo "================================================"

# 实时监控循环
trap 'echo ""; echo "监控已停止"; exit 0' INT

while true; do
    if kill -0 $MEDIADRIVER_PID 2>/dev/null; then
        STATS=$(ps -o %cpu,rss,stat --no-headers -p $MEDIADRIVER_PID 2>/dev/null)
        if [ -n "$STATS" ]; then
            CPU=$(echo $STATS | awk '{print $1}')
            MEM_KB=$(echo $STATS | awk '{print $2}')
            STAT=$(echo $STATS | awk '{print $3}')
            MEM_MB=$(echo "scale=1; $MEM_KB/1024" | bc -l)
            
            printf "%-20s %6s%% %8s  %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$CPU" "$MEM_MB" "$STAT"
        else
            echo "$(date '+%Y-%m-%d %H:%M:%S') 进程监控失败"
        fi
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') ❌ MediaDriver进程已停止"
        break
    fi
    sleep 1
done