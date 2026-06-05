using System.Runtime.InteropServices;

namespace NvidiaPanelClicker.Services;

internal static class Win32Helper
{
    public const int SwMaximize = 3;
    public const int SwRestore = 9;

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);

    [DllImport("user32.dll")]
    public static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool IsWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern IntPtr SendMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

    public const uint WmClose = 0x0010;
    public const uint WmSysCommand = 0x0112;
    public static readonly IntPtr ScClose = new(0xF060);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT
    {
        public int Left, Top, Right, Bottom;
    }

    [DllImport("user32.dll")]
    public static extern void SetCursorPos(int x, int y);

    [DllImport("user32.dll")]
    public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);

    [DllImport("user32.dll")]
    public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

    public const uint MouseeventfLeftdown = 0x0002;
    public const uint MouseeventfLeftup = 0x0004;
    public const byte VkReturn = 0x0D;
    public const uint KeyeventfKeyup = 0x0002;

    public static void ClickScreenPoint(int x, int y)
    {
        SetCursorPos(x, y);
        Thread.Sleep(80);
        mouse_event(MouseeventfLeftdown, 0, 0, 0, UIntPtr.Zero);
        Thread.Sleep(40);
        mouse_event(MouseeventfLeftup, 0, 0, 0, UIntPtr.Zero);
        Thread.Sleep(120);
    }

    public static void SendEnter()
    {
        keybd_event(VkReturn, 0, 0, UIntPtr.Zero);
        Thread.Sleep(50);
        keybd_event(VkReturn, 0, KeyeventfKeyup, UIntPtr.Zero);
        Thread.Sleep(80);
    }
}
