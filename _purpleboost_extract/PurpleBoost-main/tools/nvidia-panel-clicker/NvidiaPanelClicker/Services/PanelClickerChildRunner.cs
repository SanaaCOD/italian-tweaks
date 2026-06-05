using System.Diagnostics;
using System.Text.Json;
using System.Text.Json.Serialization;
using NvidiaPanelClicker.Models;

namespace NvidiaPanelClicker.Services;

/// <summary>Exécute une tâche panneau comme le bouton individuel HTA (processus enfant séparé).</summary>
internal static class PanelClickerChildRunner
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
    };

    public static ClickerResult? RunIndividualTask(string purpleBoostRoot, string task, int timeoutMs = 120_000)
    {
        var exe = ResolveExePath();
        if (string.IsNullOrEmpty(exe) || !File.Exists(exe))
        {
            FileLogger.Error("NvidiaPanelClicker.exe introuvable pour tâche enfant : " + task);
            return null;
        }

        var resultFile = Path.Combine(Path.GetTempPath(), "nv-panel-" + task + "-" + Guid.NewGuid().ToString("N") + ".json");
        var args = "--json --purpleboost-root \"" + purpleBoostRoot + "\" --task " + task
            + " --result-file \"" + resultFile + "\"";

        FileLogger.Info("Processus enfant : \"" + exe + "\" " + args);

        using var proc = new Process
        {
            StartInfo = new ProcessStartInfo
            {
                FileName = exe,
                Arguments = args,
                WorkingDirectory = Path.GetDirectoryName(exe) ?? purpleBoostRoot,
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            }
        };

        try
        {
            if (!proc.Start())
            {
                FileLogger.Error("Démarrage processus enfant impossible : " + task);
                return null;
            }

            if (!proc.WaitForExit(timeoutMs))
            {
                try { proc.Kill(true); } catch { }
                FileLogger.Error("Timeout processus enfant : " + task);
                return null;
            }

            if (File.Exists(resultFile))
            {
                var json = File.ReadAllText(resultFile);
                try { File.Delete(resultFile); } catch { }
                return JsonSerializer.Deserialize<ClickerResult>(json, JsonOptions);
            }

            var stdout = proc.StandardOutput.ReadToEnd();
            if (!string.IsNullOrWhiteSpace(stdout))
            {
                try
                {
                    return JsonSerializer.Deserialize<ClickerResult>(stdout.Trim(), JsonOptions);
                }
                catch { }
            }

            FileLogger.Error("Réponse processus enfant illisible : " + task + " exit=" + proc.ExitCode);
            return null;
        }
        catch (Exception ex)
        {
            FileLogger.Error("Processus enfant exception (" + task + ") : " + ex.Message);
            return null;
        }
    }

    private static string? ResolveExePath()
    {
        var processPath = Environment.ProcessPath;
        if (!string.IsNullOrEmpty(processPath) && File.Exists(processPath))
            return processPath;

        var baseDir = AppContext.BaseDirectory;
        var candidates = new[]
        {
            Path.Combine(baseDir, "NvidiaPanelClicker.exe"),
            Path.Combine(baseDir, "..", "NvidiaPanelClicker.exe"),
            Path.Combine(baseDir, "..", "..", "NvidiaPanelClicker.exe")
        };

        foreach (var c in candidates)
        {
            var full = Path.GetFullPath(c);
            if (File.Exists(full)) return full;
        }

        return null;
    }
}
