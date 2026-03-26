using BuildCsToBazel.Parsing;
using BuildCsToBazel.Emitting;
using BuildCsToBazel.Resolution;

namespace BuildCsToBazel;

class Program
{
    static int Main(string[] args)
    {
        if (args.Length < 1)
        {
            PrintUsage();
            return 1;
        }

        var command = args[0];
        var options = ParseOptions(args[1..]);

        if (!options.TryGetValue("--ue-source", out var ueSource))
        {
            Console.Error.WriteLine("ERROR: --ue-source is required");
            return 1;
        }

        if (!Directory.Exists(ueSource))
        {
            Console.Error.WriteLine($"ERROR: Directory not found: {ueSource}");
            return 1;
        }

        return command switch
        {
            "scan" => RunScan(ueSource),
            "generate" => RunGenerate(ueSource, options),
            "resolve" => RunResolve(ueSource),
            _ => PrintUsage(),
        };
    }

    static int RunScan(string ueSource)
    {
        Console.WriteLine($"Scanning {ueSource} for .Build.cs files...\n");

        var resolver = new ModulePathResolver(ueSource);
        var parser = new BuildCsParser();

        int simple = 0, conditional = 0, complex = 0, total = 0;
        var complexModules = new List<string>();

        foreach (var file in Directory.EnumerateFiles(ueSource, "*.Build.cs", SearchOption.AllDirectories))
        {
            total++;
            var moduleType = InferModuleType(file);
            var info = parser.Parse(file, moduleType);

            if (info.NeedsManualReview)
            {
                complex++;
                complexModules.Add($"  {info.Name}: {string.Join("; ", info.Warnings)}");
            }
            else if (info.Warnings.Any(w => w.Contains("Conditional")))
            {
                conditional++;
            }
            else
            {
                simple++;
            }
        }

        Console.WriteLine($"Total modules:  {total}");
        Console.WriteLine($"  Simple:       {simple} ({100 * simple / total}%)");
        Console.WriteLine($"  Conditional:  {conditional} ({100 * conditional / total}%)");
        Console.WriteLine($"  Complex:      {complex} ({100 * complex / total}%)");
        Console.WriteLine($"\nModule resolver: {resolver.Count} modules mapped");

        if (complexModules.Count > 0)
        {
            Console.WriteLine($"\nComplex modules (need manual review):");
            foreach (var m in complexModules.Take(20))
                Console.WriteLine(m);
            if (complexModules.Count > 20)
                Console.WriteLine($"  ... and {complexModules.Count - 20} more");
        }

        return 0;
    }

    static int RunGenerate(string ueSource, Dictionary<string, string> options)
    {
        var outputDir = options.GetValueOrDefault("--output", "generated_ue_modules");
        var singleModule = options.GetValueOrDefault("--module");
        var skipComplex = options.ContainsKey("--skip-complex");

        Console.WriteLine($"Generating BUILD.bazel files from {ueSource}");
        Console.WriteLine($"Output: {outputDir}");
        if (singleModule != null) Console.WriteLine($"Module: {singleModule}");
        Console.WriteLine();

        var resolver = new ModulePathResolver(ueSource);
        var parser = new BuildCsParser();
        var emitter = new StarlarkEmitter(resolver);

        int generated = 0, skipped = 0, failed = 0;

        foreach (var file in Directory.EnumerateFiles(ueSource, "*.Build.cs", SearchOption.AllDirectories))
        {
            var moduleName = Path.GetFileNameWithoutExtension(file).Replace(".Build", "");

            if (singleModule != null && moduleName != singleModule)
                continue;

            var moduleType = InferModuleType(file);
            var info = parser.Parse(file, moduleType);

            if (skipComplex && info.NeedsManualReview)
            {
                skipped++;
                continue;
            }

            var starlark = emitter.Emit(info);

            // Determine output path: mirror the Engine/Source/ structure
            var relDir = GetRelativeModuleDir(file, ueSource);
            var outPath = Path.Combine(outputDir, relDir, "BUILD.bazel");

            Directory.CreateDirectory(Path.GetDirectoryName(outPath)!);
            File.WriteAllText(outPath, starlark);
            generated++;

            if (info.Warnings.Count > 0)
            {
                Console.Error.WriteLine($"  WARN {moduleName}: {string.Join("; ", info.Warnings)}");
            }
        }

        Console.WriteLine($"\nGenerated: {generated}");
        Console.WriteLine($"Skipped:   {skipped}");
        Console.WriteLine($"Failed:    {failed}");

        return 0;
    }

    static int RunResolve(string ueSource)
    {
        var resolver = new ModulePathResolver(ueSource);
        Console.WriteLine($"Resolved {resolver.Count} modules:\n");

        foreach (var (name, path) in resolver.GetAll().OrderBy(kv => kv.Key))
        {
            Console.WriteLine($"  {name,-40} → {path}");
        }

        return 0;
    }

    static int PrintUsage()
    {
        Console.WriteLine("Usage: buildcs-to-bazel <command> [options]");
        Console.WriteLine();
        Console.WriteLine("Commands:");
        Console.WriteLine("  scan       Scan .Build.cs files and report complexity (dry-run)");
        Console.WriteLine("  generate   Parse .Build.cs files and emit BUILD.bazel files");
        Console.WriteLine("  resolve    Print module name → Bazel label map");
        Console.WriteLine();
        Console.WriteLine("Options:");
        Console.WriteLine("  --ue-source <path>   Path to Engine/Source directory (required)");
        Console.WriteLine("  --output <path>      Output directory (default: generated_ue_modules)");
        Console.WriteLine("  --module <name>      Process only this module");
        Console.WriteLine("  --skip-complex       Skip modules needing manual review");
        return 1;
    }

    static Dictionary<string, string> ParseOptions(string[] args)
    {
        var opts = new Dictionary<string, string>();
        for (int i = 0; i < args.Length; i++)
        {
            if (args[i].StartsWith("--"))
            {
                if (i + 1 < args.Length && !args[i + 1].StartsWith("--"))
                {
                    opts[args[i]] = args[i + 1];
                    i++;
                }
                else
                {
                    opts[args[i]] = "";
                }
            }
        }
        return opts;
    }

    static string InferModuleType(string filePath)
    {
        var normalized = filePath.Replace('\\', '/');
        if (normalized.Contains("/ThirdParty/")) return "ThirdParty";
        if (normalized.Contains("/Developer/")) return "Developer";
        if (normalized.Contains("/Editor/")) return "Editor";
        if (normalized.Contains("/Programs/")) return "Program";
        return "Runtime";
    }

    static string GetRelativeModuleDir(string filePath, string ueSource)
    {
        var dir = Path.GetDirectoryName(filePath)!;
        return Path.GetRelativePath(ueSource, dir);
    }
}
