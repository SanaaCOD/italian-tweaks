namespace UnrealLauncher;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        _ = PcTuneWindowSpec.BuildTag;
        ApplicationConfiguration.Initialize();
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        return PcTuneLaunch.Run(args);
    }
}

internal static class PcTuneLaunch
{
    private const string WindowTitle = "Unreal Gaming Optimizer";

    public static int Run(string[] args)
    {
        var (appRoot, htaPath) = AppPaths.ResolveUnrealHta(args);
        if (htaPath is null)
        {
            _ = MessageBox.Show(
                "Fichier introuvable : Unreal.hta\n\n" +
                "Ne copiez pas l'EXE seul sur le Bureau.\n" +
                "Utilisez le raccourci créé par CreateDesktopShortcut.ps1\n" +
                "ou lancez l'EXE depuis le dossier PurpleBoost / dist.",
                WindowTitle,
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
            return 2;
        }

        var bounds = PcTuneWindowSpec.ComputeBounds(Win32Window.GetPrimaryWorkArea());

        UnrealProcessCleanup.CleanupStaleOwnProcesses(htaPath);
        LaunchSessionStore.CleanupStaleFromFile(appRoot, htaPath);

        if (UnrealProcessCleanup.TryActivateVisibleInstance())
        {
            StartupTrace.LogSession(appRoot, htaPath, bounds, "existing_focus");
            return 0;
        }

        StartupTrace.LogSession(appRoot, htaPath, bounds, "new_launch");

        using var splash = new NativeSplashForm();
        using var session = new HtaHostSession(appRoot, htaPath, splash, bounds);

        splash.Shown += (_, _) => session.Start();
        Application.Run(splash);
        InstanceLock.Clear();
        return 0;
    }
}

internal static class AppPaths
{
    public static string? ParseBaseDirArg(string[] args)
    {
        if (args is null) return null;
        for (var i = 0; i < args.Length - 1; i++)
        {
            if (string.Equals(args[i], "--base-dir", StringComparison.OrdinalIgnoreCase))
                return args[i + 1].Trim().Trim('"');
        }
        return null;
    }

    static bool TryResolveFromDir(string dir, out string appRoot, out string? htaPath)
    {
        appRoot = dir;
        htaPath = null;

        var direct = Path.Combine(dir, "Unreal.hta");
        if (File.Exists(direct))
        {
            htaPath = Path.GetFullPath(direct);
            return true;
        }

        var electronApp = Path.Combine(dir, "resources", "app", "Unreal.hta");
        if (File.Exists(electronApp))
        {
            appRoot = Path.GetFullPath(Path.Combine(dir, "resources", "app"));
            htaPath = Path.GetFullPath(electronApp);
            return true;
        }

        return false;
    }

    public static (string appRoot, string? htaPath) ResolveUnrealHta(string[]? args)
    {
        args ??= Array.Empty<string>();

        var baseFromArg = ParseBaseDirArg(args);
        if (!string.IsNullOrWhiteSpace(baseFromArg) && Directory.Exists(baseFromArg))
        {
            if (TryResolveFromDir(baseFromArg, out var rootArg, out var htaArg))
                return (rootArg, htaArg);
        }

        var start = AppContext.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        var dir = start;

        for (var i = 0; i < 14; i++)
        {
            if (TryResolveFromDir(dir, out var root, out var hta))
                return (root, hta);

            var parent = Directory.GetParent(dir);
            if (parent is null)
                break;
            dir = parent.FullName;
        }

        var sibling = Path.GetFullPath(Path.Combine(start, "..", "Unreal.hta"));
        if (File.Exists(sibling))
            return (Path.GetDirectoryName(sibling)!, sibling);

        var siblingApp = Path.GetFullPath(Path.Combine(start, "..", "resources", "app", "Unreal.hta"));
        if (File.Exists(siblingApp))
            return (Path.GetDirectoryName(siblingApp)!, siblingApp);

        return (start, null);
    }
}
