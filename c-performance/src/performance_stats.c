#include "performance_stats.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdatomic.h>

int init_performance_stats(performance_stats_t *stats) {
    if (!stats) {
        return ERROR_INVALID_PARAM;
    }
    
    // 清零所有统计数据
    memset(stats, 0, sizeof(performance_stats_t));
    
    // 初始化最小延迟为最大值
    stats->counters.min_latency = UINT64_MAX;
    
    // 初始化延迟分布桶 (微秒)
    stats->latency_bucket_limits[0] = 1;     // <= 1μs
    stats->latency_bucket_limits[1] = 5;     // <= 5μs
    stats->latency_bucket_limits[2] = 10;    // <= 10μs
    stats->latency_bucket_limits[3] = 20;    // <= 20μs
    stats->latency_bucket_limits[4] = 50;    // <= 50μs
    stats->latency_bucket_limits[5] = 100;   // <= 100μs
    stats->latency_bucket_limits[6] = 500;   // <= 500μs
    stats->latency_bucket_limits[7] = 1000;  // <= 1ms
    stats->latency_bucket_limits[8] = 10000; // <= 10ms
    stats->latency_bucket_limits[9] = UINT64_MAX; // > 10ms
    
    return ERROR_SUCCESS;
}

void destroy_performance_stats(performance_stats_t *stats) {
    // C版本无需特殊清理，HdrHistogram在后续版本中添加
    (void)stats;
}

void record_message_latency(performance_stats_t *stats, timestamp_ns_t send_time, timestamp_ns_t receive_time) {
    if (!stats) return;
    
    timestamp_ns_t latency = receive_time - send_time;
    uint64_t message_index = __atomic_fetch_add(&stats->counters.message_count, 1, __ATOMIC_RELAXED);
    
    // 记录第一条和最后一条消息时间
    if (message_index == 0) {
        stats->first_message_time = receive_time;
    }
    stats->last_message_time = receive_time;
    
    // 更新总延迟
    __atomic_fetch_add(&stats->counters.total_latency, latency, __ATOMIC_RELAXED);
    
    // 更新最小延迟 (使用compare-and-swap循环)
    uint64_t current_min = __atomic_load_n(&stats->counters.min_latency, __ATOMIC_RELAXED);
    while (latency < current_min) {
        if (__atomic_compare_exchange_n(&stats->counters.min_latency, &current_min, latency, 
                                      false, __ATOMIC_RELAXED, __ATOMIC_RELAXED)) {
            // 记录最低延迟的详细信息
            stats->min_latency_message_index = message_index + 1;
            stats->min_latency_send_time = send_time;
            stats->min_latency_receive_time = receive_time;
            break;
        }
    }
    
    // 更新最大延迟
    uint64_t current_max = __atomic_load_n(&stats->counters.max_latency, __ATOMIC_RELAXED);
    while (latency > current_max) {
        if (__atomic_compare_exchange_n(&stats->counters.max_latency, &current_max, latency,
                                      false, __ATOMIC_RELAXED, __ATOMIC_RELAXED)) {
            break;
        }
    }
    
    // 记录前1000条消息的详细信息
    if (message_index < DETAILED_RECORD_COUNT) {
        stats->records.send_times[message_index] = send_time;
        stats->records.receive_times[message_index] = receive_time;
        stats->records.latencies[message_index] = latency;
        stats->records.recorded_count = message_index + 1;
    }
    
    // 更新延迟分布桶
    uint64_t latency_us = latency / 1000;  // 转换为微秒
    for (int i = 0; i < 10; i++) {
        if (latency_us <= stats->latency_bucket_limits[i]) {
            __atomic_fetch_add(&stats->latency_buckets[i], 1, __ATOMIC_RELAXED);
            break;
        }
    }
}

void record_send_latency(performance_stats_t *stats, timestamp_ns_t send_latency) {
    // 发送延迟记录 - 在后续版本中实现更详细的统计
    (void)stats;
    (void)send_latency;
}

void record_back_pressure(performance_stats_t *stats) {
    if (stats) {
        __atomic_fetch_add(&stats->counters.back_pressure_count, 1, __ATOMIC_RELAXED);
    }
}

void record_retry(performance_stats_t *stats) {
    if (stats) {
        __atomic_fetch_add(&stats->counters.retry_count, 1, __ATOMIC_RELAXED);
    }
}

