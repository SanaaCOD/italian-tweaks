namespace PurpleBoost.Services;

public interface ISubscriptionService
{
    bool IsActive { get; }

    void Refresh();
}
