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
#ifndef __RK_PCIE_RC_H__
#define __RK_PCIE_RC_H__

#include "cc_type.h"
#include "rk_pcie_type.h"

/* Vendor和Device相同的PCI设备最大支持数量 */
#define PCI_DEV_MAX             32
/* PCI总线地址最大字符数量 */
#define PCI_BUS_MAX_NAME        16

typedef void* RK_PCIE_HANDLES;

struct pcie_dev_bus {
    int dev_max_num;
    char pci_bus_address[PCI_DEV_MAX][PCI_BUS_MAX_NAME];
};

struct pcie_dev_attr_st {
    int vendor_id;
    int device_id;
    char pci_bus_address[PCI_BUS_MAX_NAME];
    unsigned char using_rc_dma: 1;
    unsigned char enable_speed: 1;
    unsigned char use_dma_only_in_rc: 1;// 只在RC端调用DMA收发数据
    unsigned char dma_exclusive: 1;     // 单个任务独占DMA通道
    unsigned int mem_type;
};

struct pcie_task_attr_st {
    int wait_timeout_ms;
    unsigned int send_buff_num;
    unsigned int send_buff_size;
    unsigned int recv_buff_num;
    unsigned int recv_buff_size;
};

struct pcie_dev_mode {
    unsigned short mode;
    unsigned short submode;
};

struct pcie_ep_obj_info_for_user {
    unsigned int magic;
    unsigned int rc_cc_version;
    unsigned int ep_cc_version;
    unsigned int func_drv_version;
    unsigned int ep_drv_version;
    unsigned short vid;
    unsigned int did;
    unsigned int sub_vid;
    unsigned int sub_did;
    unsigned int ep_bar1_reserved;
    unsigned int ep_bar5_reserved;
};

struct SOC_INFO {
    char name[16];
    unsigned short pcie_vendor_id;
    unsigned short pcie_device_id;
    unsigned int pcie_boot_state_off;
    unsigned int pcie_boot_state_val;
};

extern struct SOC_INFO soc_info_table[3];

//获取系统中所有匹配的PCI设备总线地址
int rk_pcie_get_pci_bus_addresses(int vendor_id, int device_id, struct pcie_dev_bus *pci_bus);

//重新扫描PCI设备
void rk_pcie_rescan_devices(void);

//初始化pcie设备
RK_PCIE_HANDLES rk_pcie_device_init(struct pcie_dev_attr_st *dev);

//反初始化pcie设备，释放资源
int rk_pcie_device_deinit(RK_PCIE_HANDLES handles, int en_remove);

//初始化PCIE BOOT
int rk_pcie_boot_init(RK_PCIE_HANDLES handles);

//反初始化PCIE BOOT
int rk_pcie_boot_deinit(RK_PCIE_HANDLES handles);

//下载PCIE BOOT固件
int rk_pcie_boot_download_firmware(RK_PCIE_HANDLES handles, unsigned char *firmware, unsigned long long firmware_size, unsigned long long remote_load_addr);

//获取PCIE BOOT固件
int rk_pcie_boot_upload_firmware(RK_PCIE_HANDLES handles, unsigned char *firmware, unsigned long long firmware_size, unsigned long long remote_load_addr);

int rk_pcie_get_boot_state(RK_PCIE_HANDLES handles, unsigned int off);

int rk_pcie_set_fw_info(RK_PCIE_HANDLES handles, unsigned char *buf, unsigned int off, unsigned int size);

//运行PCIE BOOT固件
int rk_pcie_boot_run(RK_PCIE_HANDLES handles);

//创建task
int rk_pcie_task_create(RK_PCIE_HANDLES handles, struct pcie_task_attr_st *task);

//销毁task
int rk_pcie_task_destroy(RK_PCIE_HANDLES handles, int task_id);

//获取ep状态信息
int rk_pcie_get_ep_info(RK_PCIE_HANDLES handles, void *status, unsigned int status_size);

//获取bar1虚拟地址
void __iomem *rk_pcie_get_bar1_user_buffer(RK_PCIE_HANDLES handles);

//获取bar5虚拟地址
void __iomem *rk_pcie_get_bar5_user_buffer(RK_PCIE_HANDLES handles);

//修改bar映射内存
unsigned long long rk_pcie_set_bar_inbound_cpu_addr(RK_PCIE_HANDLES handles, unsigned int atu_index, unsigned long long cpu_address, unsigned int size);

//获取PCIe EP基础信息
int rk_pcie_get_ep_obj_info(RK_PCIE_HANDLES handles, struct pcie_ep_obj_info_for_user *info);

//获取PCIe EP错误事件计数
int rk_pcie_get_ep_err_event_count(RK_PCIE_HANDLES handles, struct pcie_err_event_count *info);

//检查PCIe 链路是否正常
int rk_pcie_is_alive(RK_PCIE_HANDLES handles);

//获取用户自定义命令区
void __iomem *rk_pcie_get_user_cmd(RK_PCIE_HANDLES handles);

//获取buff
struct pcie_buff_node *rk_pcie_get_buff(RK_PCIE_HANDLES handles, int task_id, enum EBuff_Type type);

//发送buff
int rk_pcie_send_buff(RK_PCIE_HANDLES handles, int task_id, struct pcie_buff_node *pbuff);

//释放buff
int rk_pcie_release_buff(RK_PCIE_HANDLES handles, int task_id, struct pcie_buff_node *pbuff);

//获取buff最大的size
long rk_pcie_get_buff_max_size(RK_PCIE_HANDLES handles, int task_id, enum EBuff_Type type);

//获取ep设备当前模式
int rk_pcie_get_ep_mode(RK_PCIE_HANDLES handles, struct pcie_dev_mode *devmode);

//发送消息到EP端
int rk_pcie_send_msg_to_ep_bus(RK_PCIE_HANDLES handles, int task_id, void *data, unsigned long long size);

//发送聚合消息到EP端
int rk_pcie_send_merge_msg_to_ep_bus(RK_PCIE_HANDLES handles, int task_id, void *data, unsigned long long size);

//通过Task id获取EP消息
int rk_pcie_get_msg_for_task_id(RK_PCIE_HANDLES handles, struct pcie_task_msg_st *msg, int task_id, int timeout_ms);

//内核驱动定制接口硬件复位控制器
int rk_pcie_device_hardware_reset(RK_PCIE_HANDLES handles);

// 替换所有buff的地址，用于配置用户自定义buff
int rk_pcie_replace_buff_all(RK_PCIE_HANDLES handle, int task_id, enum EBuff_Type type, struct pcie_replace_buff_info_list_st *infos);

// 替换buff的地址，用于配置用户自定义buff
int rk_pcie_replace_buff(RK_PCIE_HANDLES handle, int task_id, enum EBuff_Type type, struct pcie_buff_node *pbuff, pcie_replace_buff_info_st *info);

#endif
