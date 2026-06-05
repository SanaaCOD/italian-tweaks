using NvidiaAutomationV2.Models;

namespace NvidiaAutomationV2.Services;

public sealed class InverseTelecineService
{
    private readonly NvidiaInverseTelecineService _registry;

    public InverseTelecineService(string purpleBoostRoot) =>
        _registry = new NvidiaInverseTelecineService(purpleBoostRoot);

    public StepResult DisableInverseTelecine() => _registry.DisableInverseTelecine();

    public StepResult DisableInverseTelecineFast() => DisableInverseTelecine();
}
