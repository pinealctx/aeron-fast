#include "binary_message.h"
#include <string.h>

// 兼容性字节序转换函数 - 使用手动实现避免CPU指令问题
static inline uint64_t safe_htobe64(uint64_t x) {
    // 手动实现字节序转换，避免使用可能不兼容的CPU指令
    union {
        uint64_t val;
        uint8_t bytes[8];
    } src, dst;
    
    src.val = x;
    dst.bytes[0] = src.bytes[7];
    dst.bytes[1] = src.bytes[6];
    dst.bytes[2] = src.bytes[5];
    dst.bytes[3] = src.bytes[4];
    dst.bytes[4] = src.bytes[3];
    dst.bytes[5] = src.bytes[2];
    dst.bytes[6] = src.bytes[1];
    dst.bytes[7] = src.bytes[0];
    
    return dst.val;
}

static inline uint64_t safe_be64toh(uint64_t x) {
    // 大端转主机序 - 和主机转大端是同样的操作
    return safe_htobe64(x);
}

void create_binary_message(uint8_t *buffer, size_t buffer_size, timestamp_ns_t timestamp) {
    // 确保缓冲区足够大
    if (buffer_size < MIN_MESSAGE_SIZE) {
        return;
    }
    
    // 写入大端时间戳 (前8字节) - 使用安全的手动转换
    volatile uint64_t timestamp_be = safe_htobe64(timestamp);
    // 使用更安全的内存复制，避免优化问题
    for (int i = 0; i < 8; i++) {
        buffer[i] = ((uint8_t*)&timestamp_be)[i];
    }
    
    // 填充数据 (0-255循环) - 与Java版本完全兼容
    for (size_t i = sizeof(uint64_t); i < buffer_size; i++) {
        buffer[i] = (uint8_t)((i - sizeof(uint64_t)) % 256);
    }
}

timestamp_ns_t parse_binary_message_timestamp(const uint8_t *buffer) {
    volatile uint64_t timestamp_be = 0;
    // 使用更安全的内存复制，避免优化问题
    for (int i = 0; i < 8; i++) {
        ((uint8_t*)&timestamp_be)[i] = buffer[i];
    }
    return safe_be64toh(timestamp_be);
}

bool validate_binary_message(const uint8_t *buffer, size_t length) {
    return (buffer != NULL) && (length >= MIN_MESSAGE_SIZE);
}