namespace BuildCsToBazel.Models;

public record ModuleInfo
{
    public required string Name { get; init; }
    public required string FilePath { get; init; }
    public required string ModuleType { get; init; } // Runtime, Developer, Editor, Program, ThirdParty

    // Dependencies
    public List<string> PublicDeps { get; init; } = [];
    public List<string> PrivateDeps { get; init; } = [];
    public List<string> PublicHeaderDeps { get; init; } = [];

    // Defines
    public List<string> Defines { get; init; } = [];
    public List<string> LocalDefines { get; init; } = [];

    // Include paths
    public List<string> PublicIncludes { get; init; } = [];
    public List<string> PrivateIncludes { get; init; } = [];
    public List<string> SystemIncludes { get; init; } = [];

    // Link options
    public List<string> Linkopts { get; init; } = [];
    public List<string> Frameworks { get; init; } = [];

    // Compiler behavior
    public bool UseRTTI { get; init; }
    public bool EnableExceptions { get; init; }
    public bool IsExternal { get; init; }

    // Platform-conditional additions (Phase 2)
    public List<ConditionalBlock> ConditionalBlocks { get; init; } = [];

    // Diagnostics
    public List<string> Warnings { get; init; } = [];
    public bool NeedsManualReview { get; init; }
}

public record ConditionalBlock
{
    public required string BazelCondition { get; init; } // e.g., "@platforms//os:macos"
    public required string RawCondition { get; init; }   // Original C# text

    public List<string> PublicDeps { get; init; } = [];
    public List<string> PrivateDeps { get; init; } = [];
    public List<string> PublicHeaderDeps { get; init; } = [];
    public List<string> Defines { get; init; } = [];
    public List<string> LocalDefines { get; init; } = [];
    public List<string> Linkopts { get; init; } = [];
    public List<string> Frameworks { get; init; } = [];
    public List<string> SystemIncludes { get; init; } = [];
    public List<string> PublicIncludes { get; init; } = [];
    public List<string> PrivateIncludes { get; init; } = [];
}
