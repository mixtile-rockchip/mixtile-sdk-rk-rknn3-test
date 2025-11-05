#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "rknn3_ini.h"

#define MAX_LINE   256
#define MAX_PAIRS  256

typedef struct {
    char section[64];
    char key  [64];
    char value[128];
} pair_t;

static pair_t g_pairs[MAX_PAIRS];
static int    g_count = 0;

/* 去掉行尾 \r \n 及空格 */
static char *strstrip(char *s) {
    char *p = s + strlen(s) - 1;
    while (p >= s && (*p == '\n' || *p == '\r' || *p == ' ' || *p == '\t'))
        *p-- = 0;
    return s;
}

int ini_load(const char *filename) {
    FILE *fp = fopen(filename, "r");
    if (!fp) return -1;

    char line[MAX_LINE];
    char curr_section[64] = "";

    while (fgets(line, sizeof(line), fp)) {
        char *p = strstrip(line);

        /* 跳过空行或注释 */
        if (*p == '\0' || *p == '#' || *p == ';') continue;

        /* 段名 [section] */
        if (*p == '[' && p[strlen(p) - 1] == ']') {
            p[strlen(p) - 1] = 0;
            strncpy(curr_section, p + 1, sizeof(curr_section) - 1);
            curr_section[sizeof(curr_section) - 1] = 0;
            continue;
        }

        /* key=value */
        char *eq = strchr(p, '=');
        if (!eq) continue;
        *eq++ = 0;

        if (g_count >= MAX_PAIRS) break;   /* 表满 */

        strncpy(g_pairs[g_count].section, curr_section, sizeof(g_pairs[0].section) - 1);
        strncpy(g_pairs[g_count].key,     strstrip(p),   sizeof(g_pairs[0].key) - 1);
        strncpy(g_pairs[g_count].value,   strstrip(eq),  sizeof(g_pairs[0].value) - 1);
        ++g_count;
    }
    fclose(fp);

    return 0;
}

const char *ini_get(const char *section, const char *key, const char *defval) {
    for (int i = 0; i < g_count; ++i)
        if (strcasecmp(g_pairs[i].section, section) == 0 &&
            strcasecmp(g_pairs[i].key,     key)     == 0)
            return g_pairs[i].value;
    return defval;
}

int ini_get_int(const char *section, const char *key, int defval) {
    const char *v = ini_get(section, key, NULL);
    return v ? (int)strtol(v, NULL, 0) : defval;
}

const char *ini_get_string(const char *section, const char *key, const char *defval)
{
    return ini_get(section, key, defval);   // 直接复用已有逻辑
}

float ini_get_float(const char *section, const char *key, float defval)
{
    const char *v = ini_get(section, key, NULL);
    if (!v) return defval;
    char *endptr = NULL;
    float d = strtod(v, &endptr);
    return (*endptr == '\0') ? d : defval;  // 仅当完整转换成功才返回
}