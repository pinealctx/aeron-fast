#!/bin/bash
# Core Dump 调试脚本

echo "🔧 设置Core Dump调试环境..."

# 1. 开启core dump
echo "设置core dump限制..."
ulimit -c unlimited
echo "当前core dump限制: $(ulimit -c)"

# 2. 设置core dump文件格式
echo "设置core dump文件格式..."
if [ -w /proc/sys/kernel/core_pattern ]; then
    echo "core.%e.%p.%t" > /proc/sys/kernel/core_pattern
    echo "Core dump模式已设置为: $(cat /proc/sys/kernel/core_pattern)"
else
    echo "警告: 无权限修改core_pattern，使用sudo:"
    echo "sudo sysctl kernel.core_pattern=core.%e.%p.%t"
fi

# 3. 检查可执行文件信息
echo ""
echo "📊 检查可执行文件信息..."
BINARY="./binary_subscriber-amd64"
if [ -f "$BINARY" ]; then
    echo "文件存在: $BINARY"
    file "$BINARY"
    echo "权限: $(ls -la "$BINARY")"
    
    # 检查动态库依赖
    echo ""
    echo "📚 动态库依赖:"
    ldd "$BINARY" 2>/dev/null || echo "静态链接或ldd不可用"
    
    # 检查是否有调试信息
    echo ""
    echo "🐛 调试信息:"
    objdump -h "$BINARY" | grep -q "\.debug" && echo "包含调试信息" || echo "无调试信息"
else
    echo "错误: 找不到可执行文件 $BINARY"
    exit 1
fi

# 4. 清理旧的core文件
echo ""
echo "🧹 清理旧core文件..."
rm -f core.* 2>/dev/null
echo "准备生成新的core dump..."

echo ""
echo "💡 使用方法:"
echo "1. 运行: $BINARY -c 10000000"
echo "2. 如果崩溃，查找: ls -la core.*"
echo "3. 调试: gdb $BINARY core.binary_subscriber.*"
echo ""
echo "🔍 GDB常用命令:"
echo "  bt         - 显示调用栈"
echo "  bt full    - 详细调用栈"
echo "  disas      - 显示汇编代码"
echo "  info reg   - 显示寄存器"
echo "  quit       - 退出gdb"