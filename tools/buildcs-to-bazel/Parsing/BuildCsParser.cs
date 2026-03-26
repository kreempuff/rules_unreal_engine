using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;
using BuildCsToBazel.Models;

namespace BuildCsToBazel.Parsing;

public class BuildCsParser
{
    // Map Build.cs property names to ModuleInfo field names
    private static readonly Dictionary<string, string> PropertyMap = new()
    {
        ["PublicDependencyModuleNames"] = "PublicDeps",
        ["PrivateDependencyModuleNames"] = "PrivateDeps",
        ["PublicIncludePathModuleNames"] = "PublicHeaderDeps",
        ["PrivateIncludePathModuleNames"] = "PrivateHeaderDeps",
        ["PublicDefinitions"] = "Defines",
        ["PrivateDefinitions"] = "LocalDefines",
        ["PublicIncludePaths"] = "PublicIncludes",
        ["PrivateIncludePaths"] = "PrivateIncludes",
        ["PublicSystemIncludePaths"] = "SystemIncludes",
        ["PublicAdditionalLibraries"] = "Linkopts",
        ["PublicSystemLibraries"] = "Linkopts",
        ["PublicFrameworks"] = "Frameworks",
    };

    private static readonly HashSet<string> KnownBoolProperties = new()
    {
        "bUseRTTI", "bEnableExceptions",
    };

    // Statements we recognize but don't extract data from (not warnings)
    private static readonly HashSet<string> IgnoredProperties = new()
    {
        "PCHUsage", "CppStandard", "bEnforceIWYU", "bLegacyPublicIncludePaths",
        "bLegacyParentIncludePaths", "bRequiresImplementModule",
        "PrivatePCHHeaderFile", "SharedPCHHeaderFile", "ShortName",
        "bPrecompile", "bUsePrecompiled", "bTreatAsEngineModule",
        "bAllowConfidentialPlatformDefines", "bDisableAutoRTFMInstrumentation",
        "bEnableUndefinedIdentifierWarnings", "bMergeUnityFiles",
        "OptimizeCode", "bWarningsAsErrors", "bEnableBufferSecurityChecks",
    };

    // Known property access patterns on sub-objects we can ignore
    private static readonly HashSet<string> IgnoredSubPropertyAccess = new()
    {
        "CppCompileWarningSettings", "UnsafeTypeCastWarningLevel",
    };

