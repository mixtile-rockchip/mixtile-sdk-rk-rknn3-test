/*
 * Copyright (c) 2025 by Rockchip Electronics Co., Ltd. All Rights Reserved.
 *
 * @brief RKNN3 (Rockchip Neural Network) Runtime API
 *
 * This header defines the public API for the RKNN3 runtime, including:
 * - Model loading and execution
 * - Tensor operations
 * - Memory management
 * - Session control for LLM models
 */

#ifndef _RKNN3_API_H
#define _RKNN3_API_H

#ifdef __cplusplus
extern "C" {
#endif

#include "float16.h"

#include <stdint.h>
#include <stdbool.h>

/**
 * @brief Error codes returned by RKNN3 API functions
 */
#define RKNN3_SUCCESS 0                       /** < execute succeed. */
#define RKNN3_ERR_FAIL -1                     /** < execute failed. */
#define RKNN3_ERR_ARGUMENT_INVALID -2         /** < parameter is invalid. */
#define RKNN3_ERR_MODEL_INVALID -3            /** < model is invalid. */
#define RKNN3_ERR_CTX_INVALID -4              /** < context is invalid. */
#define RKNN3_ERR_RUN_TASK_FAILED -5          /** < task run failed. */
#define RKNN3_ERR_OUT_OF_MEMORY -6            /** < out of memory. */
#define RKNN3_ERR_TIMEOUT -7                  /** < execute timeout. */
#define RKNN3_ERR_INPUT_INVALID -8            /** < input is invalid. */
#define RKNN3_ERR_OUTPUT_INVALID -9           /** < output is invalid. */
#define RKNN3_ERR_DEVICE_UNAVAILABLE -10      /** < device is unavailable. */
#define RKNN3_ERR_DEVICE_UNMATCH -11          /** < device is unmatch */
#define RKNN3_ERR_TARGET_PLATFORM_UNMATCH -12 /** < target platform is unmatch. */
#define RKNN3_ERR_COMMUNICATION -13           /** < communication error. */
#define RKNN3_ERR_MEM_SYNC_FAILED -14         /** < memory sync failed. */

/**
 * @brief Warning codes returned by RKNN3 API functions
 */
#define RKNN3_WARN_NPU_CORE_UNUSED -100 /* NPU core is not used, only as a warning, does not affect model execution */

/**
 * @brief Tensor-related constants
 */
#define RKNN3_MAX_DIMS 16                          /* maximum dimension of tensor. */
#define RKNN3_MAX_STRIDE_DIMS (RKNN3_MAX_DIMS + 1) /* maximum stride dimension of tensor. */
#define RKNN3_MAX_NAME_LEN 256                     /* maximum name length of tensor. */
#define RKNN3_MAX_DYNAMIC_SHAPE_NUM 512            /* maximum number of dynamic shape for each input. */
#define RKNN3_MAX_LORA_NUM 128                     /* maximum number of lora. */
#define RKNN3_MAX_SPECIAL_BOS_ID_NUM 64            /* maximum number of special Begin-Of-Sequence (BOS) token. */
#define RKNN3_MAX_SPECIAL_EOS_ID_NUM 64            /* maximum number of special End-Of-Sequence (EOS) token. */

/*
    Definition for device id
*/
#define RKNN3_MAX_DEVS 64    /* maximum number of device. */
#define RKNN3_MAX_DEV_LEN 64 /* maximum id/type length of device. */
#define RKNN3_MAX_NPU_NODE_NUM 128

#if defined(__arm__) || defined(__riscv) && __riscv_xlen == 32
typedef uint32_t rknn3_context;
#else
typedef uint64_t rknn3_context;
#endif

typedef void rknn3_session;

/**
 * @brief The query command for rknn3_query
 */
typedef enum _rknn3_query_cmd
{
  RKNN3_QUERY_IN_OUT_NUM  = 0, /** < query the number of input & output tensor. */
  RKNN3_QUERY_INPUT_ATTR  = 1, /** < query the attribute of input tensor. */
  RKNN3_QUERY_OUTPUT_ATTR = 2, /** < query the attribute of output tensor. */
  RKNN3_QUERY_PERF_DETAIL = 3, /** < query the detail performance, need set
                                 RKNN3_FLAG_COLLECT_PERF_MASK when call rknn3_init,
                                 this query needs to be valid after rknn3_outputs_get. */
  RKNN3_QUERY_PERF_RUN = 4,    /** < query the time of run,
                                 this query needs to be valid after rknn3_outputs_get. */
  RKNN3_QUERY_SDK_VERSION = 5, /** < query the sdk & driver version */

  RKNN3_QUERY_CORE_MEM_SIZE = 6, /** < query the weight & internal memory size of each core */

  RKNN3_QUERY_NATIVE_INPUT_ATTR  = 8, /** < query the attribute of native input tensor. */
  RKNN3_QUERY_NATIVE_OUTPUT_ATTR = 9, /** < query the attribute of native output tensor. */

  RKNN3_QUERY_DEVICE_MEM_INFO = 12, /** < query the attribute of rknn3 memory information. */

  RKNN3_QUERY_CORE_NUMBER = 13, /** < query the core number */

  RKNN3_QUERY_ALLOCATION_INFO = 14, /** < query the allocation info */

  RKNN3_QUERY_DYNAMIC_SHAPE_CONFIG = 15, /** < query the complete dynamic shape config */

  RKNN3_QUERY_DYNAMIC_SHAPE_INFO = 16, /** < query all supported shape combinations */

  RKNN3_QUERY_LLM_CONFIG = 17, /** < query the LLM config */

  RKNN3_QUERY_CMD_MAX
} rknn3_query_cmd;

/**
 * @brief The tensor data type.
 */
typedef enum _rknn3_tensor_type
{
  RKNN3_TENSOR_FLOAT32 = 0, /** < data type is float32. */
  RKNN3_TENSOR_FLOAT16,     /** < data type is float16. */
  RKNN3_TENSOR_INT8,        /** < data type is int8. */
  RKNN3_TENSOR_UINT8,       /** < data type is uint8. */
  RKNN3_TENSOR_INT16,       /** < data type is int16. */
  RKNN3_TENSOR_UINT16,      /** < data type is uint16. */
  RKNN3_TENSOR_INT32,       /** < data type is int32. */
  RKNN3_TENSOR_UINT32,      /** < data type is uint32. */
  RKNN3_TENSOR_INT64,       /** < data type is int64. */
  RKNN3_TENSOR_UINT64,      /** < data type is uint64. */
  RKNN3_TENSOR_BOOL,        /** < data type is boolean. */
  RKNN3_TENSOR_INT4,

  RKNN3_TENSOR_TYPE_MAX
} rknn3_tensor_type;

/**
 * @brief The quantitative type.
 */
typedef enum _rknn3_tensor_qnt_type
{
  RKNN3_TENSOR_QNT_NONE = 0,           /** < none. */
  RKNN3_TENSOR_PER_LAYER_SYMMETRIC,    /** < per layer symmetric. */
  RKNN3_TENSOR_PER_LAYER_ASYMMETRIC,   /** < per layer asymmetric. */
  RKNN3_TENSOR_PER_CHANNEL_SYMMETRIC,  /** < per channel symmetric. */
  RKNN3_TENSOR_PER_CHANNEL_ASYMMETRIC, /** < per channel asymmetric. */
  RKNN3_TENSOR_PER_GROUP_SYMMETRIC,    /** < per group symmetric. */
  RKNN3_TENSOR_PER_GROUP_ASYMMETRIC,   /** < per group asymmetric. */

  RKNN3_TENSOR_QNT_MAX
} rknn3_tensor_qnt_type;

/**
 * @brief The tensor data layout.
 */
typedef enum _rknn3_tensor_layout
{
  RKNN3_TENSOR_UNDEFINED = 0, /** < undefined. */
  RKNN3_TENSOR_NCHW,          /** < data layout is NCHW. */
  RKNN3_TENSOR_NHWC,          /** < data layout is NHWC. */
  RKNN3_TENSOR_NC1HWC2,       /** < data layout is NC1HWC2. */

  RKNN3_TENSOR_CHWN,       /** < reserved */
  RKNN3_TENSOR_HWIO,       /** < reserved */
  RKNN3_TENSOR_OIHW,       /** < reserved */
  RKNN3_TENSOR_O1I1HWI2O2, /** < reserved */

  RKNN3_TENSOR_LAYOUT_MAX
} rknn3_tensor_layout;

/**
 * @brief Memory allocation flags for creating RKNN3 tensor memory
 */
typedef enum _rknn3_mem_alloc_flags
{
  RKNN3_FLAG_MEMORY_FLAGS_DEFAULT = 0 << 0, /** < Same with RKNN3_FLAG_MEMORY_CACHEABLE */
  RKNN3_FLAG_MEMORY_CACHEABLE     = 1 << 0, /** < Create Cacheable memory. */
  RKNN3_FLAG_MEMORY_NON_CACHEABLE = 1 << 1, /** < Create NON-Cacheable memory. */
} rknn3_mem_alloc_flags;

/**
 * @brief Memory synchronization modes for rknn3_mem_sync function
 */
typedef enum _rknn3_mem_sync_mode
{
  /* the mode used for consistency of device access after CPU accesses data. */
  RKNN3_MEMORY_SYNC_TO_DEVICE = 0x1,
  /* the mode used for consistency of CPU access after device accesses data. */
  RKNN3_MEMORY_SYNC_FROM_DEVICE = 0x2,
  /* the mode used for consistency of data access between device and CPU in both directions. */
  RKNN3_MEMORY_SYNC_BIDIRECTIONAL = RKNN3_MEMORY_SYNC_TO_DEVICE | RKNN3_MEMORY_SYNC_FROM_DEVICE,
} rknn3_mem_sync_mode;

/**
 * @brief the mode of running on target NPU core.
 */
typedef enum _rknn3_core_mask
{
  RKNN3_NPU_CORE_AUTO = 0,          /* default, run on NPU core randomly. */
  RKNN3_NPU_CORE_0    = 1 << 0,     /* run on NPU core 0. */
  RKNN3_NPU_CORE_1    = 1 << 1,     /* run on NPU core 1. */
  RKNN3_NPU_CORE_2    = 1 << 2,     /* run on NPU core 2. */
  RKNN3_NPU_CORE_3    = 1 << 3,     /* run on NPU core 3. */
  RKNN3_NPU_CORE_4    = 1 << 4,     /* run on NPU core 4. */
  RKNN3_NPU_CORE_5    = 1 << 5,     /* run on NPU core 5. */
  RKNN3_NPU_CORE_6    = 1 << 6,     /* run on NPU core 6. */
  RKNN3_NPU_CORE_7    = 1 << 7,     /* run on NPU core 7. */
  RKNN3_NPU_CORE_ALL  = 0xffffffff, /* auto choice, run on NPU cores depending on platform */
} rknn3_core_mask;

/**
 * @brief Memory type for creating RKNN tensor memory
 */
typedef enum _rknn3_mem_type
{
  RKNN3_MEMORY_TYPE_NPU_DRAM = 0 << 0, /** < NPU DRAM memory. */
  RKNN3_MEMORY_TYPE_EXT_DDR  = 1 << 0, /** < External DDR memory. */
} rknn3_mem_type;

typedef enum _rknn3_kvcache_dtype
{
  RKNN3_KVCACHE_DTYPE_UNDEFINED = 0, /** < Undefined. */
  RKNN3_KVCACHE_DTYPE_INT4_TO_F16 = 1, /** < Int4 to F16. */
  RKNN3_KVCACHE_DTYPE_INT4_TO_F8 = 2, /** < Int4 to F8. */
  RKNN3_KVCACHE_DTYPE_INT8_TO_F16 = 3, /** < Int8 to F16. */
  RKNN3_KVCACHE_DTYPE_FLOAT4_TO_F16 = 4, /** < Float4 to F16. */
  RKNN3_KVCACHE_DTYPE_FLOAT4_TO_F8 = 5, /** < Float4 to F8. */
  RKNN3_KVCACHE_DTYPE_FLOAT8_TO_F16 = 6, /** < Float8 to F16. */
  RKNN3_KVCACHE_DTYPE_FLOAT8_TO_F8 = 7, /** < Float8 to F8. */
  RKNN3_KVCACHE_DTYPE_FLOAT16 = 8, /** < Float16. */
} rknn3_kvcache_dtype;

typedef enum _rknn3_kvcache_store_method
{
  RKNN3_KVCACHE_STORE_METHOD_UNDEFINED = 0, /** < Undefined. */
  RKNN3_KVCACHE_STORE_METHOD_NORMAL = 1, /** < Normal. */
  RKNN3_KVCACHE_STORE_METHOD_GROUP_QUANT = 2, /** < GroupQuant. */
} rknn3_kvcache_store_method;

/**
 * @brief the policy of KV cache.
 */
typedef enum
{
  RKNN3_KVCACHE_POLICY_DEFAULT,   /**< Default cache policy is RKNN3_KVCACHE_POLICY_RECURRENT */
  RKNN3_KVCACHE_POLICY_RECURRENT, /**< Use recurrent cache policy. */
  RKNN3_KVCACHE_POLICY_NORMAL     /**< Use normal cache policy. Only use KV cache with max_context_len */
} rknn3_kvcache_policy;

/**
 * @brief Policies for clearing KV cache
 *
 * Enumerates the different policies for clearing the key-value cache:
 * - RKNN3_KVCACHE_CLEAR_ALL: Completely clears all KV cache entries
 * - RKNN3_KVCACHE_KEEP_SYSTEM_PROMPT: Clears KV cache while preserving system prompt entries
 */
typedef enum
{
  RKNN3_KVCACHE_CLEAR_ALL = 0,      /**< Clear all KV cache entries */
  RKNN3_KVCACHE_KEEP_SYSTEM_PROMPT, /**< Clear KV cache but keep system prompt entries */
} rknn3_kvcache_clear_policy;

/**
 * @enum rknn3_llm_input_type
 * @brief Defines the types of inputs that can be fed into the LLM.
 */
typedef enum
{
  RKNN3_LLM_INPUT_PROMPT     = 0, /**< Input is a text prompt. */
  RKNN3_LLM_INPUT_TOKEN      = 1, /**< Input is a sequence of tokens. */
  RKNN3_LLM_INPUT_EMBED      = 2, /**< Input is an embedding vector. */
  RKNN3_LLM_INPUT_MULTIMODAL = 3, /**< Multimodal input */
  RKNN3_LLM_INPUT_AUX        = 4, /**< AUX input */
  RKNN3_LLM_INPUT_MAX,            /**< Maximum value for input type enumeration. */
} rknn3_llm_input_type;

/**
 * @enum LLMCallState
 * @brief Describes the possible states of an LLM call.
 */
typedef enum
{
  RKLLM_RUN_NORMAL                = 0, /**< The LLM call is in a normal running state. */
  RKLLM_RUN_WAITING               = 1, /**< The LLM call is waiting for complete UTF-8 encoded character. */
  RKLLM_RUN_FINISH                = 2, /**< The LLM call has finished execution. */
  RKLLM_RUN_STOP                  = 3, /**< The LLM call is stopped by user. */
  RKLLM_RUN_MAX_NEW_TOKEN_REACHED = 4, /**< The LLM call has reached the maximum number of new tokens. */
  RKLLM_RUN_ERROR                 = 5, /**< An error occurred during the LLM call. */
} LLMCallState;

/**
 * @brief The information for RKNN3_QUERY_IN_OUT_NUM.
 */
typedef struct _rknn3_input_output_num
{
  uint32_t n_input;  /** < the number of input. */
  uint32_t n_output; /** < the number of output. */
} rknn3_input_output_num;

/**
 * @brief Quantization information structure
 */
typedef struct
{
  float   scale;         /** < the pointer of scale data */
  int32_t zero_point;    /** < the pointer of zero point data */
} rknn3_quant_info;

/**
 * @brief The information for RKNN3_QUERY_INPUT_ATTR / RKNN3_QUERY_OUTPUT_ATTR.
 */
typedef struct _rknn3_tensor_attr
{
  uint32_t index;                /** < input parameter, the index of input/output tensor,
                                    need set before call rknn3_query. */
  char name[RKNN3_MAX_NAME_LEN]; /** < the name of tensor. */

  uint32_t n_dims;                        /** < the number of dimensions. */
  uint32_t shape[RKNN3_MAX_DIMS];         /** < the valid dimensions array. */
  uint64_t aligned_size;                  /** < the size of tensor with aligned shape in bytes. */
  uint32_t n_stride;                      /** < the number of stride. */
  uint64_t stride[RKNN3_MAX_STRIDE_DIMS]; /** < the stride of tensor, for example, the stride of a 16x16 tensor is [16*16, 16, 1]. */
  uint32_t n_elems;                       /** < the number of elements of tensor. */

  rknn3_tensor_type     dtype;    /** < the data type of tensor. */
  rknn3_tensor_layout   layout;   /** < the data layout of tensor. */
  rknn3_tensor_qnt_type qnt_type; /** < the quantization type of tensor. */
  rknn3_quant_info      qnt_info; /** < the quantization information of tensor. */

  int32_t core_id; /** < the core id of tensor buffer. */

} rknn3_tensor_attr;

/**
 * @brief The information for RKNN3_QUERY_PERF_DETAIL.
 */
typedef struct _rknn3_perf_detail
{
  char*    perf_data; /** < the string pointer of perf detail. don't need free it by user. */
  uint64_t data_len;  /** < the string length. */
} rknn3_perf_detail;

/**
 * @brief The information for RKNN3_QUERY_PERF_RUN.
 */
typedef struct _rknn3_perf_run
{
  int64_t run_duration; /** < real inference time (us) */
} rknn3_perf_run;

/**
 * @brief The information for RKNN3_QUERY_SDK_VERSION.
 */
typedef struct _rknn3_sdk_version
{
  char api_version[256]; /** < the version of rknn3 api. */
  char drv_version[256]; /** < the version of rknn3 driver. */
} rknn3_sdk_version;

/**
 * @brief The information for RKNN3_QUERY_CORE_MEM_SIZE.
 */
typedef struct _rknn3_core_mem_size
{
  int32_t core_id;        /** < the core id of memory. */
  uint64_t weight_size;   /** < the weight memory size */
  uint64_t internal_size; /** < the internal memory size */
  uint8_t  reserved[32];  /** < reserved */
} rknn3_core_mem_size;

/**
 * @brief The information for RKNN3_QUERY_CUSTOM_STRING.
 */
typedef struct _rknn3_custom_string
{
  char string[1024]; /* the string of custom, lengths max to 1024 bytes */
} rknn3_custom_string;

/**
 * @brief Tensor memory information structure
 */
typedef struct _rknn3_tensor_memory
{
  void*          virt_addr; /** < the virtual address of tensor buffer. */
  uint64_t       phys_addr; /** < the physical address of tensor buffer. */
  int32_t        fd;        /** < the fd of tensor buffer. */
  uint64_t       buffer_id; /** < the buffer id of tensor buffer, used for memory management. */
  uint64_t       offset;    /** < indicates the offset of the memory. */
  uint64_t       size;      /** < the size of tensor buffer. */
  uint64_t       flags;     /** < the flags of tensor buffer, reserved */
  int32_t        core_id;   /** < the id of npu core */
  void*          priv_data; /** < the private data of tensor buffer. */
  rknn3_mem_type mem_type;  /** < the memory type of tensor buffer. */
} rknn3_tensor_mem;

/**
 * @brief The control parameters for model loading.
 */
typedef struct _rknn3_config
{
  int32_t  priority;          /** < the priority of run */
  uint32_t run_timeout;       /** < the timeout of run in ms, 0 means no timeout */
  uint32_t run_core_mask;     /** < the core mask of model execution */
  uint8_t  user_mem_weight;   /** < whether the weight memory is allocated by user */
  uint8_t  user_mem_internal; /** < whether the internal memory is allocated by user */
  uint8_t  user_sram;         /** < whether the sram memory is allocated by user */
  uint8_t  reserved[128];     /** < reserved */
} rknn3_config;

/**
 * @brief Structure representing a RKNN3 tensor containing memory and attribute information
 *
 * This structure holds both the memory information and attributes of a tensor used in RKNN3 operations.
 * It serves as a fundamental data structure for handling tensors in the RKNN3 runtime.
 *
 * @struct _rknn3_tensor
 * @see rknn3_tensor_mem
 * @see rknn3_tensor_attr
 */
typedef struct _rknn3_tensor
{
  rknn3_tensor_mem*  mem;  /** < the memory information of tensor */
  rknn3_tensor_attr* attr; /** < the attribute of tensor */
} rknn3_tensor;

typedef rknn3_tensor rknn3_aux_tensor;

/**
 * @brief Structure containing memory allocation information for RKNN3 model.
 *
 * This structure provides detailed memory allocation information across different memory types
 * (command, weight, internal, kvcache) and their distribution across NPU cores.
 *
 */
typedef struct _rknn3_allocation_info
{
  int32_t           core_id;       /** < the physical id of npu core */
  rknn3_tensor_mem  command_mem;     /** < the memory information of command memory. */
  rknn3_tensor_mem  weight_mem;      /** < the memory information of weight memory. */
  rknn3_tensor_mem  internal_mem;  /** < the memory information of internal memory. */
  rknn3_tensor_mem  kvcache_mem;   /** < the memory information of kv cache memory. */
  uint8_t           reserved[128]; /** < reserved */
} rknn3_allocation_info;

/**
 * @brief Structure containing shape information for RKNN3 model tensors
 *
 * This structure holds comprehensive information about the shapes of input and output
 * tensors for an RKNN3 model, including tensor attributes and shape configuration details.
 *
 */
typedef struct _rknn3_shape_info
{
  int32_t            shape_id;     /** < the unique ID of this shape combination */
  uint32_t           n_inputs;     /** < the number of input tensors */
  rknn3_tensor_attr* input_attrs;  /** < array of input tensor attributes */
  uint32_t           n_outputs;    /** < the number of output tensors */
  rknn3_tensor_attr* output_attrs; /** < array of output tensor attributes */
  uint8_t            is_default;   /** < whether this is the default shape */
  uint8_t            reserved[31]; /** < reserved */
} rknn3_shape_info;

/**
 * @brief Configuration structure for dynamic shape settings
 *
 * This structure holds information about shape combinations and the current active shape
 * for dynamic shape inference in RKNN3 models.
 *
 * @param n_shapes Number of shape combinations available
 * @param current_shape_id ID of the currently active shape configuration. A value of -1 indicates no active shape
 */
typedef struct _rknn3_shape_config
{
  uint32_t n_shapes;         /** < Number of shape combinations available */
  int32_t  current_shape_id; /** < ID of the currently active shape configuration. */
} rknn3_shape_config;

/**
 * @brief Configuration structure for LLM (Language Learning Model)
 *
 * This structure contains the basic configuration parameters needed for
 * initializing and running a language learning model on RKNN3 session.
 */
typedef struct _rknn3_llm_config
{
  char*                      chat_template;           /** < chat template */
  uint32_t                   vocab_size;              /** < vocab size */
  uint32_t                   embedding_dim;           /** < embedding dim */
  uint32_t                   max_ctx_len;             /** < max context length */
  uint32_t                   max_position_embeddings; /** < max position embeddings */
  rknn3_kvcache_store_method kvcache_store_method;    /** < kvcache store method */
  rknn3_kvcache_dtype        kvcache_dtype;           /** < kvcache dtype */
  uint32_t                   kvcache_group_size;      /** < kvcache group size */
  uint32_t                   kvcache_residual_depth;  /** < kvcache residual depth */
  uint8_t                    reserved[128];           /** < reserved */
} rknn3_llm_config;

/**
 * @brief Structure containing device-specific initialization information
 *
 * This structure is used to specify device-specific parameters during the initialization
 * of the RKNN3 runtime context. It includes a device ID and reserved space for future use.
 *
 * @struct _rknn3_init_extend
 */
typedef struct _rknn3_init_extend
{
  char* device_id;       /** < input parameter, indicate which device selected. if only one
                            device connected, can set nullptr. */
  uint8_t reserved[128]; /** < reserved */
} rknn3_init_extend;

/**
 * @brief Structure containing memory information for RKNN3 device nodes
 *
 * This structure provides detailed memory information for each node in the RKNN3 device,
 * including total and free memory available for allocation.
 *
 * @struct _rknn3_node_mem_info
 */
typedef struct _rknn3_node_mem_info
{
  uint64_t total; /** < the total memory available for this node, unit Bytes */
  uint64_t free;  /** < the free memory available for this node, unit Bytes */
} rknn3_node_mem_info;

/**
 * @brief Structure containing memory information for RKNN3 device nodes
 *
 * This structure provides detailed memory information for each node in the RKNN3 device,
 * including total and free memory available for allocation.
 *
 * @struct _rknn3_dev_mem_info
 */
typedef struct _rknn3_dev_mem_info
{
  uint32_t            node_num;                              /** < the number of nodes in the device */
  uint64_t            sys_total;                             /** < the total system memory of the device, unit Bytes */
  uint64_t            sys_free;                              /** < the free system memory of the device, unit Bytes */
  rknn3_node_mem_info node_mem_info[RKNN3_MAX_NPU_NODE_NUM]; /** < the memory information of each node */
} rknn3_dev_mem_info;

/**
 * @brief Structure representing a RKNN3 device
 *
 * This structure contains information about a specific RKNN3 device, including its ID,
 * type, number of NPU cores, and memory information.
 *
 * @struct _rknn3_device
 * @see rknn3_dev_mem_info
 */
typedef struct
{
  char               id[RKNN3_MAX_DEV_LEN];   /** < the device ID. */
  char               type[RKNN3_MAX_DEV_LEN]; /** < the device type. */
  uint32_t           core_num;                /** < the number of NPU cores. */
  rknn3_dev_mem_info mem_info;                /** < the memory information of device. */
} rknn3_device;

/**
 * @brief Structure containing information about RKNN3 devices
 * @details This structure holds the count of available RKNN3 devices
 *
 * @see rknn3_device
 */
typedef struct
{
  uint32_t     n_devices;               /* the number of devices. */
  rknn3_device devices[RKNN3_MAX_DEVS]; /* the devices information. */
} rknn3_devices;

/**
 * @brief Structure containing vocabulary information for RKNN3 models
 *
 * This structure holds information about the vocabulary used in RKNN3 models,
 * including size and special token IDs.
 *
 * @struct _rknn3_vocab_info
 * @var _rknn3_vocab_info::vocab_size
 *   Size of the vocabulary
 * @var _rknn3_vocab_info::special_bos_id
 *   ID of the special Begin-Of-Sequence (BOS) token
 * @var _rknn3_vocab_info::special_eos_id
 *   ID of the special End-Of-Sequence (EOS) token
 * @var _rknn3_vocab_info::linefeed_id
 *   ID of the linefeed token
 * @var _rknn3_vocab_info::reserved
 *   Reserved bytes for future use
 */
typedef struct _rknn3_vocab_info
{
  int vocab_size; /**< Size of the vocabulary */

  // special tokens
  int special_bos_id[RKNN3_MAX_SPECIAL_BOS_ID_NUM]; /**< ID of the special Begin-Of-Sequence (BOS) token */
  int special_eos_id[RKNN3_MAX_SPECIAL_EOS_ID_NUM]; /**< ID of the special End-Of-Sequence (EOS) token */
  int n_special_bos_id;                             /**< Number of special Begin-Of-Sequence (BOS) token */
  int n_special_eos_id;                             /**< Number of special End-Of-Sequence (EOS) token */
  int linefeed_id;                                  /**< ID of the linefeed token */

  // token control
  bool skip_special_token; /**< Whether to skip special tokens during generation. */
  bool ignore_eos_token;   /**< Whether to ignore EOS token during generation. */

  uint8_t reserved[64];
} rknn3_vocab_info;

typedef struct
{
  uint8_t reserved[128]; /**< reserved */
} rknn3_llm_extend_param;

/**
 * @struct RKNN3_LLMParam
 * @brief Defines the parameters for configuring an LLM instance.
 */
typedef struct
{
  int32_t top_k;             /**< Top-K sampling parameter for token generation. */
  float   top_p;             /**< Top-P (nucleus) sampling parameter. */
  float   temperature;       /**< Sampling temperature, affecting the randomness of token selection. */
  float   repeat_penalty;    /**< Penalty for repeating tokens in generation. */
  float   frequency_penalty; /**< Penalizes frequent tokens during generation. */
  float   presence_penalty;  /**< Penalizes tokens based on their presence in the input. */
} rknn3_sampling_params;

/**
 * @struct RKNN3_LLMParam
 * @brief Defines the parameters for configuring an LLM instance.
 */
typedef struct
{
  char*                  logits_name; /**< Name of output logits. Required only when model has multiple outputs, otherwise can be NULL. */
  int32_t                max_context_len; /**< Maximum number of tokens in the context. */
  rknn3_sampling_params  sampling_param;  /**< Sampling parameters for token generation. */
  rknn3_vocab_info       vocab_info;      /**< Vocabulary information. */
  rknn3_llm_extend_param extend_param;    /**< Extend parameters. */
} rknn3_llm_param;

/**
 * @struct rknn3_lora
 * @brief Defines parameters for a Lora used in model fine-tuning.
 */
typedef struct
{
  char  lora_name[RKNN3_MAX_NAME_LEN]; /**< Name of the Lora. */
  float scale;                         /**< Scaling factor for applying the Lora. */
} rknn3_lora;

/**
 * @struct rknn3_kvcache_policy_param
 * @brief Defines parameters for the KV cache policy.
 */
typedef struct _rknn3_kvcache_policy_param
{
  uint8_t reserved[64]; /**< reserved */
} rknn3_kvcache_policy_param;

/**
 * @struct rknn3_llm_multimodal_tensor
 * @brief Represents multimodal input (e.g., text, image, audio, and video).
 */
typedef struct
{
  const char* name;            /**< Name of this tensor. */
  const char* prompt;          /**< Text prompt input. */
  bool        enable_thinking; /**< Controls whether "thinking mode" is enabled. */

  struct
  {
    float16*    image_embed;    /**< Embedding of the image (size: n_image * n_image_tokens * embedding_dim * sizeof(float16)). */
    uint64_t    n_image_tokens; /**< Number of image tokens. */
    uint64_t    n_image;        /**< Number of images. */
    const char* image_start;    /**< Start tag for image in multimodal input. */
    const char* image_end;      /**< End tag for image in multimodal input. */
    const char* image_content;  /**< Content tag for image in multimodal input. */
    uint64_t    image_width;    /**< Width of image. */
    uint64_t    image_height;   /**< Height of image. */
  } image;

  struct
  {
    float16*    audio_embed;    /**< Embedding of the audio (size: n_audio * n_audio_tokens * embedding_dim * sizeof(float16)). */
    uint64_t    n_audio_tokens; /**< Number of audio tokens. */
    uint64_t    n_audio;        /**< Number of audio. */
    const char* audio_start;    /**< Start tag for audio in multimodal input. */
    const char* audio_end;      /**< End tag for audio in multimodal input. */
    const char* audio_content;  /**< Content tag for audio in multimodal input. */
  } audio;

  struct
  {
    float16* video_embed;          /**< Embedding of the video */
                                   /**< (size: n_video * n_frame_per_video * n_frame_tokens * embedding_dim * sizeof(float16)). */
    uint64_t    n_frame_tokens;    /**< Number of frame tokens. */
    uint64_t    n_frame_per_video; /**< Number of frames per video. */
    uint64_t    n_video;           /**< Number of video. */
    const char* video_start;       /**< Start tag for video in multimodal input. */
    const char* video_end;         /**< End tag for video in multimodal input. */
    const char* video_content;     /**< Content tag for video in multimodal input. */
  } video;

} rknn3_llm_multimodal_tensor;

/**
 * @brief Structure representing a tensor for large language model operations.
 *
 * This structure contains the essential components for handling language model embeddings,
 * including the tensor name, embedding vectors, token IDs, and token count.
 *
 * @struct rknn3_llm_tensor
 * @var name    The name identifier for the tensor
 * @var embed   Pointer to the embedding vector array, organized as [n_tokens × hidden_size]
 * @var tokens  Array storing the token IDs
 * @var n_tokens Total number of tokens in the embedding
 */
typedef struct
{
  const char* name;     /**< Name of this tensor. */
  const char* prompt;   /**< Text prompt input if input_type is RKLLM_INPUT_PROMPT. */
  float16*    embed;    /**< Pointer to the embedding vector (of size n_tokens * hidden_size) if input_type is RKNN3_LLM_INPUT_EMBED. */
  int32_t*    tokens;   /**< Array of token IDs if input_type is RKNN3_LLM_INPUT_TOKEN. */
  uint64_t    n_tokens; /**< Number of tokens represented in the embedding. */
  bool        enable_thinking; /**< Controls whether "thinking mode" is enabled. */
} rknn3_llm_tensor;

// typedef rknn3_tensor rknn3_aux_tensor;

/**
 * @struct rknn3_llm_input
 * @brief Represents different types of input to the LLM via a union.
 */
typedef struct
{
  const char*          role;       /**< Message role: "user" (user input), "tool" (function result) */
  rknn3_llm_input_type input_type; /**< Specifies the type of input provided (e.g., token, embed, aux). */
  union
  {
    rknn3_llm_tensor llm_input;                    /**< Embedding if input_type is RKNN3_LLM_INPUT_EMBED. */
                                                   /**< Array of tokens if input_type is RKNN3_LLM_INPUT_TOKEN. */
    rknn3_llm_multimodal_tensor multimodal_input; /**< Multimodal input if input_type is RKNN3_LLM_INPUT_TOKEN. */
    rknn3_aux_tensor             aux_input;        /**< AUX input if input_type is RKNN3_LLM_INPUT_AUX. */
  };
} rknn3_llm_input;

/**
 * @struct rknn3_llm_infer_param
 * @brief Structure for defining parameters during inference.
 */
typedef struct
{
  int     keep_history;   /**< Flag to determine history retention (1: keep history, 0: discard history).*/
  int32_t max_new_tokens; /**< Maximum number of new tokens to generate. */
  uint8_t reserved[128];  /**< Reserved bytes for future use. */
} rknn3_llm_infer_param;

/**
 * @struct RKLLMResultLastHiddenLayer
 * @brief Structure to hold the hidden states from the last layer.
 */
typedef struct
{
  const float* hidden_states; /**< Pointer to the hidden states (of size num_tokens * embd_size). */
  int          embd_size;     /**< Size of the embedding vector. */
  int          num_tokens;    /**< Number of tokens for which hidden states are stored. */
} RKLLMResultLastHiddenLayer;

/**
 * @struct RKLLMResult
 * @brief Structure to represent the result of LLM inference.
 */
typedef struct
{
  int* token_ids;  /**< Pointer to the tokens generated by the LLM. */
  int  num_tokens; /**< Number of tokens generated. */
} RKLLMResult;

/**
 * @typedef LLMResultCallback
 * @brief Callback function to handle LLM results.
 * @param result Pointer to the LLM result.
 * @param userdata Pointer to user data for the callback.
 * @param state State of the LLM call (e.g., finished, error).
 * @return 0 on success, non-zero on error.
 */
typedef int (*LLMResultCallback)(void* userdata, RKLLMResult* result, LLMCallState state);

/**
 * @typedef LLMSamplingCallback
 * @brief Callback function to handle sampling logits.
 * @param userdata Pointer to user data for the callback.
 * @param logits Pointer to the logits array.
 * @param logits_name Name of the logits.
 * @return Return selected token id (>=0) on success, negative value on error:
 *         - >=0: Selected token id
 *         - <0: Error code
 */
typedef int (*LLMSamplingCallback)(void* userdata, float16* logits, char* logits_name);

/**
 * @brief Function pointer type for callback to get LLM embeddings
 * @param userdata Pointer to user-defined data
 * @param tokens Array of token IDs
 * @param num_tokens Number of tokens in the tokens array
 * @param embded Pointer to buffer that will store the embedding output
 * @param len Length of the embedding buffer in bytes
 * @return Returns 0 on success, non-zero value on failure
 */
typedef int (*LLMGetEmbedCallback)(void* userdata, int32_t* tokens, uint64_t num_tokens, void* embded, uint64_t len);

/**
 * @typedef LLMTokenizerCallback
 * @brief Callback function to handle tokenization.
 * @param userdata Pointer to user data for the callback.
 * @param prompt Pointer to the input prompt string.
 * @param tokens Pointer to the array of token IDs.
 * @param n_tokens_max Max tokens to generated.
 * @return Return tokens number (>=0) on success, negative value on error:
 *         - >=0: Number of tokens generated
 *         - <0: Error code
 */
typedef int (*LLMTokenizerCallback)(void* userdata, const char* text, int32_t text_len, int32_t* tokens, int32_t n_tokens_max);

/**
 * @typedef LLMGetLastHiddenLayerCallback
 * @brief Callback function to retrieve the last hidden layer.
 * @param userdata Pointer to user data for the callback.
 * @param last_hidden_layer Pointer to the last hidden layer structure.
 * @param state State of the LLM call (e.g., finished, error).
 * @return 0 on success, non-zero on error.
 */
typedef int (*LLMGetLastHiddenLayerCallback)(void* userdata, RKLLMResultLastHiddenLayer* last_hidden_layer, LLMCallState state);

/**
 * @struct RKLLMCallback
 * @brief Structure to hold callback functions for LLM operations.
 */
typedef struct
{
  LLMResultCallback result_callback; /**< callback for results returned by the LLM */
  void*             result_userdata; /**< userdata for LLMResultCallback */

  LLMSamplingCallback sampling_callback; /**< Optional: Only required when custom sampling is needed */
  void*               sampling_userdata; /**< userdata for LLMSamplingCallback */

  LLMTokenizerCallback tokenizer_callback; /**< Optional: Only required when custom tokenizer is needed */
  void*                tokenizer_userdata; /**< userdata for LLMTokenizerCallback */

  LLMGetEmbedCallback embed_callback; /**< Optional: Only required when custom embedding retrieval is needed  */
  void*               embed_userdata; /**< userdata for LLMGetEmbedCallback */

  LLMGetLastHiddenLayerCallback hidden_layer_callback; /**< Optional: Only required when get last hidden layer retrieval is needed  */
  void*                         hidden_layer_userdata; /**< userdata for LLMGetLastHiddenLayerCallback */

} RKLLMCallback;

/**
 * @struct RKLLMRunState
 * @brief Structure to hold the state of the LLM run.
 */
typedef struct
{
  uint64_t             n_total_tokens;   /**< Total number of tokens processed currently. */
  uint64_t             n_max_tokens;     /**< Maximum number of tokens can be processed. */
  uint64_t             n_decode_tokens;  /**< Number of tokens generated during the decode stage. */
  uint64_t             n_prefill_tokens; /**< Number of tokens processed during the prefill stage. */
  rknn3_kvcache_policy kvcache_policy;   /**< KV cache policy. */
  int32_t              n_loras_enabled;  /**< Number of Lora enabled. */
  rknn3_lora*          loras_enabled;    /**< Lora enabled. */
} RKLLMRunState;

/**
 * @brief Get the type string.
 * @param type The type of the tensor.
 * @return The type string.
 */
inline static const char* rknn3_get_type_string(rknn3_tensor_type type)
{
  switch (type) {
  case RKNN3_TENSOR_FLOAT32:
    return "FP32";
  case RKNN3_TENSOR_FLOAT16:
    return "FP16";
  case RKNN3_TENSOR_INT8:
    return "INT8";
  case RKNN3_TENSOR_UINT8:
    return "UINT8";
  case RKNN3_TENSOR_INT16:
    return "INT16";
  case RKNN3_TENSOR_UINT16:
    return "UINT16";
  case RKNN3_TENSOR_INT32:
    return "INT32";
  case RKNN3_TENSOR_UINT32:
    return "UINT32";
  case RKNN3_TENSOR_INT64:
    return "INT64";
  case RKNN3_TENSOR_BOOL:
    return "BOOL";
  case RKNN3_TENSOR_INT4:
    return "INT4";
  default:
    return "UNKNOW";
  }
}

/**
 * @brief Get the quantitative type string.
 * @param type The type of the tensor.
 * @return The type string.
 */
inline static const char* rknn3_get_qnt_type_string(rknn3_tensor_qnt_type type)
{
  switch (type) {
  case RKNN3_TENSOR_QNT_NONE:
    return "NONE";
  case RKNN3_TENSOR_PER_LAYER_SYMMETRIC:
    return "PER_LAYER_SYMMETRIC";
  case RKNN3_TENSOR_PER_LAYER_ASYMMETRIC:
    return "PER_LAYER_ASYMMETRIC";
  case RKNN3_TENSOR_PER_CHANNEL_SYMMETRIC:
    return "PER_CHANNEL_SYMMETRIC";
  case RKNN3_TENSOR_PER_CHANNEL_ASYMMETRIC:
    return "PER_CHANNEL_ASYMMETRIC";
  case RKNN3_TENSOR_PER_GROUP_SYMMETRIC:
    return "PER_GROUP_SYMMETRIC";
  case RKNN3_TENSOR_PER_GROUP_ASYMMETRIC:
    return "PER_GROUP_ASYMMETRIC";
  default:
    return "UNKNOWN";
  }
}

/**
 * @brief Get the layout string.
 * @param layout The layout of the tensor.
 * @return The layout string.
 */
inline static const char* rknn3_get_layout_string(rknn3_tensor_layout layout)
{
  switch (layout) {
  case RKNN3_TENSOR_UNDEFINED:
    return "UNDEFINED";
  case RKNN3_TENSOR_NCHW:
    return "NCHW";
  case RKNN3_TENSOR_NHWC:
    return "NHWC";
  case RKNN3_TENSOR_NC1HWC2:
    return "NC1HWC2";
  case RKNN3_TENSOR_CHWN:
    return "CHWN";
  case RKNN3_TENSOR_HWIO:
    return "HWIO";
  case RKNN3_TENSOR_OIHW:
    return "OIHW";
  case RKNN3_TENSOR_O1I1HWI2O2:
    return "O1I1HWI2O2";
  default:
    return "UNKNOWN";
  }
}

/**
 * @brief Initializes the RKNN3 (Rockchip Neural Network) runtime context.
 *
 * This function initializes a new RKNN3 runtime context which is required for
 * running neural network models on Rockchip NPU hardware.
 *
 * @param[out] context Pointer to the RKNN3 context handle that will be initialized
 * @param[in] init_extend Pointer to the device-specific initialization information
 * @return int Return status code:
 *         - 0: Success
 *         - <0: Error code
 *
 * @note The context must be released using rknn3_destroy when no longer needed
 */
int rknn3_init(rknn3_context* context, rknn3_init_extend* init_extend);

/**
 * @brief Loads a RKNN3 model from a file path into the specified context
 *
 * @param context The RKNN3 context handle
 * @param model_path Path to the RKNN3 model file
 * @param weight_path Path to the RKNN3 weight file
 * @return int Return status code:
 *         - 0: Success
 *         - <0: Error code
 */
int rknn3_load_model_from_path(rknn3_context context, const char* model_path, const char* weight_path);

/**
 * @brief Load RKNN3 model from memory data.
 *
 * @param context The RKNN3 context handle.
 * @param model_data Pointer to the model data in memory.
 * @param model_size Size of the model data in bytes.
 * @param weight_data Pointer to the weight data in memory.
 * @param weight_size Size of the weight data in bytes.
 *
 * @return int Return 0 if successful, otherwise return error code.
 *         Error codes:
 *         - RKNN3_ERR_FAIL: Load model failed.
 *         - RKNN3_ERR_MODEL_INVALID: Invalid model.
 *         - RKNN3_ERR_DEVICE_UNAVAILABLE: Device unavailable.
 */
int rknn3_load_model_from_data(rknn3_context context, const void* model_data, uint64_t model_size, const void* weight_data, uint64_t weight_size);

/**
 * @brief Initialize the RKNN3 model.
 *
 * @param context The RKNN3 context handle.
 * @param config Configuration parameters for model.
 * @return int Return 0 if successful, otherwise return error code.
 */
int rknn3_model_init(rknn3_context context, rknn3_config* config);

/**
 * @brief Duplicate an existing RKNN3 context
 *
 * @param context_in The source RKNN3 context to duplicate from
 * @param context_out Pointer to receive the duplicated RKNN3 context
 * @return int Return 0 if successful, otherwise return error code
 */
int rknn3_dup_context(rknn3_context context_in, rknn3_context* context_out);

/**
 * @brief Destroy an RKNN3 runtime context and release resources.
 *
 * @param context The RKNN3 context handle to be destroyed.
 *
 * @return int Return 0 if the operation is successful, otherwise return error code.
 */
int rknn3_destroy(rknn3_context context);

/**
 * @brief Query RKNN3 information or status.
 *
 * @param context The context of the RKNN3 model.
 * @param cmd The query command type (rknn3_query_cmd).
 * @param info Pointer to the buffer for storing query results.
 * @param size Size of the info buffer in bytes.
 * @return int Return 0 if successful, otherwise return error code.
 *
 * This function is used to query various information about the RKNN3 model and runtime,
 * such as SDK version, device information, model information, etc.
 * The specific information returned depends on the query command specified.
 */
int rknn3_query(rknn3_context context, rknn3_query_cmd cmd, void* info, uint64_t size);

/**
 * @brief Execute the RKNN3 model inference.
 *
 * @param context The RKNN3 context handle obtained from rknn3_init
 * @param inputs Array of input tensors containing the input data
 * @param n_inputs Number of input tensors
 * @param outputs Array of output tensors to store the inference results
 * @param n_outputs Number of output tensors
 * @return int Return 0 if successful, otherwise return error code
 *
 * This function performs inference using the specified RKNN3 model. It takes the input
 * data through the inputs array and writes the results to the outputs array.
 * Both input and output tensors must be properly allocated and configured before calling this function.
 */
int rknn3_run(rknn3_context context, const rknn3_tensor inputs[], uint32_t n_inputs, rknn3_tensor outputs[], uint32_t n_outputs);

/**
 * @brief Asynchronous execution of the RKNN3 model inference.
 *
 * @param context The RKNN3 context handle obtained from rknn3_init
 * @param inputs Array of input tensors containing the input data
 * @param n_inputs Number of input tensors
 * @param outputs Array of output tensors to store the inference results
 * @param n_outputs Number of output tensors
 * @return int Return 0 if successful, otherwise return error code
 *
 * This function performs asynchronous inference using the specified RKNN3 model.
 * It takes the input data through the inputs array and writes the results to the outputs array.
 * Both input and output tensors must be properly allocated and configured before calling this function.
 */
int rknn3_run_async(rknn3_context context, const rknn3_tensor inputs[], uint32_t n_inputs, rknn3_tensor outputs[], uint32_t n_outputs);

/**
 * @brief Wait for the completion of inference/execution.
 *
 * This function blocks until the inference or execution on the RKNN3 device is complete.
 *
 * @param context The context handle for the RKNN3 model instance.
 * @return int Return 0 for success, negative value for failure.
 */
int rknn3_wait(rknn3_context context);

/**
 * @brief Creates a tensor memory handle from physical address
 *
 * @param context The RKNN3 context handle
 * @param phys_addr The physical address of the memory
 * @param virt_addr The virtual address of the memory
 * @param size The size of the memory in bytes
 * @return rknn3_tensor_mem* A pointer to the created tensor memory handle, or NULL if creation failed
 *
 * This function creates a tensor memory handle from provided physical and virtual addresses.
 * The memory must be pre-allocated and the physical/virtual addresses must be valid.
 */
rknn3_tensor_mem* rknn3_create_mem_from_phys(rknn3_context context, uint64_t phys_addr, void* virt_addr, uint64_t size);

/**
 * @brief Creates a tensor memory object from a file descriptor.
 *
 * @param context The RKNN3 context handle.
 * @param fd File descriptor for the memory.
 * @param virt_addr Virtual address of the memory.
 * @param size Size of the memory in bytes.
 * @param offset Offset from the start of the memory referenced by fd.
 * @return rknn3_tensor_mem* Pointer to the created tensor memory object, or NULL if creation fails.
 */
rknn3_tensor_mem* rknn3_create_mem_from_fd(rknn3_context context, int32_t fd, void* virt_addr, uint64_t size, uint64_t offset);

/**
 * @brief Creates a memory buffer for RKNN3 tensors
 *
 * @param context The RKNN3 context handle
 * @param size Size of memory to allocate in bytes
 * @param core_id Target NPU core ID for memory allocation
 * @param flags Memory allocation flags to control allocation behavior
 * @return rknn3_tensor_mem* Pointer to allocated tensor memory, NULL if allocation fails
 *
 * @details This function allocates memory that can be used for RKNN3 tensor operations.
 * The memory is allocated on the specified core with the given flags.
 */
rknn3_tensor_mem* rknn3_create_mem(rknn3_context context, uint64_t size, int32_t core_id, rknn3_mem_alloc_flags flags);

/**
 * @brief Destroy memory allocated for RKNN3 tensor.
 *
 * @param context The RKNN3 context handle.
 * @param mem Pointer to the tensor memory structure to be destroyed.
 * @return int Returns 0 on success, negative value on error.
 */
int rknn3_destroy_mem(rknn3_context context, rknn3_tensor_mem* mem);

/**
 * @brief Synchronize the memory data between CPU and device.
 *
 * @param context The context of the RKNN3 model
 * @param mem The memory handle of the tensor
 * @param mode The synchronization mode:
 *             RKNN3_MEM_SYNC_TO_DEVICE: Sync data from CPU to device
 *             RKNN3_MEM_SYNC_FROM_DEVICE: Sync data from device to CPU
 *
 * @return int: Error code
 *         0: Success
 *         Others: Failure
 */
int rknn3_mem_sync(rknn3_context context, rknn3_tensor_mem* mem, rknn3_mem_sync_mode mode);

/**
 * @brief Set the model shape for dynamic input.
 *
 * @param context The context handle of the RKNN3 model.
 * @param shape_id The ID of the shape to be set. This references a predefined shape in the model.
 *
 * @return int Return 0 if successful, otherwise return error code.
 *
 * @note This function is used for models with dynamic input shapes. The shape_id must correspond
 *       to a valid shape configuration defined in the model.
 */
int rknn3_set_shape(rknn3_context context, int32_t shape_id);

/**
 * @brief Sets up KV-Cache memory for specified NPU cores.
 *
 * @param context The RKNN3 context handle
 * @param mem Pointer to KV-Cache tensor memory structure
 * @param npu_core_indices Array of NPU core indices to allocate KV-Cache memory for
 * @param n_core Number of NPU cores in the npu_core_indices array
 *
 * @return 0 on success, negative value on error
 */
int rknn3_set_kvcache_mem(rknn3_context context, rknn3_tensor_mem* mem[], int* npu_core_indices, int n_core);

/**
 * @brief Set multiple core's user-allocated internal memory
 * @param context RKNN3 context
 * @param mem User-allocated memory object array, each mem's core_id field specifies the target core
 * @param n_core Number of cores
 * @return Return RKNN3_SUCCESS on success, return error code on failure
 */
int rknn3_set_internal_mem(rknn3_context context, rknn3_tensor_mem* mem[], uint32_t n_core);

/**
 * @brief Get the list of available RKNN3 devices.
 *
 * @param pdevs Pointer to a structure that will receive the list of devices.
 *
 * @return int Return 0 if successful, otherwise return error code.
 *
 * This function populates the provided rknn3_devices structure with information about
 * all available RKNN3 devices on the system.
 */
int rknn3_find_devices(rknn3_devices* pdevs);

/**
 * @brief Initializes a new RKNN3 session with specified parameters
 *
 * @param context Pointer to the RKNN3 context to be used for the session
 * @param param Pointer to rknn3_llm_param structure containing session configuration parameters
 * @return rknn3_session Returns a session handle if successful, or NULL if initialization fails
 */
rknn3_session* rknn3_session_init(rknn3_context context, rknn3_llm_param* params, int n_params);

/**
 * @brief Enable LoRA for a RKNN3 session
 *
 * @param session Pointer to the RKNN3 session
 * @param lora Pointer to the LoRA adapter to be enabled
 * @return int Return status:
 *         - 0: Success
 *         - Other: Error code
 */
int rknn3_session_enable_lora(rknn3_session* session, rknn3_lora* lora);

/**
 * @brief Disable LoRA for a RKNN3 session
 *
 * @param session Pointer to the RKNN3 session
 * @param lora Pointer to the LoRA adapter to be disabled
 * @return int Return status:
 *         - 0: Success
 *         - Other: Error code
 */
int rknn3_session_disable_lora(rknn3_session* session, rknn3_lora* lora);

/**
 * @brief Query LoRA (Low-Rank Adaptation) information from an RKNN3 session
 *
 * @param session Pointer to the RKNN3 session
 * @param lora Double pointer to store the array of LoRA information
 * @param n_lora Pointer to store the number of LoRA entries
 * @return int Return status:
 *         - 0: Success
 *         - Other: Error code
 */
int rknn3_session_query_lora(rknn3_session* session, rknn3_lora** lora, int* n_lora);

/**
 * @brief Set the KV-Cache policy for a RKNN3 session.
 *
 * @param[in] session The RKNN3 session handle.
 * @param[in] policy The KV-Cache policy to be set.
 * @param[in] param The parameters for the KV-Cache policy.
 *
 * @return 0 on success, negative value on error.
 *
 * This function configures how KV-Cache (Key-Value Cache) behaves in the given
 * RKNN3 session. KV-Cache is commonly used in transformer-based models to store
 * intermediate attention computation results for better inference performance.
 */
int rknn3_session_set_kvcache_policy(rknn3_session* session, rknn3_kvcache_policy policy, rknn3_kvcache_policy_param* param);

/**
 * @brief Clear KV-Cache for a given RKNN3 session based on specified policy.
 *
 * @param session Pointer to the RKNN3 session handle
 * @param clear Policy for clearing KV-Cache, defines how the cache should be cleared
 * @return int Returns 0 on success, negative value on failure
 */
int rknn3_session_clear_kvcache(rknn3_session* session, rknn3_kvcache_clear_policy clear);

/**
 * @brief Load the KV-Cache from a specified path
 *
 * @param session Pointer to the RKNN3 session
 * @param kvcache Path to the KV-Cache file
 * @param size Size of the KV-Cache in bytes
 * @return int Return status:
 *         - 0: Success
 *         - Other: Error code
 */
int rknn3_session_load_kvcache(rknn3_session* session, const char* kvcache, int64_t size);

/**
 * @brief Save the KV-Cache to a specified path
 *
 * @param session Pointer to the RKNN3 session
 * @param kvcache_path Path where the KV-Cache will be saved
 * @return int Return status:
 *         - 0: Success
 *         - Other: Error code
 */
int rknn3_session_save_kvcache(rknn3_session* session, char* kvcache_path);

/**
 * @brief Query the current state of a RKNN3 session
 *
 * @param session Pointer to the RKNN3 session to query
 * @param state Pointer to store the queried run state
 * @return int Return value:
 *         - 0: Success
 *         - Other: Failure
 */
int rknn3_session_query_state(rknn3_session* session, RKLLMRunState* state);

/**
 * @brief Sets the chat template for the LLM, including system prompt, prefix, and postfix.
 *
 * This function allows you to customize the chat template by providing a system prompt, a prompt prefix, and a prompt postfix.
 * The system prompt is typically used to define the behavior or context of the language model,
 * while the prefix and postfix are used to format the user input and output respectively.
 *
 * @param session RKNN3 Session handle.
 * @param system_prompt The system prompt that defines the context or behavior of the language model.
 * @param prompt_prefix The prefix added before the user input in the chat.
 * @param prompt_postfix The postfix added after the user input in the chat.
 *
 * @return Status code (0 if the template was set successfully, non-zero for errors).
 */
int rknn3_session_set_chat_template(rknn3_session* session, const char* system_prompt, const char* prompt_prefix,
                                    const char* prompt_postfix);

/**
 * @brief Sets the callback function for a RKNN3 session
 *
 * @param session Pointer to the RKNN3 session instance
 * @param callback Pointer to the RKLLMCallback structure containing callback functions
 *
 * @return int Returns 0 on success, negative value on error
 *
 * This function allows setting callback functions that will be triggered during
 * RKNN3 model execution. The callbacks can be used for monitoring and handling
 * various events during inference.
 */
int rknn3_session_set_callback(rknn3_session* session, RKLLMCallback* callback);

/**
 * @brief Run inference with the provided inputs and parameters
 *
 * @param session Pointer to the RKNN3 session handle
 * @param inputs Array of input tensors containing the input data
 * @param n_inputs Number of input tensors provided
 * @param param Pointer to inference parameters configuration
 * @return int Returns 0 on success, negative value on failure
 */
int rknn3_session_run(rknn3_session* session, rknn3_llm_input inputs[], uint32_t n_inputs, rknn3_llm_infer_param* param);

/**
 * @brief Run inference asynchronously for a Large Language Model session
 *
 * @param session Pointer to the RKNN3 session handle
 * @param inputs Array of input tensors for the model
 * @param n_inputs Number of input tensors
 * @param param Pointer to inference parameters configuration
 * @return int Return status code:
 *         - 0: Success
 *         - <0: Error
 *
 * This function performs asynchronous inference on the given LLM session.
 * It allows non-blocking execution of the model with the provided inputs
 * and parameters.
 */
int rknn3_session_run_async(rknn3_session* session, rknn3_llm_input inputs[], uint32_t n_inputs, rknn3_llm_infer_param* param);

/**
 * @brief Stop the RKNN3 session
 *
 * @param session Pointer to the RKNN3 session to be stopped
 *
 * @return int Return status code
 *         - 0: Success
 *         - <0: Error
 *
 * This function stop the execution of the RKNN3 session

 * */
int rknn3_session_stop(rknn3_session* session);

/**
 * @brief Destroys an RKNN3 session and releases associated resources
 *
 * @param[in] session Pointer to the RKNN3 session to be destroyed
 *
 * @return int Return status code
 *         - 0: Success
 *         - <0: Error
 *
 * @note After calling this function, the session pointer becomes invalid and should not be used
 */
int rknn3_session_destroy(rknn3_session* session);

#ifdef __cplusplus
} // extern "C"
#endif

#endif //_RKNN3_API_H
