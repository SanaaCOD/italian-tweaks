using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

namespace UnrealLauncher;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        ApplicationConfiguration.Initialize();
        Application.Run(new MainForm());
    }
}

internal sealed class MainForm : Form
{
    private readonly WebView2 _webView = new() { Dock = DockStyle.Fill };

    public MainForm()
    {
        Text = "Unreal Gaming Optimizer";
        StartPosition = FormStartPosition.CenterScreen;
        MinimumSize = new Size(1280, 720);
        Size = new Size(1600, 900);
        Icon = SystemIcons.Application;

        Controls.Add(_webView);
        Load += OnFormLoad;
    }

    private async void OnFormLoad(object? sender, EventArgs e)
    {
        Load -= OnFormLoad;

        var runtimeVersion = CoreWebView2Environment.GetAvailableBrowserVersionString();
        if (string.IsNullOrWhiteSpace(runtimeVersion))
        {
            MessageBox.Show(
                "Microsoft Edge WebView2 Runtime est requis.\n\n" +
                "Installez-le depuis :\nhttps://go.microsoft.com/fwlink/p/?LinkId=2124703\n\n" +
                "Puis relancez UnrealLauncher.exe.",
                Text,
                MessageBoxButtons.OK,
                MessageBoxIcon.Warning);
            Close();
            return;
        }

        var (appRoot, htmlPath) = AppPaths.ResolveUnrealHtml();
        if (htmlPath is null)
        {
            MessageBox.Show(
                "Fichier introuvable : unreal.html\n\n" +
                "Placez UnrealLauncher.exe dans le dossier PurpleBoost,\n" +
                "ou à côté du dossier contenant unreal.html (même niveau que assets/ et Scripts/).",
                Text,
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
            Close();
            return;
        }

        try
        {
            var userData = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "UnrealLauncher",
                "WebView2");
            Directory.CreateDirectory(userData);

            var env = await CoreWebView2Environment.CreateAsync(
                null,
                userData,
                new CoreWebView2EnvironmentOptions
                {
                    AllowSingleSignOnUsingOSPrimaryAccount = false,
                });

            await _webView.EnsureCoreWebView2Async(env);

            _webView.CoreWebView2.Settings.AreDevToolsEnabled = false;
            _webView.CoreWebView2.Settings.IsStatusBarEnabled = false;
            _webView.CoreWebView2.Settings.AreDefaultContextMenusEnabled = true;

            var fileUri = new Uri(htmlPath).AbsoluteUri;
            _webView.CoreWebView2.Navigate(fileUri);

            Text = $"Unreal Gaming Optimizer — {Path.GetFileName(appRoot)}";
        }
        catch (Exception ex)
        {
            MessageBox.Show(
                "Impossible d'initialiser WebView2.\n\n" + ex.Message,
                Text,
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
            Close();
        }
    }
}

internal static class AppPaths
{
    /// <summary>
    /// Remonte les dossiers parents jusqu'à trouver unreal.html (racine PurpleBoost / projet).
    /// </summary>
    public static (string appRoot, string? htmlPath) ResolveUnrealHtml()
    {
        var start = AppContext.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        var dir = start;

        for (var i = 0; i < 10; i++)
        {
            var candidate = Path.Combine(dir, "unreal.html");
            if (File.Exists(candidate))
                return (dir, Path.GetFullPath(candidate));

            var parent = Directory.GetParent(dir);
            if (parent is null)
                break;
            dir = parent.FullName;
        }

        var sibling = Path.GetFullPath(Path.Combine(start, "..", "unreal.html"));
        if (File.Exists(sibling))
            return (Path.GetDirectoryName(sibling)!, sibling);

        return (start, null);
    }
}
