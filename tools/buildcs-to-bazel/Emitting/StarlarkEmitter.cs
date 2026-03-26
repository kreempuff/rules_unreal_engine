using System.Text;
using BuildCsToBazel.Models;
using BuildCsToBazel.Resolution;

namespace BuildCsToBazel.Emitting;

public class StarlarkEmitter
{
    private readonly ModulePathResolver _resolver;

    public StarlarkEmitter(ModulePathResolver resolver)
    {
        _resolver = resolver;
    }

    public string Emit(ModuleInfo module)
    {
        var sb = new StringBuilder();

        // Docstring
        var relativePath = GetRelativeBuildCsPath(module.FilePath);
        sb.AppendLine($"\"\"\"Unreal Engine {module.Name} module.");
        sb.AppendLine();
        sb.AppendLine($"Auto-generated from: {relativePath}");
        sb.AppendLine("\"\"\"");
        sb.AppendLine();

        // Load statement
        if (module.IsExternal)
        {
            sb.AppendLine("load(\"@rules_cc//cc:defs.bzl\", \"cc_library\")");
        }
        else
        {
            sb.AppendLine("load(\"@rules_unreal_engine//bzl:module.bzl\", \"ue_module\")");
        }
        sb.AppendLine();

        if (module.IsExternal)
        {
            EmitThirdPartyModule(sb, module);
        }
        else
        {
            EmitUeModule(sb, module);
        }

        return sb.ToString();
    }

    private void EmitUeModule(StringBuilder sb, ModuleInfo module)
    {
        sb.AppendLine("ue_module(");
        EmitStringParam(sb, "name", module.Name);

        if (module.ModuleType != "Runtime")
            EmitStringParam(sb, "module_type", module.ModuleType);

        // Dependencies — unconditional + platform-conditional select()
        EmitDepListWithSelect(sb, "public_deps", module.PublicDeps, module.ConditionalBlocks, b => b.PublicDeps, suffix: null);
        EmitDepListWithSelect(sb, "private_deps", module.PrivateDeps, module.ConditionalBlocks, b => b.PrivateDeps, suffix: null);
        EmitDepListWithSelect(sb, "public_header_deps", module.PublicHeaderDeps, module.ConditionalBlocks, b => b.PublicHeaderDeps, suffix: ":${name}_headers");

        // Defines
        EmitStringListWithSelect(sb, "defines", module.Defines, module.ConditionalBlocks, b => b.Defines);
        EmitStringListWithSelect(sb, "local_defines", module.LocalDefines, module.ConditionalBlocks, b => b.LocalDefines);

        // Include paths
        EmitStringList(sb, "public_includes", module.PublicIncludes);
        EmitStringList(sb, "private_includes", module.PrivateIncludes);
        EmitStringList(sb, "system_includes", module.SystemIncludes);

        // Link options
        EmitStringList(sb, "linkopts", module.Linkopts);
        EmitStringListWithSelect(sb, "frameworks", module.Frameworks, module.ConditionalBlocks, b => b.Frameworks);

        // Compiler flags
        if (module.UseRTTI || module.EnableExceptions)
        {
            var copts = new List<string>();
            if (module.UseRTTI) copts.Add("-frtti");
            if (module.EnableExceptions) copts.Add("-fexceptions");
            EmitStringList(sb, "copts", copts);
        }

        EmitStringParam(sb, "visibility", "[\"//visibility:public\"]", quoted: false);
        sb.AppendLine(")");
    }

    private void EmitDepListWithSelect(
        StringBuilder sb, string paramName,
        List<string> unconditional, List<ConditionalBlock> blocks,
        Func<ConditionalBlock, List<string>> selector, string? suffix)
    {
        // Gather conditional values for this param
        var conditionalByPlatform = new Dictionary<string, List<string>>();
        foreach (var block in blocks)
        {
            var values = selector(block);
            if (values.Count > 0)
            {
                if (!conditionalByPlatform.TryGetValue(block.BazelCondition, out var list))
                {
                    list = [];
                    conditionalByPlatform[block.BazelCondition] = list;
                }
                list.AddRange(values);
            }
        }

        if (unconditional.Count == 0 && conditionalByPlatform.Count == 0)
            return;

        // Resolve module names to labels
        var resolvedUnconditional = ResolveDeps(unconditional, suffix);
        var resolvedConditional = conditionalByPlatform.ToDictionary(
            kv => kv.Key,
            kv => ResolveDeps(kv.Value, suffix));

        if (resolvedConditional.Count == 0)
        {
            // No conditionals — emit plain list
            EmitRawList(sb, paramName, resolvedUnconditional);
            return;
        }

        // Has conditionals — emit unconditional + select()
        if (resolvedUnconditional.Count > 0)
        {
            EmitRawList(sb, paramName, resolvedUnconditional, trailingPlus: true);
            sb.AppendLine("    select({");
        }
        else
        {
            sb.AppendLine($"    {paramName} = select({{");
        }

        foreach (var (condition, deps) in resolvedConditional.OrderBy(kv => kv.Key))
        {
            if (deps.Count == 1)
            {
                sb.AppendLine($"        \"{condition}\": [\"{deps[0]}\"],");
            }
            else
            {
                sb.AppendLine($"        \"{condition}\": [");
                foreach (var dep in deps.OrderBy(d => d))
                    sb.AppendLine($"            \"{dep}\",");
                sb.AppendLine("        ],");
            }
        }
        sb.AppendLine("        \"//conditions:default\": [],");
        sb.AppendLine("    }),");
    }

