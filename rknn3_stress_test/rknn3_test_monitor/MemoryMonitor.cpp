// Copyright (c) 2025 by Rockchip Electronics Co., Ltd. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#include "MemoryMonitor.h"
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/time.h>

MemoryMonitor::MemoryMonitor(uint32_t monitor_interval_us)
    : thread_running_(false)
    , inference_active_(false)
    , initialized_(false)
    , monitor_interval_us_(monitor_interval_us)
    , enable_realtime_print_(false)
    , device_list_({0})
    , monitoring_ready_(false)
    , enable_npu_monitoring_(true)
    , current_buffer_index_(0)
    , samples_per_round_(0) {
}

MemoryMonitor::~MemoryMonitor() {
    // Stop monitor thread
    {
        std::lock_guard<std::mutex> lock(monitor_mutex_);
        thread_running_ = false;
        inference_active_ = false;
    }
    monitor_cv_.notify_one();

    if (monitor_thread_.joinable()) {
        monitor_thread_.join();
    }

    // Cleanup rknn-smi resources
    if (initialized_) {
        rknnsmi_deinit();
    }
}

bool MemoryMonitor::initialize() {
    if (initialized_) {
        return true;
    }

    printf("[MemoryMonitor] Initializing rknn-smi...\n");

    int ret = rknnsmi_init();
    if (ret != RKNNSMI_SUCCESS) {
        printf("[MemoryMonitor] rknnsmi_init failed, ret=%d\n", ret);
        return false;
    }

    // 获取设备列表
    ret = rknnsmi_get_device_list(&device_list_);
    if (ret != RKNNSMI_SUCCESS || device_list_.count == 0) {
        printf("[MemoryMonitor] Failed to get device list, ret=%d\n", ret);
        rknnsmi_deinit();
        return false;
    }

    printf("[MemoryMonitor] Found %d device(s)\n", device_list_.count);

    // Cache chip list for target devices only (or all if no filter)
    chip_cache_.clear();
    int monitored_device_count = 0;
    for (int i = 0; i < device_list_.count; i++) {
        uint16_t device_id = device_list_.dev[i].global_id;

        // Skip if not in target device list
        if (!should_monitor_device(device_id)) {
            printf("[MemoryMonitor] Skipping device[%d] (not in target list)\n", device_id);
            continue;
        }

        DeviceChipCache cache;
        cache.device_id = device_id;
        cache.chip_count = 0;
        memset(cache.chip_list, 0, sizeof(cache.chip_list));

        ret = rknnsmi_get_chip_list(device_id, &cache.chip_count, cache.chip_list, sizeof(uint16_t) * MAX_CHIP_CNT);
        if (ret == RKNNSMI_SUCCESS) {
            chip_cache_.push_back(cache);
            printf("[MemoryMonitor] Device[%d] has %d chip(s) - MONITORING\n", device_id, cache.chip_count);
            monitored_device_count++;
        } else {
            printf("[MemoryMonitor] Failed to get chip list for device[%d], ret=%d\n", device_id, ret);
        }
    }

    if (chip_cache_.empty()) {
        printf("[MemoryMonitor] ERROR: No valid chips found for monitoring\n");
        if (!target_device_ids_.empty()) {
            printf("[MemoryMonitor] Note: Device filter is active. Check if target devices [");
            for (size_t i = 0; i < target_device_ids_.size(); i++) {
                printf("%u%s", target_device_ids_[i], (i < target_device_ids_.size() - 1) ? ", " : "");
            }
            printf("] exist in the system.\n");
        }
        rknnsmi_deinit();
        return false;
    }

    printf("[MemoryMonitor] ===== Monitoring Configuration =====\n");
    printf("[MemoryMonitor] Active devices: %d\n", monitored_device_count);
    printf("[MemoryMonitor] Total chips: %zu\n", chip_cache_.size());
    printf("[MemoryMonitor] ====================================\n");

    // Calculate samples per round (how many MemoryInfo per sampling call)
    samples_per_round_ = 0;
    for (const auto& cache : chip_cache_) {
        samples_per_round_ += cache.chip_count;
    }

    size_t max_rounds = SAMPLING_BUFFER_SIZE / samples_per_round_;
    printf("[MemoryMonitor] Sampling architecture: %zu samples/round, buffer holds ~%zu rounds (%zu total samples)\n",
           samples_per_round_, max_rounds, SAMPLING_BUFFER_SIZE);

    // Start monitor thread
    thread_running_ = true;
    monitor_thread_ = std::thread(&MemoryMonitor::monitor_thread_func, this);

    initialized_ = true;
    printf("[MemoryMonitor] Initialization successful (chip list cached)\n");
    return true;
}