    public ModuleInfo Parse(string filePath, string moduleType)
    {
        var source = File.ReadAllText(filePath);
        var tree = CSharpSyntaxTree.ParseText(source);
        var root = tree.GetCompilationUnitRoot();

        // Find the class extending ModuleRules
        var classDecl = root.DescendantNodes()
            .OfType<ClassDeclarationSyntax>()
            .FirstOrDefault(c => c.BaseList?.Types
                .Any(t => t.ToString().Contains("ModuleRules")) == true);

        if (classDecl == null)
        {
            return new ModuleInfo
            {
                Name = Path.GetFileNameWithoutExtension(filePath).Replace(".Build", ""),
                FilePath = filePath,
                ModuleType = moduleType,
                Warnings = ["No class extending ModuleRules found"],
                NeedsManualReview = true,
            };
        }

        var moduleName = classDecl.Identifier.Text;

        // Find constructor
        var constructor = classDecl.DescendantNodes()
            .OfType<ConstructorDeclarationSyntax>()
            .FirstOrDefault();

        if (constructor?.Body == null)
        {
            return new ModuleInfo
            {
                Name = moduleName,
                FilePath = filePath,
                ModuleType = moduleType,
                Warnings = ["No constructor body found"],
                NeedsManualReview = true,
            };
        }

        // Check for virtual/override members (complexity signal)
        var hasVirtualMembers = classDecl.Members
            .Any(m => m.Modifiers.Any(mod =>
                mod.IsKind(SyntaxKind.VirtualKeyword) ||
                mod.IsKind(SyntaxKind.OverrideKeyword) ||
                mod.IsKind(SyntaxKind.ProtectedKeyword)));

        // Extract data from constructor body
        var publicDeps = new List<string>();
        var privateDeps = new List<string>();
        var publicHeaderDeps = new List<string>();
        var defines = new List<string>();
        var localDefines = new List<string>();
        var publicIncludes = new List<string>();
        var privateIncludes = new List<string>();
        var systemIncludes = new List<string>();
        var linkopts = new List<string>();
        var frameworks = new List<string>();
        var conditionalBlocks = new List<ConditionalBlock>();
        var warnings = new List<string>();
        var useRTTI = false;
        var enableExceptions = false;
        var isExternal = false;
        var unrecognized = 0;

        foreach (var statement in constructor.Body.Statements)
        {
            if (!TryExtract(statement, publicDeps, privateDeps, publicHeaderDeps,
                defines, localDefines, publicIncludes, privateIncludes,
                systemIncludes, linkopts, frameworks, conditionalBlocks, warnings,
                ref useRTTI, ref enableExceptions, ref isExternal))
            {
                unrecognized++;
            }
        }

        if (hasVirtualMembers)
            warnings.Add("Class has virtual/protected members");

        return new ModuleInfo
        {
            Name = moduleName,
            FilePath = filePath,
            ModuleType = isExternal ? "ThirdParty" : moduleType,
            PublicDeps = publicDeps,
            PrivateDeps = privateDeps,
            PublicHeaderDeps = publicHeaderDeps,
            Defines = defines,
            LocalDefines = localDefines,
            PublicIncludes = publicIncludes,
            PrivateIncludes = privateIncludes,
            SystemIncludes = systemIncludes,
            Linkopts = linkopts,
            Frameworks = frameworks,
            ConditionalBlocks = conditionalBlocks,
            UseRTTI = useRTTI,
            EnableExceptions = enableExceptions,
            IsExternal = isExternal,
            Warnings = warnings,
            NeedsManualReview = unrecognized > 3 || hasVirtualMembers,
        };
    }

    // Platform condition mapping: C# condition text → Bazel select key
    private static readonly Dictionary<string, string> PlatformConditionMap = new()
    {
        // Target.Platform == UnrealTargetPlatform.X
        ["UnrealTargetPlatform.Mac"] = "@platforms//os:macos",
        ["UnrealTargetPlatform.Win64"] = "@platforms//os:windows",
        ["UnrealTargetPlatform.Linux"] = "@platforms//os:linux",
        ["UnrealTargetPlatform.LinuxArm64"] = "@platforms//os:linux",
        ["UnrealTargetPlatform.IOS"] = "@platforms//os:ios",
        ["UnrealTargetPlatform.Android"] = "@platforms//os:android",
        ["UnrealTargetPlatform.TVOS"] = "@platforms//os:tvos",
        ["UnrealTargetPlatform.VisionOS"] = "@platforms//os:visionos",

        // Target.IsInPlatformGroup(UnrealPlatformGroup.X)
        ["UnrealPlatformGroup.Windows"] = "@platforms//os:windows",
        ["UnrealPlatformGroup.Linux"] = "@platforms//os:linux",
        ["UnrealPlatformGroup.Unix"] = "@platforms//os:linux",
        ["UnrealPlatformGroup.Apple"] = "@platforms//os:macos",
        ["UnrealPlatformGroup.IOS"] = "@platforms//os:ios",
        ["UnrealPlatformGroup.Android"] = "@platforms//os:android",
        ["UnrealPlatformGroup.Desktop"] = "@platforms//os:linux",
    };

    private static string? TryMapCondition(ExpressionSyntax condition)
    {
        var text = condition.ToString();

        // Target.Platform == UnrealTargetPlatform.X
        foreach (var (key, value) in PlatformConditionMap)
        {
            if (text.Contains(key))
                return value;
        }

        // Target.Platform.IsInGroup(X) or Target.IsInPlatformGroup(X)
        // Already covered by the contains check above

        return null;
    }

