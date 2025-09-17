# Aeron C 高性能二进制消息测试

这是Java版本`BinaryPerformancePublisher`和`BinaryPerformanceSubscriber`的C语言实现，基于Aeron C API构建，专为超低延迟、高吞吐量的性能测试而设计。

## 功能特性

### 核心功能
- **高精度时间测量**: 使用`clock_gettime(CLOCK_REALTIME)`获取纳秒级时间戳
- **二进制消息格式**: 与Java版本兼容的消息格式（8字节时间戳 + 填充数据）
- **原子性能统计**: 线程安全的延迟和吞吐量统计
- **多传输模式**: 支持UDP、IPC、NETWORK_UDP传输
- **实时监控**: 每秒更新的性能统计报告
- **命令行配置**: 灵活的参数配置系统

### 性能优化
- **Cache-line对齐**: 统计计数器按缓存行对齐，减少False Sharing
- **原子操作**: 使用`stdatomic.h`实现无锁统计更新
- **编译器优化**: 支持`-march=native`和`-O3`优化
- **内存预热**: 时间函数预热机制提高测量精度
- **最小系统调用**: 优化的轮询和发送逻辑

## 项目结构

```
c-performance/
├── include/                    # 头文件
│   ├── common_types.h         # 通用类型定义
│   ├── time_utils.h           # 时间工具函数
│   ├── binary_message.h       # 二进制消息处理
│   ├── performance_stats.h    # 性能统计模块
│   └── config_parser.h        # 配置解析器
├── src/                       # 源文件
│   ├── time_utils.c           # 时间函数实现
│   ├── binary_message.c       # 消息格式处理
│   ├── performance_stats.c    # 统计功能实现
│   ├── config_parser.c        # 参数解析实现
│   ├── binary_publisher.c     # Publisher主程序
│   └── binary_subscriber.c    # Subscriber主程序
├── CMakeLists.txt             # CMake构建配置
├── build.sh                   # 自动构建脚本
└── README.md                  # 项目文档
```

## 编译构建

### 前置条件

1. **Aeron C库**: 确保Aeron已编译并安装
```bash
cd /path/to/aeron
./gradlew clean build publishToMavenLocal
```

2. **系统要求**:
   - CMake 3.16+
   - GCC 或 Clang (支持C11)
   - POSIX兼容系统 (Linux/macOS)

### 快速构建

```bash
# 使用自动构建脚本
./build.sh

# 手动构建
mkdir build && cd build
cmake -DCMAKE_BUILD_TYPE=Release ..
make -j$(nproc)
```

### 构建选项

```bash
# Debug版本
./build.sh --debug

# 清理后重新构建
./build.sh --clean

# 指定Aeron安装目录
./build.sh --aeron-root /opt/aeron

# 详细构建输出
./build.sh --verbose
```

## 使用方法

### 基本用法

**启动Subscriber (终端1):**
```bash
./bin/binary_subscriber
```

**启动Publisher (终端2):**
```bash
./bin/binary_publisher
```

### Publisher参数

```bash
./bin/binary_publisher [选项]

选项:
  -s, --size <bytes>        消息大小 (默认: 1024)
  -c, --count <num>         测试消息数 (默认: 10000000)
  -t, --transport <方式>    传输方式: UDP, IPC 或 NETWORK_UDP
  -b, --bind <IP>           绑定到指定IP地址 (Publisher监听地址)
  -h, --help                显示帮助信息
```

### Subscriber参数

```bash
./bin/binary_subscriber [选项]

选项:
  -c, --count <数量>        目标消息数量 (默认: 50000000)
  -t, --transport <方式>    传输方式: UDP, IPC 或 NETWORK_UDP
  -o, --connect <IP>        连接到Publisher的IP地址
  -h, --help                显示帮助信息
```

## 使用示例

### 1. 本地高性能测试 (IPC模式)

```bash
# 超低延迟本机测试
# 终端1: Subscriber
./bin/binary_subscriber -t IPC -c 10000000

# 终端2: Publisher  
./bin/binary_publisher -t IPC -c 10000000 -s 512
```

### 2. 网络性能测试

