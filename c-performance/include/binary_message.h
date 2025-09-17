#ifndef BINARY_MESSAGE_H
#define BINARY_MESSAGE_H

#include "common_types.h"
#include "time_utils.h"
#include <arpa/inet.h>

// 二进制消息结构 (与Java版本兼容)
#pragma pack(push, 1)
typedef struct {
    uint64_t timestamp_be;    // 大端时间戳 (8字节)
    uint8_t data[];          // 可变长度数据
} binary_message_t;
#pragma pack(pop)

// 消息创建和解析函数
void create_binary_message(uint8_t *buffer, size_t buffer_size, timestamp_ns_t timestamp);
timestamp_ns_t parse_binary_message_timestamp(const uint8_t *buffer);
bool validate_binary_message(const uint8_t *buffer, size_t length);

#endif // BINARY_MESSAGE_H