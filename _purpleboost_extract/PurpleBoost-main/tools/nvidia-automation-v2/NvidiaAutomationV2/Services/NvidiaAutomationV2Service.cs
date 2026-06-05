using NvidiaAutomationV2.Models;

namespace NvidiaAutomationV2.Services;

public sealed class NvidiaAutomationV2Service
{
    private readonly ToolLocator _tools;
    private readonly NipProfileService _nip;
    private readonly DisplayModeService _display;
    private readonly InverseTelecineService _inverseTelecine;
    private readonly GsyncToggleService _gsync;
    private readonly AutomationV2Result _result = new();

    public NvidiaAutomationV2Service(string purpleBoostRoot)
    {
        _tools = new ToolLocator(purpleBoostRoot);
        _nip = new NipProfileService(_tools);
        _display = new DisplayModeService();
        _inverseTelecine = new InverseTelecineService(purpleBoostRoot);
        _gsync = new GsyncToggleService(_tools, _tools.FindNipProfile());
    }

    public AutomationV2Result Result => _result;

    /// <summary>Optimisation complète côté hôte HTA : G-Sync puis éclat 80 % en dernier.</summary>
    public AutomationV2Result ApplyFullNvidiaOptimizationFromHost()
    {
        FileLogger.Info("Full Nvidia Optimization: starting");

        _result.NipProfile = StepResult.Skip("NIP géré par l'hôte (HTA)");
        _result.Resolution = StepResult.Skip("Affichage géré par l'hôte (HTA)");
        _result.RefreshRate = StepResult.Skip("Affichage géré par l'hôte (HTA)");
        FileLogger.Info("NIP profile step: Skipped");
        FileLogger.Info("Max resolution step: Skipped");
        FileLogger.Info("Max refresh rate step: Skipped");

        FileLogger.Info("G-Sync OFF step: starting");
        _result.GsyncOff = DisableGsyncIfToolAvailable();
        LogGsyncOutcome(_result.GsyncOff);
        FileLogger.Info("G-Sync OFF step: " + StepOutcomeLabel(_result.GsyncOff));

        FileLogger.Info("Applying Digital Vibrance 80 final step");
        FileLogger.Info("Calling ApplyDigitalVibrance80()");
        _result.DigitalVibrance = ApplyDigitalVibrance80();
        if (_result.DigitalVibrance.Status == StepStatus.Success.ToString() && _result.DigitalVibrance.Verified)
            FileLogger.Info("Digital Vibrance RAW 38 sent");
        FileLogger.Info("Digital Vibrance 80 step: " + StepOutcomeLabel(_result.DigitalVibrance));

        FinalizeHostOptimizationResult();
        FileLogger.Info("Full Nvidia Optimization: completed");
        return _result;
    }

    public StepResult ApplyMaxResolution() => _result.Resolution = _display.ApplyMaxResolution();

    public StepResult ApplyMaxRefreshRate() => _result.RefreshRate = _display.ApplyMaxRefreshRate();

