# Rockchip AI Coprocessor Test Instruction

发布版本：V2.0.0

日期：2026-02-12

文件密级：□绝密   □秘密   □内部资料   ■公开

**免责声明**

本文档按"现状"提供，瑞芯微电子股份有限公司（"本公司"，下同）不对本文档的任何陈述、信息和内容的准确性、可靠性、完整性、适销性、特定目的性和非侵权性提供任何明示或暗示的声明或保证。本文档仅作为使用指导的参考。

由于产品版本升级或其他原因，本文档将可能在未经任何通知的情况下，不定期进行更新或修改。

**商标声明**

"Rockchip"、"瑞芯微"、"瑞芯"均为本公司的注册商标，归本公司所有。

本文档可能提及的其他所有注册商标或商标，由其各自拥有者所有。

**版权所有** **© 2026** **瑞芯微电子股份有限公司**

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
| 2026-02-12 | V2.0.0   | Zack.huang | V2.0.0       |

---

**目录**

[TOC]

---

# AICP_TEST 用户指南

## 概述

aicp_test是一套用于测试Rockchip RK1820和RK1828芯片的AI协处理器性能和功能的完整解决方案。该框架提供三个核心测试脚本，帮助用户进行全面的硬件和模型测试：

- `aicp_test.sh`: 主测试界面，提供菜单式操作体验
- `aicp_rknn_test.sh`: 模型推理功能测试工具
- `aicp_smi_test.sh`: 硬件系统管理接口测试工具

## 安装与部署

### 部署位置

将测试包安装到主机上的 `/userdata/` 目录下：

```bash
# 将测试包复制到指定目录
sudo cp -r install/aicp_test_aarch64 /userdata/aicp_test
cd /userdata/aicp_test
chmod +x *.sh
```

### 环境准备

在运行测试之前，需要确保系统满足以下条件：

1. **驱动和工具链安装**：

   - 确保RKNN驱动已正确安装
   - 验证`rknn-smi`命令可正常使用
   ```bash
   rknn-smi --version
   rknn-smi info -l
   ```

2. **模型文件准备**：
   在测试脚本同级目录的上级目录建立以下模型文件夹：
   ```
   ../cnn/          # 存放CNN模型
   ../llm/          # 存放LLM模型
   ../vlm/          # 存放VLM模型
   ```

3. **依赖程序准备**：
   确保`rknn3_cnn_demo`、`rknn3_llm_demo`、`rknn3_vlm_demo`等测试程序已在系统PATH中，或放置于测试脚本同目录下。

## 菜单导航指南

### 主菜单

运行主程序后首先进入主菜单：

```bash
/userdata/aicp_test$ ./aicp_test.sh
```

主菜单界面：
```
=================================
       AICP Test Framework
=================================

Detected 1 device(s)

1. Device 0
2. Start Testing Process
3. Show Stored Configurations
4. Exit

Please select a device or option (1-4):
```

**菜单选项说明：**
- **Device 0** (选项 1): 选择设备0进行详细配置
- **Start Testing Process** (选项 2): 执行所有已配置设备的测试任务
- **Show Stored Configurations** (选项 3): 查看当前已配置的测试设置
- **Exit** (选项 4): 退出测试框架

### 设备子菜单

选择设备后进入设备子菜单：

```
Device 0 Menu
Selected Device: 0

1. Model Testing
2. SMI Testing
3. Back to Device Selection

Please select an option (1-3):
```

**菜单选项说明：**
- **Model Testing** (选项 1): 进入模型测试配置界面
- **SMI Testing** (选项 2): 进入硬件状态测试配置界面
- **Back to Device Selection** (选项 3): 返回主菜单

## 使用场景指南

### 模型测试操作指南

当用户选择"Model Testing"后，将经历以下菜单流程：

**1. 模型类型选择菜单**
```
Select Model Category for Device 0
Current Device: 0

1. CNN Models
2. LLM Models
3. VLM Models
4. Audio Models
5. Model traversal test
6. Special Scenario 1
7. Special Scenario 2
8. Back to Device Menu

Please select a model category (1-8):
```

