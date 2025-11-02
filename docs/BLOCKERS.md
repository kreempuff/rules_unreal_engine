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

## The CoreUObject Wall

**We've reached a major milestone:** We've built all modules possible without CoreUObject!

**Modules blocked by CoreUObject:**
- JsonUtilities (needs Core + CoreUObject + Json)
- Serialization (needs Core + CoreUObject + Json + Cbor)
- PakFile (needs Core + CoreUObject + TraceLog + RSA)
- Messaging (needs Core + CoreUObject)
- MessagingCommon (needs Core + CoreUObject)
- NetCore (needs Core + CoreUObject + TraceLog + NetCommon)
- InputDevice (likely needs CoreUObject)
- ApplicationCore → InputDevice → CoreUObject
- ~90% of remaining modules need CoreUObject

**What CoreUObject provides:**
- UObject reflection system (UCLASS, UPROPERTY, UFUNCTION)
- Garbage collection
- Serialization infrastructure
- Blueprint integration
- Asset system foundation

**Why it's blocked:**
- CoreUObject needs UnrealHeaderTool (UHT) for code generation
- UHT generates .generated.h/.cpp files from reflection macros
- Chicken-egg problem: UHT needs modules, modules need UHT-generated code

## Summary

**Modules successfully built (17 total):**
✅ Core + 9 dependencies (TraceLog, BuildSettings, Launch, etc.)
✅ Json, RapidJSON, Projects
✅ NetCommon, Sockets, Networking
✅ SandboxFile, OpenGL

**Next major milestone: UHT Integration**
- This is Phase 1.3 weeks 5-8 in the plan
- Required to unlock CoreUObject
- Required to unlock 90% of remaining modules

**Strategy:**
1. Build remaining P1 modules with simple dependencies (JsonUtilities, Serialization, PakFile/RSA)
2. Investigate ConsoleManager.cpp issue (might be fixable)
3. Plan UHT integration (major milestone)
4. Build InputDevice to unblock ApplicationCore
5. Build TargetPlatform/ImageCore/DerivedDataCache to complete Core

**Last updated:** 2025-11-02
