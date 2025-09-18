#!/bin/bash

# 在Linux上调试Release版本崩溃的脚本

echo "=== 调试Release版本崩溃问题 ==="

# 首先编译一个专门用于调试的版本，保留调试信息但使用Release优化
echo "编译带调试信息的Release版本..."

cd c-performance

# 创建专门的调试构建目录
mkdir -p build-debug-release

# 使用特殊的CMake配置：Release优化 + 调试信息
cat > build-debug-release/CMakeLists.txt << 'EOF'
cmake_minimum_required(VERSION 3.16)
project(aeron-c-performance)

# 特殊的调试Release配置：保留调试信息但使用Release优化
set(CMAKE_BUILD_TYPE Release)
set(CMAKE_C_FLAGS_RELEASE "-O2 -g -DNDEBUG")
set(CMAKE_CXX_FLAGS_RELEASE "-O2 -g -DNDEBUG")

# 添加详细的编译信息
set(CMAKE_VERBOSE_MAKEFILE ON)

# 包含原始的CMake配置
include(../CMakeLists.txt)
EOF

cd build-debug-release

# 配置和编译
cmake .. -DCMAKE_BUILD_TYPE=Release
make VERBOSE=1 binary_publisher 2>&1 | tee compile.log

echo ""
echo "=== 检查生成的二进制文件 ==="
ls -la binary_publisher

# 检查CPU指令支持
echo ""
echo "=== 检查CPU支持的指令集 ==="
if [ -f /proc/cpuinfo ]; then
    echo "CPU信息:"
    grep -E "(flags|Features)" /proc/cpuinfo | head -1
    
    echo ""
    echo "支持的SIMD指令集:"
    grep -o -E "(sse|sse2|sse3|ssse3|sse4|avx|avx2|avx512)" /proc/cpuinfo | sort | uniq
fi

# 反汇编关键函数
echo ""
echo "=== 反汇编run_publisher函数 ==="
if command -v objdump >/dev/null 2>&1; then
    objdump -d binary_publisher | grep -A 50 "run_publisher" | head -100
fi

echo ""
echo "=== 准备GDB调试 ==="
echo "现在可以使用以下命令调试:"
echo "gdb ./binary_publisher"
echo ""
echo "在GDB中使用这些命令:"
echo "set args -t ipc"
echo "run"
echo "# 当崩溃时："
echo "bt"
echo "info registers"
echo "disassemble"
echo "x/20i \$pc-40"

echo ""
echo "=== 自动运行并捕获崩溃 ==="
echo "尝试运行程序并捕获崩溃信息..."

# 设置core dump
ulimit -c unlimited

# 运行程序并捕获崩溃
timeout 10s ./binary_publisher -t ipc -c 100 2>&1 || echo "程序已退出（可能崩溃）"

# 检查是否有core dump
if [ -f core ] || [ -f core.* ]; then
    echo ""
    echo "=== 发现core dump，使用GDB自动分析 ==="
    CORE_FILE=$(ls -t core* 2>/dev/null | head -1)
    if [ -n "$CORE_FILE" ]; then
        echo "分析core dump: $CORE_FILE"
        
        # 创建GDB脚本
        cat > gdb_auto.script << 'GDBEOF'
set pagination off
set print pretty on
set print array on
set print address on
echo === 崩溃时的栈回溯 ===\n
bt
echo \n=== 寄存器状态 ===\n
info registers
echo \n=== 崩溃位置的反汇编 ===\n
disassemble
echo \n=== 崩溃位置前后的指令 ===\n
x/20i $pc-40
echo \n=== 内存状态 ===\n
info proc mappings
echo \n=== 所有线程的栈回溯 ===\n
thread apply all bt
quit
GDBEOF

        gdb -batch -x gdb_auto.script ./binary_publisher "$CORE_FILE" 2>&1 | tee crash_analysis.log
        
        echo ""
        echo "崩溃分析完成，结果保存在 crash_analysis.log"
    fi
fi

echo ""
echo "调试脚本执行完成。"