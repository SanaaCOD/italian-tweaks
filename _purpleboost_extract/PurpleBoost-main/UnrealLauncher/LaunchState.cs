using System.Text.Json;
using System.Text.Json.Serialization;

namespace UnrealLauncher;

internal sealed class LaunchState
{
    [JsonPropertyName("phase")]
    public string Phase { get; set; } = "";

    [JsonPropertyName("message")]
    public string? Message { get; set; }

    [JsonPropertyName("ts")]
    public long Ts { get; set; }

    public static LaunchState? TryParse(string json)
    {
        try
        {
            return JsonSerializer.Deserialize<LaunchState>(json);
        }
        catch
        {
            return null;
        }
    }
}

internal static class LaunchStatePaths
{
    public static string StateFile(string appRoot) =>
        Path.Combine(appRoot, "logs", "launch-state.json");
}