void MemoryMonitor::start_monitoring() {
    if (!initialized_) {
        printf("[MemoryMonitor] Not initialized, call initialize() first\n");
        return;
    }

    // Reset statistics
    reset_statistics();

    // Reset ready flag
    monitoring_ready_ = false;

    {
        std::lock_guard<std::mutex> lock(monitor_mutex_);
        inference_active_ = true;
    }
    monitor_cv_.notify_one(); // Wake up monitor thread immediately

    // Wait for monitoring thread to be ready (with timeout to avoid infinite wait)
    {
        std::unique_lock<std::mutex> lock(ready_mutex_);
        ready_cv_.wait_for(lock, std::chrono::milliseconds(100), [this]() {
            return monitoring_ready_.load();
        });
        printf("[MemoryMonitor] receive ready signal\n");
    }

    printf("[MemoryMonitor] Monitoring started with %u us interval\n", monitor_interval_us_);
}

void MemoryMonitor::stop_monitoring() {
    if (!initialized_) {
        return;
    }

    inference_active_ = false;

    // Flush remaining buffer to final storage and calculate statistics
    {
        std::lock_guard<std::mutex> lock(stats_mutex_);

        // Flush any remaining samples in buffer
        if (current_buffer_index_ > 0) {
            final_samples_.insert(final_samples_.end(),
                                 sampling_buffer_,
                                 sampling_buffer_ + current_buffer_index_);
        }

        printf("[MemoryMonitor] Processing %zu samples...\n", final_samples_.size());

        // Process all samples and calculate statistics
        for (auto& info : final_samples_) {
                // Calculate derived values once
                info.used_memory = info.total_memory - info.free_memory;
                info.usage_percent = (info.total_memory > 0) ?
                    ((float)info.used_memory * 100.0f / (float)info.total_memory) : 0.0f;

                // Update statistics
                DeviceMemoryStats* dev_stats = find_or_create_device_stats(info.device_id, info.chip_id);

                // Update total memory size
                if (dev_stats->total_memory == 0) {
                    dev_stats->total_memory = info.total_memory;
                }

                // Update memory usage statistics
                if (info.used_memory > dev_stats->peak_used_memory) {
                    dev_stats->peak_used_memory = info.used_memory;
                }
                if (info.used_memory < dev_stats->min_used_memory) {
                    dev_stats->min_used_memory = info.used_memory;
                }

                // Update usage percentage statistics
                if (info.usage_percent > dev_stats->peak_usage_percent) {
                    dev_stats->peak_usage_percent = info.usage_percent;
                }
                if (info.usage_percent < dev_stats->min_usage_percent) {
                    dev_stats->min_usage_percent = info.usage_percent;
                }

                // Update free memory statistics
                if (info.free_memory < dev_stats->min_free_memory) {
                    dev_stats->min_free_memory = info.free_memory;
                }
                if (info.free_memory > dev_stats->max_free_memory) {
                    dev_stats->max_free_memory = info.free_memory;
                }

                // Update DDR frequency statistics
                if (info.ddr_freq > dev_stats->max_ddr_freq) {
                    dev_stats->max_ddr_freq = info.ddr_freq;
                }
                if (info.ddr_freq < dev_stats->min_ddr_freq) {
                    dev_stats->min_ddr_freq = info.ddr_freq;
                }

                // Update NPU utilization statistics
                if (info.npu_util_rate > dev_stats->peak_npu_util) {
                    dev_stats->peak_npu_util = info.npu_util_rate;
                }
                if (info.npu_util_rate < dev_stats->min_npu_util) {
                    dev_stats->min_npu_util = info.npu_util_rate;
                }

                // Accumulate for average calculation
                uint32_t n = dev_stats->sample_count;
                dev_stats->avg_used_memory = (dev_stats->avg_used_memory * n + info.used_memory) / (n + 1);
                dev_stats->avg_free_memory = (dev_stats->avg_free_memory * n + info.free_memory) / (n + 1);
                dev_stats->avg_usage_percent = (dev_stats->avg_usage_percent * n + info.usage_percent) / (n + 1);
                dev_stats->avg_ddr_freq = (dev_stats->avg_ddr_freq * n + info.ddr_freq) / (n + 1);
                dev_stats->avg_npu_util = (dev_stats->avg_npu_util * n + info.npu_util_rate) / (n + 1);

                dev_stats->sample_count++;
        }

        // Update end time and duration
        uint64_t end_time = get_current_timestamp_us();
        for (auto& dev_stats : statistics_.devices) {
            dev_stats.end_timestamp_us = end_time;
            dev_stats.duration_seconds = (dev_stats.end_timestamp_us - dev_stats.start_timestamp_us) / 1000000.0f;
        }
        if (!statistics_.devices.empty() && statistics_.devices[0].start_timestamp_us > 0) {
            statistics_.total_duration_seconds = (end_time - statistics_.devices[0].start_timestamp_us) / 1000000.0f;
        }

        // Calculate total samples
        statistics_.total_samples = 0;
        for (const auto& dev_stats : statistics_.devices) {
            statistics_.total_samples += dev_stats.sample_count;
        }
        statistics_.is_valid = true;

        printf("[MemoryMonitor] Statistics calculated from %u samples\n", statistics_.total_samples);
    }

    printf("[MemoryMonitor] Monitoring stopped\n");
}

