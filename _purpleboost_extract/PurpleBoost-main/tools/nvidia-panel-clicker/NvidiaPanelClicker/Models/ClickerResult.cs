namespace NvidiaPanelClicker.Models;

public sealed class ClickerResult
{
    public bool Success { get; set; }
    public string Task { get; set; } = "";
    public string UiStatus { get; set; } = "";
    public bool Verified { get; set; }
    public string Message { get; set; } = "";
    public List<string> LogLines { get; set; } = new();
    public Dictionary<string, string>? Children { get; set; }
}