    private bool TryExtract(
        StatementSyntax statement,
        List<string> publicDeps, List<string> privateDeps, List<string> publicHeaderDeps,
        List<string> defines, List<string> localDefines,
        List<string> publicIncludes, List<string> privateIncludes, List<string> systemIncludes,
        List<string> linkopts, List<string> frameworks,
        List<ConditionalBlock> conditionalBlocks, List<string> warnings,
        ref bool useRTTI, ref bool enableExceptions, ref bool isExternal)
    {
        if (statement is not ExpressionStatementSyntax exprStmt)
        {
            // Handle if-statements: try to map condition to a Bazel platform
            if (statement is IfStatementSyntax ifStmt)
            {
                return TryExtractConditional(ifStmt, conditionalBlocks, warnings);
            }
            return false;
        }

        var expr = exprStmt.Expression;

        // Pattern: PropertyName.Add("value") or PropertyName.AddRange(new string[] { ... })
        if (expr is InvocationExpressionSyntax invocation &&
            invocation.Expression is MemberAccessExpressionSyntax memberAccess)
        {
            var methodName = memberAccess.Name.Identifier.Text;
            var receiverText = memberAccess.Expression.ToString();

            // Check for known helper methods
            if (receiverText is "AddEngineThirdPartyPrivateStaticDependencies" or
                "AddEngineThirdPartyPrivateDynamicDependencies" ||
                memberAccess.Expression is IdentifierNameSyntax { Identifier.Text:
                    "AddEngineThirdPartyPrivateStaticDependencies" or
                    "AddEngineThirdPartyPrivateDynamicDependencies" })
            {
                // This is a direct method call: AddEngineThirdPartyPrivateStaticDependencies(Target, "lib1", ...)
                return TryExtractHelperCall(invocation, privateDeps);
            }

            // Check if the invocation itself is the helper method (not on a receiver)
            if (expr is InvocationExpressionSyntax { Expression: IdentifierNameSyntax idName } &&
                (idName.Identifier.Text == "AddEngineThirdPartyPrivateStaticDependencies" ||
                 idName.Identifier.Text == "AddEngineThirdPartyPrivateDynamicDependencies"))
            {
                return TryExtractHelperCall(invocation, privateDeps);
            }

            // Get the target list for this property
            var targetList = GetTargetList(receiverText,
                publicDeps, privateDeps, publicHeaderDeps,
                defines, localDefines, publicIncludes, privateIncludes,
                systemIncludes, linkopts, frameworks);

            if (targetList == null)
            {
                // Check if it's a known-but-ignored property
                if (IsIgnoredAccess(receiverText))
                    return true;
                return false;
            }

            if (methodName == "Add")
                return TryExtractAdd(invocation, targetList);
            if (methodName == "AddRange")
                return TryExtractAddRange(invocation, targetList);
        }

        // Pattern: direct helper call without member access
        if (expr is InvocationExpressionSyntax directCall &&
            directCall.Expression is IdentifierNameSyntax directId)
        {
            if (directId.Identifier.Text is "AddEngineThirdPartyPrivateStaticDependencies"
                or "AddEngineThirdPartyPrivateDynamicDependencies")
            {
                return TryExtractHelperCall(directCall, privateDeps);
            }
            if (directId.Identifier.Text is "SetupModulePhysicsSupport"
                or "SetupGameplayDebuggerSupport" or "SetupIrisSupport"
                or "SetupModuleChaosVisualDebuggerSupport" or "EnableMeshEditorSupport"
                or "SetupVerse")
            {
                // Known helpers that we skip in MVP
                return true;
            }
        }

        // Pattern: Type = ModuleType.External or boolean assignments
        if (expr is AssignmentExpressionSyntax assignment)
        {
            var leftText = assignment.Left.ToString();
            var rightText = assignment.Right.ToString();

            if (leftText == "Type" && rightText.Contains("External"))
            {
                isExternal = true;
                return true;
            }

            if (leftText == "bUseRTTI" && rightText == "true")
            {
                useRTTI = true;
                return true;
            }

            if (leftText == "bEnableExceptions" && rightText == "true")
            {
                enableExceptions = true;
                return true;
            }

            // Known boolean/enum properties we can safely ignore
            if (KnownBoolProperties.Contains(leftText) || IgnoredProperties.Contains(leftText))
                return true;
        }

        return false;
    }

