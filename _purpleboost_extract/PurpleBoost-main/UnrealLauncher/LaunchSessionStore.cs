using System.Diagnostics;
using System.Text.Json;

namespace UnrealLauncher;

internal sealed class LaunchSessionRecord
{
    public int LauncherPid { get; set; }
    public int MshtaPid { get; set; }
    public long StartedUtc { get; set; }
}

internal static class LaunchSessionStore
{
    public static string GetSessionPath(string appRoot) =>
        Path.Combine(appRoot, "logs", "launch-session.json");

    public static void Write(string appRoot, int mshtaPid)
    {
        try
        {
            var path = GetSessionPath(appRoot);
            var dir = Path.GetDirectoryName(path);
            if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);

            var record = new LaunchSessionRecord
            {
                LauncherPid = Process.GetCurrentProcess().Id,
                MshtaPid = mshtaPid,
                StartedUtc = DateTimeOffset.UtcNow.ToUnixTimeSeconds(),
            };
            File.WriteAllText(path, JsonSerializer.Serialize(record));
        }
        catch { /* ignore */ }
    }

    public static void WriteMshtaOnly(string appRoot, int mshtaPid)
    {
        try
        {
            var path = GetSessionPath(appRoot);
            var dir = Path.GetDirectoryName(path);
            if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);

            var record = new LaunchSessionRecord
            {
                LauncherPid = 0,
                MshtaPid = mshtaPid,
                StartedUtc = DateTimeOffset.UtcNow.ToUnixTimeSeconds(),
            };
            File.WriteAllText(path, JsonSerializer.Serialize(record));
        }
        catch { /* ignore */ }
    }

    public static void Clear(string appRoot)
    {
        try
        {
            var path = GetSessionPath(appRoot);
            if (File.Exists(path)) File.Delete(path);
        }
        catch { /* ignore */ }
    }

    public static void ClearFromHtaPath(string htaPath)
    {
        try
        {
            var appRoot = Path.GetDirectoryName(htaPath);
            if (!string.IsNullOrEmpty(appRoot)) Clear(appRoot);
        }
        catch { /* ignore */ }
    }

    public static void CleanupStaleFromFile(string appRoot, string htaPath)
    {
        var hadLive = false;
        try
        {
            var path = GetSessionPath(appRoot);
            if (!File.Exists(path)) return;

            var json = File.ReadAllText(path);
            var record = JsonSerializer.Deserialize<LaunchSessionRecord>(json);
            if (record is null) return;

            if (record.MshtaPid > 0)
            {
                if (IsLiveMshta(record.MshtaPid))
                    hadLive = true;
                else
                    TryCleanupPid(record.MshtaPid);
            }

            if (!hadLive && record.LauncherPid > 0 && record.LauncherPid != Process.GetCurrentProcess().Id)
                TryCleanupLauncherPid(record.LauncherPid);

            if (!hadLive)
                Clear(appRoot);
        }
        catch { /* ignore */ }
    }

    private static bool IsLiveMshta(int pid)
    {
        try
        {
            using var p = Process.GetProcessById(pid);
            if (p.HasExited) return false;
            var hwnd = Win32Window.FindHtaWindowForProcess(pid, "Unreal Gaming Optimizer", "Unreal");
            return hwnd != IntPtr.Zero && Win32Window.IsInteractiveWindow(hwnd);
        }
        catch
        {
            return false;
        }
    }

    private static void TryCleanupPid(int pid)
    {
        try
        {
            using var p = Process.GetProcessById(pid);
            if (p.HasExited) return;

            var hwnd = Win32Window.FindHtaWindowForProcess(pid, "Unreal Gaming Optimizer", "Unreal");
            if (hwnd != IntPtr.Zero && Win32Window.IsInteractiveWindow(hwnd))
                return;

            p.Kill(entireProcessTree: true);
        }
        catch (ArgumentException)
        {
            /* already exited */
        }
        catch { /* ignore */ }
    }

    private static void TryCleanupLauncherPid(int pid)
    {
        try
        {
            using var p = Process.GetProcessById(pid);
            if (p.HasExited) return;
            p.Kill(entireProcessTree: false);
        }
        catch { /* ignore */ }
    }
}
