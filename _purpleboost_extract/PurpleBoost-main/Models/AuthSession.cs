namespace PurpleBoost.Models;

public sealed class AuthSession
{
    public required string Email { get; init; }
    public required string Token { get; init; }
    public bool SubscriptionActive { get; init; }
}
