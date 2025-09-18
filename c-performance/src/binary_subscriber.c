#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <signal.h>
#include <time.h>
#include <unistd.h>
#include <pthread.h>
#include <sys/time.h>

#include "aeronc.h"
#include "time_utils.h"
#include "binary_message.h"
#include "performance_stats.h"
#include "config_parser.h"

// 全局变量
static bool running = true;
static pthread_mutex_t stats_mutex = PTHREAD_MUTEX_INITIALIZER;

// 性能统计结构
typedef struct {
    uint64_t messages_received;
    uint64_t bytes_received;
    uint64_t fragments_received;
    uint64_t polling_iterations;
    uint64_t start_time;
    uint64_t end_time;
    uint64_t last_stats_time;
    uint64_t last_messages_received;
    uint64_t last_bytes_received;
    
    // 延迟统计
    performance_stats_t *latency_stats;
    uint64_t min_latency;
    uint64_t max_latency;
    uint64_t total_latency;
} subscriber_stats_t;

static subscriber_stats_t g_stats = {0};
static uint64_t g_target_messages = 0;

// 信号处理器
void signal_handler(int signal) {
    (void)signal;
    running = false;
    printf("\n收到停止信号，准备退出...\n");
}

// 安装信号处理器
void setup_signal_handlers() {
    signal(SIGINT, signal_handler);
    signal(SIGTERM, signal_handler);
}

// 初始化统计
int init_subscriber_stats() {
    g_stats.latency_stats = create_performance_stats();
    if (!g_stats.latency_stats) {
        return ERROR_MEMORY_ALLOCATION;
    }
    
    g_stats.min_latency = UINT64_MAX;
    g_stats.max_latency = 0;
    g_stats.start_time = get_timestamp_ns();
    g_stats.last_stats_time = g_stats.start_time;
    
    return ERROR_SUCCESS;
}

// 清理统计
void cleanup_subscriber_stats() {
    if (g_stats.latency_stats) {
        destroy_performance_stats(g_stats.latency_stats);
        g_stats.latency_stats = NULL;
    }
}

// 打印实时统计信息
void print_realtime_stats() {
    pthread_mutex_lock(&stats_mutex);
    
    uint64_t current_time = get_timestamp_ns();
    uint64_t interval_time = current_time - g_stats.last_stats_time;
    uint64_t interval_messages = g_stats.messages_received - g_stats.last_messages_received;
    uint64_t interval_bytes = g_stats.bytes_received - g_stats.last_bytes_received;
    
    if (interval_time > 0) {
        // 使用整数运算避免浮点数兼容性问题
        uint64_t msg_rate = (interval_messages * 1000000000ULL) / interval_time;
        uint64_t byte_rate_mb = (interval_bytes * 1000000000ULL) / interval_time / (1024 * 1024);
        
        printf("收到: %8" PRIu64 "/%" PRIu64 ", 字节: %10" PRIu64 ", 速率: %8" PRIu64 " 消息/秒, %6" PRIu64 " MB/秒\n",
               g_stats.messages_received,
               g_target_messages,
               g_stats.bytes_received,
               msg_rate,
               byte_rate_mb);
    }
    
    g_stats.last_stats_time = current_time;
    g_stats.last_messages_received = g_stats.messages_received;
    g_stats.last_bytes_received = g_stats.bytes_received;
    
    pthread_mutex_unlock(&stats_mutex);
}

// 打印最终统计信息
void print_final_stats() {
    pthread_mutex_lock(&stats_mutex);
    
    uint64_t total_duration = g_stats.end_time - g_stats.start_time;
    
    printf("\n=== 最终性能统计 ===\n");
    printf("总消息数:     %" PRIu64 "\n", g_stats.messages_received);
    printf("总字节数:     %" PRIu64 "\n", g_stats.bytes_received);
    printf("总片段数:     %" PRIu64 "\n", g_stats.fragments_received);
    printf("轮询次数:     %" PRIu64 "\n", g_stats.polling_iterations);
    printf("总耗时:       %" PRIu64 " ns (%" PRIu64 " 秒)\n",
           (uint64_t)total_duration, (uint64_t)(total_duration / 1000000000ULL));    if (total_duration > 0) {
        uint64_t msg_throughput = (g_stats.messages_received * 1000000000ULL) / total_duration;
        uint64_t byte_throughput = (g_stats.bytes_received * 1000000000ULL) / total_duration / (1024 * 1024);
        
        printf("平均吞吐量:   %" PRIu64 " 消息/秒\n", msg_throughput);
        printf("平均带宽:     %" PRIu64 " MB/秒\n", byte_throughput);
    }
    
    // 延迟统计
    if (g_stats.messages_received > 0) {
        printf("\n=== 延迟统计 ===\n");
        printf("最小延迟:     %" PRIu64 " ns (%" PRIu64 " μs)\n",
               (uint64_t)g_stats.min_latency, (uint64_t)(g_stats.min_latency / 1000ULL));
        printf("最大延迟:     %" PRIu64 " ns (%" PRIu64 " μs)\n",
               (uint64_t)g_stats.max_latency, (uint64_t)(g_stats.max_latency / 1000ULL));        uint64_t avg_latency = g_stats.total_latency / g_stats.messages_received;
        printf("平均延迟:     %" PRIu64 " ns (%" PRIu64 " μs)\n",
               (uint64_t)avg_latency, (uint64_t)(avg_latency / 1000ULL));        // 详细延迟分布 (如果性能统计可用)
        if (g_stats.latency_stats) {
            print_latency_distribution(g_stats.latency_stats);
        }
    }
    
    pthread_mutex_unlock(&stats_mutex);
}

