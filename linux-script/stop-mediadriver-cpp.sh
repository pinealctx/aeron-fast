#!/bin/bash
# stop-mediadriver-cpp.sh
#
# 🛑 停止Aeron C++ MediaDriver

echo "🛑 停止Aeron C++ MediaDriver..."

# 查找C++ MediaDriver进程 (aeronmd)
PIDS=$(pgrep -f "aeronmd")

if [ -z "$PIDS" ]; then
    echo "ℹ️  没有发现运行中的C++ MediaDriver进程"
    exit 0
fi

echo "📋 发现C++ MediaDriver进程: $PIDS"

# 优雅停止
echo "⏳ 尝试优雅停止..."
kill $PIDS
sleep 3

# 检查是否已停止
REMAINING=$(pgrep -f "aeronmd")
if [ -n "$REMAINING" ]; then
    echo "⚠️  强制停止残留进程: $REMAINING"
    kill -9 $REMAINING
    sleep 1
fi

# 最终检查
FINAL_CHECK=$(pgrep -f "aeronmd")
if [ -z "$FINAL_CHECK" ]; then
    echo "✅ C++ MediaDriver 已成功停止"
    
    # 显示Aeron目录状态
    AERON_DIR="/dev/shm/aeron"
    if [ -d "$AERON_DIR" ]; then
        echo "📁 Aeron目录状态: $AERON_DIR"
        echo "   - 文件数量: $(find $AERON_DIR -type f 2>/dev/null | wc -l)"
        echo "   - 目录大小: $(du -sh $AERON_DIR 2>/dev/null | cut -f1)"
        echo ""
        echo "💡 提示: Aeron目录保留在RAM磁盘中，可手动清理："
        echo "   rm -rf $AERON_DIR/*"
    fi
else
    echo "❌ 仍有进程在运行: $FINAL_CHECK"
    echo "可能需要手动处理或检查系统状态"
    exit 1
fi

echo ""
echo "🔍 验证命令:"
echo "   检查进程: ps aux | grep aeronmd"
echo "   检查目录: ls -la /dev/shm/aeron/"
echo ""
echo "🛑 C++ MediaDriver 停止完成!"