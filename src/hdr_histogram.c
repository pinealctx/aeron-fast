#include "hdr_histogram.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

// 计算桶索引
static int bucket_index(hdr_histogram_t* histogram, uint64_t value) {
    if (value == 0) return 0;
    if (value >= (1ULL << (histogram->precision + 1))) {
        return histogram->bucket_count - 1;
    }
    
    int leading_zeros = __builtin_clzll(value);
    int bucket_index = (64 - leading_zeros - 1) * (1 << histogram->precision);
    int sub_bucket = (int)((value << leading_zeros) >> (64 - histogram->precision));
    return bucket_index + sub_bucket;
}

// 从桶索引获取值
static uint64_t value_from_index(hdr_histogram_t* histogram, int index) {
    if (index == 0) return 0;
    
    int bucket_index = index >> histogram->precision;
    int sub_bucket = index & ((1 << histogram->precision) - 1);
    
    if (bucket_index == 0) {
        return sub_bucket;
    }
    
    uint64_t power_of_two = 1ULL << bucket_index;
    return power_of_two + ((uint64_t)sub_bucket * power_of_two >> histogram->precision);
}

hdr_histogram_t* hdr_histogram_create(uint64_t max_value, int precision) {
    if (precision < 1 || precision > 5) {
        return NULL;
    }
    
    hdr_histogram_t* histogram = malloc(sizeof(hdr_histogram_t));
    if (!histogram) {
        return NULL;
    }
    
    // 计算所需的桶数量
    int leading_zeros = __builtin_clzll(max_value);
    int bucket_count = ((64 - leading_zeros) + 1) * (1 << precision);
    
    histogram->buckets = calloc(bucket_count, sizeof(uint64_t));
    if (!histogram->buckets) {
        free(histogram);
        return NULL;
    }
    
    histogram->bucket_count = bucket_count;
    histogram->min_value = UINT64_MAX;
    histogram->max_value = 0;
    histogram->total_count = 0;
    histogram->total_value = 0;
    histogram->precision = precision;
    
    return histogram;
}

void hdr_histogram_destroy(hdr_histogram_t* histogram) {
    if (histogram) {
        free(histogram->buckets);
        free(histogram);
    }
}

void hdr_histogram_record(hdr_histogram_t* histogram, uint64_t value) {
    if (!histogram) return;
    
    int index = bucket_index(histogram, value);
    if (index >= 0 && index < histogram->bucket_count) {
        histogram->buckets[index]++;
        histogram->total_count++;
        histogram->total_value += value;
        
        if (value < histogram->min_value) {
            histogram->min_value = value;
        }
        if (value > histogram->max_value) {
            histogram->max_value = value;
        }
    }
}

uint64_t hdr_histogram_value_at_percentile(hdr_histogram_t* histogram, double percentile) {
    if (!histogram || histogram->total_count == 0) {
        return 0;
    }
    
    uint64_t target_count = (uint64_t)((percentile / 100.0) * histogram->total_count);
    uint64_t accumulated_count = 0;
    
    for (int i = 0; i < histogram->bucket_count; i++) {
        accumulated_count += histogram->buckets[i];
        if (accumulated_count >= target_count) {
            return value_from_index(histogram, i);
        }
    }
    
    return histogram->max_value;
}

double hdr_histogram_mean(hdr_histogram_t* histogram) {
    if (!histogram || histogram->total_count == 0) {
        return 0.0;
    }
    return (double)histogram->total_value / (double)histogram->total_count;
}

uint64_t hdr_histogram_min(hdr_histogram_t* histogram) {
    return histogram ? histogram->min_value : 0;
}

uint64_t hdr_histogram_max(hdr_histogram_t* histogram) {
    return histogram ? histogram->max_value : 0;
}

uint64_t hdr_histogram_total_count(hdr_histogram_t* histogram) {
    return histogram ? histogram->total_count : 0;
}

void hdr_histogram_print_percentiles(hdr_histogram_t* histogram, const char* name) {
    if (!histogram || histogram->total_count == 0) {
        printf("=== %s 延迟统计 ===\n", name);
        printf("  无数据\n\n");
        return;
    }
    
    printf("=== %s 延迟统计 ===\n", name);
    printf("  样本数量: %lu\n", histogram->total_count);
    printf("  平均延迟: %.2f μs\n", hdr_histogram_mean(histogram));
    printf("  最小延迟: %lu μs\n", histogram->min_value);
    printf("  最大延迟: %lu μs\n", histogram->max_value);
    printf("\n");
    
    printf("  百分位统计:\n");
    double percentiles[] = {50.0, 90.0, 95.0, 99.0, 99.9, 99.99};
    int num_percentiles = sizeof(percentiles) / sizeof(percentiles[0]);
    
    for (int i = 0; i < num_percentiles; i++) {
        uint64_t value = hdr_histogram_value_at_percentile(histogram, percentiles[i]);
        printf("    P%.2f: %lu μs\n", percentiles[i], value);
    }
    printf("\n");
}

void hdr_histogram_reset(hdr_histogram_t* histogram) {
    if (!histogram) return;
    
    memset(histogram->buckets, 0, histogram->bucket_count * sizeof(uint64_t));
    histogram->min_value = UINT64_MAX;
    histogram->max_value = 0;
    histogram->total_count = 0;
    histogram->total_value = 0;
}
