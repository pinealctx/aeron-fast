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