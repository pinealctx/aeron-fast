#ifndef HDR_HISTOGRAM_H
#define HDR_HISTOGRAM_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * 简化的HdrHistogram实现
 * 用于高精度延迟测量的百分位统计
 */

typedef struct {
    uint64_t* buckets;      // 桶数组
    int bucket_count;       // 桶数量
    uint64_t min_value;     // 最小值
    uint64_t max_value;     // 最大值
    uint64_t total_count;   // 总样本数
    uint64_t total_value;   // 总值（用于计算平均值）
    int precision;          // 精度位数
} hdr_histogram_t;

/**
 * 创建直方图
 * @param max_value 最大值（微秒）
 * @param precision 精度位数
 * @return 直方图指针，失败返回NULL
 */
hdr_histogram_t* hdr_histogram_create(uint64_t max_value, int precision);

/**
 * 销毁直方图
 */
void hdr_histogram_destroy(hdr_histogram_t* histogram);

/**
 * 记录值
 * @param histogram 直方图
 * @param value 值（微秒）
 */
void hdr_histogram_record(hdr_histogram_t* histogram, uint64_t value);

/**
 * 获取百分位值
 * @param histogram 直方图
 * @param percentile 百分位 (0.0-100.0)
 * @return 百分位对应的值
 */
uint64_t hdr_histogram_value_at_percentile(hdr_histogram_t* histogram, double percentile);

/**
 * 获取平均值
 */
double hdr_histogram_mean(hdr_histogram_t* histogram);

/**
 * 获取最小值
 */
uint64_t hdr_histogram_min(hdr_histogram_t* histogram);

/**
 * 获取最大值
 */
uint64_t hdr_histogram_max(hdr_histogram_t* histogram);

/**
 * 获取总样本数
 */
uint64_t hdr_histogram_total_count(hdr_histogram_t* histogram);

/**
 * 打印百分位统计
 */
void hdr_histogram_print_percentiles(hdr_histogram_t* histogram, const char* name);

/**
 * 重置直方图
 */
void hdr_histogram_reset(hdr_histogram_t* histogram);

#ifdef __cplusplus
}
#endif

#endif // HDR_HISTOGRAM_H