void print_performance_summary(const performance_stats_t *stats, const config_t *config, const char *role) {
    if (!stats || !config || !role) return;
    
    uint64_t final_count = __atomic_load_n(&stats->counters.message_count, __ATOMIC_ACQUIRE);
    uint64_t total_latency = __atomic_load_n(&stats->counters.total_latency, __ATOMIC_ACQUIRE);
    uint64_t min_latency = __atomic_load_n(&stats->counters.min_latency, __ATOMIC_ACQUIRE);
    uint64_t max_latency = __atomic_load_n(&stats->counters.max_latency, __ATOMIC_ACQUIRE);
    uint64_t back_pressure_count = __atomic_load_n(&stats->counters.back_pressure_count, __ATOMIC_ACQUIRE);
    uint64_t retry_count = __atomic_load_n(&stats->counters.retry_count, __ATOMIC_ACQUIRE);
    
    timestamp_ns_t time_span_ns = stats->last_message_time - stats->first_message_time;
    double time_span_sec = (double)time_span_ns / 1000000000.0;
    double messages_per_sec = (double)final_count / time_span_sec;
    double avg_latency_us = (double)total_latency / (double)final_count / 1000.0;
    double min_latency_us = (double)min_latency / 1000.0;
    double max_latency_us = (double)max_latency / 1000.0;
    double throughput_mbps = (messages_per_sec * config->message_size) / (1024 * 1024);
    
    printf("\n\n=== 📊 %s 性能统计报告 ===\n", role);
    printf("总处理消息数: %lu 条\n", final_count);
    printf("消息大小: %zu bytes\n", config->message_size);
    printf("测试总时长: %.3f 秒\n", time_span_sec);
    printf("\n");
    
    printf("📈 吞吐量性能:\n");
    printf("  消息吞吐量: %.0f msg/sec\n", messages_per_sec);
    printf("  数据吞吐量: %.2f MB/sec\n", throughput_mbps);
    printf("\n");
    
    if (strcmp(role, "Subscriber") == 0) {
        printf("⚡ 端到端延迟统计 (receiveTime - sendTime):\n");
        printf("  平均延迟: %.2f μs\n", avg_latency_us);
        printf("  最小延迟: %.2f μs (消息#%lu)\n", min_latency_us, stats->min_latency_message_index);
        printf("  最大延迟: %.2f μs\n", max_latency_us);
        printf("\n");
        
        printf("📊 延迟分布统计:\n");
        for (int i = 0; i < 10; i++) {
            uint64_t count = __atomic_load_n(&stats->latency_buckets[i], __ATOMIC_RELAXED);
            double percentage = (double)count * 100.0 / (double)final_count;
            if (i == 9) {
                printf("  > %lu μs: %lu (%.2f%%)\n", stats->latency_bucket_limits[8], count, percentage);
            } else {
                printf("  ≤ %lu μs: %lu (%.2f%%)\n", stats->latency_bucket_limits[i], count, percentage);
            }
        }
    } else {
        printf("📊 发送统计:\n");
        printf("  背压次数: %lu 次\n", back_pressure_count);
        printf("  重试总数: %lu 次\n", retry_count);
        if (final_count > 0) {
            printf("  平均重试: %.2f 次/消息\n", (double)retry_count / (double)final_count);
            printf("  背压率: %.2f%%\n", (double)back_pressure_count * 100.0 / (double)final_count);
        }
    }
    
    printf("\n");
    
    // 性能评估
    if (strcmp(role, "Subscriber") == 0) {
        if (avg_latency_us < 1.0) {
            printf("🚀 延迟性能: 超低延迟 (< 1μs) - 极致性能!\n");
        } else if (avg_latency_us < 5.0) {
            printf("⚡ 延迟性能: 优秀 (< 5μs) - 高效处理!\n");
        } else if (avg_latency_us < 20.0) {
            printf("✅ 延迟性能: 良好 (< 20μs) - 稳定表现!\n");
        } else {
            printf("⚠️ 延迟性能: 需要优化 (>= 20μs)\n");
        }
    }
    
    if (messages_per_sec > 5000000) {
        printf("🚀 吞吐量: 超高性能 (> 500万/秒)!\n");
    } else if (messages_per_sec > 1000000) {
        printf("⚡ 吞吐量: 百万级性能!\n");
    } else if (messages_per_sec > 500000) {
        printf("✅ 吞吐量: 50万+性能!\n");
    } else {
        printf("⚠️ 吞吐量: 需要优化\n");
    }
    
    printf("\n测试完成! 🎉\n");
}

