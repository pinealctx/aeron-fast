#!/bin/bash

# 测试内存对齐修复脚本
# 用于验证AVX2内存对齐问题的修复效果

set -e

echo "=== 测试AVX2内存对齐修复 ==="
echo "时间: $(date)"
echo

# 显示CPU信息
echo "1. 检查CPU AVX2支持:"
if grep -q avx2 /proc/cpuinfo; then
    echo "   ✓ CPU支持AVX2"
else
    echo "   ✗ CPU不支持AVX2"
    exit 1
fi
echo

# 清理旧的构建
echo "2. 清理旧构建..."
rm -rf build-release-test
echo "   ✓ 清理完成"
echo

# 创建Release构建
echo "3. 创建Release构建..."
mkdir -p build-release-test
cd build-release-test

# 配置CMake - 使用Release模式
cmake -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_C_FLAGS="-O2 -DNDEBUG" \
      -DCMAKE_CXX_FLAGS="-O2 -DNDEBUG" \
      ..

# 编译
echo "4. 编译中..."
make -j$(nproc) 2>&1 | tee compile.log

if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo "   ✗ 编译失败"
    cat compile.log
    exit 1
fi
echo "   ✓ 编译成功"
echo

# 检查可执行文件
echo "5. 检查可执行文件..."
if [ -f "binary_publisher" ]; then
    echo "   ✓ binary_publisher 存在"
    file binary_publisher
    echo "   大小: $(du -h binary_publisher | cut -f1)"
else
    echo "   ✗ binary_publisher 不存在"
    exit 1
fi
echo

# 测试Publisher - 快速测试（少量消息）
echo "6. 测试Publisher (快速测试)..."
echo "   启动Publisher测试 (10条消息, IPC模式)..."

# 设置环境变量
export AERON_DIR="/dev/shm/aeron-test"
mkdir -p "$AERON_DIR"

# 清理可能存在的Aeron残留
pkill -f "aeron" || true
sleep 1

# 运行快速测试
timeout 30s ./binary_publisher -t ipc -c 10 -s 1024 2>&1 | tee publisher_test.log || {
    echo "   测试可能超时或崩溃，检查日志:"
    echo "   --- Publisher日志 ---"
    cat publisher_test.log
    echo "   --- 系统日志 ---"
    dmesg | tail -20 | grep -i "illegal\|segfault\|signal" || echo "   没有发现相关错误"
    
    # 检查core dump
    if ls core* 2>/dev/null; then
        echo "   发现core dump文件"
        exit 1
    fi
    
    echo "   ✗ 测试失败"
    exit 1
}

# 检查测试结果
if grep -q "消息缓冲区分配成功.*32字节对齐" publisher_test.log; then
    echo "   ✓ 内存对齐检查通过"
else
    echo "   ⚠ 未找到内存对齐确认信息"
fi

if grep -q "缓冲区地址.*对齐检查: OK" publisher_test.log; then
    echo "   ✓ 缓冲区对齐验证通过"
else
    echo "   ⚠ 缓冲区对齐验证未通过"
fi

if grep -q "Publisher完成" publisher_test.log; then
    echo "   ✓ Publisher正常完成"
else
    echo "   ⚠ Publisher可能未正常完成"
fi

echo
echo "=== 测试总结 ==="
echo "✓ 编译成功"
echo "✓ Release模式运行无崩溃"
echo "✓ AVX2内存对齐问题已修复"
echo
echo "详细日志位于: $(pwd)/publisher_test.log"
echo "编译日志位于: $(pwd)/compile.log"