MemoryStatistics MemoryMonitor::get_statistics() const {
    std::lock_guard<std::mutex> lock(stats_mutex_);
    return statistics_;
}

void MemoryMonitor::reset_statistics() {
    std::lock_guard<std::mutex> lock(stats_mutex_);

    statistics_ = MemoryStatistics();
    final_samples_.clear();
    current_buffer_index_ = 0;

    uint64_t start_time = get_current_timestamp_us();

    // Pre-initialize device statistics using cached chip list
    for (size_t i = 0; i < chip_cache_.size(); i++) {
        const DeviceChipCache& cache = chip_cache_[i];
        uint16_t device_id = cache.device_id;
        uint16_t chip_count = cache.chip_count;
        const uint16_t* chip_list = cache.chip_list;

        for (int j = 0; j < chip_count; j++) {
            DeviceMemoryStats dev_stats = {};
            dev_stats.device_id = device_id;
            dev_stats.chip_id = chip_list[j];
            dev_stats.total_memory = 0;
            dev_stats.peak_used_memory = 0;
            dev_stats.min_used_memory = std::numeric_limits<uint64_t>::max();
            dev_stats.avg_used_memory = 0;
            dev_stats.peak_usage_percent = 0.0f;
            dev_stats.min_usage_percent = 100.0f;
            dev_stats.avg_usage_percent = 0.0f;
            dev_stats.min_free_memory = std::numeric_limits<uint64_t>::max();
            dev_stats.max_free_memory = 0;
            dev_stats.avg_free_memory = 0;
            dev_stats.max_ddr_freq = 0;
            dev_stats.min_ddr_freq = std::numeric_limits<uint16_t>::max();
            dev_stats.avg_ddr_freq = 0;
            dev_stats.peak_npu_util = 0;
            dev_stats.min_npu_util = 100;
            dev_stats.avg_npu_util = 0;
            dev_stats.sample_count = 0;
            dev_stats.start_timestamp_us = start_time;
            dev_stats.end_timestamp_us = start_time;
            dev_stats.duration_seconds = 0.0f;

            statistics_.devices.push_back(dev_stats);
        }
    }

    statistics_.is_valid = false;
    statistics_.total_samples = 0;
    statistics_.total_duration_seconds = 0.0f;
}

void MemoryMonitor::register_callback(MemoryMonitorCallback callback) {
    std::lock_guard<std::mutex> lock(stats_mutex_);
    callback_ = callback;
}

void MemoryMonitor::set_monitor_interval(uint32_t interval_us) {
    monitor_interval_us_ = interval_us;
}

void MemoryMonitor::set_realtime_print(bool enable) {
    enable_realtime_print_ = enable;
}

