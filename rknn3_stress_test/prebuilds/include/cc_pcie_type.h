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
#ifndef __INCLUDE_CC_PCIE_TYPE_H__
#define __INCLUDE_CC_PCIE_TYPE_H__

#define CC_VERSION                      0x00030200 /* XXAABBCC VerAA.BB.CC, like V3.0.0 */
#define COMPATIBLE_CC_VERSION           0x00030200
#define COMPATIBLE_FUNC_DRV_VERSION     0x00030200

/* rkep device mode status definition */
#define RKEP_MODE_BOOTROM               1
#define RKEP_MODE_LOADER                2
#define RKEP_MODE_KERNEL                3
#define RKEP_MODE_FUN0                  4
#define RKEP_MODE_ERR                   0xffff
/* Common status */
#define RKEP_SMODE_INIT                 0
#define RKEP_SMODE_LNKRDY               1
#define RKEP_SMODE_LNKUP                2
#define RKEP_SMODE_ERR                  0xffff
/* Firmware download status */
#define RKEP_SMODE_FWDLRDY              0x10
#define RKEP_SMODE_FWDLDONE             0x11
/* Application status*/
#define RKEP_SMODE_APPRDY               0x20
#define RKEP_SMODE_APPDEINIT            0x21

/* DMA Task Max NUM */
#ifdef CONFIG_CC_TINY_VER
#define PCIE_DMA_TASK_MAX               (8)
#else
#define PCIE_DMA_TASK_MAX               (255)
#endif

/* Task 消息数据最大长度 */
#define TASK_MSG_DATA_SIZE              (1504)   //1.5k - 32

/* 替换buff的buff数量，和单个任务的最大buff数量一致 */
#define PCIE_REPLACE_BUFF_MAX_NUM       (7)

enum EBuff_Type {
    E_SEND = 0, //send buff
    E_RECV,    //recv buff
};

enum EMem_type {
    E_MEM_TYPE_MIN = 0,
    E_MEM_TYPE_HUGEPAGE,
    E_MEM_TYPE_RKDRM,
    E_MEM_TYPE_RKEP,
    E_MEM_TYPE_DUMMY,
    E_MEM_TYPE_MAX,
};

enum ETask_Msg_Type {
    E_TASK_MSG_NONE = 0,
    E_TASK_MSG_CREATE,      //Create Task
    E_TASK_MSG_DESTROY,     //Destory Task
    E_TASK_MSG_USER,        //User
    E_TASK_MSG_MAX,
};

struct pcie_buff_node {
    unsigned char *vir_addr;
    unsigned long long phy_addr;
    unsigned int size;
};

struct pcie_task_msg_st {
    enum ETask_Msg_Type type;
    int task_id;
    unsigned int size;
    char lock;
    unsigned char data[TASK_MSG_DATA_SIZE];
};

struct pcie_err_event_count {
    unsigned char ebuf_overflow;
    unsigned char ebuf_under_run;
    unsigned char decode_error;
    unsigned char running_disparity_error;
    unsigned char skp_os_parity_error;
    unsigned char sync_header_error;
    unsigned char ctl_skp_os_parity_error;
    unsigned char detect_ei_infer;
    unsigned char receiver_error;
    unsigned char rx_recovery_request;
    unsigned char n_fts_timeout;
    unsigned char framing_error;
    unsigned char deskew_error;
    unsigned char bad_tlp;
    unsigned char lrc_error;
    unsigned char bad_dllp;
    unsigned char replay_number_rollover;
    unsigned char replay_timeout;
    unsigned char rx_nak_dllp;
    unsigned char tx_nak_dllp;
    unsigned char retry_tlp;
    unsigned char fc_timeout;
    unsigned char poisoned_tlp;
    unsigned char ecr_error;
    unsigned char unsupported_request;
    unsigned char completer_abort;
    unsigned char completion_timeout;
    /* The location above is hardware information and cannot be changed */
    unsigned char redundant_phase;
};


typedef struct pcie_buff_node pcie_replace_buff_info_st;

struct pcie_replace_buff_info_list_st {
    pcie_replace_buff_info_st info[PCIE_REPLACE_BUFF_MAX_NUM];
    unsigned int buff_num;
};

#endif // __INCLUDE_CC_PCIE_TYPE_H__
