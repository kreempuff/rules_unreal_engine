# Effort Estimate: rules_unreal_engine to 1.0

**Date:** 2025-10-30
**Status:** Pre-1.0 Planning

---

## Executive Summary

**Bottom Line:** Completing `rules_unreal_engine` to 1.0 (full build + cook + package) is a **12-18 month effort** requiring **2-3 dedicated engineers** with expertise in:
- Unreal Engine architecture
- Bazel build systems
- Go programming
- Cross-platform toolchains

**Total Effort:** 36-54 person-months
**Estimated Cost:** $450k-$675k (at $150k/engineer/year)

---

## Current State Assessment

### What Exists

Based on repo inspection (`git log`, `cmd/`, `docs/`):

✅ **Infrastructure:**
- Go CLI framework (Cobra)
- Bazel MODULE.bazel setup
- CI/CD with GitHub Actions
- Git dependency downloading (`cmd/gitDeps.go`)
- XML parsing utilities (`cmd/parse-xml`)

✅ **Tooling:**
- Minimal command structure
- Bazel rules skeleton
- Module system foundation

### What's Missing (per Roadmap)

❌ **All critical functionality:**
- [ ] Build Unreal Engine from source
- [ ] UBT (UnrealBuildTool) replacement
- [ ] UAT (UnrealAutomationTool) replacement
- [ ] Cook pipeline
- [ ] Package pipeline
- [ ] Platform-specific toolchain integration

**Completion Status:** ~5-10% (infrastructure only)

---

## Detailed Scope Breakdown

### Phase 1: UnrealBuildTool (UBT) Replacement

**Goal:** Build Unreal Engine C++ modules with Bazel

#### 1.1 Setup.sh Replacement (4-6 weeks)
- Parse `Engine/Build/Commit.gitdeps.xml`
- Download git dependencies (~20-30 repos)
- Unpack binary dependencies (platform SDKs, tools)
- Verify checksums and signatures
- **Status:** Partially done (gitDeps.go exists)

**Complexity:** MEDIUM
**Blockers:** Network reliability, binary distribution rights

#### 1.2 Module Graph Analysis (6-8 weeks)
- Parse all `.Build.cs` files (~3000+ modules)
- Build dependency graph (handle circular deps)
- Extract compiler settings per module
- Map UE module types to Bazel rules:
  - `Runtime` → `cc_library`
  - `Developer` → `cc_library` (editor-only)
  - `Editor` → `cc_library` + `cc_binary`
  - `Program` → `cc_binary`

**Complexity:** VERY HIGH
**Challenges:**
- C# `.Build.cs` files use complex conditional logic
- Platform-specific rules (`bCompileForIOS`, `bCompileForMac`, etc.)
- Dynamic module discovery at build time

#### 1.3 Compiler Toolchain Integration (8-12 weeks)
- Integrate platform compilers:
  - **Mac:** Clang 16.1+ (via Xcode)
  - **Windows:** MSVC 2022
  - **Linux:** Clang/GCC
- Configure include paths, defines, flags
- Implement Unreal's custom build tools:
  - `UnrealHeaderTool` (UHT) - reflection code generation
  - `ShaderCompileWorker`
  - `CrashReportClient` build

**Complexity:** VERY HIGH
**Challenges:**
- UHT must run before C++ compilation (codegen step)
- Each platform has unique compiler quirks
- Unreal uses custom `.natvis`, `.pch`, and `.ispc` files

#### 1.4 Build Core Engine Modules (12-16 weeks)
- Build `Core` module (foundation)
- Build `CoreUObject` (reflection system)
- Build `Engine` (main runtime)
- Build `Renderer` (graphics)
- Build 2000+ remaining modules

**Complexity:** EXTREME
**Bottleneck:** Circular dependencies, PCH management, parallel builds

**Estimated Phase 1 Total:** 30-42 weeks (7-10 months)

---

### Phase 2: UnrealAutomationTool (UAT) Replacement

**Goal:** Cook, stage, and package game projects