    private bool TryExtractConditional(IfStatementSyntax ifStmt, List<ConditionalBlock> blocks, List<string> warnings)
    {
        // Walk the if/else-if chain
        var current = ifStmt;
        bool anyMapped = false;

        while (current != null)
        {
            var bazelCondition = TryMapCondition(current.Condition);

            if (bazelCondition != null)
            {
                // Extract statements from the if-body into a ConditionalBlock
                var block = ExtractConditionalBody(current.Statement, bazelCondition, current.Condition.ToString());
                if (block != null)
                {
                    blocks.Add(block);
                    anyMapped = true;
                }
            }
            else
            {
                // Unrecognized condition — add warning but don't fail
                var condText = current.Condition.ToString();
                if (condText.Length > 80) condText = condText[..80];
                warnings.Add($"Unrecognized condition: {condText}");
            }

            // Follow the else-if chain
            if (current.Else?.Statement is IfStatementSyntax elseIf)
            {
                current = elseIf;
            }
            else
            {
                // Plain else block — skip (would need "//conditions:default" handling)
                current = null;
            }
        }

        return anyMapped;
    }

    private ConditionalBlock? ExtractConditionalBody(StatementSyntax body, string bazelCondition, string rawCondition)
    {
        // Get the list of statements (handle both block and single statements)
        IEnumerable<StatementSyntax> statements;
        if (body is BlockSyntax block)
            statements = block.Statements;
        else
            statements = [body];

        var publicDeps = new List<string>();
        var privateDeps = new List<string>();
        var publicHeaderDeps = new List<string>();
        var defines = new List<string>();
        var localDefines = new List<string>();
        var publicIncludes = new List<string>();
        var privateIncludes = new List<string>();
        var systemIncludes = new List<string>();
        var linkopts = new List<string>();
        var frameworks = new List<string>();
        var nestedBlocks = new List<ConditionalBlock>();
        var warnings = new List<string>();
        var useRTTI = false;
        var enableExceptions = false;
        var isExternal = false;

        foreach (var stmt in statements)
        {
            // Reuse the same extraction logic for inner statements
            TryExtract(stmt, publicDeps, privateDeps, publicHeaderDeps,
                defines, localDefines, publicIncludes, privateIncludes,
                systemIncludes, linkopts, frameworks, nestedBlocks, warnings,
                ref useRTTI, ref enableExceptions, ref isExternal);
        }

        // Only create a block if something was extracted
        if (publicDeps.Count == 0 && privateDeps.Count == 0 && publicHeaderDeps.Count == 0 &&
            defines.Count == 0 && localDefines.Count == 0 && linkopts.Count == 0 &&
            frameworks.Count == 0 && systemIncludes.Count == 0 &&
            publicIncludes.Count == 0 && privateIncludes.Count == 0)
            return null;

        return new ConditionalBlock
        {
            BazelCondition = bazelCondition,
            RawCondition = rawCondition,
            PublicDeps = publicDeps,
            PrivateDeps = privateDeps,
            PublicHeaderDeps = publicHeaderDeps,
            Defines = defines,
            LocalDefines = localDefines,
            Linkopts = linkopts,
            Frameworks = frameworks,
            SystemIncludes = systemIncludes,
            PublicIncludes = publicIncludes,
            PrivateIncludes = privateIncludes,
        };
    }

