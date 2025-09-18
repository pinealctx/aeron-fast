#include "config_parser.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <getopt.h>

void set_default_config(config_t *config) {
    if (!config) return;
    
    config->transport_type = TRANSPORT_UDP;
    strncpy(config->channel, DEFAULT_CHANNEL, sizeof(config->channel) - 1);
    config->channel[sizeof(config->channel) - 1] = '\0';
    config->custom_endpoint[0] = '\0';
    config->aeron_dir[0] = '\0';  // 初始化为空，由load_config_from_env设置
    config->stream_id = DEFAULT_STREAM_ID;
    config->message_size = DEFAULT_MESSAGE_SIZE;
    config->message_count = DEFAULT_MESSAGE_COUNT;
    config->target_message_count = DEFAULT_TARGET_MESSAGE_COUNT;
    config->fragment_limit = DEFAULT_FRAGMENT_LIMIT;
}

void load_config_from_env(config_t *config) {
    if (!config) return;
    
    const char *aeron_dir = getenv("AERON_DIR");
    if (aeron_dir) {
        strncpy(config->aeron_dir, aeron_dir, sizeof(config->aeron_dir) - 1);
        config->aeron_dir[sizeof(config->aeron_dir) - 1] = '\0';
    } else {
        // 使用默认值
        strncpy(config->aeron_dir, "/dev/shm/aeron", sizeof(config->aeron_dir) - 1);
        config->aeron_dir[sizeof(config->aeron_dir) - 1] = '\0';
    }
}

const char* transport_type_to_string(transport_type_t type) {
    switch (type) {
        case TRANSPORT_UDP: return "UDP";
        case TRANSPORT_IPC: return "IPC"; 
        case TRANSPORT_NETWORK_UDP: return "NETWORK_UDP";
        default: return "UNKNOWN";
    }
}

const char* get_effective_channel(const config_t *config, char *buffer, size_t buffer_size) {
    if (!config || !buffer || buffer_size == 0) {
        return NULL;
    }
    
    switch (config->transport_type) {
        case TRANSPORT_UDP:
            if (config->custom_endpoint[0] != '\0') {
                snprintf(buffer, buffer_size, "aeron:udp?endpoint=%s:20121", config->custom_endpoint);
            } else {
                snprintf(buffer, buffer_size, "aeron:udp?endpoint=localhost:20121");
            }
            break;
            
        case TRANSPORT_IPC:
            snprintf(buffer, buffer_size, "aeron:ipc?term-length=1048576");
            break;
            
        case TRANSPORT_NETWORK_UDP:
            if (config->custom_endpoint[0] != '\0') {
                snprintf(buffer, buffer_size, "aeron:udp?endpoint=%s:20121", config->custom_endpoint);
            } else {
                snprintf(buffer, buffer_size, "aeron:udp?endpoint=localhost:20121");
            }
            break;
            
        default:
            snprintf(buffer, buffer_size, "aeron:udp?endpoint=localhost:20121");
            break;
    }
    
    return buffer;
}

