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
#ifndef RKNNSMI_H
#define RKNNSMI_H

#include "rknnsmi_common.h"
#include "cc_pcie_type.h"

typedef struct {
    int (*init)(void **ctx);
    int (*send)(void *ctx, uint16_t device_id, uint32_t cmd, void *data, uint32_t data_size);
    int (*receive)(void *ctx, uint16_t device_id, uint32_t max_data_size, void *data, uint32_t *data_size);
    int (*deinit)(void *ctx);
} nsmi_comm_ops;

int rknnsmi_init(void);
int rknnsmi_deinit(void);
int rknnsmi_get_device_list(struct nsmi_device_list *list);
int rknnsmi_get_version(char *version, size_t buffer_size, enum NSMI_VERSION_TYPE type, uint16_t device_id);
int rknnsmi_get_chip_list(uint16_t device_id, uint16_t *chip_num, uint16_t *chip_list, size_t list_size);
int rknnsmi_get_chip_info(uint16_t device_id, uint16_t chip_id, struct nsmi_chip_info *chip_info);
int rknnsmi_get_device_info(uint16_t device_id, struct nsmi_device_info *device_info);
int rknnsmi_get_pcie_info(uint16_t device_id, uint16_t chip_id, struct nsmi_pcie_info *pcie_info);
int rknnsmi_get_cpu_info(uint16_t device_id, uint16_t chip_id, struct nsmi_cpu_info *cpu_info);
int rknnsmi_get_npu_info(uint16_t device_id, uint16_t chip_id, struct nsmi_npu_info *npu_info);
int rknnsmi_get_device_power(uint16_t device_id, uint32_t *power);
int rknnsmi_get_device_voltage(uint16_t device_id, uint32_t *voltage);
int rknnsmi_get_chip_health(uint16_t device_id, uint16_t chip_id, enum NSMI_CHIP_HEALTH_STATUS *health);
int rknnsmi_get_system_time(uint16_t device_id, uint16_t chip_id, uint32_t *time);
int rknnsmi_get_chip_temperature(uint16_t device_id, uint16_t chip_id, int32_t *temperature);
int rknnsmi_get_device_temperature(uint16_t device_id, int32_t *temperature);
int rknnsmi_get_memory_info(uint16_t device_id, uint16_t chip_id, struct nsmi_memory_info *memory_info);
int rknnsmi_get_fan_info(uint16_t device_id, uint32_t *speed_ratio);
int rknnsmi_get_pcie_err_event_count(uint16_t device_id, struct pcie_err_event_count *err_event_count);
int rknnsmi_get_reset_reason(uint16_t device_id, uint16_t chip_id, enum NSMI_RESET_REASON *reason);
int rknnsmi_get_work_mode(uint16_t device_id, uint16_t chip_id, enum NSMI_WORK_MODE *work_mode);
int rknnsmi_reset_device(uint16_t device_id);
int rknnsmi_hw_reset_device(uint16_t device_id);
int rknnsmi_set_cpu_freq(uint16_t device_id, uint16_t chip_id, uint16_t cpu_freq);
int rknnsmi_set_npu_freq(uint16_t device_id, uint16_t chip_id, uint16_t npu_freq);
int rknnsmi_set_log_level(enum NSMI_LOG_MODULE module, uint16_t device_id, uint16_t chip_id, uint16_t level);
int rknnsmi_set_work_mode(uint16_t device_id, uint16_t chip_id, enum NSMI_WORK_MODE work_mode);
int rknnsmi_collect_log(uint16_t device_id, uint16_t log_type, char *log_dir);

#endif // RKNNSMI_H
