#define _GNU_SOURCE
#include "hires_time.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <unistd.h>
#include <sched.h>
#include <pthread.h>
#include <errno.h>

// 将timespec转换为纳秒
static inline timestamp_ns_t timespec_to_ns(const struct timespec* ts) {
    return (timestamp_ns_t)ts->tv_sec * 1000000000ULL + (timestamp_ns_t)ts->tv_nsec;
}

timestamp_ns_t hires_time_now(time_source_t source) {
    struct timespec ts;
    clockid_t clock_id;
    
    switch (source) {
        case TIME_SOURCE_REALTIME:
            clock_id = CLOCK_REALTIME;
            break;
        case TIME_SOURCE_MONOTONIC:
            clock_id = CLOCK_MONOTONIC;
            break;
        case TIME_SOURCE_MONOTONIC_RAW:
#ifdef CLOCK_MONOTONIC_RAW
            clock_id = CLOCK_MONOTONIC_RAW;
#else
            clock_id = CLOCK_MONOTONIC;
#endif
            break;
        case TIME_SOURCE_PROCESS_CPUTIME:
#ifdef CLOCK_PROCESS_CPUTIME_ID
            clock_id = CLOCK_PROCESS_CPUTIME_ID;
#else
            clock_id = CLOCK_MONOTONIC;
#endif
            break;
        case TIME_SOURCE_THREAD_CPUTIME:
#ifdef CLOCK_THREAD_CPUTIME_ID
            clock_id = CLOCK_THREAD_CPUTIME_ID;
#else
            clock_id = CLOCK_MONOTONIC;
#endif
            break;
        default:
            clock_id = CLOCK_MONOTONIC;
            break;
    }
    
    if (clock_gettime(clock_id, &ts) != 0) {
        // 备用方案：使用gettimeofday
        struct timeval tv;
        gettimeofday(&tv, NULL);
        return (timestamp_ns_t)tv.tv_sec * 1000000000ULL + (timestamp_ns_t)tv.tv_usec * 1000ULL;
    }
    
    return timespec_to_ns(&ts);
}

timestamp_ns_t hires_time_unix_nano(void) {
    return hires_time_now(TIME_SOURCE_REALTIME);
}

timestamp_ns_t hires_time_monotonic_nano(void) {
    return hires_time_now(TIME_SOURCE_MONOTONIC);
}

timestamp_ns_t hires_time_monotonic_raw_nano(void) {
    return hires_time_now(TIME_SOURCE_MONOTONIC_RAW);
}

void hires_time_stats_init(time_stats_t* stats) {
    memset(stats, 0, sizeof(time_stats_t));
    stats->min = UINT64_MAX;
    stats->max = 0;
}

void hires_time_stats_update(time_stats_t* stats, timestamp_ns_t value) {
    if (value < stats->min) stats->min = value;
    if (value > stats->max) stats->max = value;
    stats->total += value;
    stats->count++;
}

void hires_time_stats_finalize(time_stats_t* stats) {
    if (stats->count == 0) return;
    
    stats->mean = (double)stats->total / (double)stats->count;
    
    // 注意：这里没有计算方差，因为需要第二次遍历数据
    // 在实际使用中，如果需要方差，应该在收集数据时同时计算
    stats->variance = 0.0;
    stats->std_dev = 0.0;
}

void hires_time_stats_print(const time_stats_t* stats, const char* name) {
    printf("=== %s 统计 ===\n", name);
    printf("  样本数量: %lu\n", stats->count);
    if (stats->count > 0) {
        printf("  最小值: %lu ns (%.2f μs)\n", stats->min, hires_time_ns_to_us(stats->min));
        printf("  最大值: %lu ns (%.2f μs)\n", stats->max, hires_time_ns_to_us(stats->max));
        printf("  平均值: %.2f ns (%.2f μs)\n", stats->mean, hires_time_ns_to_us((timestamp_ns_t)stats->mean));
        printf("  范围: %lu ns (%.2f μs)\n", stats->max - stats->min, hires_time_ns_to_us(stats->max - stats->min));
        if (stats->mean > 0) {
            printf("  抖动比例: %.1fx\n", (double)stats->max / stats->mean);
        }
    }
    printf("\n");
}

void hires_time_check_stability(time_source_t source, int samples, time_stats_t* results) {
    printf("检查 %s 稳定性 (%d 个样本)...\n", hires_time_source_name(source), samples);
    
    hires_time_stats_init(results);
    
    // 预热
    for (int i = 0; i < 100; i++) {
        hires_time_now(source);
    }
    
    timestamp_ns_t* timestamps = malloc(samples * sizeof(timestamp_ns_t));
    if (!timestamps) {
        fprintf(stderr, "内存分配失败\n");
        return;
    }
    
    // 收集时间戳
    for (int i = 0; i < samples; i++) {
        timestamps[i] = hires_time_now(source);
        // 微小延迟，避免连续调用优化
        __asm__ __volatile__("" ::: "memory");
    }
    
    // 计算间隔
    for (int i = 1; i < samples; i++) {
        int64_t interval = hires_time_diff(timestamps[i], timestamps[i-1]);
        if (interval >= 0) {  // 忽略负值（时钟回退）
            hires_time_stats_update(results, (timestamp_ns_t)interval);
        }
    }
    
    hires_time_stats_finalize(results);
    hires_time_stats_print(results, hires_time_source_name(source));
    
    free(timestamps);
}

void hires_time_warmup(void) {
    printf("预热时间获取函数...\n");
    
    // 预热所有时间源
    for (int source = TIME_SOURCE_REALTIME; source <= TIME_SOURCE_THREAD_CPUTIME; source++) {
        for (int i = 0; i < 1000; i++) {
            hires_time_now((time_source_t)source);
        }
    }
    
    printf("预热完成\n");
}

const char* hires_time_source_name(time_source_t source) {
    switch (source) {
        case TIME_SOURCE_REALTIME:
            return "CLOCK_REALTIME";
        case TIME_SOURCE_MONOTONIC:
            return "CLOCK_MONOTONIC";
        case TIME_SOURCE_MONOTONIC_RAW:
            return "CLOCK_MONOTONIC_RAW";
        case TIME_SOURCE_PROCESS_CPUTIME:
            return "CLOCK_PROCESS_CPUTIME_ID";
        case TIME_SOURCE_THREAD_CPUTIME:
            return "CLOCK_THREAD_CPUTIME_ID";
        default:
            return "UNKNOWN";
    }
}

int hires_time_set_cpu_affinity(int core_id) {
#ifdef __linux__
    cpu_set_t cpuset;
    CPU_ZERO(&cpuset);
    CPU_SET(core_id, &cpuset);
    
    int result = sched_setaffinity(0, sizeof(cpu_set_t), &cpuset);
    if (result == 0) {
        printf("成功设置CPU亲和性到核心 %d\n", core_id);
    } else {
        perror("设置CPU亲和性失败");
    }
    return result;
#else
    (void)core_id;  // 避免编译警告
    printf("当前平台不支持CPU亲和性设置\n");
    return -1;
#endif
}

int hires_time_set_realtime_priority(int priority) {
    struct sched_param param;
    param.sched_priority = priority;
    
    int result = sched_setscheduler(0, SCHED_FIFO, &param);
    if (result == 0) {
        printf("成功设置实时优先级: %d\n", priority);
    } else {
        perror("设置实时优先级失败 (可能需要root权限)");
    }
    return result;
}