int parse_publisher_args(int argc, char **argv, config_t *config) {
    if (!config) return ERROR_INVALID_PARAM;
    
    set_default_config(config);
    load_config_from_env(config);
    
    static struct option long_options[] = {
        {"size", required_argument, 0, 's'},
        {"count", required_argument, 0, 'c'},
        {"transport", required_argument, 0, 't'},
        {"bind", required_argument, 0, 'b'},
        {"listen", required_argument, 0, 'l'},
        {"endpoint", required_argument, 0, 'e'},
        {"ip", required_argument, 0, 'i'},
        {"help", no_argument, 0, 'h'},
        {0, 0, 0, 0}
    };
    
    int opt;
    int option_index = 0;
    
    while ((opt = getopt_long(argc, argv, "s:c:t:b:l:e:i:h", long_options, &option_index)) != -1) {
        switch (opt) {
            case 's':
                config->message_size = (size_t)atoi(optarg);
                break;
                
            case 'c':
                config->message_count = (uint64_t)atoll(optarg);
                break;
                
            case 't':
                if (strcmp(optarg, "UDP") == 0 || strcmp(optarg, "udp") == 0) {
                    config->transport_type = TRANSPORT_UDP;
                } else if (strcmp(optarg, "IPC") == 0 || strcmp(optarg, "ipc") == 0) {
                    config->transport_type = TRANSPORT_IPC;
                } else if (strcmp(optarg, "NETWORK_UDP") == 0 || strcmp(optarg, "network_udp") == 0) {
                    config->transport_type = TRANSPORT_NETWORK_UDP;
                } else {
                    fprintf(stderr, "错误: 无效的传输方式: %s\n", optarg);
                    return ERROR_INVALID_PARAM;
                }
                break;
                
            case 'b':
            case 'l':
            case 'e':
            case 'i':
                strncpy(config->custom_endpoint, optarg, sizeof(config->custom_endpoint) - 1);
                config->custom_endpoint[sizeof(config->custom_endpoint) - 1] = '\0';
                printf("Publisher将绑定到: %s:20121\n", config->custom_endpoint);
                break;
                
            case 'h':
                print_publisher_usage(argv[0]);
                return 1;  // 表示显示帮助后退出
                
            default:
                fprintf(stderr, "错误: 未知参数\n");
                print_publisher_usage(argv[0]);
                return ERROR_INVALID_PARAM;
        }
    }
    
    return validate_config(config);
}

int parse_subscriber_args(int argc, char **argv, config_t *config) {
    if (!config) return ERROR_INVALID_PARAM;
    
    set_default_config(config);
    load_config_from_env(config);
    
    static struct option long_options[] = {
        {"count", required_argument, 0, 'c'},
        {"transport", required_argument, 0, 't'},
        {"connect", required_argument, 0, 'o'},
        {"endpoint", required_argument, 0, 'e'},
        {"ip", required_argument, 0, 'i'},
        {"help", no_argument, 0, 'h'},
        {0, 0, 0, 0}
    };
    
    int opt;
    int option_index = 0;
    
    while ((opt = getopt_long(argc, argv, "c:t:o:e:i:h", long_options, &option_index)) != -1) {
        switch (opt) {
            case 'c':
                config->target_message_count = (uint64_t)atoll(optarg);
                break;
                
            case 't':
                if (strcmp(optarg, "UDP") == 0 || strcmp(optarg, "udp") == 0) {
                    config->transport_type = TRANSPORT_UDP;
                } else if (strcmp(optarg, "IPC") == 0 || strcmp(optarg, "ipc") == 0) {
                    config->transport_type = TRANSPORT_IPC;
                } else if (strcmp(optarg, "NETWORK_UDP") == 0 || strcmp(optarg, "network_udp") == 0) {
                    config->transport_type = TRANSPORT_NETWORK_UDP;
                } else {
                    fprintf(stderr, "错误: 无效的传输方式: %s\n", optarg);
                    return ERROR_INVALID_PARAM;
                }
                break;
                
            case 'o':
            case 'e':
            case 'i':
                strncpy(config->custom_endpoint, optarg, sizeof(config->custom_endpoint) - 1);
                config->custom_endpoint[sizeof(config->custom_endpoint) - 1] = '\0';
                printf("Subscriber将连接到: %s:20121\n", config->custom_endpoint);
                break;
                
            case 'h':
                print_subscriber_usage(argv[0]);
                return 1;  // 表示显示帮助后退出
                
            default:
                fprintf(stderr, "错误: 未知参数\n");
                print_subscriber_usage(argv[0]);
                return ERROR_INVALID_PARAM;
        }
    }
    
    return validate_config(config);
}

int validate_config(config_t *config) {
    if (!config) return ERROR_INVALID_PARAM;
    
    // 验证消息大小
    if (config->message_size < MIN_MESSAGE_SIZE) {
        fprintf(stderr, "错误: 消息大小必须至少%d字节(用于时间戳)\n", MIN_MESSAGE_SIZE);
        return ERROR_INVALID_PARAM;
    }
    
    // 验证消息数量
    if (config->message_count == 0 || config->target_message_count == 0) {
        fprintf(stderr, "错误: 消息数量必须大于0\n");
        return ERROR_INVALID_PARAM;
    }
    
    // 验证NETWORK_UDP模式必须指定端点
    if (config->transport_type == TRANSPORT_NETWORK_UDP && config->custom_endpoint[0] == '\0') {
        fprintf(stderr, "错误: NETWORK_UDP模式必须指定IP地址\n");
        return ERROR_INVALID_PARAM;
    }
    
    return ERROR_SUCCESS;
}