// 统计报告线程
void* stats_thread(void* arg) {
    (void)arg;
    
    while (running && g_stats.messages_received < g_target_messages) {
        sleep(1);
        if (running) {
            print_realtime_stats();
        }
    }
    
    return NULL;
}

// 消息处理函数
void process_message_fragment(
    void *clientd,
    const uint8_t *buffer,
    size_t length,
    aeron_header_t *header)
{
    (void)clientd;
    (void)header;
    
    if (length < TIMESTAMP_SIZE) {
        // 消息太短，跳过
        return;
    }
    
    // 解析时间戳
    uint64_t send_timestamp = parse_binary_message_timestamp(buffer);
    uint64_t receive_timestamp = get_timestamp_ns();
    
    // 计算延迟
    uint64_t latency = receive_timestamp - send_timestamp;
    
    // 更新统计
    pthread_mutex_lock(&stats_mutex);
    
    g_stats.messages_received++;
    g_stats.bytes_received += length;
    g_stats.fragments_received++;
    
    // 延迟统计
    if (latency < g_stats.min_latency) {
        g_stats.min_latency = latency;
    }
    if (latency > g_stats.max_latency) {
        g_stats.max_latency = latency;
    }
    g_stats.total_latency += latency;
    
    // 记录到性能统计
    if (g_stats.latency_stats) {
        record_latency(g_stats.latency_stats, latency);
    }
    
    pthread_mutex_unlock(&stats_mutex);
    
    // 检查是否达到目标
    if (g_stats.messages_received >= g_target_messages) {
        g_stats.end_time = receive_timestamp;
        running = false;
    }
}

// 主接收循环
int run_subscriber(aeron_subscription_t *subscription, const config_t *config) {
    printf("开始接收消息，目标: %" PRIu64 " 条，按Ctrl+C停止...\n", config->target_message_count);
    
    g_target_messages = config->target_message_count;
    
    // 初始化统计
    if (init_subscriber_stats() != ERROR_SUCCESS) {
        fprintf(stderr, "错误: 初始化统计失败\n");
        return ERROR_MEMORY_ALLOCATION;
    }
    
    // 创建统计报告线程
    pthread_t stats_tid;
    if (pthread_create(&stats_tid, NULL, stats_thread, NULL) != 0) {
        fprintf(stderr, "警告: 无法创建统计线程\n");
    }
    
    
    printf("\n开始接收消息...\n");
    
    // 主接收循环
    while (running && g_stats.messages_received < g_target_messages) {
        g_stats.polling_iterations++;
        
        // 轮询消息
        int fragments_received = aeron_subscription_poll(
            subscription,
            process_message_fragment,
            NULL,  // clientd
            config->fragment_limit
        );
        
        if (fragments_received < 0) {
            fprintf(stderr, "错误: 轮询失败 (错误码: %d)\n", fragments_received);
            break;
        }
        
        // 如果没有收到消息，短暂休眠避免CPU占用过高
        if (fragments_received == 0) {
            usleep(1);  // 1 微秒
        }
    }
    
    if (g_stats.end_time == 0) {
        g_stats.end_time = get_timestamp_ns();
    }
    
    running = false;
    
    // 等待统计线程结束
    pthread_join(stats_tid, NULL);
    
    // 打印最终统计
    print_final_stats();
    
    // 清理统计
    cleanup_subscriber_stats();
    
    return ERROR_SUCCESS;
}

