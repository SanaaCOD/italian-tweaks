namespace PurpleBoost.Services;

public sealed class PowerShellService : IPowerShellService
{
    public Task<PowerShellExecutionResult> ExecuteScriptFileAsync(
        string scriptRelativePath,
        bool runAsAdministrator,
        CancellationToken cancellationToken = default)
    {
        // Volontairement non implémenté : branchez ici ProcessStartInfo + -File + élévation UAC.
        _ = scriptRelativePath;
        _ = runAsAdministrator;
        return Task.FromResult(
            new PowerShellExecutionResult(
                Success: false,
                ExitCode: -1,
                StandardOutput: string.Empty,
                StandardError: "Exécution PowerShell non branchée (sécurité / MVP)."));
    }
}
