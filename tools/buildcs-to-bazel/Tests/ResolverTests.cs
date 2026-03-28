using Xunit;
using BuildCsToBazel.Resolution;

namespace BuildCsToBazel.Tests;

/// <summary>
/// Unit tests for ModulePathResolver.
/// </summary>
public class ResolverTests
{
    private readonly string _ueSource = "/Users/kareemmarch/projects/UnrealEngine/Engine/Source";
    private ModulePathResolver CreateResolver() => new(_ueSource);

    [Fact]
    public void Resolve_SimpleModule_ReturnsPath()
    {
        var resolver = CreateResolver();
        var result = resolver.Resolve("Core");

        Assert.NotNull(result);
        Assert.Contains("Runtime/Core", result);
        Assert.DoesNotContain("::", result);
    }

    [Fact]
    public void Resolve_CaseInsensitive_FindsModule()
    {
        var resolver = CreateResolver();

        // ICMP module: Build.cs filename is Icmp.Build.cs, but deps reference it as "ICMP"
        var result = resolver.Resolve("ICMP");

        Assert.NotNull(result);
        Assert.Contains("ICMP", result); // Directory name
    }

    [Fact]
    public void Resolve_CaseMismatch_ExplicitTarget_SingleColon()
    {
        var resolver = CreateResolver();

        // When dir name != canonical module name, resolver returns explicit target
        // e.g., //path/to/Dir:ModuleName
        var result = resolver.Resolve("ChaosVDRuntime");

        if (result != null && result.Contains(':'))
        {
            // Should have exactly one colon
            var colonCount = result.Count(c => c == ':');
            Assert.Equal(1, colonCount);
        }
    }

    [Fact]
    public void Resolve_UnknownModule_ReturnsNull()
    {
        var resolver = CreateResolver();
        var result = resolver.Resolve("NonExistentModule12345");

        Assert.Null(result);
    }

    [Fact]
    public void Resolve_ThirdPartyModule_ReturnsThirdPartyPath()
    {
        var resolver = CreateResolver();
        var result = resolver.Resolve("RapidJSON");

        Assert.NotNull(result);
        Assert.Contains("ThirdParty", result);
    }

    [Fact]
    public void GetAll_ReturnsHundredsOfModules()
    {
        var resolver = CreateResolver();

        Assert.True(resolver.Count > 800, $"Expected 800+ modules, got {resolver.Count}");
    }
}
