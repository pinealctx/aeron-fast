#ifndef CONFIG_PARSER_H
#define CONFIG_PARSER_H

#include "common_types.h"

// 命令行参数解析
int parse_publisher_args(int argc, char **argv, config_t *config);
int parse_subscriber_args(int argc, char **argv, config_t *config);

// 配置验证和默认值设置
int validate_config(config_t *config);
void set_default_config(config_t *config);

// 配置打印和帮助
void print_publisher_usage(const char *program_name);
void print_subscriber_usage(const char *program_name);
void print_config_summary(const config_t *config);

// 环境变量支持
void load_config_from_env(config_t *config);

// 获取有效的Channel字符串
const char* get_effective_channel(const config_t *config, char *buffer, size_t buffer_size);

// 传输类型转换
const char* transport_type_to_string(transport_type_t type);

#endif // CONFIG_PARSER_H