void print_publisher_usage(const char *program_name) {
    printf("用法: %s [选项]\n", program_name);
    printf("\n");
    printf("选项:\n");
    printf("  -s, --size <bytes>        消息大小 (默认: %d)\n", DEFAULT_MESSAGE_SIZE);
    printf("  -c, --count <num>         测试消息数 (默认: %d)\n", DEFAULT_MESSAGE_COUNT);
    printf("  -t, --transport <方式>    传输方式: UDP, IPC 或 NETWORK_UDP (默认: UDP)\n");
    printf("  -b, --bind <IP>           绑定到指定IP地址 (Publisher监听地址)\n");
    printf("  -l, --listen <IP>         绑定到指定IP地址 (同 -bind)\n");
    printf("  -e, --endpoint <IP>       绑定到指定IP地址 (同 -bind)\n");
    printf("  -i, --ip <IP>             绑定到指定IP地址 (同 -bind)\n");
    printf("  -h, --help                显示帮助信息\n");
    printf("\n");
    printf("传输方式:\n");
    printf("  UDP        - 使用UDP网络传输 (默认localhost，可用-bind指定IP)\n");
    printf("  IPC        - 使用进程间通信 (适合本机超低延迟测试)\n");
    printf("  NETWORK_UDP - 使用UDP网络传输到指定IP (需要-bind参数)\n");
    printf("\n");
    printf("示例:\n");
    printf("  %s                                      # 使用默认设置\n", program_name);
    printf("  %s -t IPC                               # 使用IPC模式\n", program_name);
    printf("  %s -bind 0.0.0.0 -c 10000000            # 监听所有接口，1000万条消息\n", program_name);
}

void print_subscriber_usage(const char *program_name) {
    printf("用法: %s [选项]\n", program_name);
    printf("\n");
    printf("选项:\n");
    printf("  -c, --count <数量>        目标消息数量 (默认: %d)\n", DEFAULT_TARGET_MESSAGE_COUNT);
    printf("  -t, --transport <方式>    传输方式: UDP, IPC 或 NETWORK_UDP (默认: UDP)\n");
    printf("  -o, --connect <IP>        连接到Publisher的IP地址\n");
    printf("  -e, --endpoint <IP>       连接到Publisher的IP地址 (同 -connect)\n");
    printf("  -i, --ip <IP>             连接到Publisher的IP地址 (同 -connect)\n");
    printf("  -h, --help                显示此帮助信息\n");
    printf("\n");
    printf("传输方式:\n");
    printf("  UDP        - 使用UDP网络传输 (默认连接localhost，可用-connect指定Publisher IP)\n");
    printf("  IPC        - 使用进程间通信 (适合本机超低延迟测试)\n");
    printf("  NETWORK_UDP - 使用UDP网络传输连接指定IP (需要-connect参数)\n");
    printf("\n");
    printf("示例:\n");
    printf("  %s                                      # 使用默认UDP模式\n", program_name);
    printf("  %s -t IPC                               # 使用IPC模式\n", program_name);
    printf("  %s -c 50000000                          # 5000万条消息\n", program_name);
    printf("  %s -connect 192.168.0.106               # 连接到指定IP\n", program_name);
}

void print_config_summary(const config_t *config) {
    if (!config) return;
    
    char channel_buffer[512];
    
    printf("=== Aeron二进制高性能测试配置 ===\n");
    printf("传输方式: %s\n", transport_type_to_string(config->transport_type));
    printf("Channel: %s\n", get_effective_channel(config, channel_buffer, sizeof(channel_buffer)));
    printf("Stream ID: %d\n", config->stream_id);
    printf("消息大小: %zu bytes\n", config->message_size);
    printf("\n");
}