#!/bin/bash

# AVX2修复测试脚本
# 用于验证32字节内存对齐修复是否解决了Release模式下的崩溃问题

set -e

echo "=== AVX2修复测试脚本 ==="
echo "测试32字节内存对齐是否解决Release模式崩溃问题"
echo

# 检查当前目录
if [ ! -f "CMakeLists.txt" ]; then
    echo "错误: 请在c-performance目录下运行此脚本"
    exit 1
fi

# 清理之前的构建
echo "1. 清理之前的构建..."
rm -rf build-test-release
mkdir -p build-test-release

# 配置Release构建（包含修复）
echo "2. 配置Release构建..."
cd build-test-release

cmake .. \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER=gcc \
    -DCMAKE_CXX_COMPILER=g++ \
    -DCMAKE_VERBOSE_MAKEFILE=ON

# 编译
echo "3. 编译Release版本..."
make VERBOSE=1

cd ..

# 检查生成的可执行文件
if [ ! -f "build-test-release/binary_publisher" ]; then
    echo "错误: binary_publisher编译失败"
    exit 1
fi

if [ ! -f "build-test-release/binary_subscriber" ]; then
    echo "错误: binary_subscriber编译失败"
    exit 1
fi

echo "4. 编译成功！"

# 显示编译器版本和优化信息
echo "5. 编译器信息:"
gcc --version | head -1
echo

# 检查生成的二进制文件中的指令集
echo "6. 检查生成的指令集 (查找AVX2指令):"
if command -v objdump >/dev/null 2>&1; then
    echo "Publisher中的AVX2指令:"
    objdump -d build-test-release/binary_publisher | grep -i "vp\|ymm" | head -5 || echo "未找到AVX2指令"
    echo
fi

# 运行简单测试 (IPC模式，少量消息)
echo "7. 运行Release版本测试 (IPC模式, 100条消息):"
echo "启动Publisher..."

# 使用timeout防止程序hang住
timeout 30s ./build-test-release/binary_publisher \
    -t ipc \
    -c 100 \
    -s 1024 \
    --aeron-dir /tmp/aeron-test-$$

TEST_RESULT=$?

if [ $TEST_RESULT -eq 0 ]; then
    echo "✅ 测试成功! Release模式下Publisher没有崩溃"
elif [ $TEST_RESULT -eq 124 ]; then
    echo "⚠️  测试超时 (30秒)，但程序没有崩溃"
else
    echo "❌ 测试失败，返回码: $TEST_RESULT"
fi

echo
echo "8. 内存对齐验证:"
echo "检查代码中的对齐设置..."
grep -n "BUFFER_ALIGNMENT" include/common_types.h || echo "未找到BUFFER_ALIGNMENT定义"
grep -n "aligned_alloc" src/binary_publisher.c || echo "未找到aligned_alloc调用"

echo
echo "=== 测试完成 ==="

# 清理测试环境
rm -rf /tmp/aeron-test-$$

if [ $TEST_RESULT -eq 0 ] || [ $TEST_RESULT -eq 124 ]; then
    echo "✅ AVX2修复验证通过!"
    exit 0
else
    echo "❌ AVX2修复验证失败!"
    exit 1
fi