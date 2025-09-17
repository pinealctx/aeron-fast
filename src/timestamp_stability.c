#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "hires_time.h"

void print_usage(const char* program_name) {
    printf("用法: %s [选项]\n", program_name);
    printf("选项:\n");
    printf("  -s <样本数>     测试样本数量 (默认: 10000)\n");
    printf("  -c <核心ID>     绑定到指定CPU核心\n");
    printf("  -p <优先级>     设置实时优先级 (1-99)\n");
    printf("  -h              显示帮助信息\n");
    printf("\n");
    printf("示例:\n");
    printf("  %s                    # 使用默认设置\n", program_name);
    printf("  %s -s 50000           # 测试50000个样本\n", program_name);
    printf("  %s -c 2 -p 50         # 绑定核心2，实时优先级50\n", program_name);
}

int main(int argc, char* argv[]) {
    int samples = 10000;
    int cpu_core = -1;
    int rt_priority = -1;
    int opt;
    
    // 解析命令行参数
    while ((opt = getopt(argc, argv, "s:c:p:h")) != -1) {
        switch (opt) {
            case 's':
                samples = atoi(optarg);
                if (samples < 100 || samples > 1000000) {
                    fprintf(stderr, "样本数应在 100-1000000 之间\n");
                    return 1;
                }
                break;
            case 'c':
                cpu_core = atoi(optarg);
                break;
            case 'p':
                rt_priority = atoi(optarg);
                if (rt_priority < 1 || rt_priority > 99) {
                    fprintf(stderr, "实时优先级应在 1-99 之间\n");
                    return 1;
                }
                break;
            case 'h':
                print_usage(argv[0]);
                return 0;
            default:
                print_usage(argv[0]);
                return 1;
        }
    }
    
    printf("🕒 C语言时间戳稳定性检查工具\n");
    printf("样本数量: %d\n", samples);
    printf("=".repeat(60));
    printf("\n");
    
    // 设置CPU亲和性
    if (cpu_core >= 0) {
        hires_time_set_cpu_affinity(cpu_core);
    }
    
    // 设置实时优先级
    if (rt_priority > 0) {
        hires_time_set_realtime_priority(rt_priority);
    }
    
    // 预热
    hires_time_warmup();
    printf("\n");
    
    // 测试所有时间源
    time_source_t sources[] = {
        TIME_SOURCE_REALTIME,
        TIME_SOURCE_MONOTONIC,
        TIME_SOURCE_MONOTONIC_RAW,
        TIME_SOURCE_PROCESS_CPUTIME,
        TIME_SOURCE_THREAD_CPUTIME
    };
    
    int num_sources = sizeof(sources) / sizeof(sources[0]);
    time_stats_t results[num_sources];
    
    for (int i = 0; i < num_sources; i++) {
        hires_time_check_stability(sources[i], samples, &results[i]);
    }
    
    // 生成对比报告
    printf("📊 时间源对比报告\n");
    printf("=".repeat(80));
    printf("\n");
    printf("%-25s %12s %12s %12s %10s\n", 
           "时间源", "平均(ns)", "最小(ns)", "最大(ns)", "抖动比例");
    printf("-".repeat(80));
    printf("\n");
    
    int best_source = -1;
    double best_jitter = 1e9;
    
    for (int i = 0; i < num_sources; i++) {
        if (results[i].count > 0) {
            double jitter_ratio = (double)results[i].max / results[i].mean;
            printf("%-25s %12.1f %12lu %12lu %9.1fx\n",
                   hires_time_source_name(sources[i]),
                   results[i].mean,
                   results[i].min,
                   results[i].max,
                   jitter_ratio);
            
            if (jitter_ratio < best_jitter) {
                best_jitter = jitter_ratio;
                best_source = i;
            }
        }
    }
    
    printf("\n");
    
    // 推荐
    if (best_source >= 0) {
        printf("🏆 推荐时间源: %s (抖动: %.1fx)\n", 
               hires_time_source_name(sources[best_source]), best_jitter);
    }
    
    printf("\n💡 使用建议:\n");
    printf("  - 跨机器测试: 使用 CLOCK_REALTIME (绝对时间)\n");
    printf("  - 本机测试: 使用 CLOCK_MONOTONIC (相对时间，不受NTP影响)\n");
    printf("  - 超高精度: 使用 CLOCK_MONOTONIC_RAW (未经调整的单调时间)\n");
    printf("  - 如果抖动过大: 检查系统负载、中断、电源管理设置\n");
    printf("  - 低延迟设置: 使用 -c 和 -p 参数绑定CPU核心和提升优先级\n");
    
    return 0;
}
