#include "ftk/core/bootstrap.hpp"

#if defined(__ANDROID__)
#include <jni.h>

extern "C" JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM*, void*) {
  ftk::Bootstrap::start_async();
  return JNI_VERSION_1_6;
}

__attribute__((constructor)) static void ftk_android_constructor() {
  ftk::Bootstrap::start_async();
}
#endif

