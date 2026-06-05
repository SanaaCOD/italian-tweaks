using PurpleBoost.Models;

namespace PurpleBoost.Services;

public interface IAuthService
{
    AuthSession? CurrentSession { get; }

    Task<AuthSession> LoginAsync(string email, string password, CancellationToken cancellationToken = default);

    Task<AuthSession> RegisterAsync(string email, string password, CancellationToken cancellationToken = default);

    void Logout();
}
