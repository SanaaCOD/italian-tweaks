using System.Diagnostics;

namespace UnrealLauncher;

internal sealed class HtaHostSession : IDisposable
{
    private const int HandoffPrepareMs = 300;
    private const int HandoffShowDelayMs = 50;
    private const int HandoffSplashHoldMs = 60;

    private static readonly string[] WindowTitles =
    [
        "Unreal Gaming Optimizer",
        "Unreal",
    ];

    private readonly string _appRoot;
    private readonly string _htaPath;
    private readonly NativeSplashForm _splash;
    private readonly Rectangle _mainBounds;
    private readonly System.Windows.Forms.Timer _pollTimer;
    private readonly System.Windows.Forms.Timer _hideTimer;

    private Process? _process;
    private IntPtr _htaHwnd;
    private string _lastPhase = "";
    private bool _handedOff;

    public HtaHostSession(string appRoot, string htaPath, NativeSplashForm splash, Rectangle mainBounds)
    {
        _appRoot = appRoot;
        _htaPath = htaPath;
        _splash = splash;
        _mainBounds = mainBounds;

        _hideTimer = new System.Windows.Forms.Timer { Interval = 30 };
        _hideTimer.Tick += (_, _) => TryKeepHtaHidden();

        _pollTimer = new System.Windows.Forms.Timer { Interval = 90 };
        _pollTimer.Tick += (_, _) => PollLaunchState();
    }

    public void Start()
    {
        var statePath = LaunchStatePaths.StateFile(_appRoot);
        try
        {
            var dir = Path.GetDirectoryName(statePath);
            if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
            File.WriteAllText(statePath,
                $$"""{"phase":"starting","message":"Initialisation…","w":{{_mainBounds.Width}},"h":{{_mainBounds.Height}},"ts":0}""");
        }
        catch { /* best effort */ }

        var sysRoot = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
        var mshta = Path.Combine(sysRoot, "System32", "mshta.exe");
        if (!File.Exists(mshta)) mshta = "mshta.exe";

        var args = "\"" + _htaPath + "\" --base-dir \"" + _appRoot + "\" --launcher-mode"
            + " --window-width " + _mainBounds.Width
            + " --window-height " + _mainBounds.Height;

        _process = Process.Start(new ProcessStartInfo
        {
            FileName = mshta,
            Arguments = args,
            WorkingDirectory = _appRoot,
            UseShellExecute = false,
        });

        if (_process is { HasExited: false })
            LaunchSessionStore.Write(_appRoot, _process.Id);

        _hideTimer.Start();
        _pollTimer.Start();
    }

    private void EnsureHtaHwnd()
    {
        if (_htaHwnd == IntPtr.Zero)
            _htaHwnd = Win32Window.FindHtaWindow(WindowTitles);
    }

    private void TryKeepHtaHidden()
    {
        if (_handedOff) return;
        EnsureHtaHwnd();
        if (_htaHwnd == IntPtr.Zero) return;
        Win32Window.Hide(_htaHwnd);
        Win32Window.PreparePcTuneHostHidden(_htaHwnd, _mainBounds);
    }

    private void PollLaunchState()
    {
        if (_handedOff) return;

        var path = LaunchStatePaths.StateFile(_appRoot);
        if (!File.Exists(path)) return;

        string json;
        try { json = File.ReadAllText(path); }
        catch { return; }

        var state = LaunchState.TryParse(json);
        if (state is null || string.IsNullOrWhiteSpace(state.Phase)) return;

        var phase = state.Phase.Trim().ToLowerInvariant();
        if (phase == _lastPhase && phase is not ("loading" or "ready")) return;
        _lastPhase = phase;

        switch (phase)
        {
            case "auth":
                HandoffForAuth();
                break;
            case "loading":
                ShowSplashOverHta(state.Message);
                break;
            case "ready":
                BeginHandoffToApplication();
                break;
            case "error":
                _splash.SetStatus(state.Message ?? "Erreur de démarrage.");
                break;
            default:
                if (!string.IsNullOrWhiteSpace(state.Message))
                    _splash.SetStatus(state.Message);
                break;
        }
    }

    private void ShowSplashOverHta(string? message)
    {
        EnsureHtaHwnd();
        if (_htaHwnd != IntPtr.Zero)
            Win32Window.Hide(_htaHwnd);

        if (!_splash.Visible) _splash.Show();
        _splash.TopMost = true;
        _splash.BringToFront();
        _splash.SetStatus(message);
    }

    private void HandoffForAuth()
    {
        _hideTimer.Stop();
        EnsureHtaHwnd();
        _splash.Hide();
        _splash.TopMost = false;
        if (_htaHwnd == IntPtr.Zero) return;
        Win32Window.ShowPcTuneHost(_htaHwnd, _mainBounds);
    }

    private void BeginHandoffToApplication()
    {
        if (_handedOff) return;
        _handedOff = true;
        _pollTimer.Stop();
        _hideTimer.Stop();

        EnsureHtaHwnd();

        _splash.Show();
        _splash.TopMost = true;
        _splash.BringToFront();
        _splash.SetStatus("Ouverture…");

        if (_htaHwnd == IntPtr.Zero)
        {
            FinishAfterHandoff();
            return;
        }

        Win32Window.Hide(_htaHwnd);
        Win32Window.PreparePcTuneHostHidden(_htaHwnd, _mainBounds);

        var prepareTimer = new System.Windows.Forms.Timer { Interval = HandoffPrepareMs };
        prepareTimer.Tick += (_, _) =>
        {
            prepareTimer.Stop();
            prepareTimer.Dispose();
            Win32Window.ShowPcTuneHost(_htaHwnd, _mainBounds);

            var holdTimer = new System.Windows.Forms.Timer { Interval = HandoffSplashHoldMs };
            holdTimer.Tick += (_, _) =>
            {
                holdTimer.Stop();
                holdTimer.Dispose();
                FinishAfterHandoff();
            };
            holdTimer.Start();
        };
        prepareTimer.Start();
    }

    private void FinishAfterHandoff()
    {
        _splash.Hide();
        _splash.TopMost = false;
        _splash.ShowInTaskbar = false;

        if (_process is { HasExited: false })
        {
            LaunchSessionStore.WriteMshtaOnly(_appRoot, _process.Id);
            InstanceLock.WriteMshta(_process.Id);
            StartupTrace.LogSession(_appRoot, _htaPath, _mainBounds, "handoff_ready", mshtaPid: _process.Id);
        }

        Application.Exit();
    }

    public void Dispose()
    {
        _pollTimer.Dispose();
        _hideTimer.Dispose();
        try
        {
            if (!_handedOff && _process is { HasExited: false })
            {
                _process.Kill(entireProcessTree: true);
                LaunchSessionStore.Clear(_appRoot);
                InstanceLock.Clear();
            }
        }
        catch { /* ignore */ }
        _process?.Dispose();
    }
}
