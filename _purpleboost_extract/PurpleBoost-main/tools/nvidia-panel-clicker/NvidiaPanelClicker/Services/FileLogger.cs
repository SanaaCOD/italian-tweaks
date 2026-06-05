namespace NvidiaPanelClicker.Services;

public static class FileLogger
{
    private static readonly List<string> _paths = new();
    private static readonly object Lock = new();

    public static void Configure(string logPath) => Configure(new[] { logPath });

    public static void Configure(IEnumerable<string> logPaths)
    {
        lock (Lock)
        {
            _paths.Clear();
            foreach (var logPath in logPaths)
            {
                if (string.IsNullOrWhiteSpace(logPath)) continue;
                var dir = Path.GetDirectoryName(logPath);
                if (!string.IsNullOrEmpty(dir))
                    Directory.CreateDirectory(dir);
                _paths.Add(logPath);
            }
        }
    }

    public static string? LogPath => _paths.Count > 0 ? _paths[0] : null;

    public static void Info(string msg) => Write("INFO", msg);
    public static void Warn(string msg) => Write("WARN", msg);
    public static void Error(string msg) => Write("ERROR", msg);

    public static IReadOnlyList<string> ReadTailLines(int maxLines)
    {
        var path = LogPath;
        if (string.IsNullOrEmpty(path) || !File.Exists(path) || maxLines <= 0)
            return Array.Empty<string>();

        try
        {
            var lines = File.ReadAllLines(path);
            if (lines.Length <= maxLines) return lines;
            return lines[^maxLines..];
        }
        catch
        {
            return Array.Empty<string>();
        }
    }

    private static void Write(string level, string msg)
    {
        var line = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + " [" + level + "] " + msg;
        lock (Lock)
        {
            if (_paths.Count == 0) return;
            foreach (var path in _paths.ToArray())
            {
                try { File.AppendAllText(path, line + Environment.NewLine); } catch { }
            }
        }
    }
}
