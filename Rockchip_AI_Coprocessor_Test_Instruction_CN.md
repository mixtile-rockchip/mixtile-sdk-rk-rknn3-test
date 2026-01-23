# Rockchip AI Coprocessor Test Instruction

发布版本：V1.0.0

日期：2026-01-14

文件密级：□绝密   □秘密   □内部资料   ■公开

**免责声明**

本文档按“现状”提供，瑞芯微电子股份有限公司（“本公司”，下同）不对本文档的任何陈述、信息和内容的准确性、可靠性、完整性、适销性、特定目的性和非侵权性提供任何明示或暗示的声明或保证。本文档仅作为使用指导的参考。

由于产品版本升级或其他原因，本文档将可能在未经任何通知的情况下，不定期进行更新或修改。

**商标声明**

“Rockchip”、“瑞芯微”、“瑞芯”均为本公司的注册商标，归本公司所有。

本文档可能提及的其他所有注册商标或商标，由其各自拥有者所有。

**版权所有** **© 2025** **瑞芯微电子股份有限公司**

超越合理使用范畴，非经本公司书面许可，任何单位和个人不得擅自摘抄、复制本文档内容的部分或全部，并不得以任何形式传播。

瑞芯微电子股份有限公司

Rockchip Electronics Co., Ltd.

地址：     福建省福州市铜盘路软件园A区18号

网址：     www.rock-chips.com

客户服务电话： +86-4007-700-590

客户服务传真： +86-591-83951833

客户服务邮箱： fae@rock-chips.com

---

**前言**

**概述**

本文档主要介绍RK1820, RK1828协处理器AI Coprocessor Test环境搭建和测试方法。

**读者对象**

本文档（本指南）主要适用于以下工程师：

技术支持工程师

软件开发工程师

**修订记录**

| **日期**   | **版本** | **作者**   | **修改说明** |
| ---------- | -------- | ---------- | ------------ |
| 2026-01-14 | V1.0.0   | Zack.huang | 初始版本     |

---

**目录**

[TOC]

---

## 简介

AI Coprocessor 测试工具是一套用于测试 RK1820, RK1828协处理器性能和稳定性的综合测试套件。该工具包含两个主要模块：RKNN 测试模块和 RKNN-SMI 测试模块，支持 CNN、LLM 和 VLM等多种模型类型。

## 目录结构

```
├── ai_test.sh              # 主入口脚本
├── aicp_smi_test.sh       # RKNN-SMI 测试模块
├── aicp_rknn_test.sh      # RKNN 测试模块
├── rknn3_cnn_test.sh      # CNN 模型测试脚本
├── rknn3_llm_test.sh      # LLM 模型测试脚本
├── rknn3_vlm_test.sh      # VLM 模型测试脚本
└── test_results/          # 测试结果存储目录
```

## 快速开始

### 准备工作

在运行测试前，请确保：

1. 将模型文件放置在“aicp_test_架构”同级目录结构下，如下：

   ```
   ..
   ├── cnn/
   │   └── [模型名称]/
   │       └── *.rknn
   ├── llm/
   │   └── [模型名称]/
   │       └── *.rknn
   └── vlm/
       └── [模型名称]/
           └── *.rknn
   ```



2. 确保 RKNN 驱动已正确安装并加载，在host上执行rknn-smi --version：

   ```
   root@rk3588-buildroot:/userdata/aicp_test_aarch64# rknn-smi --version
     rknn-smi version              : 1.1.0
     PCIe driver version           : 3.3.0
     RC chips connect version      : 3.2.0
     EP chips connect version      : 3.2.0
     PCIe Device 0 firmware version: NA
     rknn3 API version             : 1.0.0  #这里打印rknn_runtime的版本
   ```



### 运行测试

```
chmod +x ai_test.sh
./ai_test.sh
```

## 功能详解

### 主菜单

运行主脚本后，将进入主菜单：

```
========================================
      AI Coprocessor Test Script
          Version 1.0
========================================
Main Menu Options:
1. RKNN Test
2. RKNN-SMI Test
3. Exit
```

### RKNN 测试模块

1. CNN 模型测试
   - 用于测试卷积神经网络模型
   - 支持参数配置：循环次数、设备ID、核心掩码等
