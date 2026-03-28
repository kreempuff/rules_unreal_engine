namespace BuildCsToBazel.Resolution;

public class ModulePathResolver
{
    private readonly Dictionary<string, string> _moduleToPath = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, string> _moduleToType = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, string> _moduleToCanonicalName = new(); // lowercase key → original case

    public ModulePathResolver(string engineSourcePath)
    {
        Scan(engineSourcePath);
    }

    private void Scan(string engineSourcePath)
    {
        foreach (var file in Directory.EnumerateFiles(engineSourcePath, "*.Build.cs", SearchOption.AllDirectories))
        {
            var fileName = Path.GetFileName(file);
            if (!fileName.EndsWith(".Build.cs", StringComparison.OrdinalIgnoreCase))
                continue;

            var moduleName = fileName[..^".Build.cs".Length];
            var moduleDir = Path.GetDirectoryName(file)!;
            // engineSourcePath is .../Engine/Source — we want paths relative to UE root (parent of Engine/)
            var ueRoot = Path.GetDirectoryName(Path.GetDirectoryName(engineSourcePath)!)!;
            var relativePath = Path.GetRelativePath(ueRoot, moduleDir);

            // Normalize to forward slashes for Bazel labels
            var bazelPath = "//UnrealEngine/" + relativePath.Replace('\\', '/');
            var moduleType = InferModuleType(relativePath);

            if (_moduleToPath.TryGetValue(moduleName, out var existing))
            {
                // Duplicate module name — keep the first one, warn
                Console.Error.WriteLine($"WARNING: Duplicate module name '{moduleName}': {existing} vs {bazelPath}");
                continue;
            }

            _moduleToPath[moduleName] = bazelPath;
            _moduleToType[moduleName] = moduleType;
            _moduleToCanonicalName[moduleName.ToLowerInvariant()] = moduleName;
        }
    }

    private static string InferModuleType(string relativePath)
    {
        var normalized = relativePath.Replace('\\', '/');
        if (normalized.Contains("/ThirdParty/")) return "ThirdParty";
        if (normalized.Contains("/Developer/")) return "Developer";
        if (normalized.Contains("/Editor/")) return "Editor";
        if (normalized.Contains("/Programs/")) return "Program";
        return "Runtime";
    }

    public string? Resolve(string moduleName)
    {
        if (!_moduleToPath.TryGetValue(moduleName, out var path))
            return null;

        // Always return explicit target: //path:CanonicalName
        // This ensures the target name uses the canonical case from the filename,
        // not the caller's case (e.g., "NVAftermath" vs "NVaftermath")
        var canonicalName = _moduleToCanonicalName.GetValueOrDefault(moduleName.ToLowerInvariant(), moduleName);
        return path + ":" + canonicalName;
    }

    public string? GetModuleType(string moduleName)
    {
        return _moduleToType.GetValueOrDefault(moduleName);
    }

    public IReadOnlyDictionary<string, string> GetAll() => _moduleToPath;

    public int Count => _moduleToPath.Count;
}
