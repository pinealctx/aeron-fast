#ifndef COMMON_TYPES_H
#define COMMON_TYPES_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

// 缓存行大小常量
#define CACHE_LINE_SIZE 64
#define BUFFER_ALIGNMENT 16

// 默认配置常量
#define DEFAULT_CHANNEL "aeron:udp?endpoint=localhost:20121"
#define DEFAULT_STREAM_ID 1001
// 消息相关常量
#define TIMESTAMP_SIZE 8
#define MIN_MESSAGE_SIZE TIMESTAMP_SIZE
#define DEFAULT_MESSAGE_SIZE 1024
#define DEFAULT_MESSAGE_COUNT 1000000
#define DEFAULT_TARGET_MESSAGE_COUNT 20000000
#define DEFAULT_FRAGMENT_LIMIT 10

// 传输类型枚举
typedef enum {
    TRANSPORT_UDP,
    TRANSPORT_IPC,
    TRANSPORT_NETWORK_UDP
} transport_type_t;

// 通用配置结构
typedef struct {
    transport_type_t transport_type;
    char channel[256];
    char custom_endpoint[64];
    char aeron_dir[256];
    int32_t stream_id;
    size_t message_size;
    uint64_t message_count;
    uint64_t target_message_count;
    int fragment_limit;
} config_t;

// 错误码定义
typedef enum {
    ERROR_SUCCESS = 0,
    ERROR_INVALID_PARAM = -1,
    ERROR_MEMORY_ALLOC = -2,
    ERROR_MEMORY_ALLOCATION = -2,  // 兼容别名
    ERROR_TIMEOUT = -3,
    ERROR_NETWORK = -4,
    ERROR_FILE_IO = -5
} error_code_t;

#endif // COMMON_TYPES_H