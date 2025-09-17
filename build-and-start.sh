#!/bin/bash
# Aeron C语言MediaDriver完整构建和部署脚本
set -e

echo "🏗️  Aeron C MediaDriver 构建和部署流程"
echo "=================================="

# 检查Docker
if ! command -v docker &> /dev/null; then
    echo "❌ Docker未安装，请先安装Docker"
    exit 1
fi

# 检查Docker守护进程
if ! docker info &> /dev/null; then
    echo "❌ Docker守护进程未运行，请启动Docker"
    exit 1
fi

echo "✅ Docker环境检查通过"

# 执行构建
echo ""
echo "🔨 开始构建Aeron C MediaDriver..."
if [ -f "build_aeron_driver.sh" ]; then
    chmod +x build_aeron_driver.sh
    ./build_aeron_driver.sh
else
    echo "❌ 找不到build_aeron_driver.sh，请确保在正确目录"
    exit 1
fi

echo ""
echo "🎯 构建完成！检查生成的文件..."

# 检查生成的二进制文件
if ls aeronmd*-amd64 1> /dev/null 2>&1; then
    echo "✅ AMD64 二进制文件:"
    ls -la aeronmd*-amd64
fi

if ls aeronmd*-arm64 1> /dev/null 2>&1; then
    echo "✅ ARM64 二进制文件:"
    ls -la aeronmd*-arm64
fi

echo ""
echo "🚀 现在可以启动MediaDriver:"
echo "   ./start-aeron-mediadriver.sh"
echo ""
echo "📁 或者直接运行二进制文件:"
echo "   ./aeronmd_s-amd64 (静态链接版本，推荐)"
echo "   ./aeronmd-amd64   (动态链接版本)"
echo ""
echo "💡 提示: 使用 -v 参数查看版本信息"
echo "💡 提示: 使用 -h 参数查看帮助信息"
