#include "time_utils.h"
#include <stdio.h>

// 时间戳转换工具
timestamp_ns_t us_to_ns(uint64_t microseconds) {
    return microseconds * 1000ULL;
}

uint64_t ns_to_us(timestamp_ns_t nanoseconds) {
    return nanoseconds / 1000ULL;
}

timestamp_ns_t ms_to_ns(uint64_t milliseconds) {
    return milliseconds * 1000000ULL;
}

// 预热时间函数 (等价于Java的JNI预热)
void warmup_time_functions(int iterations) {
    printf("🔥 Time functions warmup...\n");
    
    timestamp_ns_t start = get_timestamp_ns();
    volatile timestamp_ns_t dummy;
    
    for (int i = 0; i < iterations; i++) {
        dummy = get_timestamp_ns();
        dummy = get_monotonic_ns();
        dummy = rdtsc();
    }
    
    timestamp_ns_t end = get_timestamp_ns();
    double duration_ms = (double)(end - start) / 1000000.0;
    
    printf("✅ Time functions warmup completed: %d iterations in %.2f ms\n", 
           iterations, duration_ms);
    
    // 避免编译器优化掉dummy变量
    (void)dummy;
}