void print_detailed_records(const performance_stats_t *stats) {
    if (!stats || stats->records.recorded_count == 0) return;
    
    printf("\n📋 前%zu条消息的详细记录:\n", stats->records.recorded_count);
    printf("Index\\tSendTime\\t\\tReceiveTime\\t\\tLatency(μs)\n");
    printf("-----\\t--------\\t\\t-----------\\t\\t-----------\n");
    
    for (size_t i = 0; i < stats->records.recorded_count && i < 20; i++) {  // 只显示前20条
        double latency_us = (double)stats->records.latencies[i] / 1000.0;
        printf("%zu\t%lu\t%lu\t%.2f\n", 
               i + 1, 
               stats->records.send_times[i],
               stats->records.receive_times[i],
               latency_us);
    }
    
    if (stats->records.recorded_count > 20) {
        printf("... (显示前20条，共%zu条记录)\n", stats->records.recorded_count);
    }
}

// 创建性能统计实例
performance_stats_t* create_performance_stats(void) {
    performance_stats_t* stats = calloc(1, sizeof(performance_stats_t));
    if (!stats) {
        return NULL;
    }
    
    // 初始化延迟桶限制 (微秒)
    stats->latency_bucket_limits[0] = 1;      // < 1μs
    stats->latency_bucket_limits[1] = 5;      // < 5μs  
    stats->latency_bucket_limits[2] = 10;     // < 10μs
    stats->latency_bucket_limits[3] = 50;     // < 50μs
    stats->latency_bucket_limits[4] = 100;    // < 100μs
    stats->latency_bucket_limits[5] = 500;    // < 500μs
    stats->latency_bucket_limits[6] = 1000;   // < 1ms
    stats->latency_bucket_limits[7] = 5000;   // < 5ms
    stats->latency_bucket_limits[8] = 10000;  // < 10ms
    stats->latency_bucket_limits[9] = UINT64_MAX; // >= 10ms
    
    // 初始化最小/最大延迟
    stats->counters.min_latency = UINT64_MAX;
    stats->counters.max_latency = 0;
    
    return stats;
}

// 记录延迟
void record_latency(performance_stats_t *stats, uint64_t latency_ns) {
    if (!stats) return;
    
    // 原子更新计数器
    __atomic_add_fetch(&stats->counters.message_count, 1, __ATOMIC_RELAXED);
    __atomic_add_fetch(&stats->counters.total_latency, latency_ns, __ATOMIC_RELAXED);
    
    // 更新最小/最大延迟
    uint64_t current_min = __atomic_load_n(&stats->counters.min_latency, __ATOMIC_RELAXED);
    while (latency_ns < current_min) {
        if (__atomic_compare_exchange_n(&stats->counters.min_latency, &current_min, latency_ns,
                                       false, __ATOMIC_RELAXED, __ATOMIC_RELAXED)) {
            break;
        }
    }
    
    uint64_t current_max = __atomic_load_n(&stats->counters.max_latency, __ATOMIC_RELAXED);
    while (latency_ns > current_max) {
        if (__atomic_compare_exchange_n(&stats->counters.max_latency, &current_max, latency_ns,
                                       false, __ATOMIC_RELAXED, __ATOMIC_RELAXED)) {
            break;
        }
    }
    
    // 更新延迟分布桶
    uint64_t latency_us = latency_ns / 1000;  // 转换为微秒
    for (int i = 0; i < 10; i++) {
        if (latency_us < stats->latency_bucket_limits[i]) {
            __atomic_add_fetch(&stats->latency_buckets[i], 1, __ATOMIC_RELAXED);
            break;
        }
    }
    
    // 记录详细信息 (前1000条)
    size_t current_count = __atomic_load_n(&stats->records.recorded_count, __ATOMIC_RELAXED);
    if (current_count < DETAILED_RECORD_COUNT) {
        if (__atomic_compare_exchange_n(&stats->records.recorded_count, &current_count, current_count + 1,
                                       false, __ATOMIC_RELAXED, __ATOMIC_RELAXED)) {
            stats->records.latencies[current_count] = latency_ns;
        }
    }
}

// 打印延迟分布
void print_latency_distribution(const performance_stats_t *stats) {
    if (!stats) return;
    
    printf("\n=== 延迟分布 ===\n");
    printf("延迟范围        消息数量    百分比\n");
    printf("----------------------------------------\n");
    
    uint64_t total_messages = stats->counters.message_count;
    if (total_messages == 0) {
        printf("无延迟数据\n");
        return;
    }
    
    const char* range_labels[] = {
        "< 1μs", "< 5μs", "< 10μs", "< 50μs", "< 100μs",
        "< 500μs", "< 1ms", "< 5ms", "< 10ms", ">= 10ms"
    };
    
    for (int i = 0; i < 10; i++) {
        uint64_t count = stats->latency_buckets[i];
        double percentage = (double)count * 100.0 / total_messages;
        printf("%-12s    %8lu    %6.2f%%\n", range_labels[i], count, percentage);
    }
}