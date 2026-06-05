namespace UnrealLauncher;

internal sealed class NativeSplashForm : Form
{
    private readonly Label _statusLabel;
    private readonly System.Windows.Forms.Timer _spinTimer;
    private float _angle;

    public NativeSplashForm()
    {
        Text = "Unreal Gaming Optimizer";
        FormBorderStyle = FormBorderStyle.None;
        StartPosition = FormStartPosition.Manual;
        BackColor = ColorTranslator.FromHtml(PcTuneWindowSpec.BackgroundColor);
        ForeColor = Color.FromArgb(156, 163, 175);
        TopMost = true;
        ShowInTaskbar = true;
        DoubleBuffered = true;
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer, true);

        _statusLabel = new Label
        {
            AutoSize = false,
            TextAlign = ContentAlignment.MiddleCenter,
            Dock = DockStyle.Bottom,
            Height = 56,
            ForeColor = Color.FromArgb(156, 163, 175),
            BackColor = ColorTranslator.FromHtml(PcTuneWindowSpec.BackgroundColor),
            Font = new Font("Segoe UI", 10f, FontStyle.Regular),
            Text = "Démarrage…"
        };

        Controls.Add(_statusLabel);

        _spinTimer = new System.Windows.Forms.Timer { Interval = 16 };
        _spinTimer.Tick += (_, _) =>
        {
            _angle += 6f;
            if (_angle >= 360f) _angle -= 360f;
            Invalidate();
        };
        _spinTimer.Start();

        Load += (_, _) =>
        {
            Bounds = PcTuneWindowSpec.ComputeSplashBounds(Win32Window.GetPrimaryWorkArea());
        };
    }

    public void SetStatus(string? message)
    {
        if (InvokeRequired)
        {
            BeginInvoke(() => SetStatus(message));
            return;
        }
        _statusLabel.Text = string.IsNullOrWhiteSpace(message) ? "Démarrage…" : message.Trim();
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        var g = e.Graphics;
        g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;

        var cx = ClientSize.Width / 2;
        var cy = ClientSize.Height / 2 - 16;
        const int radius = 20;
        const int penWidth = 3;

        using var trackPen = new Pen(Color.FromArgb(40, 168, 85, 247), penWidth);
        g.DrawEllipse(trackPen, cx - radius, cy - radius, radius * 2, radius * 2);

        using var arcPen = new Pen(Color.FromArgb(192, 192, 132, 252), penWidth)
        {
            StartCap = System.Drawing.Drawing2D.LineCap.Round,
            EndCap = System.Drawing.Drawing2D.LineCap.Round
        };
        var rect = new Rectangle(cx - radius, cy - radius, radius * 2, radius * 2);
        g.DrawArc(arcPen, rect, _angle, 110);
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing) _spinTimer.Dispose();
        base.Dispose(disposing);
    }
}