2. LLM 模型测试
   - 用于测试大语言模型
   - 支持额外参数：序列长度、新生成token数量
3. VLM 模型测试
   - 用于测试视觉语言模型
   - 支持参数配置：循环次数、设备ID、核心掩码等
4. 全部模型循环测试
   - 自动扫描并测试所有可用模型
   - 支持批量参数设置

选定上述功能选项后，系统将引导用户进行参数配置，用户只需按照提示输入相应的参数值即可启动测试流程。

#### 参数说明

- **循环次数（loop_count）**：测试执行的推理次数（1-100000）
- **设备ID（device_id）**：指定使用的设备编号（0-64）
- **设备核心（core_mask）**：NPU核心掩码，使用十六进制格式的8位二进制掩码指定启用的核心。对应的掩码位上置1表示启用该核心。例如：二进制11111111对应十六进制0xff（全部8核），00001111对应0x0f（核心0-3），00000001对应0x01（仅核心0）。所使用的核心数需要和模型内部配置一致
- **序列长度（seq_len）**：LLM模型的输入序列长度
- **新Token数量（new_tokens）**：LLM模型新生成的token数量
- **测试时长（loop_time）**：测试持续时间（小时），0表示只按循环次数运行，非0时按时长和循环次数运行，取后完成者停止
- **是否使用YUV数据（use_yuv）**：CNN模型使用，1表示输入图片为YUV格式，0表示RGB格式，LLM/VLM为保留参数默认0


### RKNN-SMI 测试模块

#### 功能选项

1. 综合RKNN-SMI测试
   - 版本信息查询
   - 设备信息查询
   - 拓扑信息查询
   - 内存、风扇、温度、电压等状态查询
   - CPU/NPU频率设置测试
   - 工作模式设置测试

1. 重启测试
   - 硬件重置测试
   - 支持无限循环或指定次数
   - 验证系统重启后功能恢复

## 高级功能

aicp_test还包含一些高级功能，可以输入更加详细的参数来满足定制化测试需求。用户可以单独运行更加细粒度的测试脚本来进行模块测试

### CNN 模型测试

#### 单设备测试
```bash
./rknn3_cnn_test.sh <model_path> <loop_time_hours> <count_loop> <device_id> [core_mask] [use_yuv] [save_result]
```

参数说明：
- model_path: 模型文件所在目录路径
- loop_time_hours: 测试时长（小时）
- count_loop: 循环次数
- device_id: 设备ID
- core_mask: 核心掩码（可选，默认0xff）cnn一般为单核0x01
- use_yuv: 是否使用YUV格式（可选，默认0）
- save_result: 是否保存结果（可选，默认1）执行后结果保存在同路径文件夹下/test_results/performance/的cnn.log中

示例：
```bash
./rknn3_cnn_test.sh ../cnn/MobilenetV1 0 10 1 0x01 0 1
```

#### 多设备测试
```bash
./rknn3_cnn_multiple_test.sh <model_path> <loop_time_hours> <count_loop> <device_list> <core_mask> [use_yuv] [save_result]
```

特有参数：
- device_list: 设备ID列表，空格分隔，如 "0 1"
- core_mask: CNN多设备使用核心ID列表，空格分隔，如 "1 2 3 4" 表示所有设备使用相同的核心

示例：
```bash
# 设备0和1都使用核心1、2、3、4
./rknn3_cnn_multiple_test.sh ../cnn/MobilenetV1/mobilenet_v1 0 100 "0 1" "1 2 3 4" 0 1
```

### LLM 模型测试

#### 单设备测试
```bash
./rknn3_llm_test.sh <model_dir> <seq_len> <new_tokens> <loop_time> <loop_count> <device_id> [core_mask] [use_yuv] [save_result]
```

参数说明：
- model_dir: 模型文件所在目录路径
- seq_len: 输入序列长度
- new_tokens: 生成的token数量
- loop_time: 测试时长（小时）
- loop_count: 循环次数
- device_id: 设备ID
- core_mask: 核心掩码（可选，默认0xff
- use_yuv: 保留参数（可选，默认0）目前无效果
- save_result: 是否保存结果（可选，默认1）执行后结果保存在同路径文件夹下/test_results/performance/的llm.log中