**模型类型选择说明：**
- **CNN Models** (选项 1): 适用于卷积神经网络相关模型测试，如图像分类、目标检测等
- **LLM Models** (选项 2): 适用于大语言模型测试，如文本生成、对话等
- **VLM Models** (选项 3): 适用于视觉语言模型测试，如图文生成、理解等
- **Audio Models** (选项 4): 适用于音频处理模型测试，如语音识别、音频生成等
- **Model traversal test** (选项 5): 批量测试所有可用模型，适合全面评估设备性能
- **Special Scenarios** (选项 6-7): 预设的特殊测试场景
- **Back to Device Menu** (选项 8): 返回设备子菜单

**2. 模型选择菜单**
选择模型类型后，系统会扫描模型目录并显示模型选择菜单：
```
Select Specific Model for [模型类型] (Device 0)
Model Type: [类型]
Subtype: [子类型]
Current Device: 0

1. [模型名称1]
2. [模型名称2]
...
N. Back to Model Category Selection

Please select a model to test (1-N):
```

**操作说明：** 系统自动扫描`../[模型类型]/`目录下的所有子目录作为可用模型，用户选择需要测试的具体模型。

**3. 测试类型选择菜单**
选择具体模型后，进入测试类型选择菜单：
```
Select Test Type for [模型名]
Model Type: [类型]
Model Path: [路径]
Device ID: 0

1. Functional Test
2. Stress Test
3. Custom Test
4. Back to Model Selection

Please select a test type (1-4):
```

**测试类型选择说明：**
- **Functional Test** (选项 1): 执行基本推理功能测试，验证模型是否能正常工作
- **Stress Test** (选项 2): 长时间运行模型测试稳定性，用户需输入运行时长（小时）
- **Custom Test** (选项 3): 自定义参数测试，用户可输入额外参数进行特殊测试
- **Back to Model Selection** (选项 4): 返回模型选择菜单

### SMI测试操作指南

当用户选择"SMI Testing"后，将进入硬件状态测试流程：

**1. SMI测试类型选择菜单**
```
Select SMI test type for device 0:
1. Comprehensive SMI Test (Information Query and Settings)
2. Reset Test
3. Back to Device Menu

Please select a test type (1-3):
```

**SMI测试类型选择说明：**
- **Comprehensive SMI Test** (选项 1): 全面的硬件状态检测，包括版本信息、内存状态、温度、电压、CPU/NPU频率、工作模式等
- **Reset Test** (选项 2): 设备重置功能测试，验证设备重置后的恢复能力
- **Back to Device Menu** (选项 3): 返回设备子菜单

## 多设备测试管理

### 配置多设备测试

可以在主菜单为多个设备分别配置不同类型的测试任务，然后通过"Start Testing Process"一次性执行所有配置的任务。

### 监控测试进度

启动并发测试后，系统会显示实时状态监控表：

```
=======================================
    Concurrent Testing Process Status
=======================================
Task ID  Device ID  Config Type      Status      Run Time(s)
-------  ---------  -----------      ------      ---------
0        0          Model Testing    RUNNING     120
1        1          SMI Testing      SUCCESS     45
```

**状态说明：**
- **RUNNING**: 测试正在进行中
- **SUCCESS**: 测试成功完成
- **FAILED**: 测试执行失败

### 查看测试结果

测试完成后，系统会显示汇总结果：

- 总体任务数量
- 成功和失败的任务数量
- 每个设备的详细测试结果
- 失败项目的日志文件位置

## 高级功能

### 查看已存储配置

在主菜单选择"Show Stored Configurations"可以查看所有设备的已配置测试设置。

### 配置管理

- 每次在菜单中选择测试类型后，配置会自动保存
- 可在执行测试前通过查看功能确认配置是否正确

## 日志和结果

### 日志位置

所有测试日志默认保存在`./test_results/`目录下，按设备ID和时间戳命名。

### 结果查看

测试结束后可通过查看日志文件了解详细结果：
```bash
# 查看特定设备的测试日志
cat ./test_results/device_0_*.log
```