    public AutomationV2Result ApplyAllNvidiaGamingSkipNipIfNeeded(
        bool skipNip,
        bool skipDisplay = false,
        bool skipDigitalVibrance = false)
    {
        FileLogger.Info("Full Nvidia Optimization: starting");
        FileLogger.Info("=== ApplyAllNvidiaGaming === skipNip=" + skipNip + " skipDisplay=" + skipDisplay
            + " skipDigitalVibrance=" + skipDigitalVibrance);

        if (!skipNip)
            _result.NipProfile = ApplyNipProfile();
        else if (_result.NipProfile.Status == StepStatus.Skipped.ToString() && string.IsNullOrEmpty(_result.NipProfile.Message))
            _result.NipProfile = StepResult.Skip("NIP géré par l'hôte (élévation)");
        LogStepOutcome("NIP profile", _result.NipProfile);

        if (!skipDisplay)
        {
            var (res, hz) = ApplyMaxResolutionAndRefreshRate();
            _result.Resolution = res;
            _result.RefreshRate = hz;
        }
        else
        {
            _result.Resolution = StepResult.Skip("Affichage géré par l'hôte (helper HTA)");
            _result.RefreshRate = StepResult.Skip("Affichage géré par l'hôte (helper HTA)");
            FileLogger.Info("DISPLAY=skipped (HTA helper)");
        }
        LogStepOutcome("Max resolution", _result.Resolution);
        LogStepOutcome("Max refresh rate", _result.RefreshRate);

        FileLogger.Info("STEP=DisableGsyncIfToolAvailable order=4");
        _result.GsyncOff = DisableGsyncIfToolAvailable();
        LogGsyncOutcome(_result.GsyncOff);

        if (!skipDigitalVibrance)
        {
            FileLogger.Info("Applying Digital Vibrance 80 as final step");
            _result.DigitalVibrance = ApplyDigitalVibrance80();
            LogDigitalVibranceOutcome(_result.DigitalVibrance);
        }
        else
        {
            _result.DigitalVibrance = StepResult.Skip("Éclat numérique : étape finale gérée par l'hôte (HTA)");
            FileLogger.Info("Digital Vibrance: deferred to host final step");
        }

        VerifyAll();

        _result.Success = ComputeCoreStepsSuccess();
        if (_result.Success
            && _result.GsyncOff.Status == StepStatus.Skipped.ToString()
            && _result.GsyncOff.Message.Contains("outil manquant", StringComparison.OrdinalIgnoreCase))
            FileLogger.Info("Nvidia full optimization completed with warnings");

        FileLogger.Info("Full Nvidia Optimization: completed success=" + _result.Success);
        FileLogger.Info("=== ApplyAllNvidiaGaming done success=" + _result.Success + " ===");
        return _result;
    }

    public StepResult ApplyNipProfile() => _result.NipProfile = _nip.ApplyNipProfile();

    public (StepResult Resolution, StepResult RefreshRate) ApplyMaxResolutionAndRefreshRate()
    {
        _result.Resolution = ApplyMaxResolution();
        _result.RefreshRate = ApplyMaxRefreshRate();
        return (_result.Resolution, _result.RefreshRate);
    }

    public StepResult ApplyDigitalVibrance80()
    {
        using var api = new NvidiaColorApiService();
        return _result.DigitalVibrance = api.ApplyDigitalVibrance80();
    }

    public StepResult ApplyDigitalVibrance() => ApplyDigitalVibrance80();

    public StepResult DisableGsync() => _result.GsyncOff = _gsync.DisableGsync();

    public StepResult DisableGsyncIfToolAvailable() => _result.GsyncOff = _gsync.DisableGsyncIfToolAvailable();

    public StepResult ApplyGsyncOff() => DisableGsync();

    public StepResult DisableInverseTelecine() => _result.InverseTelecine = _inverseTelecine.DisableInverseTelecine();

    public StepResult DisableInverseTelecineFast() => _result.InverseTelecine = _inverseTelecine.DisableInverseTelecineFast();

    public AutomationV2Result VerifyAll()
    {
        FileLogger.Info("STEP=VerifyAll");
        _result.Messages.Clear();

        AppendVerify("NIP", _result.NipProfile);
        AppendVerify("Resolution", _result.Resolution);
        AppendVerify("RefreshRate", _result.RefreshRate);
        AppendVerify("DigitalVibrance", _result.DigitalVibrance);
        AppendVerify("GsyncOff", _result.GsyncOff);
        AppendVerify("InverseTelecine", _result.InverseTelecine);

        return _result;
    }

    private void AppendVerify(string name, StepResult step)
    {
        var line = $"{name}={step.Status} verified={step.Verified} msg={step.Message}";
        _result.Messages.Add(line);
        FileLogger.Info("VERIFY " + line);
    }

