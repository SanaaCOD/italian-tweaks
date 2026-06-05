namespace NvidiaPerformanceRegScan.Models;

public sealed class RegistryValueSnapshot
{
    public string Name { get; set; } = "";
    public string Kind { get; set; } = "";
    public string Preview { get; set; } = "";
}

public sealed class NvtweakCaptureResult
{
    public bool Success { get; set; }
    public string Phase { get; set; } = "";
    public string UiStatus { get; set; } = "";
    public string Message { get; set; } = "";
    public string RegistryPath { get; set; } = "";
    public string DeviceKey { get; set; } = "";
    public int ValueCount { get; set; }
    public string SnapshotPath { get; set; } = "";
    public string? DiffPath { get; set; }
    public int? ChangedCount { get; set; }
    public List<RegistryValueSnapshot> Values { get; set; } = new();
}
