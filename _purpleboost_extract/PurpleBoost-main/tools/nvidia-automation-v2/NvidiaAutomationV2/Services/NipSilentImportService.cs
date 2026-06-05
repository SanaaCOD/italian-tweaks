using System.Diagnostics;
using System.Runtime.InteropServices;

namespace NvidiaAutomationV2.Services;

/// <summary>
/// STABLE — stable-nvidia-nip-silent-import (NE PAS RÉÉCRIRE)
/// Import .nip via nvidiaProfileInspector.exe -silentImport uniquement — jamais d'UI NPI.
/// État validé : profil appliqué, fenêtre NPI masquée, paramètres 3D OK.
/// </summary>
public static class NipSilentImportService
{
    private const int SwHide = 0;

    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    public static ProcessRunResult Import(string inspectorExe, string nipPath, int timeoutMs = 120_000)
    {
        var nipFull = Path.GetFullPath(nipPath);
        var inspectorFull = Path.GetFullPath(inspectorExe);
        var arguments = $"-silentImport \"{nipFull}\"";
        var cmdLine = $"\"{inspectorFull}\" {arguments}";
        FileLogger.Info("NPI_SILENT_CMD=" + cmdLine);

        var psi = new ProcessStartInfo
        {
            FileName = inspectorFull,
            Arguments = arguments,
            WorkingDirectory = Path.GetDirectoryName(inspectorFull) ?? "",
            UseShellExecute = false,
            CreateNoWindow = true,
            WindowStyle = ProcessWindowStyle.Hidden,
            RedirectStandardOutput = true,
            RedirectStandardError = true
        };

        Process? process;
        try
        {
            process = Process.Start(psi);
        }
        catch (System.ComponentModel.Win32Exception ex) when (ex.NativeErrorCode == 740)
        {
            FileLogger.Warn("NPI_SILENT: élévation requise, relance masquée");
            return ImportViaHiddenElevatedHost(inspectorFull, nipFull, timeoutMs);
        }

        if (process == null)
        {
            FileLogger.Error("NPI_SILENT: Process.Start failed");
            return new ProcessRunResult { ExitCode = 18, StdErr = "Process.Start failed" };
        }

        using (process)
        {

            HideProcessMainWindow(process);

            var stdout = process.StandardOutput.ReadToEnd();
            var stderr = process.StandardError.ReadToEnd();

            if (!process.WaitForExit(timeoutMs))
            {
                try { process.Kill(true); } catch { /* ignore */ }
                FileLogger.Warn("NPI_SILENT: timeout");
                return new ProcessRunResult { ExitCode = 124, StdOut = stdout, StdErr = stderr, TimedOut = true };
            }

            HideProcessMainWindow(process);
            FileLogger.Info($"NPI_SILENT_EXIT={process.ExitCode}");
            if (!string.IsNullOrWhiteSpace(stderr))
                FileLogger.Info("NPI_SILENT_STDERR=" + stderr.Trim());

            return new ProcessRunResult
            {
                ExitCode = process.ExitCode,
                StdOut = stdout,
                StdErr = stderr
            };
        }
    }

    private static ProcessRunResult ImportViaHiddenElevatedHost(string inspectorFull, string nipFull, int timeoutMs)
    {
        var scriptPath = Path.Combine(Path.GetTempPath(), "purpleboost-npi-silent-" + Guid.NewGuid().ToString("N") + ".ps1");
        var script = string.Join(Environment.NewLine, new[]
        {
            "$ErrorActionPreference = 'Stop'",
            "Add-Type @'",
            "using System; using System.Runtime.InteropServices;",
            "public class NpiWinHide { [DllImport(\"user32.dll\")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow); }",
            "'@ -ErrorAction SilentlyContinue",
            "$psi = New-Object System.Diagnostics.ProcessStartInfo",
            "$psi.FileName = '" + inspectorFull.Replace("'", "''") + "'",
            "$psi.Arguments = '-silentImport \"" + nipFull.Replace("\"", "`\"") + "\"'",
            "$psi.WorkingDirectory = '" + (Path.GetDirectoryName(inspectorFull) ?? "").Replace("'", "''") + "'",
            "$psi.UseShellExecute = $false",
            "$psi.CreateNoWindow = $true",
            "$psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden",
            "$p = [System.Diagnostics.Process]::Start($psi)",
            "if (-not $p) { exit 18 }",
            "for ($i = 0; $i -lt 60; $i++) {",
            "  Start-Sleep -Milliseconds 80",
            "  try { $p.Refresh() } catch {}",
            "  if ($p.MainWindowHandle -ne [IntPtr]::Zero) { [void][NpiWinHide]::ShowWindow($p.MainWindowHandle, 0); break }",
            "}",
            "$null = $p.WaitForExit()",
            "exit $p.ExitCode"
        });
        File.WriteAllText(scriptPath, script);

        try
        {
            var hostPsi = new ProcessStartInfo
            {
                FileName = "powershell.exe",
                Arguments = $"-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"{scriptPath}\"",
                UseShellExecute = true,
                Verb = "runas",
                WindowStyle = ProcessWindowStyle.Hidden,
                CreateNoWindow = true
            };
            using var host = Process.Start(hostPsi);
            if (host == null)
                return new ProcessRunResult { ExitCode = 18, StdErr = "elevated host start failed" };
            if (!host.WaitForExit(timeoutMs))
            {
                try { host.Kill(true); } catch { /* ignore */ }
                return new ProcessRunResult { ExitCode = 124, TimedOut = true };
            }
            return new ProcessRunResult { ExitCode = host.ExitCode };
        }
        finally
        {
            try { File.Delete(scriptPath); } catch { /* ignore */ }
        }
    }

    private static void HideProcessMainWindow(Process process)
    {
        for (var i = 0; i < 60; i++)
        {
            try
            {
                process.Refresh();
                if (process.MainWindowHandle != IntPtr.Zero)
                {
                    ShowWindow(process.MainWindowHandle, SwHide);
                    FileLogger.Info("NPI_SILENT: fenêtre principale masquée");
                    return;
                }
            }
            catch { /* ignore */ }

            Thread.Sleep(80);
        }
    }
}
