/*
 * Copyright 2025 Rockchip Electronics Co. LTD
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 */
#ifndef RKNNSMI_COMMON_H
#define RKNNSMI_COMMON_H

#include <stdint.h>
#include <stdbool.h>

#define MAX_FREQ_CNT         10
#define MAX_DEVICE_CNT       16
#define MAX_CHIP_CNT         16
#define MAX_CHIP_INFO_LEN    32
#define MAX_PRODUCT_INFO_LEN 32

/* API return codes */
#define RKNNSMI_SUCCESS            0  // 成功
#define RKNNSMI_ERR_GENERIC        -1 // 通用错误
#define RKNNSMI_ERR_PARAMETER      -2 // 参数错误
#define RKNNSMI_ERR_ACCESS_DENIED  -3 // 拒绝访问，权限错误
#define RKNNSMI_ERR_STATE          -4 // 状态错误，如设备未就绪等
#define RKNNSMI_ERR_NOT_SUPPORTED  -5 // 功能不支持
#define RKNNSMI_ERR_INVALID_DEVICE -6 // 不支持的设备，如指定的 ID 不存在等
#define RKNNSMI_ERR_TIMEOUT        -7 // 超时
#define RKNNSMI_ERR_MEM            -8 // 内存操作错误，如内存不足

/* nsmi command */
#define RKNNSMI_CMD_IDLE 0 // 空闲

#define RKNNSMI_CMD_GET_VERSION            1  // 获取版本号
#define RKNNSMI_CMD_GET_CHIP_LIST          2  // 获取芯片列表
#define RKNNSMI_CMD_GET_CHIP_INFO          3  // 获取芯片信息
#define RKNNSMI_CMD_GET_DEVICE_INFO        4  // 获取设备信息
#define RKNNSMI_CMD_GET_CPU_INFO           5  // 获取 CPU 信息
#define RKNNSMI_CMD_GET_NPU_INFO           6  // 获取 NPU 信息
#define RKNNSMI_CMD_GET_DEVICE_POWER       7  // 获取设备功耗
#define RKNNSMI_CMD_GET_DEVICE_VOLTAGE     8  // 获取设备电压
#define RKNNSMI_CMD_GET_CHIP_HEALTH        9  // 获取芯片健康状态
#define RKNNSMI_CMD_GET_SYSTEM_TIME        10 // 获取系统时间
#define RKNNSMI_CMD_GET_CHIP_TEMPERATURE   11 // 获取芯片温度
#define RKNNSMI_CMD_GET_DEVICE_TEMPERATURE 12 // 获取设备温度
#define RKNNSMI_CMD_GET_MEMORY_INFO        13 // 获取内存信息
#define RKNNSMI_CMD_GET_FAN_INFO           14 // 获取风扇信息
#define RKNNSMI_CMD_GET_RESET_REASON       15 // 获取复位原因
#define RKNNSMI_CMD_GET_WORK_MODE          16 // 获取工作模式
#define RKNNSMI_CMD_GET_PREFILL_MODE       17 // 获取预填充模式
#define RKNNSMI_CMD_GET_DEVICE_CURRENT     18 // 获取设备电流

#define RKNNSMI_CMD_RESET_DEVICE     101 // 重启设备
#define RKNNSMI_CMD_SET_CPU_FREQ     102 // 设置 CPU 频率
#define RKNNSMI_CMD_SET_NPU_FREQ     103 // 设置 NPU 频率
#define RKNNSMI_CMD_SET_LOG_LEVEL    104 // 设置日志等级
#define RKNNSMI_CMD_SET_WORK_MODE    105 // 设置工作模式
#define RKNNSMI_CMD_SET_PREFILL_MODE 106 // 设置预填充模式

#define RKNNSMI_CMD_COLLECT_LOG 201 // 收集日志
#define RKNNSMI_CMD_GET_LOG_LEN 202 // 获取日志长度

#define RKNNSMI_CMD_HEARTBEAT 999 // 心跳

/* nsmi task command */
#define NSMI_TASK_CMD_GET_CURRENT_LOG 0
#define NSMI_TASK_CMD_GET_LAST_LOG    1

enum NSMI_COMM_STATE {
    NSMI_COMM_STATE_IDLE = 0,
    NSMI_COMM_STATE_REQUEST,
    NSMI_COMM_STATE_RESPONSE_OK,
    NSMI_COMM_STATE_RESPONSE_ERROR,
};

