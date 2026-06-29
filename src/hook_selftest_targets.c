#if defined(_MSC_VER)
#define FTK_NOINLINE __declspec(noinline)
#else
#define FTK_NOINLINE __attribute__((noinline))
#endif

static volatile int ftk_selftest_sink = 0;

FTK_NOINLINE int ftk_selftest_target_add(int a, int b) {
    int value = a + b + 7;
    ftk_selftest_sink += value & 1;

    if (ftk_selftest_sink == -1234567) {
        return ftk_selftest_sink;
    }

    return value;
}

FTK_NOINLINE int ftk_selftest_detour_add(int a, int b) {
    ftk_selftest_sink += (a ^ b) & 1;
    return 4242;
}

FTK_NOINLINE int ftk_selftest_probe_target(void) {
    return 11;
}

FTK_NOINLINE int ftk_selftest_probe_detour(void) {
    return 22;
}
