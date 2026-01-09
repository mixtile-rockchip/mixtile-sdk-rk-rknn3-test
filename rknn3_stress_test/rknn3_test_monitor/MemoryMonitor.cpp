/*
 * Memory Monitor Class Implementation
 */

#include "MemoryMonitor.h"
#include <stdio.h>
#include <unistd.h>
#include <sys/time.h>

MemoryMonitor::MemoryMonitor(uint32_t monitor_interval_us)
    : thread_running_(false)
    , inference_active_(false)
    , initialized_(false)
    , monitor_interval_us_(monitor_interval_us)
    , enable_realtime_print_(false)
    , device_list_({0}) {
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

    // Start monitor thread
    thread_running_ = true;
    monitor_thread_ = std::thread(&MemoryMonitor::monitor_thread_func, this);

    initialized_ = true;
    printf("[MemoryMonitor] Initialization successful\n");
    return true;
}

void MemoryMonitor::start_monitoring() {
    if (!initialized_) {
        printf("[MemoryMonitor] Not initialized, call initialize() first\n");
        return;
    }

    // Reset statistics
    reset_statistics();

    {
        std::lock_guard<std::mutex> lock(monitor_mutex_);
        inference_active_ = true;
    }
    monitor_cv_.notify_one(); // Wake up monitor thread immediately

    printf("[MemoryMonitor] Monitoring started with %u us interval\n", monitor_interval_us_);
}

void MemoryMonitor::stop_monitoring() {
    if (!initialized_) {
        return;
    }

    inference_active_ = false;

    // Update end time and duration in statistics
    {
        std::lock_guard<std::mutex> lock(stats_mutex_);
        uint64_t end_time = get_current_timestamp_us();
        for (auto& dev_stats : statistics_.devices) {
            dev_stats.end_timestamp_us = end_time;
            dev_stats.duration_seconds = (dev_stats.end_timestamp_us - dev_stats.start_timestamp_us) / 1000000.0f;
        }
        if (!statistics_.devices.empty() && statistics_.devices[0].start_timestamp_us > 0) {
            statistics_.total_duration_seconds = (end_time - statistics_.devices[0].start_timestamp_us) / 1000000.0f;
        }
        statistics_.is_valid = true;
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
    detailed_samples_.clear();

    uint64_t start_time = get_current_timestamp_us();

    // Pre-initialize device statistics
    for (int i = 0; i < device_list_.count; i++) {
        uint16_t device_id = device_list_.dev[i].global_id;
        uint16_t chip_list[MAX_CHIP_CNT] = {0};
        uint16_t chip_count = 0;

        int ret = rknnsmi_get_chip_list(device_id, &chip_count, chip_list, sizeof(uint16_t) * MAX_CHIP_CNT);
        if (ret == RKNNSMI_SUCCESS) {
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
    std::vector<MemoryInfo> current_memory_info;
    uint64_t timestamp = get_current_timestamp_us();

    for (int i = 0; i < device_list_.count; i++) {
        uint16_t device_id = device_list_.dev[i].global_id;
        uint16_t chip_list[MAX_CHIP_CNT] = {0};
        uint16_t chip_count = 0;

        int ret = rknnsmi_get_chip_list(device_id, &chip_count, chip_list, sizeof(uint16_t) * MAX_CHIP_CNT);
        if (ret != RKNNSMI_SUCCESS) {
            continue;
        }

        for (int j = 0; j < chip_count; j++) {
            struct nsmi_memory_info memory_info = {0};
            ret = rknnsmi_get_memory_info(device_id, chip_list[j], &memory_info);
            if (ret == RKNNSMI_SUCCESS) {
                uint64_t used_memory = memory_info.total_size - memory_info.free_size;
                float memory_usage_percent = (float)used_memory * 100.0f / (float)memory_info.total_size;

                // Get NPU utilization
                struct nsmi_npu_info npu_info = {0};
                uint16_t npu_util = 0;
                if (rknnsmi_get_npu_info(device_id, chip_list[j], &npu_info) == RKNNSMI_SUCCESS) {
                    npu_util = npu_info.util_rate;
                }

                MemoryInfo info = {
                    device_id,
                    chip_list[j],
                    memory_info.total_size,
                    used_memory,
                    memory_info.free_size,
                    memory_usage_percent,
                    memory_info.cur_freq,
                    npu_util,
                    timestamp
                };

                current_memory_info.push_back(info);

                // Optional realtime printing (disabled by default to avoid excessive logs)
                if (enable_realtime_print_) {
                    printf("[MemoryMonitor] Device[%d] Chip[%d]: Used=%.2fMB (%.1f%%), Free=%.2fMB, DDR=%uMHz\n",
                           device_id, chip_list[j],
                           (float)used_memory / 1024.0f / 1024.0f,
                           memory_usage_percent,
                           (float)memory_info.free_size / 1024.0f / 1024.0f,
                           memory_info.cur_freq);
                }
            }
        }
    }

    // Update statistics
    if (!current_memory_info.empty()) {
        update_statistics(current_memory_info);

        // Save detailed sampling data (optional, for future trend analysis)
        {
            std::lock_guard<std::mutex> lock(stats_mutex_);
            detailed_samples_.push_back(current_memory_info);
        }

        // Call callback function (if registered)
        if (callback_) {
            callback_(current_memory_info);
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

        // Monitor during inference
        while (inference_active_.load() && thread_running_.load()) {
            monitor_memory_once();
            usleep(monitor_interval_us_); // Use configurable monitoring interval
        }

        printf("[MemoryMonitor] Inference finished - entering sleep mode\n");
    }

    printf("[MemoryMonitor] Monitor thread stopped\n");
}
