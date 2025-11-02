# Module Build Roadmap

**Purpose:** Strategic roadmap for building Unreal Engine modules with Bazel
**Use Case:** Mac development + Linux dedicated server for multiplayer games
**Scope:** ~35-40 critical modules (not all 835)

**See also:** [PLAN.md](PLAN.md) for tactical Phase 1.3 task list

---

## Priority Tiers

- **P0:** Critical path - Must build first, blocks everything else
- **P1:** Essential runtime - Required for any UE program to run
- **P2:** Gameplay foundation - Required for actual game functionality
- **P3:** Polish & platform - Client-only features, can defer

---

## P0: Critical Path

### Core ✅ (98.6% complete)
- **Why:** Foundation of everything in UE
- **Complexity:** Hard (514 files, platform-specific, module dependencies)
- **Dependencies:** TraceLog, BuildSettings, AtomicQueue, GSL, BLAKE3, AutoRTFM, OodleDataCompression, xxhash, Launch (minimal)
- **Server:** ✅ Required
- **Status:** 507/514 files compiling, libCore.a (44 MB)
- **Blockers:** 7 files need ImageCore, TargetPlatform, DerivedDataCache, IntelTBB modules

### UnrealHeaderTool (UHT)
- **Why:** Generates reflection code (.generated.h/.cpp) for UCLASS/UPROPERTY
- **Complexity:** Very Hard (chicken-egg: needs Core/CoreUObject, but they need UHT)
- **Dependencies:** Core, CoreUObject, Json, Projects, and many others
- **Server:** ✅ Required (build tool)
- **Strategy:** Bootstrap with precompiled UHT or build minimal Core first

### CoreUObject
- **Why:** Object system, reflection, serialization - required by 90% of modules
- **Complexity:** Hard (heavy UHT usage - UCLASS/UPROPERTY everywhere)
- **Dependencies:** Core, TraceLog, CorePreciseFP, AutoRTFM, Projects, Json
- **Server:** ✅ Required
- **Blocker:** Requires UHT integration complete

### Projects ✅ (100% complete)
- **Why:** Plugin system, .uproject parsing, module discovery
- **Complexity:** Simple (mostly JSON parsing)
- **Dependencies:** Core, Json
- **Server:** ✅ Required
- **Status:** 14/14 files compiling, libProjects.a (4.6 MB)
- **Build time:** 3.5 seconds

### Json ✅ (100% complete)
- **Why:** Configuration, data serialization, used everywhere
- **Complexity:** Simple (JSON parsing with RapidJSON)
- **Dependencies:** Core, RapidJSON (header-only)
- **Server:** ✅ Required
- **Status:** 9/9 files compiling, libJson.a (1.7 MB)
- **Build time:** 2.2 seconds

### RapidJSON ✅ (ThirdParty - header-only)
- **Why:** Fast JSON parser/generator used by Json module
- **Complexity:** Trivial (header-only third-party library)
- **Dependencies:** None
- **Server:** ✅ Required
- **Status:** Header-only library (v1.1.0)

---

## P1: Essential Runtime

### JsonUtilities
- **Why:** UE-specific JSON helpers
- **Complexity:** Simple
- **Dependencies:** Core, Json
- **Server:** ✅ Required

### Serialization
- **Why:** Binary serialization, save games, network replication
- **Complexity:** Medium
- **Dependencies:** Core, TraceLog
- **Server:** ✅ Required (critical for networking)

### NetCommon
- **Why:** Shared networking utilities
- **Complexity:** Simple
- **Dependencies:** Core
- **Server:** ✅ Required

### Sockets
- **Why:** Low-level TCP/UDP socket primitives
- **Complexity:** Medium (platform-specific implementations)
- **Dependencies:** Core, NetCommon
- **Server:** ✅ Required
- **Priority:** **HIGH** for multiplayer

### Networking
- **Why:** Connection management, packet handling
- **Complexity:** Medium
- **Dependencies:** Core, Sockets
- **Server:** ✅ Required
- **Priority:** **HIGH** for multiplayer

