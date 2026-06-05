namespace PurpleBoost.Services;

/// <summary>
/// Exécution PowerShell (futur). Aucun script dangereux ne doit être lancé sans confirmation UI + garde-fous.
/// </summary>
public interface IPowerShellService
{
    Task<PowerShellExecutionResult> ExecuteScriptFileAsync(
        string scriptRelativePath,
        bool runAsAdministrator,
        CancellationToken cancellationToken = default);
}

public sealed record PowerShellExecutionResult(bool Success, int ExitCode, string StandardOutput, string StandardError);
