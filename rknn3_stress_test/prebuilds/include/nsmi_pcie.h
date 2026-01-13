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
#ifndef NSMI_PCIE_H
#define NSMI_PCIE_H

#include <stdint.h>
#include "rk_pcie_rc.h"
#include "cc_pcie_type.h"

struct pcie_additional_info {
    struct pcie_ep_obj_info_for_user ep_obj_info;
    uint32_t domain;
    uint32_t bdf_bus_id;
    uint32_t bdf_device_id;
    uint32_t bdf_func_id;
};

extern const nsmi_comm_ops pcie_ops;

int pcie_get_dev_num(int *dev_num);
int pcie_dev_is_alive(void *ctx, uint16_t device_id, bool *is_alive);
int pcie_get_additional_info(void *ctx, uint16_t device_id, struct pcie_additional_info *pcie_info);
int pcie_hw_reset_device(void *ctx, uint16_t device_id);
int pcie_get_ep_err_even_count(void *ctx, uint16_t device_id, struct pcie_err_event_count *info);

#endif // NSMI_PCIE_H