```bash
# 服务器端 (IP: 192.168.0.106)
./bin/binary_subscriber -connect 0.0.0.0 -c 50000000

# 客户端
./bin/binary_publisher -bind 192.168.0.106 -c 50000000 -s 1024
```

### 3. 大消息吞吐量测试

```bash
# 测试大消息的吞吐量
./bin/binary_subscriber -c 1000000
./bin/binary_publisher -c 1000000 -s 65536  # 64KB消息
```

## 性能特性

### 延迟测量
- **端到端延迟**: 从发送到接收的完整时间测量
- **纳秒精度**: 使用高精度系统时钟
- **统计分布**: 最小、最大、平均延迟统计
- **实时监控**: 每秒更新的延迟报告

### 吞吐量统计
- **消息速率**: 消息/秒统计
- **带宽统计**: MB/秒带宽使用率
- **实时显示**: 滚动更新的性能指标
- **背压监控**: 背压事件统计

### 输出示例

```
=== Aeron C 版本 BinaryPerformancePublisher ===
传输方式: IPC
Channel: aeron:ipc?term-length=1048576
Stream ID: 1001
消息大小: 1024 bytes

开始发送 10000000 条消息，每条 1024 字节...
消息:     100000, 字节:   102400000, 速率:   987654 消息/秒,  964.5 MB/秒
消息:     200000, 字节:   204800000, 速率:  1045321 消息/秒, 1020.8 MB/秒
...

=== 最终性能统计 ===
总消息数:     10000000
总字节数:     10240000000
总耗时:       9.573 秒
平均吞吐量:   1044589.23 消息/秒
平均带宽:     1020.10 MB/秒
```

## 与Java版本的差异

### 相同功能
- ✅ 相同的二进制消息格式 (8字节时间戳 + 填充)
- ✅ 端到端延迟测量
- ✅ 吞吐量和带宽统计
- ✅ 多传输方式支持 (UDP/IPC/NETWORK_UDP)
- ✅ 可配置消息大小和数量

### C版本优势
- 🚀 **更低系统开销**: 无JVM垃圾收集延迟
- 🚀 **原生性能**: 直接编译为机器码
- 🚀 **更少内存占用**: 无Java运行时内存开销
- 🚀 **确定性延迟**: 无GC停顿影响

### 实现差异
- **时间测量**: `clock_gettime()` 替代 `TimeX.unixNanoJNI()`
- **统计实现**: 原子操作替代Java concurrent包
- **内存管理**: 手动内存管理，优化缓存行对齐
- **配置系统**: C风格命令行解析

## 性能调优建议

### 系统级优化
```bash
# 设置CPU频率策略
echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor

# 禁用CPU节能
sudo cpupower frequency-set -g performance

# 增大网络缓冲区
echo 'net.core.rmem_max = 134217728' | sudo tee -a /etc/sysctl.conf
echo 'net.core.wmem_max = 134217728' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

### 应用级优化
- **CPU亲和性**: 使用`taskset`绑定特定CPU核心
- **内存锁定**: 使用`mlockall()`锁定内存页面
- **实时优先级**: 使用`SCHED_FIFO`调度策略
- **NUMA优化**: 绑定到特定NUMA节点

## 故障排除

### 常见问题

1. **找不到Aeron库**
```bash
# 设置库路径
export LD_LIBRARY_PATH=/path/to/aeron/lib:$LD_LIBRARY_PATH

# 或使用--aeron-root指定路径
./build.sh --aeron-root /path/to/aeron
```

2. **权限不足**
```bash
# 添加执行权限
chmod +x build.sh
chmod +x bin/binary_*
```

3. **连接超时**
```bash
# 检查防火墙设置
sudo ufw allow 20121

# 检查网络连接
netstat -an | grep 20121
```

## 开发说明

### 代码架构
- **模块化设计**: 功能分离，便于维护和测试
- **错误处理**: 完整的错误检查和资源清理
- **线程安全**: 原子操作确保多线程安全
- **性能优先**: 关键路径优化，最小化延迟

### 扩展开发
- 添加新的传输协议支持
- 实现更多统计指标
- 集成其他时间测量方法
- 添加配置文件支持

## 许可证

本项目遵循与原Aeron项目相同的Apache License 2.0许可证。

## 贡献

欢迎提交Issue和Pull Request来改进这个C语言实现！