/* data structure */
typedef enum {
    NSMI_COMM_MODE_PCIE = 0,
    NSMI_COMM_MODE_USB,
} NSMI_COMM_MODE;

enum NSMI_WORK_MODE {
    NSMI_WORK_MODE_EFFICIENT = 0,
    NSMI_WORK_MODE_NORMAL,
    NSMI_WORK_MODE_PERFORMANCE,
    NSMI_WORK_MODE_USER,
    NSMI_WORK_MODE_UNDEFINED,
};

enum NSMI_PREFILL_MODE {
    NSMI_PREFILL_MODE_EFFICIENT = 0,
    NSMI_PREFILL_MODE_PERFORMANCE,
    NSMI_PREFILL_MODE_UNDEFINED,
};

enum NSMI_CHIP_HEALTH_STATUS {
    NSMI_CHIP_HEALTH_STATUS_OK = 0,   // 正常
    NSMI_CHIP_HEALTH_STATUS_WARNING,  // 一般告警
    NSMI_CHIP_HEALTH_STATUS_ALARM,    // 重要告警
    NSMI_CHIP_HEALTH_STATUS_CRITICAL, // 紧急告警
    NSMI_CHIP_HEALTH_STATUS_UNKNOWN,  // 未知状态
    NSMI_CHIP_HEALTH_STATUS_MAX,
};

enum NSMI_VERSION_TYPE {
    NSMI_VERSION_TYPE_NSMI = 0,         // rk_nsmi 版本
    NSMI_VERSION_TYPE_PCIE_DRV,         // PCIe 驱动版本
    NSMI_VERSION_TYPE_RC_CHIPS_CONNECT, // RC 端 chips_connect 版本
    NSMI_VERSION_TYPE_EP_CHIPS_CONNECT, // EP 端 chips_connect 版本
    NSMI_VERSION_TYPE_FIRMWARE,         // NPU 设备固件版本
    NSMI_VERSION_TYPE_LIBRKNN3_API,     // librknn3_api 库版本
    NSMI_VERSION_TYPE_NSMI_MAX,
};

enum NSMI_RESET_REASON {
    NSMI_RESET_REASON_NPOR = 0,
    NSMI_RESET_REASON_SOFT,
    NSMI_RESET_REASON_TSADC,
    NSMI_RESET_REASON_SUBSOC_WDT,
    NSMI_RESET_REASON_VRV0_WDT,
    NSMI_RESET_REASON_VRV1_WDT,
    NSMI_RESET_REASON_CRC_CHECK,
    NSMI_RESET_REASON_MAX,
};

enum NSMI_LOG_MODULE {
    NSMI_LOG_MODULE_NSMI_HOST = 0, // 主机端 NSMI 日志
    NSMI_LOG_MODULE_NSMI_DEVICE,   // 设备端 NSMI 日志
    NSMI_LOG_MODULE_MAX,
};

typedef enum {
    NSMI_LOG_VERBOSE = 0,
    NSMI_LOG_DEBUG,
    NSMI_LOG_INFO,
    NSMI_LOG_WARN,
    NSMI_LOG_ERROR,
    NSMI_LOG_NONE
} NSMI_LOG_LEVEL;

struct nsmi_chip_list {
    uint16_t chip_num;
    uint16_t chip_id[MAX_CHIP_CNT];
};

struct nsmi_chip_info {
    uint16_t chip_id;
    char chip_name[MAX_CHIP_INFO_LEN];
    char chip_ver[MAX_CHIP_INFO_LEN];
    unsigned char cpuid[MAX_CHIP_INFO_LEN];
    uint16_t cpuid_len;
    uint16_t cpu_cnt;
    uint16_t npu_cnt;
};

struct nsmi_device_list {
    uint16_t count;
    struct {
        NSMI_COMM_MODE mode;
        uint16_t global_id;
        uint16_t internal_id;
    } dev[MAX_DEVICE_CNT];
};
struct nsmi_device_info {
    uint16_t device_id;
    char product_name[MAX_PRODUCT_INFO_LEN];
    char manufacturer[MAX_PRODUCT_INFO_LEN];
    char serial_num[MAX_PRODUCT_INFO_LEN];
    char reserve[64];
};