### NetCore
- **Why:** High-level networking types and interfaces
- **Complexity:** Medium
- **Dependencies:** Core, CoreUObject, TraceLog, NetCommon
- **Server:** ✅ Required
- **Priority:** **HIGH** for multiplayer

### PakFile
- **Why:** Archive file system for packaged games
- **Complexity:** Medium
- **Dependencies:** Core, RSA
- **Server:** ✅ Required (servers run from pak files)

### RSA (ThirdParty)
- **Why:** Encryption for pak files and secure connections
- **Complexity:** Simple (third-party crypto)
- **Dependencies:** Core
- **Server:** ✅ Required

### ApplicationCore
- **Why:** Platform abstraction, windowing, input system foundation
- **Complexity:** Medium (platform-specific)
- **Dependencies:** Core, RHI (include only)
- **Server:** ⚠️ Partial (headless mode still needs some platform services)

### InputCore
- **Why:** Input event system (keyboard, mouse, gamepad)
- **Complexity:** Simple
- **Dependencies:** Core, CoreUObject
- **Server:** ❌ Not required (but harmless)

### Messaging / MessagingCommon
- **Why:** Internal message bus (used by Engine, Networking)
- **Complexity:** Simple
- **Dependencies:** Core, CoreUObject
- **Server:** ✅ Required

---

## P2: Gameplay Foundation

### Engine
- **Why:** Game framework (Actor, Pawn, GameMode, World, Level)
- **Complexity:** **VERY HARD** (5000+ files, most complex module)
- **Dependencies:** Core, CoreUObject, NetCore, ImageCore, Json, SlateCore, Slate, InputCore, Messaging, RenderCore, RHI, Sockets, AssetRegistry, PakFile, PhysicsCore, GameplayTags, AudioExtensions, and ~50 more
- **Server:** ✅ Required
- **Strategy:** Build incrementally - subsystems one at a time

### PhysicsCore
- **Why:** Physics abstractions (collision, rigid bodies)
- **Complexity:** Medium
- **Dependencies:** Core, CoreUObject, Chaos
- **Server:** ✅ Required (server-authoritative physics)
- **Priority:** **HIGH** for multiplayer determinism

### GameplayTags
- **Why:** Tag system (widely used in modern UE games)
- **Complexity:** Simple
- **Dependencies:** Core, CoreUObject
- **Server:** ✅ Required

### AssetRegistry
- **Why:** Asset database, content discovery
- **Complexity:** Medium
- **Dependencies:** Core, CoreUObject
- **Server:** ⚠️ Partial (dynamic content loading)

### RHI / RHICore
- **Why:** Render Hardware Interface abstraction
- **Complexity:** Hard (D3D12/Vulkan/Metal/OpenGL backends)
- **Dependencies:** Core, TraceLog, ApplicationCore
- **Server:** ❌ Use NullDrv for headless server
- **Mac client:** ✅ Required (Metal backend)

### RenderCore
- **Why:** Rendering utilities, shader management
- **Complexity:** Hard
- **Dependencies:** RHI, CoreUObject, Json, Projects, ApplicationCore
- **Server:** ❌ Not required
- **Mac client:** ✅ Required

### SlateCore / Slate
- **Why:** UI framework
- **Complexity:** Medium-Hard
- **Dependencies:** Core, CoreUObject, InputCore, Json, ApplicationCore
- **Server:** ❌ Not required (no UI)
- **Mac client:** ✅ Required

---

## P3: Polish & Platform-Specific

### Renderer
- **Why:** High-level rendering (deferred, post-processing, lighting)
- **Complexity:** Very Hard
- **Dependencies:** RenderCore, RHI, Engine
- **Server:** ❌ Not required
- **Mac client:** ✅ Required

### UMG (Unreal Motion Graphics)
- **Why:** Designer-friendly UI (HUD, menus)
- **Complexity:** Hard
- **Dependencies:** Slate, SlateCore, Engine, MovieScene
- **Server:** ❌ Not required
- **Mac client:** ✅ Required (if using UMG for UI)

### AudioMixer / AudioMixerCore
- **Why:** Sound system
- **Complexity:** Hard (DSP, platform audio backends)
- **Dependencies:** Core, Engine, AudioExtensions, SignalProcessing
- **Server:** ❌ Not required
- **Mac client:** ✅ Required (if using audio)

