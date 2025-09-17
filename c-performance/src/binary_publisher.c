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

// 性能统计
typedef struct {
    uint64_t messages_sent;
    uint64_t bytes_sent;
    uint64_t send_errors;
    uint64_t back_pressure_events;
    uint64_t start_time;
    uint64_t last_stats_time;
    uint64_t last_messages_sent;
    uint64_t last_bytes_sent;
} publisher_stats_t;

static publisher_stats_t g_stats = {0};

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

// 打印统计信息
void print_stats(bool final) {
    pthread_mutex_lock(&stats_mutex);
    
    uint64_t current_time = get_timestamp_ns();
    uint64_t total_duration = current_time - g_stats.start_time;
    
    if (final) {
        printf("\n=== 最终性能统计 ===\n");
        printf("总消息数:     %lu\n", g_stats.messages_sent);
        printf("总字节数:     %lu\n", g_stats.bytes_sent);
        printf("发送错误:     %lu\n", g_stats.send_errors);
        printf("背压事件:     %lu\n", g_stats.back_pressure_events);
        printf("总耗时:       %.3f 秒\n", total_duration / 1.0e9);
        
        if (total_duration > 0) {
            printf("平均吞吐量:   %.2f 消息/秒\n", 
                   g_stats.messages_sent * 1.0e9 / total_duration);
            printf("平均带宽:     %.2f MB/秒\n", 
                   g_stats.bytes_sent * 1.0e9 / total_duration / (1024 * 1024));
        }
    } else {
        uint64_t interval_time = current_time - g_stats.last_stats_time;
        uint64_t interval_messages = g_stats.messages_sent - g_stats.last_messages_sent;
        uint64_t interval_bytes = g_stats.bytes_sent - g_stats.last_bytes_sent;
        
        if (interval_time > 0) {
            printf("消息: %8lu, 字节: %10lu, 速率: %8.0f 消息/秒, %6.1f MB/秒\n",
                   g_stats.messages_sent,
                   g_stats.bytes_sent,
                   interval_messages * 1.0e9 / interval_time,
                   interval_bytes * 1.0e9 / interval_time / (1024 * 1024));
        }
        
        g_stats.last_stats_time = current_time;
        g_stats.last_messages_sent = g_stats.messages_sent;
        g_stats.last_bytes_sent = g_stats.bytes_sent;
    }
    
    pthread_mutex_unlock(&stats_mutex);
}

// 统计报告线程
void* stats_thread(void* arg) {
    (void)arg;
    
    while (running) {
        sleep(1);
        if (running) {
            print_stats(false);
        }
    }
    
    return NULL;
}

// 背压处理器
void offer_failed_handler(aeron_publication_t *publication, int64_t position) {
    (void)publication;
    (void)position;
    
    pthread_mutex_lock(&stats_mutex);
    g_stats.back_pressure_events++;
    pthread_mutex_unlock(&stats_mutex);
    
    // 简单的背压处理：短暂休眠
    usleep(1);
}

// 发布消息函数
int64_t publish_message(aeron_publication_t *publication, uint8_t *message, size_t message_size) {
    int64_t result = aeron_publication_offer(
        publication,
        message,
        message_size,
        NULL,
        NULL
    );
    
    if (result > 0) {
        // 成功发送
        pthread_mutex_lock(&stats_mutex);
        g_stats.messages_sent++;
        g_stats.bytes_sent += message_size;
        pthread_mutex_unlock(&stats_mutex);
    } else if (result == AERON_PUBLICATION_BACK_PRESSURED) {
        offer_failed_handler(publication, result);
        return -1;  // 背压，稍后重试
    } else if (result == AERON_PUBLICATION_NOT_CONNECTED ||
               result == AERON_PUBLICATION_ADMIN_ACTION ||
               result == AERON_PUBLICATION_CLOSED) {
        pthread_mutex_lock(&stats_mutex);
        g_stats.send_errors++;
        pthread_mutex_unlock(&stats_mutex);
        return -2;  // 严重错误
    }
    
    return result;
}

