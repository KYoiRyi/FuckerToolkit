extern void ftk_platform_constructor_entry(void);

__attribute__((constructor))
static void ftk_auto_start(void) {
    ftk_platform_constructor_entry();
}
