// Test that UE compiler flags are applied correctly

// This should fail to compile if C++ exceptions are enabled
// Note: On Mac/iOS with Objective-C++, __EXCEPTIONS may be defined for ObjC exceptions
// but C++ exceptions are still disabled via -fno-exceptions
void test_no_exceptions() {
    #if defined(__EXCEPTIONS) && !defined(__OBJC__)
        #error "C++ exceptions should be disabled (-fno-exceptions)"
    #endif
}

// This should fail to compile if RTTI is enabled
void test_no_rtti() {
    #ifdef __GXX_RTTI
        #error "RTTI should be disabled (-fno-rtti)"
    #endif
}

// Verify C++20
#if __cplusplus < 202002L
    #error "C++20 or later required"
#endif
