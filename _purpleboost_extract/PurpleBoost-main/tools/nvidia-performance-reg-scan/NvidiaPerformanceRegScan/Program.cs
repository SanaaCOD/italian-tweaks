using System.Text.Json;
using System.Text.Json.Serialization;
using NvidiaPerformanceRegScan.Models;
using NvidiaPerformanceRegScan.Services;

namespace NvidiaPerformanceRegScan;

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
        if (!TryParse(args, out var root, out var mode, out var capturePhase, out var err))
        {
            EmitJson(new ScanResult { Success = false, Message = err });
            return 2;
        }

        switch (mode)
        {
            case RunMode.Apply:
            {
                var apply = new PerformanceImageSettingsApplyService().Run(root);
                EmitJson(apply);
                return apply.UiStatus == "registry_written" ? 0 : 1;
            }
            case RunMode.CaptureNvtweak:
            {
                var cap = new NvtweakDeviceCaptureService().Capture(root, capturePhase);
                EmitJson(cap);
                return cap.Success ? 0 : 1;
            }
            default:
            {
                var scan = new PerformanceRegScanService().Run(root);
                EmitJson(scan);
                return scan.Success ? 0 : 1;
            }
        }
    }

    private enum RunMode { Scan, Apply, CaptureNvtweak }

    private static bool TryParse(string[] args, out string root, out RunMode mode, out string capturePhase, out string err)
    {
        root = "";
        err = "";
        mode = RunMode.Scan;
        capturePhase = "";
        var json = false;
        for (var i = 0; i < args.Length; i++)
        {
            var a = args[i];
            if (a == "--json") { json = true; continue; }
            if (a == "--apply-image-settings") { mode = RunMode.Apply; continue; }
            if (a == "--capture-nvtweak") { mode = RunMode.CaptureNvtweak; continue; }
            if (a == "--phase" && i + 1 < args.Length)
            {
                capturePhase = args[++i].Trim().ToLowerInvariant();
                continue;
            }
            if (a == "--purpleboost-root" && i + 1 < args.Length)
            {
                root = args[++i].Trim().TrimEnd('\\', '/');
                continue;
            }
        }

        if (!json)
        {
            err = "Usage: NvidiaPerformanceRegScan.exe --json --purpleboost-root <path> [--apply-image-settings|--capture-nvtweak --phase before|after|--scan-only]";
            return false;
        }

        if (string.IsNullOrWhiteSpace(root))
        {
            err = "--purpleboost-root requis";
            return false;
        }

        if (mode == RunMode.CaptureNvtweak && capturePhase is not ("before" or "after"))
        {
            err = "--capture-nvtweak requiert --phase before ou after";
            return false;
        }

        return true;
    }

    private static void EmitJson<T>(T result)
    {
        Console.OutputEncoding = System.Text.Encoding.UTF8;
        Console.WriteLine(JsonSerializer.Serialize(result, JsonOptions));
    }
}
