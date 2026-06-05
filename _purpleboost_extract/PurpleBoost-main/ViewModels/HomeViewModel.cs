using PurpleBoost.Helpers;
using PurpleBoost.Models;
using PurpleBoost.Services;
using System.Windows.Input;

namespace PurpleBoost.ViewModels;

public sealed class HomeViewModel : BaseViewModel
{
    private readonly IHardwareService _hardware;
    private readonly ILogService _log;

    private bool _isBusy;
    private string _cpuName = "—";
    private string _cpuUsage = HardwareSnapshot.MissingLabel;
    private string _gpuName = "—";
    private string _gpuUsage = HardwareSnapshot.MissingLabel;
    private string _ramTotal = "—";
    private string _ramUsage = HardwareSnapshot.MissingLabel;
    private string _cpuTemp = HardwareSnapshot.MissingLabel;
    private string _gpuTemp = HardwareSnapshot.MissingLabel;

    public HomeViewModel(IHardwareService hardware, ILogService log)
    {
        _hardware = hardware;
        _log = log;
        RefreshCommand = new RelayCommand(() => _ = RefreshAsync());
    }

    public ICommand RefreshCommand { get; }

    public bool IsBusy
    {
        get => _isBusy;
        private set => SetProperty(ref _isBusy, value);
    }

    public string CpuName
    {
        get => _cpuName;
        private set => SetProperty(ref _cpuName, value);
    }

    public string CpuUsage
    {
        get => _cpuUsage;
        private set => SetProperty(ref _cpuUsage, value);
    }

    public string GpuName
    {
        get => _gpuName;
        private set => SetProperty(ref _gpuName, value);
    }

    public string GpuUsage
    {
        get => _gpuUsage;
        private set => SetProperty(ref _gpuUsage, value);
    }

    public string RamTotal
    {
        get => _ramTotal;
        private set => SetProperty(ref _ramTotal, value);
    }

    public string RamUsage
    {
        get => _ramUsage;
        private set => SetProperty(ref _ramUsage, value);
    }

    public string CpuTemperature
    {
        get => _cpuTemp;
        private set => SetProperty(ref _cpuTemp, value);
    }

    public string GpuTemperature
    {
        get => _gpuTemp;
        private set => SetProperty(ref _gpuTemp, value);
    }

    public async Task RefreshAsync()
    {
        if (IsBusy)
            return;

        IsBusy = true;
        try
        {
            var s = await _hardware.GetSnapshotAsync().ConfigureAwait(true);
            CpuName = s.CpuName;
            CpuUsage = s.CpuUsage;
            GpuName = s.GpuName;
            GpuUsage = s.GpuUsage;
            RamTotal = s.RamTotal;
            RamUsage = s.RamUsage;
            CpuTemperature = s.CpuTemperature;
            GpuTemperature = s.GpuTemperature;

            _log.Append(LogLevel.Info, "Matériel rafraîchi (dashboard).");
        }
        catch (Exception ex)
        {
            _log.Append(LogLevel.Error, $"Erreur détection matérielle : {ex.Message}");
        }
        finally
        {
            IsBusy = false;
        }
    }
}
