using System.IO;
using System.Reflection;
using System.Windows;
using Microsoft.Win32;
using PurpleBoost.Helpers;
using PurpleBoost.Models;
using PurpleBoost.Services;
using System.Windows.Input;

namespace PurpleBoost.ViewModels;

public sealed class SettingsViewModel : BaseViewModel
{
    private readonly ILogService _log;

    public SettingsViewModel(ILogService log)
    {
        _log = log;
        ExportLogsCommand = new RelayCommand(ExportLogs);

        ThemeText = "Sombre (smoke / néon violet)";
        LanguageText = "Français";
        LogsFolder = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "PurpleBoost",
            "Logs");

        try
        {
            Directory.CreateDirectory(LogsFolder);
        }
        catch
        {
            // ignore
        }

        AppVersion = ReadAppVersion();
    }

    public ICommand ExportLogsCommand { get; }

    public string ThemeText { get; }
    public string LanguageText { get; }
    public string LogsFolder { get; }
    public string AppVersion { get; }

    private static string ReadAppVersion()
    {
        try
        {
            var asm = Assembly.GetExecutingAssembly();
            var info = asm.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion;
            if (!string.IsNullOrWhiteSpace(info))
                return info;

            return asm.GetName().Version?.ToString() ?? "0.0.0";
        }
        catch
        {
            return "0.0.0";
        }
    }

    private void ExportLogs()
    {
        try
        {
            var dlg = new SaveFileDialog
            {
                Title = "Exporter les logs",
                Filter = "Fichiers texte (*.txt)|*.txt|Tous les fichiers (*.*)|*.*",
                FileName = $"purpleboost-logs-{DateTime.Now:yyyyMMdd-HHmmss}.txt",
            };

            if (dlg.ShowDialog() != true)
                return;

            File.WriteAllText(dlg.FileName, _log.ExportText());
            _log.Append(LogLevel.Info, $"Logs exportés : {dlg.FileName}");
            MessageBox.Show("Export terminé.", "PurpleBoost", MessageBoxButton.OK, MessageBoxImage.Information);
        }
        catch (Exception ex)
        {
            MessageBox.Show(ex.Message, "PurpleBoost — export", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }
}
