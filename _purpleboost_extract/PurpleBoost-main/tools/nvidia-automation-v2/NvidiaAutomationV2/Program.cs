using System.Security.Principal;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using NvidiaAutomationV2.Models;
using NvidiaAutomationV2.Services;

namespace NvidiaAutomationV2;

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
        if (!TryParse(args, out var opts, out var err))
        {
            EmitJson(new AutomationV2Result
            {
                Success = false,
                Messages = { err }
            });
            return 2;
        }

        var logPath = Path.Combine(opts.PurpleBoostRoot, "logs", "nvidia-automation-v2.log");
        FileLogger.Configure(logPath);
        FileLogger.Info("=== NvidiaAutomationV2 ===");
        FileLogger.Info("Args: " + string.Join(" ", args));

        if (opts.HealthCheck)
        {
            var hc = RunNvidiaModuleHealthCheck(opts.PurpleBoostRoot);
            Console.WriteLine(JsonSerializer.Serialize(hc, JsonOptions));
            return hc.Ok ? 0 : 1;
        }

        if (opts.ApplyNipOnly)
        {
            var nipService = new NipProfileService(new ToolLocator(opts.PurpleBoostRoot));
            var nipStep = nipService.ApplyNipProfile();
            var nipOnly = new AutomationV2Result
            {
                Success = nipStep.Status == StepStatus.Success.ToString(),
                NipProfile = nipStep
            };
            EmitJson(nipOnly);
            return nipOnly.Success ? 0 : 1;
        }

        if (opts.ApplyDigitalVibranceOnly)
        {
            using var api = new NvidiaColorApiService();
            var vibStep = api.ApplyDigitalVibrance80();
            var vibOnly = new AutomationV2Result
            {
                Success = vibStep.Status == StepStatus.Success.ToString() && vibStep.Verified,
                DigitalVibrance = vibStep
            };
            EmitJson(vibOnly);
            return vibOnly.Success ? 0 : 1;
        }

        if (opts.DisableInverseTelecineRegistryOnly)
        {
            if (!IsRunningAsAdministrator())
            {
                var notAdmin = new AutomationV2Result
                {
                    Success = false,
                    InverseTelecine = StepResult.Fail("Action non lancée en administrateur", "registry_xalg_cadence"),
                    Message = "Action non lancée en administrateur"
                };
                notAdmin.InverseTelecine.UiStatus = "error";
                EmitJson(notAdmin, opts.ResultFile);
                return 1;
            }

            var it = new InverseTelecineService(opts.PurpleBoostRoot).DisableInverseTelecine();
            var itResult = new AutomationV2Result
            {
                Success = it.Changed && it.Verified,
                InverseTelecine = it,
                Message = it.Message
            };
            EmitJson(itResult, opts.ResultFile);
            return itResult.Success ? 0 : 1;
        }

        if (opts.DisableGsyncOnly)
        {
            var gsyncService = new NvidiaAutomationV2Service(opts.PurpleBoostRoot);
            var gsyncStep = gsyncService.DisableGsync();
            var gsyncOnly = new AutomationV2Result
            {
                Success = gsyncStep.Status == StepStatus.Success.ToString() && gsyncStep.Verified,
                GsyncOff = gsyncStep
            };
            EmitJson(gsyncOnly);
            return gsyncOnly.Success ? 0 : 1;
        }

        if (opts.DisableInverseTelecineOnly || opts.DisableInverseTelecineFastOnly)
        {
            var itService = new NvidiaAutomationV2Service(opts.PurpleBoostRoot);
            var itStep = opts.DisableInverseTelecineFastOnly
                ? itService.DisableInverseTelecineFast()
                : itService.DisableInverseTelecine();
            EmitJson(new AutomationV2Result
            {
                Success = itStep.Status == StepStatus.Success.ToString() && itStep.Verified,
                InverseTelecine = itStep,
                Message = itStep.Message
            });
            return 0;
        }

        if (opts.ApplyHostFull)
        {
            AutomationV2Result hostResult;
            try
            {
                var hostService = new NvidiaAutomationV2Service(opts.PurpleBoostRoot);
                hostResult = hostService.ApplyFullNvidiaOptimizationFromHost();
            }
            catch (Exception ex)
            {
                FileLogger.Info("ApplyHostFull exception: " + ex.Message);
                hostResult = new AutomationV2Result
                {
                    Success = false,
                    Warning = true,
                    Message = "Optimisation Nvidia : erreur interne — " + ex.Message,
                    DigitalVibrance = StepResult.Fail(ex.Message),
                    Messages = { ex.ToString() }
                };
                hostResult.Steps = new List<NvidiaStepResult>
                {
                    new() { Name = "DigitalVibrance", Status = "Failed", Message = ex.Message }
                };
            }

            EmitJson(hostResult);
            return 0;
        }

        var service = new NvidiaAutomationV2Service(opts.PurpleBoostRoot);
        AutomationV2Result result;

        if (opts.ApplyAll)
        {
            if (!opts.SkipNip)
                service.ApplyNipProfile();
            result = service.ApplyAllNvidiaGamingSkipNipIfNeeded(
                opts.SkipNip, opts.SkipDisplay, opts.SkipDigitalVibrance);
        }
        else if (opts.VerifyOnly)
        {
            result = service.Result;
            service.VerifyAll();
            result = service.Result;
        }
        else
        {
            if (opts.StepNip) { result = service.Result; service.ApplyNipProfile(); }
            if (opts.StepDisplay) service.ApplyMaxResolutionAndRefreshRate();
            if (opts.StepVibrance) service.ApplyDigitalVibrance80();
            if (opts.StepGsync) service.DisableGsync();
            if (opts.StepInverseTelecine) service.DisableInverseTelecine();
            result = service.Result;
            result.Success = result.NipProfile.Status != StepStatus.Failed.ToString();
        }

        EmitJson(result);
        return result.Success ? 0 : 1;
    }

    private sealed class HealthCheckDto
    {
        public bool Ok { get; set; }
        public bool NvidiaModuleDetected { get; set; }
        public bool NipInspectorDetected { get; set; }
        public bool NipProfileDetected { get; set; }
        public bool DisplayHelperDetected { get; set; }
        public bool ExistingAutomationPreserved { get; set; } = true;
        public string Message { get; set; } = "";
    }

    private static HealthCheckDto RunNvidiaModuleHealthCheck(string root)
    {
        var tools = new ToolLocator(root);
        var exe = Path.Combine(root, "tools", "nvidia-automation-v2", "NvidiaAutomationV2.exe");
        var inspector = tools.FindNvidiaProfileInspector();
        var nip = tools.FindNipProfile();
        var helper = tools.FindDisplayHelper();
        FileLogger.Info("HEALTHCHECK Nvidia V2 module only (no DDU/NVCleanInstall)");
        return new HealthCheckDto
        {
            Ok = File.Exists(exe) && inspector != null,
            NvidiaModuleDetected = File.Exists(exe),
            NipInspectorDetected = inspector != null,
            NipProfileDetected = nip != null,
            DisplayHelperDetected = helper != null,
            Message = "NvidiaAutomationV2 isolated — does not modify DDU or NVCleanInstall"
        };
    }

    private static void EmitJson(AutomationV2Result result, string? resultFile = null)
    {
        var json = JsonSerializer.Serialize(result, JsonOptions);
        Console.WriteLine(json);
        if (string.IsNullOrWhiteSpace(resultFile)) return;
        var path = Path.GetFullPath(resultFile);
        var dir = Path.GetDirectoryName(path);
        if (!string.IsNullOrEmpty(dir))
            Directory.CreateDirectory(dir);
        File.WriteAllText(path, json, Encoding.UTF8);
    }

    private static bool IsRunningAsAdministrator()
    {
        try
        {
            using var identity = WindowsIdentity.GetCurrent();
            var principal = new WindowsPrincipal(identity);
            return principal.IsInRole(WindowsBuiltInRole.Administrator);
        }
        catch
        {
            return false;
        }
    }

    private static bool TryParse(string[] args, out CliOptions opts, out string error)
    {
        opts = new CliOptions();
        error = "";

        for (var i = 0; i < args.Length; i++)
        {
            var a = args[i];
            switch (a)
            {
                case "--apply-all":
                    opts.ApplyAll = true;
                    break;
                case "--apply-nip":
                    opts.ApplyNipOnly = true;
                    break;
                case "--apply-digital-vibrance-80":
                    opts.ApplyDigitalVibranceOnly = true;
                    break;
                case "--disable-inverse-telecine-registry-only":
                    opts.DisableInverseTelecineRegistryOnly = true;
                    break;
                case "--disable-gsync-only":
                    opts.DisableGsyncOnly = true;
                    break;
                case "--apply-host-full":
                    opts.ApplyHostFull = true;
                    break;
                case "--disable-inverse-telecine-only":
                    opts.DisableInverseTelecineOnly = true;
                    break;
                case "--disable-inverse-telecine-fast-only":
                    opts.DisableInverseTelecineFastOnly = true;
                    break;
                case "--step-inverse-telecine":
                    opts.StepInverseTelecine = true;
                    break;
                case "--verify-only":
                    opts.VerifyOnly = true;
                    break;
                case "--health-check":
                    opts.HealthCheck = true;
                    break;
                case "--json":
                    opts.Json = true;
                    break;
                case "--purpleboost-root":
                    if (i + 1 >= args.Length) { error = "Missing --purpleboost-root value"; return false; }
                    opts.PurpleBoostRoot = args[++i];
                    break;
                case "--result-file":
                    if (i + 1 >= args.Length) { error = "Missing --result-file value"; return false; }
                    opts.ResultFile = args[++i];
                    break;
                case "--step-nip":
                    opts.StepNip = true;
                    break;
                case "--step-display":
                    opts.StepDisplay = true;
                    break;
                case "--step-vibrance":
                    opts.StepVibrance = true;
                    break;
                case "--step-gsync":
                    opts.StepGsync = true;
                    break;
                case "--skip-nip":
                    opts.SkipNip = true;
                    break;
                case "--skip-display":
                    opts.SkipDisplay = true;
                    break;
                case "--skip-digital-vibrance":
                    opts.SkipDigitalVibrance = true;
                    break;
                default:
                    error = "Unknown arg: " + a;
                    return false;
            }
        }

        if (string.IsNullOrWhiteSpace(opts.PurpleBoostRoot))
        {
            var baseDir = AppContext.BaseDirectory.TrimEnd('\\', '/');
            var guess = Path.GetFullPath(Path.Combine(baseDir, "..", "..", ".."));
            if (Directory.Exists(Path.Combine(guess, "tools")))
                opts.PurpleBoostRoot = guess;
            else
                opts.PurpleBoostRoot = Directory.GetCurrentDirectory();
        }

        opts.PurpleBoostRoot = Path.GetFullPath(opts.PurpleBoostRoot);

        if (!string.IsNullOrWhiteSpace(opts.ResultFile) && !Path.IsPathRooted(opts.ResultFile))
            opts.ResultFile = Path.GetFullPath(Path.Combine(opts.PurpleBoostRoot, opts.ResultFile));

        if (!opts.ApplyAll && !opts.ApplyNipOnly && !opts.ApplyDigitalVibranceOnly
            && !opts.DisableInverseTelecineRegistryOnly
            && !opts.DisableGsyncOnly
            && !opts.DisableInverseTelecineOnly && !opts.DisableInverseTelecineFastOnly
            && !opts.ApplyHostFull && !opts.VerifyOnly && !opts.HealthCheck &&
            !opts.StepNip && !opts.StepDisplay && !opts.StepVibrance &&
            !opts.StepGsync && !opts.StepInverseTelecine)
            opts.ApplyAll = true;

        return true;
    }

    private sealed class CliOptions
    {
        public string PurpleBoostRoot { get; set; } = "";
        public bool ApplyAll { get; set; }
        public bool ApplyNipOnly { get; set; }
        public bool ApplyDigitalVibranceOnly { get; set; }
        public bool DisableInverseTelecineRegistryOnly { get; set; }
        public bool DisableGsyncOnly { get; set; }
        public bool ApplyHostFull { get; set; }
        public bool DisableInverseTelecineOnly { get; set; }
        public bool DisableInverseTelecineFastOnly { get; set; }
        public bool StepInverseTelecine { get; set; }
        public bool SkipDisplay { get; set; }
        public bool VerifyOnly { get; set; }
        public bool Json { get; set; } = true;
        public bool StepNip { get; set; }
        public bool StepDisplay { get; set; }
        public bool StepVibrance { get; set; }
        public bool StepGsync { get; set; }
        public bool SkipNip { get; set; }
        public bool SkipDigitalVibrance { get; set; }
        public bool HealthCheck { get; set; }
        public string ResultFile { get; set; } = "";
    }
}
