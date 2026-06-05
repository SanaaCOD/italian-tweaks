using System.Windows;
using PurpleBoost.Helpers;
using PurpleBoost.Services;
using System.Windows.Input;

namespace PurpleBoost.ViewModels;

public sealed class AccountViewModel : BaseViewModel
{
    private readonly IAuthService _auth;
    private readonly ISubscriptionService _subscription;

    private string _email = string.Empty;
    private string _password = string.Empty;
    private string _subscriptionStatus = "Inactif";
    private string _sessionEmail = "Non connecté";

    public AccountViewModel(IAuthService auth, ISubscriptionService subscription)
    {
        _auth = auth;
        _subscription = subscription;
        LoginCommand = new RelayCommand(() => _ = LoginAsync(), CanLogin);
        RegisterCommand = new RelayCommand(() => _ = RegisterAsync(), CanLogin);
        LogoutCommand = new RelayCommand(Logout, () => _auth.CurrentSession is not null);

        RefreshUi();
    }

    public ICommand LoginCommand { get; }
    public ICommand RegisterCommand { get; }
    public ICommand LogoutCommand { get; }

    public string Email
    {
        get => _email;
        set
        {
            if (!SetProperty(ref _email, value))
                return;

            RaiseAuthCommands();
        }
    }

    public string Password
    {
        get => _password;
        set
        {
            if (!SetProperty(ref _password, value))
                return;

            RaiseAuthCommands();
        }
    }

    public string SubscriptionStatus
    {
        get => _subscriptionStatus;
        private set => SetProperty(ref _subscriptionStatus, value);
    }

    public string SessionEmail
    {
        get => _sessionEmail;
        private set => SetProperty(ref _sessionEmail, value);
    }

    private bool CanLogin() =>
        !string.IsNullOrWhiteSpace(Email) && !string.IsNullOrWhiteSpace(Password);

    private void RaiseAuthCommands()
    {
        if (LoginCommand is RelayCommand l)
            l.RaiseCanExecuteChanged();
        if (RegisterCommand is RelayCommand r)
            r.RaiseCanExecuteChanged();
    }

    private async Task LoginAsync()
    {
        try
        {
            await _auth.LoginAsync(Email, Password).ConfigureAwait(true);
            _subscription.Refresh();
            RefreshUi();
        }
        catch (Exception ex)
        {
            MessageBox.Show(ex.Message, "PurpleBoost — connexion", MessageBoxButton.OK, MessageBoxImage.Information);
        }
    }

    private async Task RegisterAsync()
    {
        try
        {
            await _auth.RegisterAsync(Email, Password).ConfigureAwait(true);
            _subscription.Refresh();
            RefreshUi();
        }
        catch (Exception ex)
        {
            MessageBox.Show(ex.Message, "PurpleBoost — inscription", MessageBoxButton.OK, MessageBoxImage.Information);
        }
    }

    private void Logout()
    {
        _auth.Logout();
        _subscription.Refresh();
        RefreshUi();
    }

    private void RefreshUi()
    {
        var s = _auth.CurrentSession;
        SessionEmail = s?.Email ?? "Non connecté";
        SubscriptionStatus = s?.SubscriptionActive == true ? "Actif" : "Inactif";

        if (LogoutCommand is RelayCommand lo)
            lo.RaiseCanExecuteChanged();
    }
}
