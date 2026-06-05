using System.Text.Json.Serialization;

namespace NvidiaAutomationV2.Models;

public enum StepStatus
{
    Success,
    Failed,
    Skipped,
    Unsupported
}

public sealed class StepResult
{
    [JsonPropertyName("status")]
    public string Status { get; set; } = StepStatus.Skipped.ToString();

    [JsonPropertyName("message")]
    public string Message { get; set; } = "";

    [JsonPropertyName("verified")]
    public bool Verified { get; set; }

    [JsonPropertyName("method")]
    public string Method { get; set; } = "";

    [JsonPropertyName("evidence")]
    public string Evidence { get; set; } = "";

    /// <summary>applied | error | ignored | not_implemented — pour l'UI (vert uniquement si applied + verified + evidence).</summary>
    [JsonPropertyName("uiStatus")]
    public string UiStatus { get; set; } = "";

    [JsonPropertyName("registryChanged")]
    public bool RegistryChanged { get; set; }

    [JsonPropertyName("changed")]
    public bool Changed { get; set; }

    [JsonPropertyName("modifiedCount")]
    public int ModifiedCount { get; set; }

    public static StepResult Ok(string message, bool verified = true) =>
        new()
        {
            Status = StepStatus.Success.ToString(),
            Message = message,
            Verified = verified,
            UiStatus = verified ? "applied" : "error"
        };

    public static StepResult OkVerified(string message, string method, string evidence, int modifiedCount = 1) =>
        new()
        {
            Status = StepStatus.Success.ToString(),
            Message = message,
            Verified = true,
            Method = method,
            Evidence = evidence,
            UiStatus = "applied",
            RegistryChanged = modifiedCount > 0,
            Changed = modifiedCount > 0,
            ModifiedCount = modifiedCount
        };

    public static StepResult Fail(string message, string? method = null) =>
        new()
        {
            Status = StepStatus.Failed.ToString(),
            Message = message,
            Verified = false,
            Method = method ?? "",
            UiStatus = "error"
        };

    public static StepResult Skip(string message, string? method = null) =>
        new()
        {
            Status = StepStatus.Skipped.ToString(),
            Message = message,
            Verified = false,
            Method = method ?? "",
            UiStatus = "ignored"
        };

    public static StepResult Unsupported(string message) =>
        new()
        {
            Status = StepStatus.Unsupported.ToString(),
            Message = message,
            Verified = false,
            UiStatus = "ignored"
        };

    public static StepResult NotImplemented(string message, string? method = null) =>
        new()
        {
            Status = StepStatus.Unsupported.ToString(),
            Message = message,
            Verified = false,
            Method = method ?? "",
            UiStatus = "not_implemented"
        };
}

public sealed class AutomationV2Result
{
    [JsonPropertyName("success")]
    public bool Success { get; set; }

    [JsonPropertyName("nipProfile")]
    public StepResult NipProfile { get; set; } = new();

    [JsonPropertyName("resolution")]
    public StepResult Resolution { get; set; } = new();

    [JsonPropertyName("refreshRate")]
    public StepResult RefreshRate { get; set; } = new();

    [JsonPropertyName("digitalVibrance")]
    public StepResult DigitalVibrance { get; set; } = new();

    [JsonPropertyName("gsyncOff")]
    public StepResult GsyncOff { get; set; } = new();

    [JsonPropertyName("inverseTelecine")]
    public StepResult InverseTelecine { get; set; } = new();

    [JsonPropertyName("messages")]
    public List<string> Messages { get; set; } = new();

    [JsonPropertyName("message")]
    public string Message { get; set; } = "";

    [JsonPropertyName("warning")]
    public bool Warning { get; set; }

    [JsonPropertyName("steps")]
    public List<NvidiaStepResult> Steps { get; set; } = new();

}
