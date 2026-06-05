using System.Windows;
using System.Windows.Controls;
using PurpleBoost.ViewModels;

namespace PurpleBoost.Views;

public partial class AccountView : UserControl
{
    public AccountView()
    {
        InitializeComponent();
    }

    private void PwBox_OnPasswordChanged(object sender, RoutedEventArgs e)
    {
        if (DataContext is AccountViewModel vm)
            vm.Password = PwBox.Password;
    }
}