// 主发布循环
int run_publisher(aeron_publication_t *publication, const config_t *config) {
    printf("开始发送消息，按Ctrl+C停止...\n");
    
    // 分配消息缓冲区
    uint8_t *message_buffer = malloc(config->message_size);
    if (!message_buffer) {
        fprintf(stderr, "错误: 无法分配消息缓冲区\n");
        return ERROR_MEMORY_ALLOCATION;
    }
    
    // 初始化消息内容（固定模式）
    for (size_t i = TIMESTAMP_SIZE; i < config->message_size; i++) {
        message_buffer[i] = (uint8_t)(i % 256);
    }
    
    // 创建统计报告线程
    pthread_t stats_tid;
    if (pthread_create(&stats_tid, NULL, stats_thread, NULL) != 0) {
        fprintf(stderr, "警告: 无法创建统计线程\n");
    }
    
    // 记录开始时间
    g_stats.start_time = get_timestamp_ns();
    g_stats.last_stats_time = g_stats.start_time;
    
    // 预热时间函数
    warmup_time_functions(1000);
    
    uint64_t messages_to_send = config->message_count;
    uint64_t successful_sends = 0;
    uint64_t retry_count = 0;
    const uint64_t MAX_RETRIES = 1000000;  // 最大重试次数
    
    printf("\n开始发送 %lu 条消息，每条 %zu 字节...\n", 
           messages_to_send, config->message_size);
    
    while (running && successful_sends < messages_to_send) {
        // 创建带时间戳的消息
        uint64_t timestamp = get_timestamp_ns();
        create_binary_message(message_buffer, config->message_size, timestamp);
        
        // 尝试发送消息
        int64_t result = publish_message(publication, message_buffer, config->message_size);
        
        if (result > 0) {
            // 成功发送
            successful_sends++;
            retry_count = 0;
            
            // 检查是否达到目标
            if (successful_sends >= messages_to_send) {
                break;
            }
        } else if (result == -1) {
            // 背压，重试
            retry_count++;
            if (retry_count > MAX_RETRIES) {
                fprintf(stderr, "错误: 背压重试次数超限\n");
                break;
            }
            usleep(1);  // 短暂等待
            continue;
        } else {
            // 严重错误
            fprintf(stderr, "错误: 发送失败 (错误码: %ld)\n", result);
            break;
        }
    }
    
    running = false;
    
    // 等待统计线程结束
    pthread_join(stats_tid, NULL);
    
    // 打印最终统计
    print_stats(true);
    
    free(message_buffer);
    return ERROR_SUCCESS;
}

// 等待连接
int wait_for_connection(aeron_publication_t *publication, int timeout_seconds) {
    printf("等待Subscriber连接...");
    fflush(stdout);
    
    time_t start_time = time(NULL);
    while (!aeron_publication_is_connected(publication)) {
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
    printf("=== Aeron C 版本 BinaryPerformancePublisher ===\n");
    printf("基于 Aeron C API 的高性能二进制消息发布器\n\n");
    
    // 解析命令行参数
    config_t config;
    int parse_result = parse_publisher_args(argc, argv, &config);
    if (parse_result != ERROR_SUCCESS) {
        if (parse_result == 1) {
            // 显示了帮助信息
            return 0;
        }
        return 1;
    }
    
    // 打印配置摘要
    print_config_summary(&config);
    
    // 设置信号处理器
    setup_signal_handlers();
    
    // 初始化Aeron
    aeron_context_t *context = NULL;
    aeron_t *aeron = NULL;
    aeron_publication_t *publication = NULL;
    
    printf("初始化Aeron...\n");
    
    // 创建Aeron上下文
    if (aeron_context_init(&context) < 0) {
        fprintf(stderr, "错误: 无法初始化Aeron上下文: %s\n", aeron_errmsg());
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
    
    printf("添加Publication: %s, Stream ID: %d\n", channel, config.stream_id);
    
    // 添加Publication
    aeron_async_add_publication_t *async_publication;
    if (aeron_async_add_publication(
        &async_publication,
        aeron,
        channel,
        config.stream_id) < 0) {
        fprintf(stderr, "错误: 无法添加Publication: %s\n", aeron_errmsg());
        aeron_close(aeron);
        aeron_context_close(context);
        return 1;
    }
    
    // 等待Publication就绪
    printf("等待Publication就绪...\n");
    while (aeron_async_add_publication_poll(&publication, async_publication) == 0) {
        usleep(1000);  // 1ms
        if (!running) {
            fprintf(stderr, "被中断，退出\n");
            aeron_close(aeron);
            aeron_context_close(context);
            return 1;
        }
    }
    
    if (!publication) {
        fprintf(stderr, "错误: Publication创建失败\n");
        aeron_close(aeron);
        aeron_context_close(context);
        return 1;
    }
    
    printf("Publication创建成功！\n");
    
    // 等待连接（可选，取决于需求）
    if (config.transport_type != TRANSPORT_IPC) {
        if (wait_for_connection(publication, 30) != ERROR_SUCCESS) {
            fprintf(stderr, "警告: 没有Subscriber连接，但继续发送\n");
        }
    }
    
    // 运行发布器
    int result = run_publisher(publication, &config);
    
    // 清理资源
    printf("\n清理资源...\n");
    if (publication) {
        aeron_publication_close(publication, NULL, NULL);
    }
    
    if (aeron) {
        aeron_close(aeron);
    }
    
    if (context) {
        aeron_context_close(context);
    }
    
    printf("Publisher完成\n");
    return result == ERROR_SUCCESS ? 0 : 1;
}