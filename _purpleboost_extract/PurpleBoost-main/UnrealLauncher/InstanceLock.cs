using System.Diagnostics;
using System.Text.Json;

namespace UnrealLauncher;

internal sealed class InstanceLockRecord
{
    public int MshtaPid { get; set; }
    public long UpdatedUtc { get; set; }
}

internal static class InstanceLock
{
    public static string LockPath =>
        Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
            "PurpleBoost",
            "instance.lock");

    public static void Clear()
    {
        try
        {
            if (File.Exists(LockPath)) File.Delete(LockPath);
        }
        catch { /* ignore */ }
    }

    public static void WriteMshta(int mshtaPid)
    {
        try
        {
            var dir = Path.GetDirectoryName(LockPath);
            if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);

            var record = new InstanceLockRecord
            {
                MshtaPid = mshtaPid,
                UpdatedUtc = DateTimeOffset.UtcNow.ToUnixTimeSeconds(),
            };
            File.WriteAllText(LockPath, JsonSerializer.Serialize(record));
        }
        catch { /* ignore */ }
    }

    public static int? ReadMshtaPid()
    {
        try
        {
            if (!File.Exists(LockPath)) return null;
            var record = JsonSerializer.Deserialize<InstanceLockRecord>(File.ReadAllText(LockPath));
            return record?.MshtaPid > 0 ? record.MshtaPid : null;
        }
        catch
        {
            return null;
        }
    }

    public static bool IsRecordedPidAlive()
    {
        var pid = ReadMshtaPid();
        if (!pid.HasValue) return false;

        try
        {
            using var p = Process.GetProcessById(pid.Value);
            if (p.HasExited) return false;

            var hwnd = Win32Window.FindHtaWindowForProcess(pid.Value, "Unreal Gaming Optimizer", "Unreal");
            return hwnd != IntPtr.Zero && Win32Window.IsInteractiveWindow(hwnd);
        }
        catch
        {
            return false;
        }
    }
}
