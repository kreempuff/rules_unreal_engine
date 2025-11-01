#include "Platform.h"

void PlatformFunction() {
    #ifdef PLATFORM_MAC
        // Mac-specific code
    #elif defined(PLATFORM_LINUX)
        // Linux-specific code
    #endif
}