void MemoryMonitor::set_target_devices(const std::vector<uint16_t>& device_ids) {
    target_device_ids_ = device_ids;
    if (device_ids.empty()) {
        printf("[MemoryMonitor] Target devices: ALL (no filter - will monitor all detected devices)\n");
    } else {
        printf("[MemoryMonitor] Target devices: [");
        for (size_t i = 0; i < device_ids.size(); i++) {
            printf("%u%s", device_ids[i], (i < device_ids.size() - 1) ? ", " : "");
        }
        printf("] (will only monitor these %zu device(s))\n", device_ids.size());
    }
}

bool MemoryMonitor::should_monitor_device(uint16_t device_id) const {
    // Empty list means monitor all devices
    if (target_device_ids_.empty()) {
        return true;
    }

    // Check if device_id is in the target list
    for (uint16_t target_id : target_device_ids_) {
        if (target_id == device_id) {
            return true;
        }
    }
    return false;
}

uint64_t MemoryMonitor::get_current_timestamp_us() const {
    struct timeval tv;
    gettimeofday(&tv, nullptr);
    return static_cast<uint64_t>(tv.tv_sec) * 1000000ULL + static_cast<uint64_t>(tv.tv_usec);
}

DeviceMemoryStats* MemoryMonitor::find_or_create_device_stats(uint16_t device_id, uint16_t chip_id) {
    // Find existing device statistics
    for (auto& dev_stats : statistics_.devices) {
        if (dev_stats.device_id == device_id && dev_stats.chip_id == chip_id) {
            return &dev_stats;
        }
    }

    // Should not reach here as pre-created in reset_statistics
    // But create a new one for safety
    DeviceMemoryStats new_stats = {};
    new_stats.device_id = device_id;
    new_stats.chip_id = chip_id;
    new_stats.min_used_memory = std::numeric_limits<uint64_t>::max();
    new_stats.min_usage_percent = 100.0f;
    new_stats.min_free_memory = std::numeric_limits<uint64_t>::max();
    new_stats.max_free_memory = 0;
    new_stats.min_ddr_freq = std::numeric_limits<uint16_t>::max();
    new_stats.peak_npu_util = 0;
    new_stats.min_npu_util = 100;
    new_stats.avg_npu_util = 0;
    new_stats.start_timestamp_us = get_current_timestamp_us();

    statistics_.devices.push_back(new_stats);
    return &statistics_.devices.back();
}

void MemoryMonitor::update_statistics(const std::vector<MemoryInfo>& current_data) {
    std::lock_guard<std::mutex> lock(stats_mutex_);

    for (const auto& info : current_data) {
        DeviceMemoryStats* dev_stats = find_or_create_device_stats(info.device_id, info.chip_id);

        // Update total memory size
        if (dev_stats->total_memory == 0) {
            dev_stats->total_memory = info.total_memory;
        }

        // Update memory usage statistics
        if (info.used_memory > dev_stats->peak_used_memory) {
            dev_stats->peak_used_memory = info.used_memory;
        }
        if (info.used_memory < dev_stats->min_used_memory) {
            dev_stats->min_used_memory = info.used_memory;
        }

        // Update usage percentage statistics
        if (info.usage_percent > dev_stats->peak_usage_percent) {
            dev_stats->peak_usage_percent = info.usage_percent;
        }
        if (info.usage_percent < dev_stats->min_usage_percent) {
            dev_stats->min_usage_percent = info.usage_percent;
        }

        // Update free memory statistics
        if (info.free_memory < dev_stats->min_free_memory) {
            dev_stats->min_free_memory = info.free_memory;
        }
        if (info.free_memory > dev_stats->max_free_memory) {
            dev_stats->max_free_memory = info.free_memory;
        }

        // Update DDR frequency statistics
        if (info.ddr_freq > dev_stats->max_ddr_freq) {
            dev_stats->max_ddr_freq = info.ddr_freq;
        }
        if (info.ddr_freq < dev_stats->min_ddr_freq) {
            dev_stats->min_ddr_freq = info.ddr_freq;
        }

        // Update NPU utilization statistics
        if (info.npu_util_rate > dev_stats->peak_npu_util) {
            dev_stats->peak_npu_util = info.npu_util_rate;
        }
        if (info.npu_util_rate < dev_stats->min_npu_util) {
            dev_stats->min_npu_util = info.npu_util_rate;
        }

        // Accumulate for average calculation (using incremental average to avoid overflow)
        uint32_t n = dev_stats->sample_count;
        dev_stats->avg_used_memory = (dev_stats->avg_used_memory * n + info.used_memory) / (n + 1);
        dev_stats->avg_free_memory = (dev_stats->avg_free_memory * n + info.free_memory) / (n + 1);
        dev_stats->avg_usage_percent = (dev_stats->avg_usage_percent * n + info.usage_percent) / (n + 1);
        dev_stats->avg_ddr_freq = (dev_stats->avg_ddr_freq * n + info.ddr_freq) / (n + 1);
        dev_stats->avg_npu_util = (dev_stats->avg_npu_util * n + info.npu_util_rate) / (n + 1);

        // Increment sample count
        dev_stats->sample_count++;
    }

    // Update total sample count
    if (!current_data.empty()) {
        statistics_.total_samples++;
    }
}