    private static bool TryExtractAdd(InvocationExpressionSyntax invocation, List<string> target)
    {
        if (invocation.ArgumentList.Arguments.Count != 1)
            return false;

        var arg = invocation.ArgumentList.Arguments[0].Expression;
        if (arg is LiteralExpressionSyntax { Token.ValueText: var value })
        {
            target.Add(value);
            return true;
        }

        return false;
    }

    private static bool TryExtractAddRange(InvocationExpressionSyntax invocation, List<string> target)
    {
        if (invocation.ArgumentList.Arguments.Count != 1)
            return false;

        var arg = invocation.ArgumentList.Arguments[0].Expression;

        // new string[] { "a", "b" } or new[] { "a", "b" }
        InitializerExpressionSyntax? initializer = null;

        if (arg is ArrayCreationExpressionSyntax arrayCreation)
            initializer = arrayCreation.Initializer;
        else if (arg is ImplicitArrayCreationExpressionSyntax implicitArray)
            initializer = implicitArray.Initializer;
        else if (arg is CollectionExpressionSyntax collection)
        {
            // C# 12 collection expressions: ["a", "b"]
            foreach (var element in collection.Elements)
            {
                if (element is ExpressionElementSyntax { Expression: LiteralExpressionSyntax lit })
                    target.Add(lit.Token.ValueText);
            }
            return true;
        }

        if (initializer == null)
            return false;

        foreach (var element in initializer.Expressions)
        {
            if (element is LiteralExpressionSyntax literal)
                target.Add(literal.Token.ValueText);
        }

        return true;
    }

    private static bool TryExtractHelperCall(InvocationExpressionSyntax invocation, List<string> privateDeps)
    {
        // Skip first argument (Target), extract remaining string literals
        var args = invocation.ArgumentList.Arguments;
        for (int i = 1; i < args.Count; i++)
        {
            if (args[i].Expression is LiteralExpressionSyntax literal)
                privateDeps.Add(literal.Token.ValueText);
        }
        return args.Count > 1;
    }

    private static List<string>? GetTargetList(
        string propertyName,
        List<string> publicDeps, List<string> privateDeps, List<string> publicHeaderDeps,
        List<string> defines, List<string> localDefines,
        List<string> publicIncludes, List<string> privateIncludes, List<string> systemIncludes,
        List<string> linkopts, List<string> frameworks)
    {
        return propertyName switch
        {
            "PublicDependencyModuleNames" => publicDeps,
            "PrivateDependencyModuleNames" => privateDeps,
            "PublicIncludePathModuleNames" => publicHeaderDeps,
            "PrivateIncludePathModuleNames" => publicHeaderDeps, // Treat as header deps too
            "PublicDefinitions" => defines,
            "PrivateDefinitions" => localDefines,
            "PublicIncludePaths" => publicIncludes,
            "PrivateIncludePaths" => privateIncludes,
            "PublicSystemIncludePaths" => systemIncludes,
            "PublicAdditionalLibraries" => linkopts,
            "PublicSystemLibraries" => linkopts,
            "PublicFrameworks" => frameworks,
            "PublicWeakFrameworks" => frameworks,
            _ => null,
        };
    }

    private static bool IsIgnoredAccess(string text)
    {
        foreach (var prop in IgnoredSubPropertyAccess)
        {
            if (text.Contains(prop))
                return true;
        }
        // DynamicallyLoadedModuleNames, CircularlyReferencedDependentModules, etc.
        if (text.Contains("DynamicallyLoadedModuleNames") ||
            text.Contains("CircularlyReferencedDependentModules") ||
            text.Contains("PublicDelayLoadDLLs") ||
            text.Contains("RuntimeDependencies") ||
            text.Contains("AdditionalPropertiesForReceipt") ||
            text.Contains("ExternalDependencies") ||
            text.Contains("AdditionalBundleResources"))
            return true;
        return false;
    }
}
