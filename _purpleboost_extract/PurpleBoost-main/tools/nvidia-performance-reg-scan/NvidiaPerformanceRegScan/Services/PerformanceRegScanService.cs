using System.Text;
using Microsoft.Win32;
using NvidiaPerformanceRegScan.Models;

namespace NvidiaPerformanceRegScan.Services;

public sealed class PerformanceRegScanService
{
    private static readonly string[] Keywords =
    {
        "performance", "quality", "preview", "image", "preference", "prefer",
        "global", "nvcpl", "tweak", "3d", "accent", "emphas", "settings", "setting"
    };

    private const int MaxCandidates = 500;
    private const int MaxKeysVisited = 120_000;

    private readonly List<RegCandidate> _candidates = new();
    private readonly HashSet<string> _seen = new(StringComparer.OrdinalIgnoreCase);
    private int _keysVisited;

    public ScanResult Run(string purpleBoostRoot)
    {
        var notes = new List<string>();
        try
        {
            ScanHive(RegistryHive.CurrentUser, RegistryView.Default, @"Software\NVIDIA Corporation", "HKCU", maxDepth: 24, notes);
            ScanHive(RegistryHive.LocalMachine, RegistryView.Registry64, @"SOFTWARE\NVIDIA Corporation", "HKLM", maxDepth: 24, notes);
            ScanHive(RegistryHive.LocalMachine, RegistryView.Registry64, @"SYSTEM\CurrentControlSet\Services\nvlddmkm", "HKLM", maxDepth: 8, notes);
            ScanHive(RegistryHive.LocalMachine, RegistryView.Registry64, @"SYSTEM\CurrentControlSet\Control\Video", "HKLM", maxDepth: 14, notes);
        }
        catch (Exception ex)
        {
            notes.Add("scan_exception=" + ex.Message);
        }

        _candidates.Sort((a, b) => CandidatePriority(b).CompareTo(CandidatePriority(a)));

        var logPath = Path.Combine(purpleBoostRoot, "logs", "nvidia-performance-reg-candidates.txt");
        WriteCandidatesFile(logPath);

        var count = _candidates.Count;
        return new ScanResult
        {
            Success = true,
            CandidateCount = count,
            Candidates = _candidates.ToList(),
            CandidatesLogPath = logPath,
            Message = count > 0
                ? "Mode performance : clé candidate trouvée"
                : "Mode performance : aucune clé candidate trouvée",
            ScanNotes = notes
        };
    }

    private void ScanHive(RegistryHive hive, RegistryView view, string subPath, string hiveLabel, int maxDepth, List<string> notes)
    {
        try
        {
            using var baseKey = RegistryKey.OpenBaseKey(hive, view);
            using var root = baseKey.OpenSubKey(subPath, writable: false);
            if (root == null)
            {
                notes.Add(hiveLabel + ":" + subPath + "=missing");
                return;
            }

            WalkKey(root, subPath, hiveLabel, maxDepth, 0, notes);
            notes.Add(hiveLabel + ":" + subPath + "=ok keys=" + _keysVisited);
        }
        catch (UnauthorizedAccessException)
        {
            notes.Add(hiveLabel + ":" + subPath + "=access_denied");
        }
        catch (Exception ex)
        {
            notes.Add(hiveLabel + ":" + subPath + "=error " + ex.Message);
        }
    }

    private void WalkKey(RegistryKey key, string fullPath, string hiveLabel, int maxDepth, int depth, List<string> notes)
    {
        if (_candidates.Count >= MaxCandidates || _keysVisited >= MaxKeysVisited)
            return;

        _keysVisited++;

        try
        {
            CollectMatchingValues(key, fullPath, hiveLabel);

            if (depth >= maxDepth) return;

            foreach (var subName in key.GetSubKeyNames())
            {
                if (_candidates.Count >= MaxCandidates || _keysVisited >= MaxKeysVisited)
                {
                    notes.Add("scan_truncated_at=" + fullPath);
                    return;
                }

                var childPath = fullPath + "\\" + subName;
                if (!PathMightContainRelevantData(childPath) && depth > 2 && !SubKeyNameMightMatch(subName))
                    continue;

                try
                {
                    using var child = key.OpenSubKey(subName, writable: false);
                    if (child != null)
                        WalkKey(child, childPath, hiveLabel, maxDepth, depth + 1, notes);
                }
                catch
                {
                    /* skip inaccessible subkey */
                }
            }
        }
        catch
        {
            /* skip key */
        }
    }

    private static bool PathMightContainRelevantData(string path)
    {
        var p = path.ToLowerInvariant();
        foreach (var kw in Keywords)
        {
            if (p.Contains(kw, StringComparison.Ordinal))
                return true;
        }
        return p.Contains("nvidia", StringComparison.Ordinal)
               || p.Contains("nvcpl", StringComparison.Ordinal)
               || p.Contains("global", StringComparison.Ordinal)
               || p.Contains("drs", StringComparison.Ordinal)
               || p.Contains("opengl", StringComparison.Ordinal)
               || p.Contains("direct3d", StringComparison.Ordinal)
               || p.Contains("image", StringComparison.Ordinal);
    }

    private static bool SubKeyNameMightMatch(string name)
    {
        var n = name.ToLowerInvariant();
        foreach (var kw in Keywords)
        {
            if (n.Contains(kw, StringComparison.Ordinal))
                return true;
        }
        return n.Contains("nv", StringComparison.Ordinal) && n.Length <= 12;
    }

