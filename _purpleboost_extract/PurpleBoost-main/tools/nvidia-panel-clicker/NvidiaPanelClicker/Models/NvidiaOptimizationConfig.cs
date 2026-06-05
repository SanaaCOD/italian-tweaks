using System.Text.Json;
using System.Text.Json.Serialization;

namespace NvidiaPanelClicker.Models;

public sealed class NvidiaOptimizationConfig
{
    public int DigitalVibrance { get; set; } = 80;
    public bool RunNipProfile { get; set; } = true;
    public bool RunDigitalVibrance { get; set; } = true;
    public bool RunDisplaySettings { get; set; } = true;
    public bool RunPanelSettings { get; set; } = true;
    public bool CloseNvidiaPanelAtEnd { get; set; } = true;
    public bool BringUnrealToFrontAtEnd { get; set; } = true;
    public PanelSettingsConfig PanelSettings { get; set; } = new();

    public static NvidiaOptimizationConfig Load(string purpleBoostRoot)
    {
        var path = Path.Combine(purpleBoostRoot, "config", "nvidia-optimization.json");
        if (!File.Exists(path))
            return new NvidiaOptimizationConfig();

        try
        {
            var json = File.ReadAllText(path);
            var cfg = JsonSerializer.Deserialize<NvidiaOptimizationConfig>(json, JsonOptions);
            return cfg ?? new NvidiaOptimizationConfig();
        }
        catch
        {
            return new NvidiaOptimizationConfig();
        }
    }

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
        ReadCommentHandling = JsonCommentHandling.Skip,
        AllowTrailingCommas = true
    };
}

public sealed class PanelSettingsConfig
{
    public bool RunNoScaling { get; set; } = true;
    public bool RunPreviewPerformance { get; set; } = true;
    public bool RunInverseTelecine { get; set; } = true;
    public int DelayAfterNoScalingMs { get; set; } = 4000;
    public int DelayBetweenPanelStepsMs { get; set; } = 1000;
}
