using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using NvidiaPanelClicker.Models;
using NvidiaPanelClicker.Services;

namespace NvidiaPanelClicker;

internal static class Program
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        WriteIndented = false
    };

    public static int Main(string[] args)
    {
        if (!TryParse(args, out var root, out var task, out var resultFile, out var logFile, out var err))
        {
            Emit(new ClickerResult { Success = false, UiStatus = "error", Message = err }, null);
            return 2;
        }

        if (task is "ensure-panel-open" or "open-panel" or "close-panel" or "accept-panel-license")
        {
            Directory.CreateDirectory(Path.Combine(root, "logs", "nvidia-final"));
            var panelLogs = new List<string>
            {
                Path.Combine(root, "logs", "nvidia-panel-clicker.log"),
                Path.Combine(root, "logs", "nvidia-final", "nvidia-full-optimization.log")
            };
            if (!string.IsNullOrWhiteSpace(logFile))
                panelLogs.Add(logFile);
            FileLogger.Configure(panelLogs);
        }
        else
        {
            var logPath = string.IsNullOrWhiteSpace(logFile)
                ? task == "apply-panel-nvidia-settings"
                    ? Path.Combine(root, "logs", "nvidia-final", "04-panel-settings.log")
                    : Path.Combine(root, "logs", "nvidia-panel-clicker.log")
                : logFile;
            FileLogger.Configure(logPath);
        }

        FileLogger.Info("=== NvidiaPanelClicker === task=" + task);

        var service = new PanelClickerService();
        ClickerResult result = task switch
        {
            "open-panel" => new PanelOpenService().RunOpenPanel(),
            "accept-panel-license" => new PanelLicenseAcceptService().Run(),
            "close-panel" => new PanelCloseService().CloseNvidiaControlPanelAtEnd(),
            "ensure-panel-open" => service.EnsureNvidiaControlPanelOpen(),
            "inverse-telecine" => service.RunInverseTelecine(),
            "no-scaling" => service.RunNoScaling(),
            "preview-performance" => service.RunPreviewPerformance(),
            "apply-panel-nvidia-settings" => service.RunCombinedPanelSettings(root),
            _ => new ClickerResult { Success = false, UiStatus = "error", Message = "Tâche inconnue: " + task }
        };

        Emit(result, resultFile);
        return result.Success ? 0 : 1;
    }

    private static bool TryParse(string[] args, out string root, out string task, out string resultFile, out string logFile, out string err)
    {
        root = "";
        task = "";
        resultFile = "";
        logFile = "";
        err = "";
        var json = false;
        for (var i = 0; i < args.Length; i++)
        {
            var a = args[i];
            if (a == "--json") { json = true; continue; }
            if (a == "--apply-panel-nvidia-settings") { task = "apply-panel-nvidia-settings"; continue; }
            if (a == "--task" && i + 1 < args.Length) { task = args[++i].Trim().ToLowerInvariant(); continue; }
            if (a == "--purpleboost-root" && i + 1 < args.Length) { root = args[++i].Trim().TrimEnd('\\', '/'); continue; }
            if (a == "--result-file" && i + 1 < args.Length) { resultFile = args[++i].Trim(); continue; }
            if (a == "--log-file" && i + 1 < args.Length) { logFile = args[++i].Trim(); continue; }
        }

        if (!json) { err = "Usage: --json --purpleboost-root <path> --task <name>|--apply-panel-nvidia-settings [--result-file path]"; return false; }
        if (string.IsNullOrWhiteSpace(root)) { err = "--purpleboost-root requis"; return false; }
        if (task is not ("open-panel" or "close-panel" or "ensure-panel-open" or "accept-panel-license" or "inverse-telecine" or "no-scaling" or "preview-performance" or "apply-panel-nvidia-settings"))
        {
            err = "--task open-panel|close-panel|ensure-panel-open|accept-panel-license|inverse-telecine|no-scaling|preview-performance|apply-panel-nvidia-settings requis";
            return false;
        }

        root = Path.GetFullPath(root);
        if (!string.IsNullOrWhiteSpace(resultFile) && !Path.IsPathRooted(resultFile))
            resultFile = Path.GetFullPath(Path.Combine(root, resultFile));
        if (!string.IsNullOrWhiteSpace(logFile) && !Path.IsPathRooted(logFile))
            logFile = Path.GetFullPath(Path.Combine(root, logFile));

        return true;
    }

    private static void Emit(ClickerResult result, string? resultFile)
    {
        var json = JsonSerializer.Serialize(result, JsonOptions);
        Console.OutputEncoding = Encoding.UTF8;
        Console.WriteLine(json);
        if (string.IsNullOrWhiteSpace(resultFile)) return;
        var dir = Path.GetDirectoryName(resultFile);
        if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
        File.WriteAllText(resultFile!, json, Encoding.UTF8);
    }
}
