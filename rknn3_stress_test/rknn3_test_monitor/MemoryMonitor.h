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

#ifndef MEMORY_MONITOR_H
#define MEMORY_MONITOR_H

#include <atomic>
#include <mutex>
#include <condition_variable>
#include <thread>
#include <vector>
#include <functional>
#include <limits>

extern "C" {
#include "rknnsmi.h"
}

#define MAX_CHIP_CNT 16

// Single memory sampling data structure
struct MemoryInfo {
    uint16_t device_id;
    uint16_t chip_id;
    uint64_t total_memory;     // Total memory size (bytes)
    uint64_t used_memory;      // Used memory (bytes)
    uint64_t free_memory;      // Free memory (bytes)
    float usage_percent;       // Usage percentage
    uint16_t ddr_freq;         // DDR frequency (MHz)
    uint16_t npu_util_rate;    // NPU utilization rate (%)
    uint64_t timestamp;        // Timestamp (microseconds)
};

// Statistics for a single device/chip
struct DeviceMemoryStats {
    uint16_t device_id;
    uint16_t chip_id;
    uint64_t total_memory;         // Total memory size (bytes)

    // Memory usage statistics (bytes)
    uint64_t peak_used_memory;     // Peak usage
    uint64_t min_used_memory;      // Minimum usage
    uint64_t avg_used_memory;      // Average usage

    // Memory usage percentage statistics
    float peak_usage_percent;      // Peak usage percentage
    float min_usage_percent;       // Minimum usage percentage
    float avg_usage_percent;       // Average usage percentage

    // Free memory statistics (bytes)
    uint64_t min_free_memory;      // Minimum free memory
    uint64_t max_free_memory;      // Maximum free memory
    uint64_t avg_free_memory;      // Average free memory

    // DDR frequency statistics (MHz)
    uint16_t max_ddr_freq;
    uint16_t min_ddr_freq;
    uint16_t avg_ddr_freq;

    // NPU utilization statistics (percentage)
    uint16_t peak_npu_util;        // Peak NPU utilization
    uint16_t min_npu_util;         // Minimum NPU utilization
    uint16_t avg_npu_util;         // Average NPU utilization

    // Sampling information
    uint32_t sample_count;         // Number of samples
    uint64_t start_timestamp_us;   // Start timestamp (microseconds)
    uint64_t end_timestamp_us;     // End timestamp (microseconds)
    float duration_seconds;        // Monitoring duration (seconds)
};

// Overall statistics - for user consumption
struct MemoryStatistics {
    std::vector<DeviceMemoryStats> devices;
    bool is_valid;                 // Whether data is valid
    uint32_t total_samples;        // Total number of samples
    float total_duration_seconds;  // Total monitoring duration (seconds)

    MemoryStatistics() : is_valid(false), total_samples(0), total_duration_seconds(0.0f) {}
};

// Memory monitor callback function type (advanced feature, optional)
using MemoryMonitorCallback = std::function<void(const std::vector<MemoryInfo>&)>;

class MemoryMonitor {
public:
    /**
     * Constructor - Initialize memory monitor
     * @param monitor_interval_us Monitoring interval (microseconds), default 10ms
     */
    explicit MemoryMonitor(uint32_t monitor_interval_us = 10000);

    /**
     * Destructor - Cleanup resources
     */
    ~MemoryMonitor();

    /**
     * Initialize rknn-smi
     * @return true if success, false if failed
     */
    bool initialize();

    /**
     * Start memory monitoring - Wake up monitor thread and reset statistics
     */
    void start_monitoring();

    /**
     * Stop memory monitoring - Put monitor thread to sleep
     */
    void stop_monitoring();

    /**
     * Get statistics - Primary interface
     * @return Statistics structure containing peak, average, min values etc.
     */
    MemoryStatistics get_statistics() const;

    /**
     * Reset statistics
     */
    void reset_statistics();

    /**
     * Register monitoring data callback function (advanced feature, optional)
     * @param callback Callback function invoked when new monitoring data is available
     */
    void register_callback(MemoryMonitorCallback callback);

    /**
     * Set monitoring interval
     * @param interval_us New monitoring interval (microseconds)
     */
    void set_monitor_interval(uint32_t interval_us);

    /**
     * Set whether to enable realtime printing (disabled by default)
     * @param enable true to enable realtime printing, false to disable
     */
    void set_realtime_print(bool enable);

    /**
     * Set target devices to monitor (call before initialize())
     * @param device_ids Vector of device IDs to monitor (empty = monitor all devices)
     *
     * Examples:
     *   monitor->set_target_devices({});           // Monitor all devices
     *   monitor->set_target_devices({0});          // Monitor device 0 only
     *   monitor->set_target_devices({0, 1});       // Monitor devices 0 and 1
     *   monitor->set_target_devices({0, 2, 3});    // Monitor devices 0, 2, and 3
     */
    void set_target_devices(const std::vector<uint16_t>& device_ids);

    /**
     * Get initialization status
     * @return true if initialized, false otherwise
     */
    bool is_initialized() const { return initialized_; }

    /**
     * Get monitoring status
     * @return true if monitoring is active, false otherwise
     */
    bool is_monitoring() const { return inference_active_.load(); }

private:
    // Single memory monitoring function
    void monitor_memory_once();

    // Monitor thread function
    void monitor_thread_func();

    // Get current timestamp (microseconds)
    uint64_t get_current_timestamp_us() const;

    // Update statistics
    void update_statistics(const std::vector<MemoryInfo>& current_data);

    // Find or create device statistics
    DeviceMemoryStats* find_or_create_device_stats(uint16_t device_id, uint16_t chip_id);

    // Thread synchronization variables
    std::mutex monitor_mutex_;
    std::condition_variable monitor_cv_;
    std::atomic<bool> thread_running_;
    std::atomic<bool> inference_active_;
    std::thread monitor_thread_;

    // Synchronization to ensure monitoring thread is ready before inference starts
    std::mutex ready_mutex_;
    std::condition_variable ready_cv_;
    std::atomic<bool> monitoring_ready_;

    // Statistics data synchronization
    mutable std::mutex stats_mutex_;
    MemoryStatistics statistics_;

    // High-performance sampling architecture:
    static constexpr size_t SAMPLING_BUFFER_SIZE = 1024;  // Buffer for ~500+ sampling rounds
    MemoryInfo sampling_buffer_[SAMPLING_BUFFER_SIZE];
    size_t current_buffer_index_;

    // Final storage (only touched when buffer is full or monitoring stops)
    std::vector<MemoryInfo> final_samples_;
    size_t samples_per_round_;  // How many samples per monitoring round

    // Configuration parameters
    uint32_t monitor_interval_us_;
    bool enable_realtime_print_;

    // Callback function (advanced feature)
    MemoryMonitorCallback callback_;

    // Initialization status
    bool initialized_;
    struct nsmi_device_list device_list_;

    // Cached chip information (to avoid repeated queries)
    struct DeviceChipCache {
        uint16_t device_id;
        uint16_t chip_count;
        uint16_t chip_list[MAX_CHIP_CNT];
    };
    std::vector<DeviceChipCache> chip_cache_;

    // Feature flags
    bool enable_npu_monitoring_;

    // Target devices filter (empty = monitor all devices)
    std::vector<uint16_t> target_device_ids_;

    // Helper function to check if device should be monitored
    bool should_monitor_device(uint16_t device_id) const;
};

#endif // MEMORY_MONITOR_H
