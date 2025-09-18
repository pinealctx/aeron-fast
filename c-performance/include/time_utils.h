#ifndef TIME_UTILS_H
#define TIME_UTILS_H

#include <stdint.h>
#include <time.h>
#include <inttypes.h>

// 时间戳类型
typedef uint64_t timestamp_ns_t;

// 跨平台的uint64_t格式化宏
#ifndef PRIu64
#define PRIu64 "llu"
#endif

// 获取高精度时间戳 (纳秒)
static inline timestamp_ns_t get_timestamp_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    return (timestamp_ns_t)ts.tv_sec * 1000000000ULL + (timestamp_ns_t)ts.tv_nsec;
}

// 获取单调时钟 (用于延迟测量)
static inline timestamp_ns_t get_monotonic_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (timestamp_ns_t)ts.tv_sec * 1000000000ULL + (timestamp_ns_t)ts.tv_nsec;
}

// RDTSC时间戳 (可选高性能方案) - 使用安全的回退机制
static inline uint64_t rdtsc(void) {
    // 直接使用clock_gettime避免CPU兼容性问题
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000000000ULL + (uint64_t)ts.tv_nsec;
}

// 时间戳转换工具
timestamp_ns_t us_to_ns(uint64_t microseconds);
uint64_t ns_to_us(timestamp_ns_t nanoseconds);
timestamp_ns_t ms_to_ns(uint64_t milliseconds);

#endif // TIME_UTILS_H