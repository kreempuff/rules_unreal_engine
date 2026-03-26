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

        // Dependencies — resolve module names to Bazel labels
        EmitDepList(sb, "public_deps", module.PublicDeps, suffix: null);
        EmitDepList(sb, "private_deps", module.PrivateDeps, suffix: null);
        EmitDepList(sb, "public_header_deps", module.PublicHeaderDeps, suffix: ":${name}_headers");

        // Defines
        EmitStringList(sb, "defines", module.Defines);
        EmitStringList(sb, "local_defines", module.LocalDefines);

        // Include paths
        EmitStringList(sb, "public_includes", module.PublicIncludes);
        EmitStringList(sb, "private_includes", module.PrivateIncludes);
        EmitStringList(sb, "system_includes", module.SystemIncludes);

        // Link options
        EmitStringList(sb, "linkopts", module.Linkopts);
        EmitStringList(sb, "frameworks", module.Frameworks);

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

    private static void EmitRawList(StringBuilder sb, string paramName, List<string> values, bool rawValues = false)
    {
        if (values.Count == 0) return;

        if (values.Count == 1)
        {
            var val = rawValues ? values[0] : $"\"{values[0]}\"";
            sb.AppendLine($"    {paramName} = [{val}],");
        }
        else
        {
            sb.AppendLine($"    {paramName} = [");
            foreach (var value in values)
            {
                var val = rawValues ? value : $"\"{value}\"";
                sb.AppendLine($"        {val},");
            }
            sb.AppendLine("    ],");
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