#### 2.1 AutomationUtils Core (8-10 weeks)
Port `AutomationUtils.Automation` (~50k lines C#):
- Command-line parsing and execution
- Logging and structured output
- File operations (copy, compress, hash)
- Process spawning and monitoring
- Platform detection

**Status:** Similar to your plugin manager tool (Go CLI)
**Complexity:** HIGH

#### 2.2 BuildCookRun Command (10-14 weeks)
Implement the critical cooking pipeline:

**Cook Phase:**
1. Launch UnrealEditor with `-run=cook` commandlet
2. Parse `.uproject` and `.uasset` files
3. Compile shaders for target platform
4. Serialize cooked assets to `.uasset` binary
5. Generate `.pak` files (asset packages)

**Stage Phase:**
1. Copy cooked content to staging directory
2. Include platform-specific binaries
3. Handle plugin content and dependencies

**Package Phase:**
1. Create platform-specific bundles:
   - **Mac:** `.app` bundle with code signing
   - **Windows:** Installer (.exe, .msi)
   - **Linux:** AppImage or tarball
   - **iOS/Android:** `.ipa`/`.apk` with signing

**Complexity:** EXTREME
**Why it's hard:**
- Cooking requires running the Editor (not Bazel-native)
- Shader compilation is multi-threaded and platform-specific
- Code signing requires developer certificates
- Package formats vary wildly per platform

#### 2.3 Platform Automation Modules (16-20 weeks)

Port platform-specific UAT modules:

**Apple Platforms (8-10 weeks):**
- `Apple.Automation` - Xcode integration
- `Mac.Automation` - `.app` bundle creation
- `IOS.Automation` - `.ipa` packaging
- `TVOS.Automation` - tvOS builds
- `VisionOS.Automation` - visionOS builds (NEW in UE 5.6)

**Challenges:**
- Xcode project generation
- Code signing and provisioning profiles
- Entitlements and sandboxing
- Notarization for distribution

**Windows Platform (4-6 weeks):**
- `Windows.Automation` - MSVC builds
- Installer creation (Nullsoft, WiX)

**Mobile Platforms (6-8 weeks):**
- `Android.Automation` - APK/AAB packaging
- Gradle build system integration
- Android NDK toolchain

**Estimated Phase 2 Total:** 34-44 weeks (8-11 months)

---

### Phase 3: Testing & Validation (12-16 weeks)

#### 3.1 Unit Tests
- Go unit tests for all modules
- Bazel test targets
- Mock external dependencies

#### 3.2 Integration Tests
- Full build pipeline tests
- Cook/package validation
- Cross-platform CI/CD

#### 3.3 Performance Optimization
- Bazel remote caching setup
- Incremental build optimization
- Parallel execution tuning

#### 3.4 Documentation
- Migration guide from UBT/UAT
- API documentation
- Example projects

**Estimated Phase 3 Total:** 12-16 weeks (3-4 months)

---

## Total Timeline

| Phase | Duration | Cumulative |
|-------|----------|------------|
| **Phase 1:** UBT Replacement | 30-42 weeks | 30-42 weeks |
| **Phase 2:** UAT Replacement | 34-44 weeks | 64-86 weeks |
| **Phase 3:** Testing & Docs | 12-16 weeks | 76-102 weeks |
| **TOTAL** | **76-102 weeks** | **~18-24 months** |

With 2-3 engineers working in parallel: **12-18 months**

---

## Risk Assessment

### Technical Risks

🔴 **HIGH RISK:**
1. **Unreal Engine Updates:** Epic releases 4-6 major versions per year. Maintaining compatibility is ongoing.
2. **UHT Code Generation:** Bazel doesn't natively support Unreal's reflection system.
3. **Cooking Complexity:** The cook process is undocumented and changes frequently.
4. **Platform SDK Changes:** Apple/Google update their toolchains 1-2x per year.

🟡 **MEDIUM RISK:**
1. **Third-Party Plugins:** Marketplace plugins may break with Bazel builds.
2. **Performance:** Bazel overhead might slow small projects (vs UBT).
3. **Team Expertise:** Requires deep knowledge of Unreal + Bazel + Go.

🟢 **LOW RISK:**
1. **Community Support:** Bazel has strong community and docs.
2. **Go Ecosystem:** Mature libraries for CLI, parsing, compression.

### Business Risks

- **Opportunity Cost:** 12-18 months of engineering time
- **Maintenance Burden:** Must track Epic's upstream changes indefinitely
- **Adoption:** Other developers won't use unsupported tools
- **ROI:** Only valuable if building Unreal from source regularly

---

## Alternative Approaches

### Option A: Minimal Scope (Cook-Only)

**Scope:** Only replace UAT's `BuildCookRun` command
- Keep using UBT for C++ builds
- Focus on cooking + packaging automation

**Effort:** 8-12 months (Phase 2 only)
**Benefit:** Solves immediate pain point (your current issue)

### Option B: Hybrid Approach

**Scope:** Bazel for dependency management, UBT/UAT for builds
- Use Bazel for asset pipeline
- Keep UBT/UAT for C++ compilation

**Effort:** 3-6 months
**Benefit:** Hermetic builds without full rewrite

### Option C: Fix Current Issue First

**Scope:** Solve the NuGet vulnerability blocking cook
- Disable vulnerability checks or update packages
- Get Kra packaged with existing tools

**Effort:** 1-2 hours
**Benefit:** Immediate unblock, evaluate Bazel later

---

## Resource Requirements

### Team Composition

**Minimum Viable Team:**
- 1x Unreal Engine Expert (C++/UE architecture)
- 1x Bazel Expert (build systems)
- 1x Go Developer (CLI tools)

**Ideal Team:**
- 2x Unreal Engineers (build + runtime)
- 1x Bazel/Build Systems Engineer
- 1x Go Developer
- 1x DevOps Engineer (CI/CD)

### Infrastructure

- **CI/CD:** GitHub Actions or BuildKite ($500-2000/month)
- **Bazel Remote Cache:** ~500GB-2TB storage ($50-200/month)
- **Development Machines:** Mac + Windows + Linux workstations

---

## Recommendation

### For Immediate Goal (Cook Kra Game)

❌ **Do NOT pursue rules_unreal_engine now**

**Why:**
- 12-18 month effort to solve a 1-hour problem
- Current UAT issue is solvable without rewrite
- Project is 5% complete, needs 95% more work

**Recommended Actions:**
1. Fix NuGet vulnerability blocking cook (1 hour)
2. Complete Kra build/cook/package pipeline (1-2 days)
3. Evaluate Bazel after shipping game

### For Long-Term Vision

✅ **Continue rules_unreal_engine as side project**

**Rationale:**
- Valuable learning experience
- Future-proofs your workflow
- Community contribution potential

**Suggested Roadmap:**
1. **Next 3 months:** Implement Phase 1.1-1.2 (Setup + Module parsing)
2. **Months 4-6:** Build single UE module as proof-of-concept
3. **Month 6:** Re-evaluate based on POC results
4. **Months 7-12:** Phase 1.3-1.4 if POC successful
5. **Year 2:** Phase 2 (UAT) if still motivated

---

## Success Metrics

Define success criteria before investing further:

✅ **Technical Metrics:**
- Build UE Editor in <1 hour (vs 2-3 hours with UBT)
- 90%+ cache hit rate on incremental builds
- Bit-identical output to Epic's official builds

✅ **Business Metrics:**
- Reduces CI/CD build times by 50%+
- Enables hermetic builds on any machine
- Supports all target platforms (Mac, Windows, Linux, iOS, Android)

✅ **Adoption Metrics:**
- 3+ external projects using rules_unreal_engine
- Active community contributions
- Epic Games acknowledges or adopts approach

---

## Conclusion

**rules_unreal_engine is an ambitious, worthwhile project**, but it's a **multi-year commitment** requiring significant engineering resources.

**For your immediate problem (cooking Kra):** Use existing UAT with a simple fix.

**For your long-term vision:** Continue building rules_unreal_engine incrementally as time permits, with realistic expectations about timeline and effort.

---

## Appendix: Prior Art

### Similar Projects

- [ue5-bazel](https://github.com/botman99/ue5-bazel) - Experimental UE5 Bazel rules
- [rules_unreal](https://github.com/electronicarts/rules_unreal) - EA's Unreal Bazel integration (archived)
- [ue4-docker](https://github.com/adamrehn/ue4-docker) - Containerized UE builds

### Lessons Learned

1. **Unreal's build system is intentionally complex** - Epic prioritizes flexibility over simplicity
2. **C++ build systems are notoriously difficult** - Bazel's CC rules have quirks
3. **Cooking is the hardest part** - Requires deep UE internals knowledge
4. **Platform-specific code dominates** - 70% of UAT is platform-specific

### References

- [Bazel C++ Rules](https://bazel.build/reference/be/c-cpp)
- [Unreal Build System Docs](https://docs.unrealengine.com/en-US/ProductionPipelines/BuildTools/)
- [Go Rules for Bazel](https://github.com/bazelbuild/rules_go)
