using System.Text.Json;
using UnrealNvidiaDisplayHelper.Models;
using UnrealNvidiaDisplayHelper.Services;

namespace UnrealNvidiaDisplayHelper;

internal static class Program
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = false
    };

    public static int Main(string[] args)
    {
        FileLogger.Configure();
        FileLogger.Info("=== UnrealNvidiaDisplayHelper démarré ===");
        FileLogger.Info("Args: " + string.Join(" ", args));

        if (!CliOptions.TryParse(args, out var options, out var parseError))
        {
            return EmitCritical(new HelperResult
            {
                Success = false,
                Messages = { parseError }
            });
        }

        var result = new HelperResult { Success = true };
        var display = new DisplayModeService();
        var critical = false;

        try
        {
            if (!display.FindPrimaryDisplay())
            {
                result.Messages.Add("Aucun écran principal détecté");
                critical = true;
            }
            else
            {
                var applyDisplay = options.ApplyFull && !options.StatusOnly;
                display.FillDisplayModeStatus(result, applyDisplay, options.DryRun);
                if (applyDisplay && string.IsNullOrEmpty(result.DisplayMode.Resolution) && !options.DryRun)
                {
                    result.Messages.Add("Impossible d'appliquer le mode d'affichage");
                    critical = true;
                }

                using var nvapi = new NvApiService();
                var nvOk = nvapi.TryInitialize(display.PrimaryDeviceName);
                FileLogger.Info("NVAPI disponible=" + nvOk);

                if (options.StatusOnly)
                {
                    nvapi.ReadStatus(result);
                }
                else if (options.ScalingOnly)
                {
                    if (nvOk)
                        nvapi.ApplyScaling(result, options.DryRun);
                    else
                    {
                        result.Scaling.Applied = false;
                        result.Scaling.Verified = false;
                        result.Scaling.Mode = "No scaling";
                        result.Messages.Add("Scaling NVIDIA non disponible (NVAPI)");
                    }
                }
                else if (options.ApplyFull)
                {
                    if (nvOk)
                    {
                        nvapi.ApplyScaling(result, options.DryRun);
                        if (options.SkipDigitalVibrance)
                        {
                            result.DigitalVibrance.Applied = false;
                            result.DigitalVibrance.Verified = false;
                            result.DigitalVibrance.Value = "skipped";
                            result.Messages.Add("Digital Vibrance ignoré (--skip-digital-vibrance)");
                            FileLogger.Info("Digital Vibrance skipped (--skip-digital-vibrance)");
                        }
                        else
                        {
                            nvapi.ApplyDigitalVibrance(result, options.DryRun);
                        }
                        nvapi.ApplyGsyncVrr(result, options.DryRun);
                    }
                    else
                    {
                        result.Scaling.Applied = false;
                        result.Scaling.Verified = false;
                        result.Scaling.Mode = "No scaling";
                        result.Messages.Add("Scaling NVIDIA non disponible sur cette configuration");

                        result.DigitalVibrance.Applied = false;
                        result.DigitalVibrance.Verified = false;
                        result.DigitalVibrance.Value = "80%";
                        result.Messages.Add("Digital Vibrance non disponible via NVAPI");

                        result.Gsync.Applied = false;
                        result.Gsync.Verified = false;
                        result.Gsync.State = "Unknown";
                        result.Messages.Add("Désactivation G-Sync/VRR non disponible via API sur cette configuration");
                    }
                }
            }

            if (critical)
                result.Success = false;

            var exitCode = ComputeExitCode(result, critical, options);
            FileLogger.Info("ExitCode=" + exitCode + " success=" + result.Success);
            WriteJsonStdout(result);
            return exitCode;
        }
        catch (Exception ex)
        {
            FileLogger.Error(ex.ToString());
            return EmitCritical(new HelperResult
            {
                Success = false,
                Messages = { "Erreur critique : " + ex.Message }
            });
        }
    }

    private static int ComputeExitCode(HelperResult result, bool critical, CliOptions options)
    {
        if (critical || !result.Success)
            return 1;

        if (options.StatusOnly)
            return 0;

        var hasUnverified = HasUnverifiedApplied(result);
        var hasUnavailable = HasUnavailable(result);
        if (hasUnverified || hasUnavailable)
            return 2;

        return 0;
    }

    private static bool HasUnverifiedApplied(HelperResult r) =>
        (r.DisplayMode.Applied && !r.DisplayMode.Verified) ||
        (r.Scaling.Applied && !r.Scaling.Verified) ||
        (r.DigitalVibrance.Applied && !r.DigitalVibrance.Verified) ||
        (r.Gsync.Applied && !r.Gsync.Verified);

    private static bool HasUnavailable(HelperResult r) =>
        (!r.Scaling.Applied && !r.Scaling.Verified) ||
        (!r.DigitalVibrance.Applied && !r.DigitalVibrance.Verified) ||
        (!r.Gsync.Applied && !r.Gsync.Verified);

    private static void WriteJsonStdout(HelperResult result)
    {
        var json = JsonSerializer.Serialize(result, JsonOptions);
        Console.Out.WriteLine(json);
    }

    private static int EmitCritical(HelperResult result)
    {
        WriteJsonStdout(result);
        return 1;
    }
}
