using System.IO;
using System.Text.Json;
using PurpleBoost.Models;

namespace PurpleBoost.Services;

/// <summary>
/// Auth mockée locale (fichier JSON). Remplacez par appels HTTP + Stripe Customer Portal plus tard.
/// </summary>
public sealed class AuthService : IAuthService
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
    };

    private readonly string _sessionPath;
    private AuthSession? _session;

    public AuthService()
    {
        var root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "PurpleBoost");
        Directory.CreateDirectory(root);
        _sessionPath = Path.Combine(root, "session.json");
        _session = TryLoad();
    }

    public AuthSession? CurrentSession => _session;

    public Task<AuthSession> LoginAsync(string email, string password, CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (string.IsNullOrWhiteSpace(email) || string.IsNullOrWhiteSpace(password))
            throw new InvalidOperationException("Email et mot de passe requis.");

        var session = new AuthSession
        {
            Email = email.Trim(),
            Token = $"mock_{Guid.NewGuid():N}",
            SubscriptionActive = email.Contains("+sub", StringComparison.OrdinalIgnoreCase),
        };

        Save(session);
        return Task.FromResult(session);
    }

    public Task<AuthSession> RegisterAsync(string email, string password, CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (string.IsNullOrWhiteSpace(email) || password.Length < 4)
            throw new InvalidOperationException("Mot de passe trop court (mock : min. 4 caractères).");

        var session = new AuthSession
        {
            Email = email.Trim(),
            Token = $"mock_{Guid.NewGuid():N}",
            SubscriptionActive = false,
        };

        Save(session);
        return Task.FromResult(session);
    }

    public void Logout()
    {
        _session = null;
        try
        {
            if (File.Exists(_sessionPath))
                File.Delete(_sessionPath);
        }
        catch
        {
            // ignore
        }
    }

    private AuthSession? TryLoad()
    {
        try
        {
            if (!File.Exists(_sessionPath))
                return null;

            var json = File.ReadAllText(_sessionPath);
            var dto = JsonSerializer.Deserialize<SessionDto>(json);
            if (dto is null || string.IsNullOrWhiteSpace(dto.Email) || string.IsNullOrWhiteSpace(dto.Token))
                return null;

            return new AuthSession
            {
                Email = dto.Email,
                Token = dto.Token,
                SubscriptionActive = dto.SubscriptionActive,
            };
        }
        catch
        {
            return null;
        }
    }

    private void Save(AuthSession session)
    {
        _session = session;
        var dto = new SessionDto
        {
            Email = session.Email,
            Token = session.Token,
            SubscriptionActive = session.SubscriptionActive,
        };
        File.WriteAllText(_sessionPath, JsonSerializer.Serialize(dto, JsonOptions));
    }

    private sealed class SessionDto
    {
        public string Email { get; set; } = string.Empty;
        public string Token { get; set; } = string.Empty;
        public bool SubscriptionActive { get; set; }
    }
}
