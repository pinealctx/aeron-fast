#ifndef PERFORMANCE_STATS_H
#define PERFORMANCE_STATS_H

#include "common_types.h"
#include "time_utils.h"

// 缓存行对齐的统计计数器
typedef struct __attribute__((aligned(CACHE_LINE_SIZE))) {
    volatile uint64_t message_count;
    char padding1[CACHE_LINE_SIZE - sizeof(uint64_t)];
    
    volatile uint64_t total_latency;
    char padding2[CACHE_LINE_SIZE - sizeof(uint64_t)];
    
    volatile uint64_t min_latency;
    volatile uint64_t max_latency;
    char padding3[CACHE_LINE_SIZE - 2 * sizeof(uint64_t)];
    
    volatile uint64_t back_pressure_count;
    volatile uint64_t retry_count;
    char padding4[CACHE_LINE_SIZE - 2 * sizeof(uint64_t)];
} stats_counters_t;

// 延迟记录数组 (前1000条消息)
#define DETAILED_RECORD_COUNT 1000
typedef struct {
    timestamp_ns_t send_times[DETAILED_RECORD_COUNT];
    timestamp_ns_t receive_times[DETAILED_RECORD_COUNT];
    timestamp_ns_t latencies[DETAILED_RECORD_COUNT];
    size_t recorded_count;
} detailed_records_t;

// 简化的统计结构 (暂时不使用HdrHistogram以简化实现)
typedef struct {
    stats_counters_t counters;
    detailed_records_t records;
    timestamp_ns_t test_start_time;
    timestamp_ns_t first_message_time;
    timestamp_ns_t last_message_time;
    
    // 最低延迟详细信息
    uint64_t min_latency_message_index;
    timestamp_ns_t min_latency_send_time;
    timestamp_ns_t min_latency_receive_time;
    
    // 延迟分布统计 (简化版本)
    uint64_t latency_buckets[10];  // 延迟分布桶
    uint64_t latency_bucket_limits[10];  // 桶的上限 (微秒)
} performance_stats_t;

// 统计函数
performance_stats_t* create_performance_stats(void);
void destroy_performance_stats(performance_stats_t *stats);
void record_latency(performance_stats_t *stats, uint64_t latency_ns);
void record_message_latency(performance_stats_t *stats, timestamp_ns_t send_time, timestamp_ns_t receive_time);
void record_send_latency(performance_stats_t *stats, timestamp_ns_t send_latency);
void record_back_pressure(performance_stats_t *stats);
void record_retry(performance_stats_t *stats);
void print_performance_summary(const performance_stats_t *stats, const config_t *config, const char *role);
void print_detailed_records(const performance_stats_t *stats);
void print_latency_distribution(const performance_stats_t *stats);

#endif // PERFORMANCE_STATS_H