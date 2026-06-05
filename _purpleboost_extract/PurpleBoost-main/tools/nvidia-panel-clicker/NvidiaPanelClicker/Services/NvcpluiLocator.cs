using Microsoft.Win32;

namespace NvidiaPanelClicker.Services;

internal sealed class NvcpluiLocator
{
    private static readonly string[] FixedCandidates =
    {
        @"C:\Program Files\NVIDIA Corporation\Control Panel Client\nvcplui.exe",
        @"C:\Program Files (x86)\NVIDIA Corporation\Control Panel Client\nvcplui.exe",
        @"C:\Windows\System32\nvcplui.exe"
    };

    private static readonly string[] ScanRoots =
    {
        @"C:\Program Files\NVIDIA Corporation",
        @"C:\Program Files (x86)\NVIDIA Corporation"
    };

    public List<string> TestedPaths { get; } = new();
    public string? FoundPath { get; private set; }

    public bool TryResolve(out string fullPath)
    {
        fullPath = "";
        FoundPath = null;
        TestedPaths.Clear();
        FileLogger.Info("Recherche nvcplui.exe");

        foreach (var candidate in FixedCandidates)
        {
            TestedPaths.Add(candidate);
            FileLogger.Info("Chemin testé : " + candidate);
            if (!File.Exists(candidate)) continue;
            FoundPath = Path.GetFullPath(candidate);
            fullPath = FoundPath;
            FileLogger.Info("Chemin trouvé : " + FoundPath);
            return true;
        }

        var fromRegistry = TryRegistryAppPath();
        if (!string.IsNullOrEmpty(fromRegistry))
        {
            TestedPaths.Add(fromRegistry);
            FileLogger.Info("Chemin testé : " + fromRegistry + " (registre App Paths)");
            if (File.Exists(fromRegistry))
            {
                FoundPath = Path.GetFullPath(fromRegistry);
                fullPath = FoundPath;
                FileLogger.Info("Chemin trouvé : " + FoundPath);
                return true;
            }
        }

        var fromScan = ScanNvidiaFolders();
        if (!string.IsNullOrEmpty(fromScan))
        {
            FoundPath = fromScan;
            fullPath = FoundPath;
            FileLogger.Info("Chemin trouvé : " + FoundPath);
            return true;
        }

        FileLogger.Error("Aucun nvcplui.exe trouvé — chemins testés : " + TestedPaths.Count);
        foreach (var p in TestedPaths)
            FileLogger.Info("  testé : " + p);
        return false;
    }

    private static string? TryRegistryAppPath()
    {
        const string subKey = @"SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\nvcplui.exe";
        try
        {
            using var key = Registry.LocalMachine.OpenSubKey(subKey);
            var value = key?.GetValue(null) as string;
            if (string.IsNullOrWhiteSpace(value)) return null;
            return value.Trim().Trim('"');
        }
        catch (Exception ex)
        {
            FileLogger.Warn("Registre App Paths : " + ex.Message);
            return null;
        }
    }

    private string? ScanNvidiaFolders()
    {
        foreach (var root in ScanRoots)
        {
            TestedPaths.Add("SCAN:" + root);
            FileLogger.Info("Chemin testé : " + root + " (scan récursif)");
            if (!Directory.Exists(root)) continue;

            try
            {
                foreach (var file in Directory.EnumerateFiles(root, "nvcplui.exe", SearchOption.AllDirectories))
                {
                    TestedPaths.Add(file);
                    if (File.Exists(file))
                        return Path.GetFullPath(file);
                }
            }
            catch (Exception ex)
            {
                FileLogger.Warn("Scan " + root + " : " + ex.Message);
            }
        }

        return null;
    }
}