struct nsmi_pcie_info {
    bool dev_is_alive;      // 设备是否在线
    uint32_t vendor_id;     // 厂商 ID
    uint32_t device_id;     // 设备 ID
    uint32_t sub_vendor_id; // 厂商子 ID
    uint32_t sub_device_id; // 设备子 ID
    uint32_t domain;
    uint32_t bdf_bus_id;    // BDF 中的总线 ID
    uint32_t bdf_device_id; // BDF 中的设备 ID
    uint32_t bdf_func_id;   // BDF 中的功能 ID
    char reserve[64];
};

struct nsmi_cpu_info {
    uint16_t cur_freq;                        // 当前频率，单位 MHz
    uint16_t support_freq_list[MAX_FREQ_CNT]; // 支持的频率列表，单位 HMz
    uint16_t support_freq_cnt;                // 支持的频率个数
    uint16_t core_cnt;                        // CPU 核的个数
    uint16_t util_rate;                       // CPU 使用率，单位%
};

struct nsmi_npu_info {
    uint16_t cur_freq;                        // 当前频率，单位 MHz
    uint16_t support_freq_list[MAX_FREQ_CNT]; // 支持的频率列表，单位 HMz
    uint16_t support_freq_cnt;                // 支持的频率个数
    uint16_t core_cnt;                        // NPU 核的个数
    uint16_t util_rate;                       // NPU 使用率，单位%
};

struct nsmi_memory_info {
    uint64_t total_size;                      // 内存总大小，单位 Byte
    uint64_t free_size;                       // 可用内存大小，单位 Byte
    uint32_t hugepage_size;                   // 大页的大小，单位 Byte, reserve
    uint32_t hugepage_total_cnt;              // 大页的总数量, reserve
    uint32_t hugepage_free_cnt;               // 大页的可用数量, reserve
    uint16_t util_rate;                       // 内存带宽占用率，单位%
    uint16_t cur_freq;                        // DDR 当前频率，单位 MHz
    uint16_t support_freq_list[MAX_FREQ_CNT]; // 支持的频率列表，单位 HMz
    uint16_t support_freq_cnt;                // 支持的频率个数
};

struct nsmi_set_freq_info {
    uint16_t chip_id;  // 芯片 ID
    uint16_t set_freq; // 设置频率，单位 MHz
};

struct nsmi_log_level {
    uint16_t chip_id;   // 芯片 ID
    uint16_t log_level; // 设置等级
};

struct nsmi_work_mode {
    uint16_t chip_id;         // 芯片 ID
    enum NSMI_WORK_MODE mode; // 工作模式
};

struct nsmi_prefill_mode {
    uint16_t chip_id;            // 芯片 ID
    enum NSMI_PREFILL_MODE mode; // 预填充模式
};

struct nsmi_collect_log_info {
    char log_path[64]; // 日志目录
    uint16_t log_type; // 日志类型
    uint32_t log_len;  // 日志长度
};

/* PCIe shm */
#define NSMI_PCIE_MAGIC_NUMBER 0x524B5656
#define NSMI_PCIE_DRV_VERSION  0x00000001
#define NSMI_PCIE_BAR_OFFSET   0x1000 // BAR1 + 4KB
#define NSMI_PCIE_BAR_SIZE     0x3000 // 12KB

#define NSMI_PCIE_MAX_DATA_SIZE 4096

struct pcie_shm_head {
    volatile uint32_t magic;
    volatile uint32_t version;
    volatile uint32_t cmd;
    volatile uint32_t status; // enum NSMI_COMM_STATE
};

struct nsmi_pcie_shm {
    volatile struct pcie_shm_head shm_head;
    volatile uint32_t data_size;
    volatile uint32_t data[NSMI_PCIE_MAX_DATA_SIZE / sizeof(uint32_t)];
};

struct task_user_cmd_st {
    unsigned int cmd;
};

/* USB frame */
#define NSMI_USB_MAX_DATA_SIZE 4096
#define NSMI_USB_HEADER_VAL    0x696D736E //'nsmi'小端

struct nsmi_usb_frame_header {
    volatile uint32_t head;
    volatile uint32_t cmd;
    volatile uint32_t status; // enum NSMI_COMM_STATE
    volatile uint32_t data_size;
    volatile uint32_t crc32;
};

#endif // RKNNSMI_COMMON_H
