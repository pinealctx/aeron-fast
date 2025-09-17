#!/bin/bash
# README for Aeron C++ MediaDriver Scripts
# 
# 🚀 Aeron C++ MediaDriver 部署和使用说明

## 📁 部署文件清单

在Linux目标机器的同一目录下部署以下文件：

```
your-deployment-dir/
├── aeronmd_s-amd64                    # C++ MediaDriver静态链接可执行文件 (505KB)
├── start-mediadriver-cpp-optimized.sh # 启动脚本
└── stop-mediadriver-cpp.sh           # 停止脚本
```

## 🔧 使用方法

### 启动MediaDriver
```bash
./start-mediadriver-cpp-optimized.sh
```

**智能启动逻辑**：
- ✅ 如果未运行：启动新的MediaDriver进程
- 🔄 如果已运行：显示运行状态，不重复启动

### 停止MediaDriver
```bash
./stop-mediadriver-cpp.sh
```

**优雅停止流程**：
1. 发送TERM信号优雅停止
2. 等待3秒确认
3. 如需要则强制停止(KILL信号)
4. 显示清理状态

## 📊 监控命令

```bash
# 检查进程状态
ps aux | grep aeronmd

# 查看Aeron目录
ls -la /dev/shm/aeron/

# 查看进程资源使用
top -p $(pgrep aeronmd)
```

## ⚡ 性能配置

C++版本包含以下优化：
- 🎯 **静态链接**: 无外部库依赖
- 🚀 **高优先级**: nice -10 (高于普通进程)
- 📊 **专用线程**: DEDICATED线程模式
- 💾 **内存优化**: 预分配和零拷贝
- 🔧 **Socket优化**: 2MB缓冲区
- 📡 **网络优化**: 8KB MTU

## 🎪 与Java版本对比

| 特性 | Java版本 | C++版本 |
|------|----------|---------|
| 启动时间 | ~2-3秒 | ~0.5秒 |
| 内存占用 | ~2GB堆 | ~20-50MB |
| 延迟 | 极低 | 更低 |
| 部署 | 需JVM | 单一可执行文件 |

## 🔍 故障排除

### 常见问题

1. **权限问题**
   ```bash
   chmod +x aeronmd_s-amd64
   chmod +x *.sh
   ```

2. **RAM磁盘问题**
   ```bash
   # 检查/dev/shm可用性
   df -h /dev/shm
   
   # 手动创建目录
   mkdir -p /dev/shm/aeron
   ```

3. **端口冲突**
   ```bash
   # 检查UDP端口使用
   netstat -ulnp | grep 4050
   ```

## 📞 支持

如有问题，请检查：
- 系统日志: `journalctl -f`
- Aeron日志: `/dev/shm/aeron/`目录
- 进程状态: `ps aux | grep aeronmd`