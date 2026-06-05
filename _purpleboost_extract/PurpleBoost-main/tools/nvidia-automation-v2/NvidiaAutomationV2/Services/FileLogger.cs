using System.Text;

namespace NvidiaAutomationV2.Services;

public static class FileLogger
{
    private static readonly object Gate = new();
    private static string? _logPath;

    public static void Configure(string? path)
    {
        _logPath = path;
        if (string.IsNullOrEmpty(_logPath)) return;
        var dir = Path.GetDirectoryName(_logPath);
        if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
    }

    public static void Info(string msg) => Write("INFO", msg);
    public static void Warn(string msg) => Write("WARN", msg);
    public static void Error(string msg) => Write("ERROR", msg);

    private static void Write(string level, string msg)
    {
        if (string.IsNullOrEmpty(_logPath)) return;
        lock (Gate)
        {
            File.AppendAllText(_logPath, $"{DateTime.Now:yyyy-MM-dd HH:mm:ss} [{level}] {msg}{Environment.NewLine}", Encoding.UTF8);
        }
    }
}
