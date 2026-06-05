namespace NvidiaPerformanceRegScan.Models;

public sealed class ApplyEntry
{
    public string DeviceKey { get; set; } = "";
    public string RegistryPath { get; set; } = "";
    public int? OldValue { get; set; }
    public int NewValue { get; set; }
    public int? ReadBackValue { get; set; }
    public bool WriteOk { get; set; }
    public bool Verified { get; set; }
    public string Status { get; set; } = "";
}

public sealed class ApplyImageSettingsResult
{
    public bool Success { get; set; }
    public string UiStatus { get; set; } = "";
    public bool Verified { get; set; }
    public string Method { get; set; } = "registry_image_settings";
    public string Evidence { get; set; } = "";
    public string Message { get; set; } = "";
    public int FoundCount { get; set; }
    public int ModifiedCount { get; set; }
    public int VerifiedCount { get; set; }
    public string ApplyLogPath { get; set; } = "";
    public string BackupPath { get; set; } = "";
    public bool NvcpluiWasRunning { get; set; }
    public bool NvcpluiClosed { get; set; }
    public List<ApplyEntry> Entries { get; set; } = new();
}
