#ifndef HIRES_TIME_H
#define HIRES_TIME_H

#include <stdint.h>
#include <time.h>
#include <sys/time.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * 高精度时间戳获取库
 * 提供纳秒级精度的时间戳，针对低延迟应用优化
 */

// 时间戳类型定义
typedef uint64_t timestamp_ns_t;

// 时间源类型
typedef enum {
    TIME_SOURCE_REALTIME,      // CLOCK_REALTIME - 系统绝对时间
    TIME_SOURCE_MONOTONIC,     // CLOCK_MONOTONIC - 单调递增时间
    TIME_SOURCE_MONOTONIC_RAW, // CLOCK_MONOTONIC_RAW - 未经NTP调整的单调时间
    TIME_SOURCE_PROCESS_CPUTIME, // CLOCK_PROCESS_CPUTIME_ID - 进程CPU时间
    TIME_SOURCE_THREAD_CPUTIME   // CLOCK_THREAD_CPUTIME_ID - 线程CPU时间
} time_source_t;

// 时间统计结构
typedef struct {
    timestamp_ns_t min;
    timestamp_ns_t max;
    timestamp_ns_t total;
    uint64_t count;
    double mean;
    double variance;
    double std_dev;
} time_stats_t;

/**
 * 获取当前时间戳（纳秒）
 * @param source 时间源类型
 * @return 纳秒时间戳
 */
timestamp_ns_t hires_time_now(time_source_t source);

/**
 * 获取Unix纳秒时间戳（绝对时间）
 * @return Unix纳秒时间戳
 */
timestamp_ns_t hires_time_unix_nano(void);

/**
 * 获取单调递增纳秒时间戳（相对时间）
 * @return 单调纳秒时间戳
 */
timestamp_ns_t hires_time_monotonic_nano(void);

/**
 * 获取原始单调递增纳秒时间戳（未经NTP调整）
 * @return 原始单调纳秒时间戳
 */
timestamp_ns_t hires_time_monotonic_raw_nano(void);

/**
 * 计算两个时间戳的差值
 * @param end 结束时间戳
 * @param start 开始时间戳
 * @return 差值（纳秒）
 */
static inline int64_t hires_time_diff(timestamp_ns_t end, timestamp_ns_t start) {
    return (int64_t)(end - start);
}

/**
 * 将纳秒转换为微秒
 */
static inline double hires_time_ns_to_us(timestamp_ns_t ns) {
    return ns / 1000.0;
}

/**
 * 将纳秒转换为毫秒
 */
static inline double hires_time_ns_to_ms(timestamp_ns_t ns) {
    return ns / 1000000.0;
}

/**
 * 将纳秒转换为秒
 */
static inline double hires_time_ns_to_s(timestamp_ns_t ns) {
    return ns / 1000000000.0;
}

/**
 * 初始化时间统计结构
 */
void hires_time_stats_init(time_stats_t* stats);

/**
 * 更新时间统计
 */
void hires_time_stats_update(time_stats_t* stats, timestamp_ns_t value);

/**
 * 完成时间统计计算
 */
void hires_time_stats_finalize(time_stats_t* stats);

/**
 * 打印时间统计
 */
void hires_time_stats_print(const time_stats_t* stats, const char* name);

/**
 * 检查时钟精度和稳定性
 * @param source 时间源
 * @param samples 样本数量
 * @param results 输出统计结果
 */
void hires_time_check_stability(time_source_t source, int samples, time_stats_t* results);

/**
 * 预热时间获取函数，减少首次调用开销
 */
void hires_time_warmup(void);

/**
 * 获取时间源名称
 */
const char* hires_time_source_name(time_source_t source);

/**
 * 设置CPU亲和性到指定核心
 * @param core_id 核心ID
 * @return 0成功，-1失败
 */
int hires_time_set_cpu_affinity(int core_id);

/**
 * 设置线程为实时优先级
 * @param priority 优先级 (1-99)
 * @return 0成功，-1失败
 */
int hires_time_set_realtime_priority(int priority);

#ifdef __cplusplus
}
#endif

#endif // HIRES_TIME_H
