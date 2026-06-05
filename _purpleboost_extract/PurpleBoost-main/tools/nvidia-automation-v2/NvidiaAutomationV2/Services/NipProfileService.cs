using NvidiaAutomationV2.Models;

namespace NvidiaAutomationV2.Services;

/// <summary>
/// STABLE — stable-nvidia-nip-silent-import : délègue à NipSilentImportService uniquement.
/// Ne pas réintroduire -silent -exportCustomized ni ouverture GUI NPI ici.
/// </summary>
public sealed class NipProfileService
{
    private readonly ToolLocator _tools;
    private bool _lastImportSuccess;

    public NipProfileService(ToolLocator tools) => _tools = tools;

    public bool LastImportSuccess => _lastImportSuccess;

    public StepResult ApplyNipProfile()
    {
        FileLogger.Info("STEP=ApplyNipProfile (silentImport C#)");
        _lastImportSuccess = false;

        var inspector = _tools.FindNvidiaProfileInspector();
        if (inspector == null)
            return StepResult.Fail("Outil Nvidia Profile Inspector manquant.");

        var nip = _tools.FindNipProfile();
        if (nip == null)
            return StepResult.Fail("Preset Nvidia UnrealGaming.nip introuvable.");

        var run = NipSilentImportService.Import(inspector, nip);

        FileLogger.Info("NPI_PATH=" + inspector);
        FileLogger.Info("NIP_PATH=" + nip);

        if (run.TimedOut)
            return StepResult.Fail("Import .nip timeout");

        if (run.ExitCode != 0)
            return StepResult.Fail("Import .nip exit=" + run.ExitCode);

        _lastImportSuccess = true;
        return StepResult.Ok("Profil NVIDIA appliqué via .nip", true);
    }

}
