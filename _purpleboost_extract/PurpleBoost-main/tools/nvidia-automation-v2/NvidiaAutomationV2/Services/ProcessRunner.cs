using System.Diagnostics;

namespace NvidiaAutomationV2.Services;

public sealed class ProcessRunResult
{
    public int ExitCode { get; init; }
    public string StdOut { get; init; } = "";
    public string StdErr { get; init; } = "";
    public bool TimedOut { get; init; }
}

public static class ProcessRunner
{
    public static ProcessRunResult Run(
        string exe,
        string arguments,
        int timeoutMs = 120_000,
        string? workingDirectory = null)
    {
        FileLogger.Info($"RUN: \"{exe}\" {arguments}");
        var psi = new ProcessStartInfo
        {
            FileName = exe,
            Arguments = arguments,
            WorkingDirectory = workingDirectory ?? Path.GetDirectoryName(exe) ?? "",
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true
        };

        using var p = Process.Start(psi);
        if (p == null)
            return new ProcessRunResult { ExitCode = -1, StdErr = "Process.Start failed" };

        var stdout = p.StandardOutput.ReadToEnd();
        var stderr = p.StandardError.ReadToEnd();
        if (!p.WaitForExit(timeoutMs))
        {
            try { p.Kill(true); } catch { /* ignore */ }
            FileLogger.Warn($"TIMEOUT: {exe}");
            return new ProcessRunResult { ExitCode = 124, StdOut = stdout, StdErr = stderr, TimedOut = true };
        }

        FileLogger.Info($"EXIT={p.ExitCode} stdout={Truncate(stdout)} stderr={Truncate(stderr)}");
        return new ProcessRunResult { ExitCode = p.ExitCode, StdOut = stdout, StdErr = stderr };
    }

    private static string Truncate(string s) =>
        s.Length <= 400 ? s : s[..400] + "...";
}
