using PurpleBoost.Models;

namespace PurpleBoost.Services;

public interface IHardwareService
{
    Task<HardwareSnapshot> GetSnapshotAsync(CancellationToken cancellationToken = default);
}
