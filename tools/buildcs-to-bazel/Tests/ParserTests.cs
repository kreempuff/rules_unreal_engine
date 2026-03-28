using Xunit;
using BuildCsToBazel.Parsing;

namespace BuildCsToBazel.Tests;

/// <summary>
/// Unit tests for BuildCsParser.
/// </summary>
public class ParserTests
{
    private readonly string _ueSource = "/Users/kareemmarch/projects/UnrealEngine/Engine/Source";

    [Fact]
    public void Parse_SimpleModule_ExtractsDeps()
    {
        var parser = new BuildCsParser();
        var file = Path.Combine(_ueSource, "Runtime/Json/Json.Build.cs");
        var info = parser.Parse(file, "Runtime");

        Assert.Equal("Json", info.Name);
        Assert.Contains("Core", info.PublicDeps);
        Assert.Contains("RapidJSON", info.PublicDeps);
        Assert.False(info.NeedsManualReview);
    }

    [Fact]
    public void Parse_ExternalModule_DetectsType()
    {
        var parser = new BuildCsParser();
        var file = Path.Combine(_ueSource, "ThirdParty/zlib/zlib.Build.cs");
        var info = parser.Parse(file, "ThirdParty");

        Assert.True(info.IsExternal);
    }

    [Fact]
    public void Parse_ModuleName_UsesFilenameNotClassName()
    {
        var parser = new BuildCsParser();
        // UElibSampleRate.Build.cs has class name UELibSampleRate (different case)
        var file = Path.Combine(_ueSource, "ThirdParty/libSampleRate/UElibSampleRate.Build.cs");
        var info = parser.Parse(file, "ThirdParty");

        Assert.Equal("UElibSampleRate", info.Name);
    }

    [Fact]
    public void Parse_ConditionalDeps_CreatesBlocks()
    {
        var parser = new BuildCsParser();
        var file = Path.Combine(_ueSource, "Runtime/ApplicationCore/ApplicationCore.Build.cs");
        var info = parser.Parse(file, "Runtime");

        Assert.True(info.ConditionalBlocks.Count > 0, "Expected conditional blocks for ApplicationCore");

        // Should have a macOS conditional
        var macBlock = info.ConditionalBlocks.FirstOrDefault(
            b => b.BazelCondition == "@platforms//os:macos");
        Assert.NotNull(macBlock);
    }

    [Fact]
    public void Parse_HelperMethod_ExtractsPrivateDeps()
    {
        var parser = new BuildCsParser();
        var file = Path.Combine(_ueSource, "Runtime/Core/Core.Build.cs");
        var info = parser.Parse(file, "Runtime");

        // Core uses AddEngineThirdPartyPrivateStaticDependencies for BLAKE3, etc.
        Assert.Contains("BLAKE3", info.PrivateDeps);
    }

    [Fact]
    public void Parse_Defines_Extracted()
    {
        var parser = new BuildCsParser();
        var file = Path.Combine(_ueSource, "Runtime/Sockets/Sockets.Build.cs");
        var info = parser.Parse(file, "Runtime");

        Assert.Contains("SOCKETS_PACKAGE=1", info.Defines);
    }
}