示例：
```bash
./rknn3_llm_test.sh ../llm/Qwen2.5-0.5B 512 512 0 1 0 0xff 0 1
```

#### 多设备测试
```bash
./rknn3_llm_multiple_test.sh <model_dir> <seq_len> <new_tokens> <loop_time> <loop_count> <device_list> <core_mask> [use_yuv] [save_result]
```

特有参数：
- device_list: 设备ID列表，空格分隔，如 "0 1 2"

示例：
```bash
./rknn3_llm_multiple_test.sh ../llm/Qwen2.5-0.5B 512 512 0 1 "0 1" 0xff 0 1
```

### VLM 模型测试

#### 单设备测试
```bash
./rknn3_vlm_test.sh <model_dir> <loop_time_hours> <count_loop> <device_id> [core_mask] [use_yuv] [save_result]
```

参数说明：
- model_dir: 模型文件所在目录路径
- loop_time_hours: 测试时长（小时）
- count_loop: 循环次数
- device_id: 设备ID
- core_mask: 核心掩码（可选，默认0xff）vlm一般使用多核或全核
- use_yuv: 保留参数（可选，默认0）目前无效果
- save_result: 是否保存结果（可选，默认1）执行后结果保存在同路径文件夹下/test_results/performance/的vlm.log中

示例：
```bash
./rknn3_vlm_test.sh ../vlm/Qwen2.5-VL-3B 0 1 0 0xff 0 1
```

#### 多设备测试
```bash
./rknn3_vlm_multiple_test.sh <model_dir> <loop_time> <loop_count> <device_list> <core_mask> [use_yuv] [save_result]
```

特有参数：
- device_list: 设备ID列表，空格分隔，如 "0 1"

示例：
```bash
./rknn3_vlm_multiple_test.sh ../vlm/Qwen2.5-VL-3B 0 1 "0 1" 0xff 0 0
```
#### 查看内容
对于VLM等模型,用户如需查看模型输出的内容,可以在模型路径下将.ini中的printresult设置为1,然后直接运行编译出的bin文件

示例：
./rknn3_vlm_demo -vm ../vlm/Qwen2.5-VL-3B/vision_Qwen2.5-VL-3B.rknn -vw ../vlm/Qwen2.5-VL-3B/vision_Qwen2.5-VL-3B.weight -lm ../vlm/Qwen2.5-VL-3B/llm_Qwen2.5-VL-3B.rknn -lw ../vlm/Qwen2.5-VL-3B/llm_Qwen2.5-VL-3B.weight -tk ../vlm/Qwen2.5-VL-3B/Qwen2.5-VL-3B.tokenizer.gguf -em ../vlm/Qwen2.5-VL-3B/Qwen2.5-VL-3B.tokenizer.gguf -im test.jpg -vc 0xff -lc 0xff -pi ../vlm/Qwen2.5-VL-3B/Qwen2.5-VL-3B.ini -vl 1 -ll 1 -tl 0
### Audio Encoder 测试

```bash
./rknn3_audio_encoder_test.sh <model_path> <loop_time_hours> <count_loop> <device_id> [core_mask] [save_result]
```

参数说明：
- model_path: 音频编码器模型所在目录路径
- loop_time_hours: 测试时长（小时）
- count_loop: 循环次数
- device_id: 设备ID
- core_mask: 核心掩码（可选，默认0xff）audio_encoder一般使用多核或全核
- save_result: 是否保存结果（可选，默认1）执行后结果保存在同路径文件夹下/test_results/performance/的audio_encoder.log中

示例：
```bash
./rknn3_audio_encoder_test.sh ../audio/qwen2_audio_encoder 1 100 0 0xff 1
```

### 环境变量

**CLEANUP_TEMP_LOG**：控制是否删除临时日志文件

- true: 测试成功后自动删除/tmp目录下的临时日志（默认行为）
- false: 保留所有临时日志，用于调试

使用方法：
```bash
# 保留临时日志用于调试
export CLEANUP_TEMP_LOG=false
./rknn3_llm_test.sh ...

# 或者单次使用
CLEANUP_TEMP_LOG=false ./rknn3_llm_test.sh ...
```

注意：测试失败时，临时日志会自动复制到 /data/rknn3_model_stress_test_log/ 目录保存，不受此环境变量影响