#include "binary_message.h"
#include <string.h>

void create_binary_message(uint8_t *buffer, size_t buffer_size, timestamp_ns_t timestamp) {
    // 确保缓冲区足够大
    if (buffer_size < MIN_MESSAGE_SIZE) {
        return;
    }
    
    // 写入大端时间戳 (前8字节)
    uint64_t timestamp_be = htobe64(timestamp);
    memcpy(buffer, &timestamp_be, sizeof(uint64_t));
    
    // 填充数据 (0-255循环) - 与Java版本完全兼容
    for (size_t i = sizeof(uint64_t); i < buffer_size; i++) {
        buffer[i] = (uint8_t)((i - sizeof(uint64_t)) % 256);
    }
}

timestamp_ns_t parse_binary_message_timestamp(const uint8_t *buffer) {
    uint64_t timestamp_be;
    memcpy(&timestamp_be, buffer, sizeof(uint64_t));
    return be64toh(timestamp_be);
}

bool validate_binary_message(const uint8_t *buffer, size_t length) {
    return (buffer != NULL) && (length >= MIN_MESSAGE_SIZE);
}