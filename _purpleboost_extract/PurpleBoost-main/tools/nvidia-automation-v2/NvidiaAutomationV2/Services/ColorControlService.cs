using NvidiaAutomationV2.Models;

namespace NvidiaAutomationV2.Services;

/// <summary>DÉSACTIVÉ — Digital Vibrance via NvidiaColorApiService.ApplyDigitalVibrance80 uniquement.</summary>
public sealed class ColorControlService
{
    public ColorControlService(ToolLocator tools) { }

    public StepResult ApplyDigitalVibrance()
    {
        FileLogger.Warn("ColorControlService.ApplyDigitalVibrance désactivé");
        return StepResult.Skip("ColorControl désactivé — utiliser ApplyDigitalVibrance80");
    }
}