### NetworkReplayStreaming
- **Why:** Demo recording/playback (killcams, replays)
- **Complexity:** Medium
- **Dependencies:** Core, Engine, Networking
- **Server:** ⚠️ Optional (servers can record demos)
- **Priority:** Useful for esports/debugging

### PacketHandler
- **Why:** Packet encryption, compression, reliability
- **Complexity:** Medium
- **Dependencies:** Core, Networking
- **Server:** ⚠️ Optional (if using encryption)

### OnlineSubsystem
- **Why:** Matchmaking, lobbies, friends, achievements
- **Complexity:** Very Hard (many platform backends)
- **Dependencies:** Core, Engine, Sockets, HTTP
- **Server:** ⚠️ Partial (server-side matchmaking)
- **Priority:** Production feature, can use custom backend initially

### HTTP / HTTPServer
- **Why:** HTTP client/server for REST APIs
- **Complexity:** Medium
- **Dependencies:** Core, Sockets, SSL
- **Server:** ⚠️ Optional (useful for admin APIs)

### Analytics
- **Why:** Telemetry and metrics
- **Complexity:** Simple
- **Dependencies:** Core, HTTP
- **Server:** ⚠️ Optional (server metrics)

---

## Dependency Graph

```
Foundation Layer:
  Core (base of everything)
  ├── TraceLog (profiling)
  ├── BuildSettings (version info)
  └── ThirdParty: AtomicQueue, GSL, BLAKE3, xxhash, OodleData, PLCrash

Code Generation:
  UnrealHeaderTool (UHT)
  └── Generates reflection for CoreUObject, Engine, etc.

Object System:
  Core → CoreUObject
  └── Projects, Json, JsonUtilities

Networking Stack (Critical for Multiplayer):
  Core → NetCommon → Sockets → Networking → NetCore
  └── Engine (integrates networking)

Runtime Services:
  Core → ApplicationCore (platform)
  Core → Serialization (save/load)
  Core → PakFile (packaging)
  Core → InputCore (input events)
  Core → Messaging (message bus)

Gameplay Framework:
  Core → CoreUObject → Engine
  ├── PhysicsCore (physics)
  ├── GameplayTags (tagging system)
  └── AssetRegistry (content database)

Rendering (Mac Client Only):
  Core → RHI → RenderCore → Renderer
  └── NullDrv (for headless server)

UI (Mac Client Only):
  Core → ApplicationCore → SlateCore → Slate → UMG

Audio (Mac Client Only):
  Core → AudioExtensions → AudioMixerCore → AudioMixer

Advanced Multiplayer:
  Networking → PacketHandler (encryption)
  Networking → NetworkReplayStreaming (demos)
  Sockets → OnlineSubsystem (matchmaking)
```

---

## Client vs Server Module Split

### Required for Both (Build Once, Use Everywhere)
- Core, CoreUObject, Projects, Json, JsonUtilities
- Serialization, PakFile, RSA
- NetCommon, Sockets, Networking, NetCore
- Engine (core gameplay logic)
- PhysicsCore (deterministic simulation)
- GameplayTags, AssetRegistry

### Mac Client Only
- Renderer, RenderCore, RHI (Metal backend)
- SlateCore, Slate, UMG (UI)
- AudioMixer, AudioMixerCore (sound)
- ApplicationCore (windowing)
- InputCore (input devices)

### Linux Server Only
- NullDrv (headless RHI)
- Minimal ApplicationCore (platform init)
- HTTP/HTTPServer (optional admin API)

### Optional for Both
- Analytics (telemetry)
- NetworkReplayStreaming (demos)
- PacketHandler (encryption)
- OnlineSubsystem (matchmaking)
- ICMP (network diagnostics)

---

## Implementation Strategy

### Quick Wins (Build These First)
1. **Json** - Simple third-party library, widely used
2. **JsonUtilities** - Thin wrapper, builds quickly
3. **NetCommon** - Simple utilities, networking foundation
4. **Projects** - Straightforward parsing, needed by many
5. **Serialization** - Medium complexity, high value

**Rationale:** These build quickly and unblock other modules