    private void CollectMatchingValues(RegistryKey key, string fullPath, string hiveLabel)
    {
        var pathLc = fullPath.ToLowerInvariant();
        var pathHit = MatchKeywords(pathLc, out var pathReason);

        foreach (var valueName in key.GetValueNames())
        {
            if (_candidates.Count >= MaxCandidates) return;
            if (string.IsNullOrEmpty(valueName)) continue;

            var nameLc = valueName.ToLowerInvariant();
            var nameHit = MatchKeywords(nameLc, out var nameReason);
            if (!pathHit && !nameHit) continue;

            object? raw;
            try { raw = key.GetValue(valueName); }
            catch { continue; }

            var preview = FormatValuePreview(raw);
            if (!pathHit && !nameHit && !ValuePreviewMightMatch(preview)) continue;

            var reason = pathHit && nameHit
                ? pathReason + "+" + nameReason
                : pathHit ? pathReason : nameReason;

            if (IsLikelyNoise(fullPath, valueName, preview)) continue;

            AddCandidate(hiveLabel, fullPath, valueName, raw, preview, reason);
        }
    }

    private static bool ValuePreviewMightMatch(string preview)
    {
        var p = preview.ToLowerInvariant();
        return p is "0" or "1" or "2" or "3" or "0x0" or "0x1" or "0x2" or "0x3";
    }

    private static bool IsLikelyNoise(string path, string valueName, string preview)
    {
        if (valueName.Equals("DriverDesc", StringComparison.OrdinalIgnoreCase)) return true;
        if (valueName.Equals("HardwareInformation", StringComparison.OrdinalIgnoreCase)) return true;
        if (preview.Length > 256) return true;
        if (path.Contains("\\Properties\\", StringComparison.OrdinalIgnoreCase)
            && !path.Contains("performance", StringComparison.OrdinalIgnoreCase)
            && !path.Contains("quality", StringComparison.OrdinalIgnoreCase)
            && !path.Contains("image", StringComparison.OrdinalIgnoreCase)
            && !path.Contains("nvcpl", StringComparison.OrdinalIgnoreCase))
            return true;
        return false;
    }

    private static int CandidatePriority(RegCandidate c)
    {
        var blob = (c.Path + "\\" + c.ValueName).ToLowerInvariant();
        if (c.ValueName.Equals("ImageSettings", StringComparison.OrdinalIgnoreCase)) return 100;
        if (blob.Contains("performance", StringComparison.Ordinal)) return 80;
        if (blob.Contains("preference", StringComparison.Ordinal) || blob.Contains("prefer", StringComparison.Ordinal)) return 70;
        if (blob.Contains("preview", StringComparison.Ordinal)) return 65;
        if (blob.Contains("quality", StringComparison.Ordinal)) return 60;
        if (blob.Contains("nvtweak", StringComparison.Ordinal) && blob.Contains("image", StringComparison.Ordinal)) return 55;
        if (blob.Contains("nvcpl", StringComparison.Ordinal)) return 40;
        if (blob.Contains("global", StringComparison.Ordinal)) return 10;
        return 0;
    }

    private static bool MatchKeywords(string text, out string reason)
    {
        foreach (var kw in Keywords)
        {
            if (text.Contains(kw, StringComparison.Ordinal))
            {
                reason = "keyword:" + kw;
                return true;
            }
        }
        reason = "";
        return false;
    }

    private void AddCandidate(string hive, string path, string valueName, object? raw, string preview, string reason)
    {
        var key = hive + "|" + path + "|" + valueName + "|" + preview;
        if (!_seen.Add(key)) return;

        _candidates.Add(new RegCandidate
        {
            Hive = hive,
            Path = path,
            ValueName = valueName,
            ValueKind = raw?.GetType().Name ?? "null",
            ValuePreview = preview,
            MatchReason = reason
        });
    }

    private static string FormatValuePreview(object? raw)
    {
        if (raw == null) return "(null)";
        return raw switch
        {
            byte[] bytes => BitConverter.ToString(bytes.Take(32).ToArray()).Replace("-", " ")
                              + (bytes.Length > 32 ? "…(" + bytes.Length + "b)" : ""),
            string[] arr => string.Join("; ", arr.Take(4)),
            string s => s.Length > 120 ? s[..120] + "…" : s,
            int i => i.ToString(),
            long l => l.ToString(),
            uint u => u.ToString(),
            _ => raw.ToString() ?? ""
        };
    }

    private void WriteCandidatesFile(string logPath)
    {
        var dir = Path.GetDirectoryName(logPath);
        if (!string.IsNullOrEmpty(dir))
            Directory.CreateDirectory(dir);

        var sb = new StringBuilder();
        sb.AppendLine("=== NVIDIA Performance Registry Candidates ===");
        sb.AppendLine("Date: " + DateTime.Now.ToString("O"));
        sb.AppendLine("Count: " + _candidates.Count);
        sb.AppendLine("KeysVisited: " + _keysVisited);
        sb.AppendLine();
        if (_candidates.Count == 0)
        {
            sb.AppendLine("(aucune clé candidate)");
        }
        else
        {
            var i = 0;
            foreach (var c in _candidates)
            {
                i++;
                sb.AppendLine("[" + i + "] " + c.Hive + "\\" + c.Path.Replace('/', '\\'));
                sb.AppendLine("  ValueName: " + c.ValueName);
                sb.AppendLine("  Kind: " + c.ValueKind);
                sb.AppendLine("  Preview: " + c.ValuePreview);
                sb.AppendLine("  Match: " + c.MatchReason);
                sb.AppendLine();
            }
        }

        File.WriteAllText(logPath, sb.ToString(), Encoding.UTF8);
    }
}
