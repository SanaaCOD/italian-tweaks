using System.Collections.ObjectModel;
using PurpleBoost.Models;
using PurpleBoost.Services;

namespace PurpleBoost.ViewModels;

public sealed class ShellViewModel : BaseViewModel
{
    private readonly IHardwareService _hardware;
    private readonly ILogService _log;
    private readonly IAuthService _auth;
    private readonly IPowerShellService _powerShell;
    private readonly ISubscriptionService _subscription;

    private object? _currentContent;
    private NavItem? _selectedNavItem;

    public ShellViewModel(
        IHardwareService hardware,
        ILogService log,
        IAuthService auth,
        IPowerShellService powerShell,
        ISubscriptionService subscription)
    {
        _hardware = hardware;
        _log = log;
        _auth = auth;
        _powerShell = powerShell;
        _subscription = subscription;

        NavItems = new ObservableCollection<NavItem>
        {
            new("Accueil", NavPage.Home),
            new("Périphérique", NavPage.Peripheral),
            new("Drivers", NavPage.Drivers),
            new("Connexion", NavPage.Connection),
            new("Jeu", NavPage.Game),
            new("Optimisation", NavPage.Optimization),
            new("Son", NavPage.Sound),
            new("Compte / Abonnement", NavPage.Account),
            new("Paramètres", NavPage.Settings),
        };

        SelectedNavItem = NavItems[0];
    }

    public ObservableCollection<NavItem> NavItems { get; }

    public NavItem? SelectedNavItem
    {
        get => _selectedNavItem;
        set
        {
            if (!SetProperty(ref _selectedNavItem, value) || value is null)
                return;

            CurrentContent = CreatePage(value.Page);
        }
    }

    public object? CurrentContent
    {
        get => _currentContent;
        private set => SetProperty(ref _currentContent, value);
    }

    public ILogService Logs => _log;

    private object CreatePage(NavPage page) =>
        page switch
        {
            NavPage.Home => new HomeViewModel(_hardware, _log),
            NavPage.Peripheral => SimplePageViewModel.Peripheral(),
            NavPage.Drivers => SimplePageViewModel.Drivers(),
            NavPage.Connection => SimplePageViewModel.Connection(),
            NavPage.Game => SimplePageViewModel.Game(),
            NavPage.Optimization => new OptimizationViewModel(_log, _powerShell),
            NavPage.Sound => SimplePageViewModel.Sound(),
            NavPage.Account => new AccountViewModel(_auth, _subscription),
            NavPage.Settings => new SettingsViewModel(_log),
            _ => new HomeViewModel(_hardware, _log),
        };
}