    private void FinalizeHostOptimizationResult()
    {
        _result.Steps = BuildStepSummary();
        _result.Success = ComputeCoreStepsSuccess();
        _result.Warning = !_result.Success
            || (_result.GsyncOff.Status == StepStatus.Skipped.ToString()
                && _result.GsyncOff.Message.Contains("outil manquant", StringComparison.OrdinalIgnoreCase));

        if (_result.Success && _result.Warning)
            _result.Message = "Optimisation Nvidia terminée avec avertissements";
        else if (_result.Success)
            _result.Message = "Optimisation Nvidia terminée";
        else
            _result.Message = "Optimisation Nvidia terminée avec erreurs partielles";
    }

    private List<NvidiaStepResult> BuildStepSummary()
    {
        return new List<NvidiaStepResult>
        {
            ToNvidiaStep("NIP", _result.NipProfile),
            ToNvidiaStep("Resolution", _result.Resolution),
            ToNvidiaStep("RefreshRate", _result.RefreshRate),
            ToNvidiaStep("GSync", _result.GsyncOff),
            ToNvidiaStep("InverseTelecine", _result.InverseTelecine),
            ToNvidiaStep("DigitalVibrance", _result.DigitalVibrance)
        };
    }

    private static NvidiaStepResult ToNvidiaStep(string name, StepResult step) =>
        new()
        {
            Name = name,
            Status = StepOutcomeLabel(step),
            Message = step.Message ?? ""
        };

    private static void LogStepOutcome(string label, StepResult step) =>
        FileLogger.Info(label + ": " + StepOutcomeLabel(step));

    private static void LogGsyncOutcome(StepResult step)
    {
        if (step.Status == StepStatus.Skipped.ToString()
            && step.Message.Contains("outil manquant", StringComparison.OrdinalIgnoreCase))
            FileLogger.Info("G-Sync OFF: Skipped");
        else
            FileLogger.Info("G-Sync OFF: " + StepOutcomeLabel(step));
    }

    private static void LogDigitalVibranceOutcome(StepResult step) =>
        FileLogger.Info("Digital Vibrance 80: " + StepOutcomeLabel(step));

    private static string StepOutcomeLabel(StepResult step)
    {
        if (step.Status == StepStatus.Success.ToString() && step.Verified)
            return "OK";
        if (step.Status == StepStatus.Skipped.ToString())
            return "Skipped";
        return "Failed";
    }

    private bool ComputeCoreStepsSuccess()
    {
        var critical = new List<StepResult>();

        var dvHandledByHost = _result.DigitalVibrance.Message.Contains("hôte", StringComparison.OrdinalIgnoreCase)
                              || _result.DigitalVibrance.Message.Contains("HTA", StringComparison.OrdinalIgnoreCase);
        if (!dvHandledByHost)
            critical.Add(_result.DigitalVibrance);

        var nipHandledByHost = _result.NipProfile.Message.Contains("hôte", StringComparison.OrdinalIgnoreCase)
                               || _result.NipProfile.Message.Contains("host", StringComparison.OrdinalIgnoreCase);
        if (!nipHandledByHost && _result.NipProfile.Status != StepStatus.Skipped.ToString())
            critical.Insert(0, _result.NipProfile);

        var displayHandledByHost = _result.Resolution.Message.Contains("hôte", StringComparison.OrdinalIgnoreCase)
                                   || _result.Resolution.Message.Contains("host", StringComparison.OrdinalIgnoreCase);
        if (!displayHandledByHost && _result.Resolution.Status != StepStatus.Skipped.ToString())
        {
            critical.Insert(0, _result.RefreshRate);
            critical.Insert(0, _result.Resolution);
        }

        if (critical.Any(s => s.Status == StepStatus.Failed.ToString()))
            return false;
        return critical.All(s => s.Status == StepStatus.Success.ToString() && s.Verified);
    }
}
