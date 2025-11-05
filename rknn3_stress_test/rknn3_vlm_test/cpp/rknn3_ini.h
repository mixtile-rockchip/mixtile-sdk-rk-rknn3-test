/* 读取整个 ini 文件，返回 0 成功，-1 失败 */
int ini_load(const char *filename);

/* 取出字符串，找不到返回 defval */
const char *ini_get(const char *section, const char *key, const char *defval);

/* 取出整型，找不到返回 defval */
int ini_get_int(const char *section, const char *key, int defval);

/* 取出字符串，找不到返回 defval */
const char *ini_get_string(const char *section, const char *key, const char *defval);

/* 取出浮点，找不到返回 defval */
float ini_get_float(const char *section, const char *key, float defval);
