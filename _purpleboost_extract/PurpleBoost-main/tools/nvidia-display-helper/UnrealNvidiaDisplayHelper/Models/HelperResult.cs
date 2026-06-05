using System.Text.Json.Serialization;

namespace UnrealNvidiaDisplayHelper.Models;

public sealed class HelperResult
{
    [JsonPropertyName("success")]
    public bool Success { get; set; }

    [JsonPropertyName("displayMode")]
    public DisplayModeResult DisplayMode { get; set; } = new();

    [JsonPropertyName("scaling")]
    public ScalingResult Scaling { get; set; } = new();

    [JsonPropertyName("digitalVibrance")]
    public DigitalVibranceResult DigitalVibrance { get; set; } = new();

    [JsonPropertyName("gsync")]
    public GsyncResult Gsync { get; set; } = new();

    [JsonPropertyName("messages")]
    public List<string> Messages { get; set; } = new();
}

public sealed class DisplayModeResult
{
    [JsonPropertyName("applied")]
    public bool Applied { get; set; }

    [JsonPropertyName("verified")]
    public bool Verified { get; set; }

    [JsonPropertyName("resolution")]
    public string Resolution { get; set; } = "";

    [JsonPropertyName("refreshRate")]
    public string RefreshRate { get; set; } = "";
}

public sealed class ScalingResult
{
    [JsonPropertyName("applied")]
    public bool Applied { get; set; }

    [JsonPropertyName("verified")]
    public bool Verified { get; set; }

    [JsonPropertyName("mode")]
    public string Mode { get; set; } = "";

    [JsonPropertyName("evidence")]
    public string Evidence { get; set; } = "";

    [JsonPropertyName("uiStatus")]
    public string UiStatus { get; set; } = "";

    [JsonPropertyName("scalingChanged")]
    public bool ScalingChanged { get; set; }
}

public sealed class DigitalVibranceResult
{
    [JsonPropertyName("applied")]
    public bool Applied { get; set; }

    [JsonPropertyName("verified")]
    public bool Verified { get; set; }

    [JsonPropertyName("value")]
    public string Value { get; set; } = "80%";
}

public sealed class GsyncResult
{
    [JsonPropertyName("applied")]
    public bool Applied { get; set; }

    [JsonPropertyName("verified")]
    public bool Verified { get; set; }

    [JsonPropertyName("state")]
    public string State { get; set; } = "Unknown";
}
