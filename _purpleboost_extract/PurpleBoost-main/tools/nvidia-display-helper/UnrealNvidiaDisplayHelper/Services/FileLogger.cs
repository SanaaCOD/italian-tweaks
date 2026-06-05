namespace UnrealNvidiaDisplayHelper.Services;

public static class FileLogger
{
    private static readonly object Gate = new();
    private static string? _logPath;

    public static void Configure(string? explicitPath = null)
    {
        if (!string.IsNullOrWhiteSpace(explicitPath))
        {
            _logPath = explicitPath;
            return;
        }

        var baseDir = AppContext.BaseDirectory.TrimEnd('\\', '/');
        var purpleBoost = FindPurpleBoostRoot(baseDir);
        var logsDir = purpleBoost != null
            ? Path.Combine(purpleBoost, "logs")
            : Path.Combine(baseDir, "logs");
        Directory.CreateDirectory(logsDir);
        _logPath = Path.Combine(logsDir, "nvidia-display-helper.log");
    }

    public static void Info(string message) => Write("INFO", message);
    public static void Warn(string message) => Write("WARN", message);
    public static void Error(string message) => Write("ERROR", message);

    private static void Write(string level, string message)
    {
        if (string.IsNullOrEmpty(_logPath)) return;
        lock (Gate)
        {
            File.AppendAllText(_logPath, $"{DateTime.Now:yyyy-MM-dd HH:mm:ss} [{level}] {message}{Environment.NewLine}");
        }
    }

    private static string? FindPurpleBoostRoot(string start)
    {
        var dir = new DirectoryInfo(start);
        for (var i = 0; i < 8 && dir != null; i++)
        {
            if (File.Exists(Path.Combine(dir.FullName, "Unreal.hta")))
                return dir.FullName;
            dir = dir.Parent;
        }
        return null;
    }
}
