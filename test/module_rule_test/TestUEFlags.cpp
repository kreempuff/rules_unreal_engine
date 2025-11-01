// Test that UE compiler flags are applied correctly

// This should fail to compile if exceptions are enabled
void test_no_exceptions() {
    #ifdef __EXCEPTIONS
        #error "Exceptions should be disabled (-fno-exceptions)"
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
