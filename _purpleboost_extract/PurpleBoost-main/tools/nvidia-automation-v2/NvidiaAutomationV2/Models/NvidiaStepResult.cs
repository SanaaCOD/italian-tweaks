using System.Text.Json.Serialization;

namespace NvidiaAutomationV2.Models;

public sealed class NvidiaStepResult
{
    [JsonPropertyName("name")]
    public string Name { get; set; } = "";

    [JsonPropertyName("status")]
    public string Status { get; set; } = "Failed";

    [JsonPropertyName("message")]
    public string Message { get; set; } = "";
}
