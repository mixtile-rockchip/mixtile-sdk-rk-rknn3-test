#ifndef _RKNN_DEMO_TIMER_H_
#define _RKNN_DEMO_TIMER_H_

#ifndef __cplusplus
#error "easy_timer.h is C++ only"
#endif

#include <time.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Define this macro to disable timing logs
// #define TIMING_DISABLED // if you don't need to print the time used, uncomment this line of code

class TIMER
{
private:
    struct timespec start_time, stop_time;
    char indent[40] = "-- ";

    double get_us_(struct timespec t)
    {
        return (static_cast<double>(t.tv_sec) * 1000000.0 + static_cast<double>(t.tv_nsec) / 1000.0);
    }

public:
    TIMER() 
    {
        start_time = {0, 0};
        stop_time = {0, 0};
    }
    ~TIMER() {}

    void indent_set(char *s)
    {
        strncpy(indent, s, sizeof(indent) - 1);
    }
    
    void indent_set(const char *s)
    {
        strncpy(indent, s, sizeof(indent) - 1);
    }

    void tik()
    {
        clock_gettime(CLOCK_MONOTONIC, &start_time);
    }

    void tok()
    {
        clock_gettime(CLOCK_MONOTONIC, &stop_time);
    }

#ifdef TIMING_DISABLED
    void print_time(char *str) {}
    void print_time(const char *str) {}
#else
    void print_time(char *str)
    {
        printf("%s%s use: %f ms\n", indent, str, get_time());
    }
    
    void print_time(const char *str)
    {
        printf("%s%s use: %f ms\n", indent, str, get_time());
    }
#endif

    float get_time()
    {
        double sec_diff = static_cast<double>(stop_time.tv_sec - start_time.tv_sec);
        double nsec_diff = static_cast<double>(stop_time.tv_nsec - start_time.tv_nsec);
        
        return static_cast<float>(sec_diff * 1000.0 + nsec_diff / 1000000.0);
    }
};
#endif
