using System.Windows;
using PurpleBoost.Services;
using PurpleBoost.ViewModels;

namespace PurpleBoost.Views;

public partial class ShellWindow : Window
{
    public ShellWindow()
    {
        InitializeComponent();

        var log = new LogService();
        var auth = new AuthService();
        var subscription = new SubscriptionService(auth);

        DataContext = new ShellViewModel(
            new HardwareService(),
            log,
            auth,
            new PowerShellService(),
            subscription);
    }
}
