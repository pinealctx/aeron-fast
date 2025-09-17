#ifndef TIME_UTILS_H
#define TIME_UTILS_H

#include <stdint.h>
#include <time.h>

// 时间戳类型
typedef uint64_t timestamp_ns_t;

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

// RDTSC时间戳 (可选高性能方案)
static inline uint64_t rdtsc(void) {
    uint32_t hi, lo;
    __asm__ __volatile__ ("rdtsc" : "=a"(lo), "=d"(hi));
    return ((uint64_t)hi << 32) | lo;
}

// 时间戳转换工具
timestamp_ns_t us_to_ns(uint64_t microseconds);
uint64_t ns_to_us(timestamp_ns_t nanoseconds);
timestamp_ns_t ms_to_ns(uint64_t milliseconds);

// 预热时间函数 (等价于Java的JNI预热)
void warmup_time_functions(int iterations);

#endif // TIME_UTILS_H