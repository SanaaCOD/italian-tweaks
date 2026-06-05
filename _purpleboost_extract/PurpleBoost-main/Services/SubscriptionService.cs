namespace PurpleBoost.Services;

public sealed class SubscriptionService : ISubscriptionService
{
    private readonly IAuthService _auth;

    public SubscriptionService(IAuthService auth)
    {
        _auth = auth;
    }

    public bool IsActive => _auth.CurrentSession?.SubscriptionActive ?? false;

    public void Refresh()
    {
        // Point d’extension : appeler une API Stripe / backend pour resynchroniser le statut.
        Changed?.Invoke(this, EventArgs.Empty);
    }

    public event EventHandler? Changed;
}