### Critical Path (Can't Skip)
1. **Core** - Everything depends on it
2. **UHT** - Required for CoreUObject and Engine
3. **CoreUObject** - Object system foundation
4. **Networking stack** - Essential for multiplayer
5. **Engine** - The "big one" that ties everything together
6. **PhysicsCore** - Server-authoritative gameplay

**Rationale:** These form the dependency spine - can't proceed without them

### Can Skip for Dedicated Server
- Renderer, RenderCore (use NullDrv)
- Slate, UMG (no UI)
- AudioMixer (no sound)
- MoviePlayer (no videos)
- UnrealEd, Editor modules (not needed for packaged games)

**Rationale:** Significant effort savings, servers don't need graphics/UI

### Defer to Later
- **Analytics, HTTP** - Useful but not MVP
- **NetworkReplayStreaming** - Great for debugging, not essential
- **OnlineSubsystem** - Production feature, can use custom backend initially
- **AudioMixer** - Can build silent game first
- **UMG** - Can use Slate directly initially

**Rationale:** These add polish but aren't blockers for basic multiplayer

---

## Risk Assessment

### High Risk
- **Engine** - Massive module, many hidden dependencies
- **UHT Integration** - Chicken-egg problem, genrule complexity
- **Precompiled libraries** - ABI mismatches (Oodle, PLCrash, TBB)
- **Cross-platform builds** - Linux server untested so far

### Medium Risk
- **PhysicsCore dependencies** - Chaos physics engine is complex
- **Platform-specific code** - Windows/Linux paths untested
- **Linking phase** - May discover missing symbols
- **Module initialization order** - Could cause runtime crashes

### Low Risk (Should Work)
- **Third-party libraries** - Json, RSA, xxhash, etc.
- **Simple wrappers** - JsonUtilities, NetCommon, etc.
- **Header-only modules** - AtomicQueue, GSL (already working)

---

## Multiplayer-Specific Considerations

### Server-Authoritative Architecture
**Server needs:**
- PhysicsCore (authoritative physics simulation)
- NetCore, Networking (handle client connections)
- Engine (gameplay logic, Actor replication)
- Serialization (save/load state)

**Server doesn't need:**
- Rendering (NullDrv)
- UI (Slate/UMG)
- Audio (silent)
- Input (AI-driven NPCs)

### Cross-Platform Determinism
**Critical for replay compatibility:**
- Same physics tick rate Mac ↔ Linux
- Same floating-point behavior
- Same RNG seeding
- Same serialization format

**Testing strategy:**
- Record replay on Mac client
- Play back on Linux server (should match exactly)
- Compare physics state checksums frame-by-frame

### Network Architecture Modules
**Minimum viable networking:**
1. Sockets (transport layer)
2. Networking (connection management)
3. NetCore (high-level replication)
4. Engine (Actor replication)

**Advanced features (defer):**
- PacketHandler (encryption - add when securing traffic)
- NetworkReplayStreaming (replays - add for debugging/esports)
- OnlineSubsystem (matchmaking - add for production)

---

## Next Steps

### Immediate
1. Fix FConsoleManager header resolution in Core
2. Continue Core compilation (21% → 50%+)
3. Identify remaining Core blockers

### Near-term
1. Complete Core module (100% compilation)
2. Symbol comparison with UBT build
3. Start UHT integration research

### Medium-term
1. UHT fully integrated
2. CoreUObject building
3. Start networking stack (Sockets, Networking)

### Long-term
1. Engine module (incremental)
2. Client/server split
3. BuildCookRun automation

---

## References

- **Current tactical plan:** [PLAN.md](PLAN.md)
- **Core module quirks:** [../ue_modules/Runtime/Core/README.md](../ue_modules/Runtime/Core/README.md)
- **Validation strategy:** [PLAN.md#validation](PLAN.md#validation)
- **Compiler flags:** [UE_COMPILER_FLAGS.md](UE_COMPILER_FLAGS.md)
- **Original scope:** [effort-estimate.md](effort-estimate.md)

---

**Last updated:** 2025-11-02
**Current focus:** Phase 1.3 - Core module compilation (21% complete)
