using System.Windows;
using PurpleBoost.Helpers;
using PurpleBoost.Models;
using PurpleBoost.Services;
using System.Windows.Input;

namespace PurpleBoost.ViewModels;

public sealed class OptimizationViewModel : BaseViewModel
{
    private readonly ILogService _log;
    private readonly IPowerShellService _powerShell;

    private bool _isRunning;
    private double _progress;
    private string _statusText = "En attente";

    public OptimizationViewModel(ILogService log, IPowerShellService powerShell)
    {
        _log = log;
        _powerShell = powerShell;
        TestOptimizationCommand = new RelayCommand(() => _ = RunTestAsync(), () => !IsRunning);
    }

    public ICommand TestOptimizationCommand { get; }

    public bool IsRunning
    {
        get => _isRunning;
        private set
        {
            if (!SetProperty(ref _isRunning, value))
                return;

            if (TestOptimizationCommand is RelayCommand rc)
                rc.RaiseCanExecuteChanged();
        }
    }

    public double Progress
    {
        get => _progress;
        private set => SetProperty(ref _progress, value);
    }

    public string StatusText
    {
        get => _statusText;
        private set => SetProperty(ref _statusText, value);
    }

    private async Task RunTestAsync()
    {
        var confirm = MessageBox.Show(
            "Cette optimisation peut modifier des paramètres Windows.\n\n"
            + "Pour l’instant, il s’agit d’un test simulé (aucun changement réel).\n\n"
            + "Continuer ?",
            "PurpleBoost — confirmation",
            MessageBoxButton.YesNo,
            MessageBoxImage.Warning);

        if (confirm != MessageBoxResult.Yes)
            return;

        IsRunning = true;
        Progress = 0;
        StatusText = "En cours";
        _log.Append(LogLevel.Pending, "Optimisation test lancée");

        try
        {
            for (var p = 0; p <= 100; p += 10)
            {
                Progress = p;
                await Task.Delay(140).ConfigureAwait(true);
            }

            StatusText = "Succès";
            _log.Append(LogLevel.Success, "Optimisation test terminée (simulation).");
        }
        catch (Exception ex)
        {
            StatusText = "Erreur";
            _log.Append(LogLevel.Error, $"Optimisation test : {ex.Message}");
        }
        finally
        {
            IsRunning = false;
            if (TestOptimizationCommand is RelayCommand rc)
                rc.RaiseCanExecuteChanged();
        }

        _ = _powerShell; // réserve : exécution réelle derrière confirmation + admin + logs fichier.
    }
}