    private void EmitStringListWithSelect(
        StringBuilder sb, string paramName,
        List<string> unconditional, List<ConditionalBlock> blocks,
        Func<ConditionalBlock, List<string>> selector)
    {
        var conditionalByPlatform = new Dictionary<string, List<string>>();
        foreach (var block in blocks)
        {
            var values = selector(block);
            if (values.Count > 0)
            {
                if (!conditionalByPlatform.TryGetValue(block.BazelCondition, out var list))
                {
                    list = [];
                    conditionalByPlatform[block.BazelCondition] = list;
                }
                list.AddRange(values);
            }
        }

        if (unconditional.Count == 0 && conditionalByPlatform.Count == 0)
            return;

        if (conditionalByPlatform.Count == 0)
        {
            EmitStringList(sb, paramName, unconditional);
            return;
        }

        // Has conditionals — emit select()
        var sorted = unconditional.OrderBy(v => v).ToList();

        if (sorted.Count > 0)
        {
            EmitRawList(sb, paramName, sorted.Select(v => $"\"{v}\"").ToList(), rawValues: true, trailingPlus: true);
            sb.AppendLine("    select({");
        }
        else
        {
            sb.AppendLine($"    {paramName} = select({{");
        }

        foreach (var (condition, values) in conditionalByPlatform.OrderBy(kv => kv.Key))
        {
            var sortedVals = values.OrderBy(v => v).ToList();
            if (sortedVals.Count == 1)
            {
                sb.AppendLine($"        \"{condition}\": [\"{sortedVals[0]}\"],");
            }
            else
            {
                sb.AppendLine($"        \"{condition}\": [");
                foreach (var v in sortedVals)
                    sb.AppendLine($"            \"{v}\",");
                sb.AppendLine("        ],");
            }
        }
        sb.AppendLine("        \"//conditions:default\": [],");
        sb.AppendLine("    }),");
    }

    private List<string> ResolveDeps(List<string> deps, string? suffix)
    {
        var resolved = new List<string>();
        foreach (var dep in deps)
        {
            var path = _resolver.Resolve(dep);
            if (path != null)
            {
                if (suffix != null)
                    resolved.Add(path + suffix.Replace("${name}", dep));
                else
                    resolved.Add(path);
            }
            // Skip unresolved deps — they'd be invalid Bazel labels
        }
        resolved.Sort();
        return resolved;
    }

    private void EmitThirdPartyModule(StringBuilder sb, ModuleInfo module)
    {
        sb.AppendLine("cc_library(");
        EmitStringParam(sb, "name", module.Name);

        // ThirdParty modules: emit hdrs glob and includes
        EmitStringParam(sb, "hdrs", "glob([\"**/*.h\"])", quoted: false);
        EmitStringList(sb, "includes", ["."]);

        // Dependencies
        EmitDepList(sb, "deps", module.PublicDeps, suffix: null);

        // Defines
        EmitStringList(sb, "defines", module.Defines);

        // Link options
        EmitStringList(sb, "linkopts", module.Linkopts);

        EmitStringParam(sb, "visibility", "[\"//visibility:public\"]", quoted: false);
        sb.AppendLine(")");
    }

    private void EmitDepList(StringBuilder sb, string paramName, List<string> deps, string? suffix)
    {
        if (deps.Count == 0) return;

        var resolved = new List<string>();
        foreach (var dep in deps)
        {
            var path = _resolver.Resolve(dep);
            if (path != null)
            {
                if (suffix != null)
                {
                    var actualSuffix = suffix.Replace("${name}", dep);
                    resolved.Add(path + actualSuffix);
                }
                else
                {
                    resolved.Add(path);
                }
            }
            else
            {
                resolved.Add($"# UNRESOLVED: {dep}");
            }
        }

        resolved.Sort();
        EmitRawList(sb, paramName, resolved);
    }

    private static void EmitStringList(StringBuilder sb, string paramName, List<string> values)
    {
        if (values.Count == 0) return;

        var sorted = values.OrderBy(v => v).ToList();
        EmitRawList(sb, paramName, sorted.Select(v => $"\"{v}\"").ToList(), rawValues: true);
    }

    private static void EmitRawList(StringBuilder sb, string paramName, List<string> values, bool rawValues = false, bool trailingPlus = false)
    {
        if (values.Count == 0) return;

        var suffix = trailingPlus ? " +" : ",";

        if (values.Count == 1)
        {
            var val = rawValues ? values[0] : $"\"{values[0]}\"";
            sb.AppendLine($"    {paramName} = [{val}]{suffix}");
        }
        else
        {
            sb.AppendLine($"    {paramName} = [");
            foreach (var value in values)
            {
                var val = rawValues ? value : $"\"{value}\"";
                sb.AppendLine($"        {val},");
            }
            sb.AppendLine($"    ]{suffix}");
        }
    }

    private static void EmitStringParam(StringBuilder sb, string paramName, string value, bool quoted = true)
    {
        if (quoted)
            sb.AppendLine($"    {paramName} = \"{value}\",");
        else
            sb.AppendLine($"    {paramName} = {value},");
    }

    private static string GetRelativeBuildCsPath(string filePath)
    {
        var idx = filePath.IndexOf("Engine/Source/", StringComparison.Ordinal);
        return idx >= 0 ? filePath[idx..] : filePath;
    }
}