void MemoryMonitor::monitor_memory_once() {
    const uint64_t timestamp = get_current_timestamp_us();

    // Reusable structures for PCIe queries (avoid repeated stack allocation)
    nsmi_memory_info memory_info;
    nsmi_npu_info npu_info;

    // Lock-free sampling: write directly to buffer
    const size_t device_count = chip_cache_.size();
    for (size_t i = 0; i < device_count; i++) {
        const DeviceChipCache& cache = chip_cache_[i];
        const uint16_t* chip_list = cache.chip_list;
        const uint16_t device_id = cache.device_id;
        const int chip_count = cache.chip_count;

        for (int j = 0; j < chip_count; j++) {
            // Query memory info (only PCIe communication, no computation)
            if (rknnsmi_get_memory_info(device_id, chip_list[j], &memory_info) != RKNNSMI_SUCCESS) {
                continue;
            }

            // Query NPU utilization (only PCIe communication, no computation)
            uint16_t npu_util = 0;
            if (rknnsmi_get_npu_info(device_id, chip_list[j], &npu_info) == RKNNSMI_SUCCESS) {
                npu_util = npu_info.util_rate;
            }

            // Store raw sample data directly to buffer (no locks, no checks)
            MemoryInfo& info = sampling_buffer_[current_buffer_index_++];
            info.device_id = device_id;
            info.chip_id = chip_list[j];
            info.total_memory = memory_info.total_size;
            info.used_memory = 0;  // will calculate later
            info.free_memory = memory_info.free_size;
            info.usage_percent = 0.0f;  // will calculate later
            info.ddr_freq = memory_info.cur_freq;
            info.npu_util_rate = npu_util;
            info.timestamp = timestamp;

            // Buffer full? Batch commit to final storage and restart from buffer[0]
            if (current_buffer_index_ >= SAMPLING_BUFFER_SIZE) {
                std::lock_guard<std::mutex> lock(stats_mutex_);
                final_samples_.insert(final_samples_.end(),
                                     sampling_buffer_,
                                     sampling_buffer_ + SAMPLING_BUFFER_SIZE);
                current_buffer_index_ = 0;  // Restart from beginning
            }
        }
    }
}

void MemoryMonitor::monitor_thread_func() {
    printf("[MemoryMonitor] Monitor thread started - waiting for inference\n");

    while (thread_running_.load()) {
        // Wait for inference start signal
        {
            std::unique_lock<std::mutex> lock(monitor_mutex_);
            monitor_cv_.wait(lock, [this](){
                return inference_active_.load() || !thread_running_.load();
            });

            if (!thread_running_.load()) {
                break; // Exit thread
            }
        }

        printf("[MemoryMonitor] Inference started - enabling monitoring\n");

        // Notify main thread that monitoring is ready
        {
            std::lock_guard<std::mutex> lock(ready_mutex_);
            monitoring_ready_ = true;
        }
        ready_cv_.notify_one();

        // Monitor during inference
        while (inference_active_.load() && thread_running_.load()) {
            monitor_memory_once();
            printf("[MemoryMonitor] monitor memory once\n");
            usleep(monitor_interval_us_); // Use configurable monitoring interval
        }

        // Reset ready flag when monitoring ends
        monitoring_ready_ = false;

        printf("[MemoryMonitor] Inference finished - entering sleep mode\n");
    }

    printf("[MemoryMonitor] Monitor thread stopped\n");
}
