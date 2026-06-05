namespace PurpleBoost.Models;

public sealed class HardwareSnapshot
{
    public const string MissingLabel = "À connecter plus tard";

    public string CpuName { get; init; } = "—";
    public string CpuUsage { get; init; } = MissingLabel;
    public string GpuName { get; init; } = "—";
    public string GpuUsage { get; init; } = MissingLabel;
    public string RamTotal { get; init; } = "—";
    public string RamUsage { get; init; } = MissingLabel;
    public string CpuTemperature { get; init; } = MissingLabel;
    public string GpuTemperature { get; init; } = MissingLabel;
}
