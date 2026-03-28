using Xunit;
using BuildCsToBazel.Models;
using BuildCsToBazel.Emitting;
using BuildCsToBazel.Resolution;

namespace BuildCsToBazel.Tests;

/// <summary>
/// Unit tests for StarlarkEmitter. Run with: dotnet test
/// </summary>
public class EmitterTests
{
    private readonly string _ueSource = "/Users/kareemmarch/projects/UnrealEngine/Engine/Source";
    private StarlarkEmitter CreateEmitter()
    {
        var resolver = new ModulePathResolver(_ueSource);
        return new StarlarkEmitter(resolver);
    }

    [Fact]
    public void Emit_SimpleModule_NoDoubleColons()
    {
        var emitter = CreateEmitter();
        var module = new ModuleInfo
        {
            Name = "Json",
            FilePath = "Engine/Source/Runtime/Json/Json.Build.cs",
            ModuleType = "Runtime",
            PublicDeps = ["Core", "RapidJSON"],
        };

        var result = emitter.Emit(module);

        // No double colons in any label
        Assert.DoesNotContain("::", result);
    }

    [Fact]
    public void Emit_ModuleWithCaseMismatch_SingleColon()
    {
        // ChaosVDRuntime lives in ChaosVisualDebugger directory — resolver returns explicit target
        var emitter = CreateEmitter();
        var module = new ModuleInfo
        {
            Name = "TestMod",
            FilePath = "Engine/Source/Runtime/TestMod/TestMod.Build.cs",
            ModuleType = "Runtime",
            PublicDeps = ["ChaosVDRuntime"],
        };

        var result = emitter.Emit(module);

        Assert.DoesNotContain("::", result);
        Assert.Contains("ChaosVDRuntime", result);
    }

    [Fact]
    public void Emit_TransitiveHeaderDeps_NoDoubleColons()
    {
        var emitter = CreateEmitter();
        var module = new ModuleInfo
        {
            Name = "AutoRTFM",
            FilePath = "Engine/Source/Runtime/AutoRTFM/AutoRTFM.Build.cs",
            ModuleType = "Runtime",
            PublicDeps = ["Core"],
        };
        var transitiveDeps = new HashSet<string> { "ChaosVDRuntime", "TraceLog", "ImageCore" };

        var result = emitter.Emit(module, transitiveDeps);

        Assert.DoesNotContain("::", result);
        // Transitive deps should have _headers suffix
        Assert.Contains("_headers", result);
    }

    [Fact]
    public void Emit_NoDuplicateDeps_SameModuleInPublicAndPrivate()
    {
        var emitter = CreateEmitter();
        var module = new ModuleInfo
        {
            Name = "TestMod",
            FilePath = "Engine/Source/Runtime/TestMod/TestMod.Build.cs",
            ModuleType = "Runtime",
            PublicDeps = ["Core", "Json"],
            PrivateDeps = ["Json", "Projects"], // Json duplicated
        };

        var result = emitter.Emit(module);

        // Json should NOT appear in private_deps (already in public_deps)
        // Projects should still be in private_deps
        Assert.Contains("private_deps", result); // Projects remains
        // Count Json label occurrences — should be exactly 1 (in public_deps only)
        var jsonLabel = "//UnrealEngine/Engine/Source/Runtime/Json";
        var count = 0;
        var idx = 0;
        while ((idx = result.IndexOf(jsonLabel, idx, StringComparison.Ordinal)) != -1) { count++; idx += jsonLabel.Length; }
        Assert.Equal(1, count);
    }

    [Fact]
    public void Emit_NoDuplicateWithinList()
    {
        var emitter = CreateEmitter();
        var module = new ModuleInfo
        {
            Name = "TestMod",
            FilePath = "Engine/Source/Runtime/TestMod/TestMod.Build.cs",
            ModuleType = "Runtime",
            PrivateDeps = ["Core", "Core", "Json"], // Core duplicated
        };

        var result = emitter.Emit(module);

        // Count occurrences of the Core label
        var coreLabel = "//UnrealEngine/Engine/Source/Runtime/Core";
        var count = 0;
        var idx = 0;
        while ((idx = result.IndexOf(coreLabel, idx, StringComparison.Ordinal)) != -1)
        {
            count++;
            idx += coreLabel.Length;
        }
        Assert.Equal(1, count);
    }

    [Fact]
    public void Emit_ConditionalDeps_DeduplicatedAgainstUnconditional()
    {
        var emitter = CreateEmitter();
        var module = new ModuleInfo
        {
            Name = "TestMod",
            FilePath = "Engine/Source/Runtime/TestMod/TestMod.Build.cs",
            ModuleType = "Runtime",
            PublicDeps = ["Core"],
            ConditionalBlocks = [
                new ConditionalBlock
                {
                    BazelCondition = "@platforms//os:macos",
                    RawCondition = "Target.Platform == UnrealTargetPlatform.Mac",
                    PublicDeps = ["Core"], // Same as unconditional — should be deduped
                },
            ],
        };

        var result = emitter.Emit(module);

        // Should NOT have a select() since the conditional dep was deduped
        Assert.DoesNotContain("select(", result);
    }

    [Fact]
    public void Emit_ExternalModule_UsesCC_Library()
    {
        var emitter = CreateEmitter();
        var module = new ModuleInfo
        {
            Name = "zlib",
            FilePath = "Engine/Source/ThirdParty/zlib/zlib.Build.cs",
            ModuleType = "ThirdParty",
            IsExternal = true,
        };

        var result = emitter.Emit(module);

        Assert.Contains("cc_library", result);
        Assert.DoesNotContain("ue_module", result);
    }
}
