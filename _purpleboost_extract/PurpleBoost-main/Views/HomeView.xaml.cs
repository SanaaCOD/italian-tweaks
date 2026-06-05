using System.Windows.Controls;
using PurpleBoost.ViewModels;

namespace PurpleBoost.Views;

public partial class HomeView : UserControl
{
    public HomeView()
    {
        InitializeComponent();
    }

    private async void HomeView_OnLoaded(object sender, System.Windows.RoutedEventArgs e)
    {
        if (DataContext is HomeViewModel vm)
            await vm.RefreshAsync().ConfigureAwait(true);
    }
}
