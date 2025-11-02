# Build Blockers and Skipped Files

This document tracks files and modules we've had to skip or exclude during the build process, along with what's needed to unblock them.

## Core Module (507/514 files - 98.6%)

### Excluded Files (7 total)

**Reason: Need other modules fully built**

1. **Private/HAL/ConsoleManager.cpp**
   - **Blocker:** FConsoleManager header visibility issue
   - **Status:** Needs investigation - header exists but class not visible
   - **Priority:** Medium

2. **Private/Misc/CoreMisc.cpp**
   - **Blocker:** Needs DerivedDataCache module with DERIVEDDATACACHE_API
   - **Module needed:** Runtime/DerivedDataCache
   - **Priority:** Low (DDC is development/caching feature)

3. **Private/Misc/ObjectThumbnail.cpp**
   - **Blocker:** Needs ImageCore module with IMAGECORE_API
   - **Module needed:** Runtime/ImageCore
   - **Priority:** Low (thumbnails are editor feature)

4. **Private/Serialization/Archive.cpp**
   - **Blocker:** Needs TargetPlatform module with TARGETPLATFORM_API
   - **Module needed:** Developer/TargetPlatform
   - **Priority:** Medium (needed for serialization)

5. **Private/Serialization/MemoryImage.cpp**
   - **Blocker:** Needs TargetPlatform module with TARGETPLATFORM_API
   - **Module needed:** Developer/TargetPlatform
   - **Priority:** Medium

6. **Private/HAL/MallocTBB.cpp**
   - **Blocker:** Needs IntelTBB third-party library
   - **Module needed:** ThirdParty/IntelTBB
   - **Priority:** Low (platform-specific allocator)

7. **Private/HAL/MallocJemalloc.cpp**
   - **Blocker:** Linux-specific allocator
   - **Module needed:** ThirdParty/jemalloc
   - **Priority:** Low (not needed for Mac)

8. **Private/HAL/MallocMimalloc.cpp**
   - **Blocker:** Windows/Linux allocator
   - **Module needed:** ThirdParty/mimalloc
   - **Priority:** Low (not needed for Mac)

### Unity Build Patterns

**Private/Compression/lz4.cpp**
- **Status:** Excluded from srcs, added to additional_hdrs
- **Reason:** Unity build - included by lz4hc.cpp, not compiled separately
- **Not a blocker:** Working as intended

## ApplicationCore Module (Blocked)

### Blocked Files (All *Application.cpp)

**Reason: All platform application entry points need InputDevice module**

Files requiring InputDevice:
- Private/Mac/MacApplication.cpp
- Private/Windows/WindowsApplication.cpp
- Private/Linux/LinuxApplication.cpp
- Private/IOS/IOSApplication.cpp
- Private/Android/AndroidApplication.cpp
- Private/Null/NullApplication.cpp

**Additional blocked files:**
- Private/Mac/MacPlatformSurvey.cpp - Needs SynthBenchmark module

**Module needed:** Runtime/InputDevice
**Priority:** HIGH (ApplicationCore is P1 essential runtime)

**Workaround attempted:** Excluding *Application.cpp files won't work - these are the core entry points
**Resolution:** Build InputDevice module first

## Summary

**Modules we can build now without blockers:**
- PakFile (needs RSA third-party)
- RSA third-party library
- JsonUtilities (needs Core + Json - both ready!)
- Serialization (needs Core + TraceLog - both ready!)

**Modules blocked by dependencies:**
- ApplicationCore → InputDevice
- NetCore → CoreUObject → UHT
- Most P2/P3 modules → CoreUObject → UHT

**Strategy:**
1. Build remaining P1 modules with simple dependencies (JsonUtilities, Serialization, PakFile/RSA)
2. Investigate ConsoleManager.cpp issue (might be fixable)
3. Plan UHT integration (major milestone)
4. Build InputDevice to unblock ApplicationCore
5. Build TargetPlatform/ImageCore/DerivedDataCache to complete Core

**Last updated:** 2025-11-02
