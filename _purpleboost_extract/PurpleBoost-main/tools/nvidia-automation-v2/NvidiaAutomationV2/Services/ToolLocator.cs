namespace NvidiaAutomationV2.Services;

public sealed class ToolLocator
{
    private readonly string _purpleBoostRoot;

    public ToolLocator(string purpleBoostRoot)
    {
        _purpleBoostRoot = purpleBoostRoot.TrimEnd('\\', '/');
    }

    public string? FindColorControlExe()
    {
        var names = new[] { "ColorControl.exe", "ColorControl_x64.exe" };
        foreach (var name in names)
        {
            var found = Search(name, new[]
            {
                Path.Combine(_purpleBoostRoot, "tools", "ColorControl", name),
                Path.Combine(_purpleBoostRoot, "tools", "colorcontrol", name),
                Path.Combine(_purpleBoostRoot, name)
            });
            if (found != null) return found;
        }
        return SearchAny(names);
    }

    public string? FindGsyncToggleExe()
    {
        var names = new[] { "gsync-toggle.exe", "gsynctoggle.exe", "GSyncToggle.exe" };
        foreach (var name in names)
        {
            var found = Search(name, new[]
            {
                Path.Combine(_purpleBoostRoot, "tools", "GsyncToggle", "gsync-toggle.exe"),
                Path.Combine(_purpleBoostRoot, "tools", "GsyncToggle", name),
                Path.Combine(_purpleBoostRoot, "tools", "gsync-toggle", "gsync-toggle.exe"),
                Path.Combine(_purpleBoostRoot, "tools", "gsync-toggle", name),
                Path.Combine(_purpleBoostRoot, "tools", "GSyncToggle", name),
                Path.Combine(_purpleBoostRoot, name)
            });
            if (found != null) return found;
        }
        return SearchAny(names);
    }

    public string? FindNvidiaProfileInspector()
    {
        var candidates = new[]
        {
            Path.Combine(_purpleBoostRoot, "tools", "NvidiaProfileInspector", "nvidiaProfileInspector.exe"),
            Path.Combine(_purpleBoostRoot, "tools", "nvidiaProfileInspector", "nvidiaProfileInspector.exe"),
            Path.Combine(_purpleBoostRoot, "tools", "nvidiaProfileInspector", "ProfileInspector", "nvidiaProfileInspector.exe"),
            Path.Combine(_purpleBoostRoot, "tools", "NVIDIA", "ProfileInspector", "nvidiaProfileInspector.exe")
        };
        foreach (var c in candidates)
        {
            if (File.Exists(c))
            {
                FileLogger.Info("NPI found: " + c);
                return c;
            }
        }
        return null;
    }

    public string? FindNipProfile()
    {
        var primary = Path.Combine(_purpleBoostRoot, "presets", "UnrealGaming.nip");
        if (File.Exists(primary))
        {
            FileLogger.Info("NIP preset found: " + primary);
            return primary;
        }

        var fallbacks = new[]
        {
            Path.Combine(_purpleBoostRoot, "tools", "profiles", "Unreal_Warzone_Performance.nip"),
            Path.Combine(_purpleBoostRoot, "tools", "nvidiaProfileInspector", "Profiles", "Unreal_Warzone_Performance.nip"),
            Path.Combine(_purpleBoostRoot, "config", "NvidiaPerformanceProfile.nip")
        };
        foreach (var p in fallbacks)
        {
            if (File.Exists(p))
            {
                FileLogger.Warn("UnrealGaming.nip absent, fallback: " + p);
                return p;
            }
        }
        return null;
    }

    public string? FindDisplayHelper()
    {
        var p = Path.Combine(_purpleBoostRoot, "tools", "nvidia-display-helper", "UnrealNvidiaDisplayHelper.exe");
        return File.Exists(p) ? p : null;
    }

    private string? Search(string fileName, IEnumerable<string> directPaths)
    {
        foreach (var p in directPaths)
        {
            if (File.Exists(p))
            {
                FileLogger.Info($"Tool found (direct): {p}");
                return p;
            }
        }
        return null;
    }

    private string? SearchAny(IEnumerable<string> fileNames)
    {
        var dirs = new List<string>
        {
            Environment.GetFolderPath(Environment.SpecialFolder.Desktop),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads"),
            _purpleBoostRoot
        };

        foreach (var dir in dirs)
        {
            if (string.IsNullOrEmpty(dir) || !Directory.Exists(dir)) continue;
            try
            {
                foreach (var name in fileNames)
                {
                    var files = Directory.GetFiles(dir, name, SearchOption.AllDirectories);
                    foreach (var f in files.Take(3))
                    {
                        FileLogger.Info($"Tool found (search): {f}");
                        return f;
                    }
                }
            }
            catch { /* ignore access */ }
        }
        return null;
    }
}