// 等待连接
int wait_for_connection(aeron_subscription_t *subscription, int timeout_seconds) {
    printf("等待Publisher连接...");
    fflush(stdout);
    
    time_t start_time = time(NULL);
    while (!aeron_subscription_is_connected(subscription)) {
        if (time(NULL) - start_time > timeout_seconds) {
            printf(" 超时\n");
            return ERROR_TIMEOUT;
        }
        printf(".");
        fflush(stdout);
        sleep(1);
    }
    
    printf(" 连接成功！\n");
    return ERROR_SUCCESS;
}

int main(int argc, char **argv) {
    printf("=== Aeron C 版本 BinaryPerformanceSubscriber ===\n");
    printf("基于 Aeron C API 的高性能二进制消息接收器\n\n");
    
    // 解析命令行参数
    config_t config;
    int parse_result = parse_subscriber_args(argc, argv, &config);
    if (parse_result != ERROR_SUCCESS) {
        if (parse_result == 1) {
            // 显示了帮助信息
            return 0;
        }
        return 1;
    }
    
    // 打印配置摘要
    print_config_summary(&config);
    printf("目标消息数:   %" PRIu64 "\n", config.target_message_count);
    printf("片段限制:     %d\n", config.fragment_limit);
    printf("\n");
    
    // 设置信号处理器
    setup_signal_handlers();
    
    // 初始化Aeron
    aeron_context_t *context = NULL;
    aeron_t *aeron = NULL;
    aeron_subscription_t *subscription = NULL;
    
    printf("初始化Aeron...\n");
    
    // 创建Aeron上下文
    if (aeron_context_init(&context) < 0) {
        fprintf(stderr, "错误: 无法初始化Aeron上下文: %s\n", aeron_errmsg());
        return 1;
    }
    
    // 设置Aeron目录（从配置）
    printf("设置Aeron目录: %s\n", config.aeron_dir);
    if (aeron_context_set_dir(context, config.aeron_dir) < 0) {
        fprintf(stderr, "错误: 无法设置Aeron目录: %s\n", aeron_errmsg());
        aeron_context_close(context);
        return 1;
    }
    
    // 启动Aeron
    if (aeron_init(&aeron, context) < 0) {
        fprintf(stderr, "错误: 无法启动Aeron: %s\n", aeron_errmsg());
        aeron_context_close(context);
        return 1;
    }
    
    if (aeron_start(aeron) < 0) {
        fprintf(stderr, "错误: 无法启动Aeron实例: %s\n", aeron_errmsg());
        aeron_close(aeron);
        aeron_context_close(context);
        return 1;
    }
    
    // 创建有效的channel字符串
    char channel_buffer[512];
    const char *channel = get_effective_channel(&config, channel_buffer, sizeof(channel_buffer));
    
    printf("添加Subscription: %s, Stream ID: %d\n", channel, config.stream_id);
    
    // 添加Subscription
    aeron_async_add_subscription_t *async_subscription;
    if (aeron_async_add_subscription(
        &async_subscription,
        aeron,
        channel,
        config.stream_id,
        NULL,  // on_available_image_handler
        NULL,  // on_available_image_clientd
        NULL,  // on_unavailable_image_handler
        NULL   // on_unavailable_image_clientd
    ) < 0) {
        fprintf(stderr, "错误: 无法添加Subscription: %s\n", aeron_errmsg());
        aeron_close(aeron);
        aeron_context_close(context);
        return 1;
    }
    
    // 等待Subscription就绪
    printf("等待Subscription就绪...\n");
    while (aeron_async_add_subscription_poll(&subscription, async_subscription) == 0) {
        usleep(1000);  // 1ms
        if (!running) {
            fprintf(stderr, "被中断，退出\n");
            aeron_close(aeron);
            aeron_context_close(context);
            return 1;
        }
    }
    
    if (!subscription) {
        fprintf(stderr, "错误: Subscription创建失败\n");
        aeron_close(aeron);
        aeron_context_close(context);
        return 1;
    }
    
    printf("Subscription创建成功！\n");
    
    // 等待Publisher连接（可选）
    if (config.transport_type != TRANSPORT_IPC) {
        if (wait_for_connection(subscription, 30) != ERROR_SUCCESS) {
            fprintf(stderr, "警告: 没有Publisher连接，但继续等待消息\n");
        }
    }
    
    // 运行订阅器
    int result = run_subscriber(subscription, &config);
    
    // 清理资源
    printf("\n清理资源...\n");
    if (subscription) {
        aeron_subscription_close(subscription, NULL, NULL);
    }
    
    if (aeron) {
        aeron_close(aeron);
    }
    
    if (context) {
        aeron_context_close(context);
    }
    
    printf("Subscriber完成\n");
    return result == ERROR_SUCCESS ? 0 : 1;
}