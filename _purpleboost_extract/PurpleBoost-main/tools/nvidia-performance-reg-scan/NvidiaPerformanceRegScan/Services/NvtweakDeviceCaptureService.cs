using System.Text;
using System.Text.Json;
using Microsoft.Win32;
using NvidiaPerformanceRegScan.Models;

namespace NvidiaPerformanceRegScan.Services;

public sealed class NvtweakDeviceCaptureService
{
    private static readonly JsonSerializerOptions SnapshotJsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = true
    };

    public const string DeviceKey = "2712060590-0";
    private const string DevicesRelativePath = @"Software\NVIDIA Corporation\Global\NVTweak\Devices";
    private static readonly string DeviceRelativePath = DevicesRelativePath + "\\" + DeviceKey;

    public NvtweakCaptureResult Capture(string purpleBoostRoot, string phase)
    {
        var logsDir = Path.Combine(purpleBoostRoot, "logs");
        Directory.CreateDirectory(logsDir);

        var phaseNorm = phase.Equals("after", StringComparison.OrdinalIgnoreCase) ? "after" : "before";
        var snapshotPath = Path.Combine(logsDir, "nvidia-performance-nvtweak-" + phaseNorm + ".json");
        var registryPath = "HKCU\\" + DeviceRelativePath;

        try
        {
            using var hkcu = RegistryKey.OpenBaseKey(RegistryHive.CurrentUser, RegistryView.Default);
            using var device = hkcu.OpenSubKey(DeviceRelativePath, writable: false);
            if (device == null)
            {
                return Fail(phaseNorm, "Clé NVTweak introuvable : " + registryPath);
            }

            var values = ReadAllValues(device);
            var doc = new
            {
                capturedAt = DateTime.Now.ToString("O"),
                phase = phaseNorm,
                registryPath,
                deviceKey = DeviceKey,
                values = values.Select(v => new { v.Name, v.Kind, v.Preview }).ToList()
            };

            File.WriteAllText(snapshotPath, JsonSerializer.Serialize(doc, SnapshotJsonOptions), Encoding.UTF8);

            string? diffPath = null;
            int? changedCount = null;
            var message = "NVTweak " + phaseNorm.ToUpperInvariant() + " capturé (" + values.Count + " valeur(s))";

            if (phaseNorm == "after")
            {
                var beforePath = Path.Combine(logsDir, "nvidia-performance-nvtweak-before.json");
                if (File.Exists(beforePath))
                {
                    diffPath = Path.Combine(logsDir, "nvidia-performance-nvtweak-diff.txt");
                    changedCount = WriteDiff(beforePath, snapshotPath, diffPath, registryPath);
                    message = "NVTweak APRÈS capturé — diff : " + changedCount + " changement(s). Voir logs\\nvidia-performance-nvtweak-diff.txt";
                }
                else
                {
                    message = "NVTweak APRÈS capturé — capturez AVANT pour générer le diff";
                }
            }
            else
            {
                message = "NVTweak AVANT capturé — réglez Performance dans le panneau puis « Capturer APRÈS »";
            }

            return new NvtweakCaptureResult
            {
                Success = true,
                Phase = phaseNorm,
                UiStatus = phaseNorm == "after" && diffPath != null ? "diff_ready" : "captured",
                Message = message,
                RegistryPath = registryPath,
                DeviceKey = DeviceKey,
                ValueCount = values.Count,
                SnapshotPath = snapshotPath,
                DiffPath = diffPath,
                ChangedCount = changedCount,
                Values = values
            };
        }
        catch (Exception ex)
        {
            return Fail(phaseNorm, "Capture impossible : " + ex.Message);
        }
    }

    private static List<RegistryValueSnapshot> ReadAllValues(RegistryKey device)
    {
        var list = new List<RegistryValueSnapshot>();
        foreach (var name in device.GetValueNames())
        {
            if (string.IsNullOrEmpty(name)) continue;
            object? raw;
            try { raw = device.GetValue(name); }
            catch { continue; }

            var kind = raw?.GetType().Name ?? "null";
            list.Add(new RegistryValueSnapshot
            {
                Name = name,
                Kind = kind,
                Preview = FormatPreview(raw)
            });
        }

        list.Sort((a, b) => string.Compare(a.Name, b.Name, StringComparison.OrdinalIgnoreCase));
        return list;
    }

    private static string FormatPreview(object? raw)
    {
        if (raw == null) return "(null)";
        return raw switch
        {
            byte[] bytes => BitConverter.ToString(bytes).Replace("-", " "),
            string[] arr => string.Join("; ", arr),
            string s => s,
            _ => raw.ToString() ?? ""
        };
    }

    private static int WriteDiff(string beforePath, string afterPath, string diffPath, string registryPath)
    {
        var before = LoadSnapshot(beforePath);
        var after = LoadSnapshot(afterPath);
        var beforeMap = before.ToDictionary(v => v.Name, v => v, StringComparer.OrdinalIgnoreCase);
        var afterMap = after.ToDictionary(v => v.Name, v => v, StringComparer.OrdinalIgnoreCase);

        var allNames = beforeMap.Keys.Union(afterMap.Keys, StringComparer.OrdinalIgnoreCase).OrderBy(n => n).ToList();
        var changed = new List<string>();

        var sb = new StringBuilder();
        sb.AppendLine("=== NVIDIA Performance NVTweak Diff ===");
        sb.AppendLine("Date: " + DateTime.Now.ToString("O"));
        sb.AppendLine("Clé unique: " + registryPath);
        sb.AppendLine("AVANT: " + beforePath);
        sb.AppendLine("APRÈS: " + afterPath);
        sb.AppendLine();

        foreach (var name in allNames)
        {
            beforeMap.TryGetValue(name, out var b);
            afterMap.TryGetValue(name, out var a);
            var bPrev = b?.Preview ?? "(absent)";
            var aPrev = a?.Preview ?? "(absent)";
            if (string.Equals(bPrev, aPrev, StringComparison.Ordinal)) continue;

            changed.Add(name);
            sb.AppendLine("[CHANGED] " + name);
            sb.AppendLine("  AVANT : " + bPrev + (b != null ? " (" + b.Kind + ")" : ""));
            sb.AppendLine("  APRÈS : " + aPrev + (a != null ? " (" + a.Kind + ")" : ""));
            sb.AppendLine();
        }

        if (changed.Count == 0)
        {
            sb.AppendLine("(aucune valeur modifiée dans cette clé — le panneau Performance utilise peut-être une autre clé/valeur)");
        }
        else
        {
            sb.AppendLine("Résumé : " + changed.Count + " valeur(s) modifiée(s) : " + string.Join(", ", changed));
        }

        File.WriteAllText(diffPath, sb.ToString(), Encoding.UTF8);
        return changed.Count;
    }

    private static List<RegistryValueSnapshot> LoadSnapshot(string path)
    {
        var json = File.ReadAllText(path);
        using var doc = JsonDocument.Parse(json);
        var list = new List<RegistryValueSnapshot>();
        if (!doc.RootElement.TryGetProperty("values", out var arr)) return list;
        foreach (var el in arr.EnumerateArray())
        {
            list.Add(new RegistryValueSnapshot
            {
                Name = GetStringProp(el, "name", "Name"),
                Kind = GetStringProp(el, "kind", "Kind"),
                Preview = GetStringProp(el, "preview", "Preview")
            });
        }
        return list;
    }

    private static string GetStringProp(JsonElement el, string camel, string pascal)
    {
        if (el.TryGetProperty(camel, out var c)) return c.GetString() ?? "";
        if (el.TryGetProperty(pascal, out var p)) return p.GetString() ?? "";
        return "";
    }

    private static NvtweakCaptureResult Fail(string phase, string message) =>
        new()
        {
            Success = false,
            Phase = phase,
            UiStatus = "error",
            Message = message,
            DeviceKey = DeviceKey,
            RegistryPath = "HKCU\\" + DeviceRelativePath
        };
}
