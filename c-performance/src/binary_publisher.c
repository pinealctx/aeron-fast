#define _GNU_SOURCE
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
        printf("总消息数:     %" PRIu64 "\n", g_stats.messages_sent);
        printf("总字节数:     %" PRIu64 "\n", g_stats.bytes_sent);
        printf("发送错误:     %" PRIu64 "\n", g_stats.send_errors);
        printf("背压事件:     %" PRIu64 "\n", g_stats.back_pressure_events);
        printf("总耗时:       %" PRIu64 " ns (%" PRIu64 " 秒)\n",
               (uint64_t)total_duration, (uint64_t)(total_duration / 1000000000ULL));        if (total_duration > 0) {
            uint64_t msg_throughput = (g_stats.messages_sent * 1000000000ULL) / total_duration;
            uint64_t byte_throughput = (g_stats.bytes_sent * 1000000000ULL) / total_duration / (1024 * 1024);
            
            printf("平均吞吐量:   %" PRIu64 " 消息/秒\n", msg_throughput);
            printf("平均带宽:     %" PRIu64 " MB/秒\n", byte_throughput);
        }
    } else {
        uint64_t interval_time = current_time - g_stats.last_stats_time;
        uint64_t interval_messages = g_stats.messages_sent - g_stats.last_messages_sent;
        uint64_t interval_bytes = g_stats.bytes_sent - g_stats.last_bytes_sent;
        
        if (interval_time > 0) {
            uint64_t interval_msg_rate = (interval_messages * 1000000000ULL) / interval_time;
            uint64_t interval_byte_rate = (interval_bytes * 1000000000ULL) / interval_time / (1024 * 1024);
            
            printf("消息: %8" PRIu64 ", 字节: %10" PRIu64 ", 速率: %8" PRIu64 " 消息/秒, %6" PRIu64 " MB/秒\n",
                   g_stats.messages_sent,
                   g_stats.bytes_sent,
                   interval_msg_rate,
                   interval_byte_rate);
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
    
    // 验证配置参数
    if (config->message_size < MIN_MESSAGE_SIZE) {
        fprintf(stderr, "错误: 消息大小 (%zu) 小于最小值 (%d)\n", 
                config->message_size, MIN_MESSAGE_SIZE);
        return ERROR_INVALID_PARAM;
    }
    
    printf("配置验证通过: message_size=%zu, MIN_MESSAGE_SIZE=%d\n", 
           config->message_size, MIN_MESSAGE_SIZE);
    
    // 分配消息缓冲区 - 使用32字节对齐避免AVX2指令崩溃
    size_t aligned_size = ((config->message_size + BUFFER_ALIGNMENT - 1) / BUFFER_ALIGNMENT) * BUFFER_ALIGNMENT;
    uint8_t *message_buffer = aligned_alloc(BUFFER_ALIGNMENT, aligned_size);
    if (!message_buffer) {
        fprintf(stderr, "错误: 无法分配对齐的消息缓冲区\n");
        return ERROR_MEMORY_ALLOCATION;
    }
    
    // 初始化整个缓冲区为0，防止优化导致的未初始化内存问题
    memset(message_buffer, 0, config->message_size);
    
    if (config->message_size > TIMESTAMP_SIZE) {
        // 计算需要填充的字节数
        size_t fill_size = config->message_size - TIMESTAMP_SIZE;
        
        // 使用更安全的方式初始化，避免循环优化问题
        uint8_t *payload_start = message_buffer + TIMESTAMP_SIZE;
        for (size_t i = 0; i < fill_size; i++) {
            payload_start[i] = (uint8_t)(i % 256);
        }
    } else {
        printf("消息大小 (%zu) 不大于时间戳大小 (%d)，跳过内容填充\n", 
               config->message_size, TIMESTAMP_SIZE);
    }
    
    // 创建统计报告线程
    pthread_t stats_tid;
    if (pthread_create(&stats_tid, NULL, stats_thread, NULL) != 0) {
        fprintf(stderr, "警告: 无法创建统计线程\n");
    }
    
    // 记录开始时间
    g_stats.start_time = get_timestamp_ns();
    g_stats.last_stats_time = g_stats.start_time;
    
    
    uint64_t messages_to_send = config->message_count;
    uint64_t successful_sends = 0;
    uint64_t retry_count = 0;
    const uint64_t MAX_RETRIES = 1000000;  // 最大重试次数
    
    printf("\n开始发送 %" PRIu64 " 条消息，每条 %zu 字节...\n", 
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
            fprintf(stderr, "错误: 发送失败 (错误码: %" PRId64 ")\n", result);
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
    
    // 设置Aeron目录（从配置）
    printf("使用Aeron目录: %s\n", config.aeron_dir);
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