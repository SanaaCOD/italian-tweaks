using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;

[ComImport, Guid("d39eed00-aefb-11d0-851a-00a0c90fdb04")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IAccessible {
    [PreserveSig] int accChildCount(out int pcountChildren);
    [return: MarshalAs(UnmanagedType.IDispatch)]
    object get_accChild([MarshalAs(UnmanagedType.Struct)] object varChild);
    [return: MarshalAs(UnmanagedType.BStr)]
    string get_accName([MarshalAs(UnmanagedType.Struct)] object varChild);
    int get_accRole([MarshalAs(UnmanagedType.Struct)] object varChild);
    int get_accState([MarshalAs(UnmanagedType.Struct)] object varChild);
    [return: MarshalAs(UnmanagedType.BStr)]
    string get_accDefaultAction([MarshalAs(UnmanagedType.Struct)] object varChild);
    void accDoDefaultAction([MarshalAs(UnmanagedType.Struct)] object varChild);
    void accSelect(int flagsSelect, [MarshalAs(UnmanagedType.Struct)] object varChild);
    void accLocation(out int pxLeft, out int pyTop, out int pcxWidth, out int pcyHeight, [MarshalAs(UnmanagedType.Struct)] object varChild);
}

public class NvidiaWin32Msaa {
    public const int BM_CLICK = 0x00F5;
    public const int BM_GETCHECK = 0x00F0;
    public const int BM_SETCHECK = 0x00F1;
    public const int BST_CHECKED = 1;
    public const int WM_COMMAND = 0x0111;
    public const int BN_CLICKED = 0;
    public const int OBJID_CLIENT = unchecked((int)0xFFFFFFFC);
    public const int STATE_SYSTEM_CHECKED = 0x10;
    public const int STATE_SYSTEM_SELECTED = 0x2;
    public const int SELFLAG_SELECT = 2;
    private static readonly Guid IID_IAccessible = new Guid("d39eed00-aefb-11d0-851a-00a0c90fdb04");
    private static readonly Regex CustomNameRx = new Regex(@"(Personnalis|Personnalise|avancée|avancee|\bCustom\b|Advanced)", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
    private static readonly Regex NextNameRx = new Regex(@"^(SUIVANT|Suivant|NEXT|&Suivant|&Next)$", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);

    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern IntPtr SetFocus(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hWnd, int Msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool IsWindowEnabled(IntPtr hWnd);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr hWnd, int nIndex);
    [DllImport("user32.dll")] public static extern int GetDlgCtrlID(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern IntPtr GetParent(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWndProc lpEnumFunc, IntPtr lParam);
    [DllImport("oleacc.dll")] public static extern int AccessibleObjectFromWindow(IntPtr hwnd, int dwId, ref Guid riid, [MarshalAs(UnmanagedType.IUnknown)] out object ppvObject);

    public delegate bool EnumWndProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr hWndParent, EnumWndProc lpEnumFunc, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }

    public class Win32ChildInfo {
        public IntPtr Hwnd;
        public string Text;
        public string ClassName;
        public RECT Rect;
        public int Style;
        public bool Visible;
        public bool Enabled;
        public int? CheckState;
        public int ControlId;
        public int ExStyle;
        public long ParentHwnd;
    }

    static readonly string[] LicenseAcceptNeedles = {
        "ACCEPTER ET CONTINUER", "Accepter et continuer",
        "ACCEPT AND CONTINUE", "Accept and Continue",
        "ACCEPTER", "Accept"
    };

    public class MsaaNodeInfo {
        public string Name;
        public int Role;
        public int State;
        public string DefaultAction;
        public string Location;
        public int Depth;
    }

    public static string GetWndText(IntPtr hwnd) {
        if (hwnd == IntPtr.Zero) return "";
        var sb = new StringBuilder(1024);
        GetWindowText(hwnd, sb, sb.Capacity);
        return sb.ToString();
    }

    public static string GetWndClass(IntPtr hwnd) {
        if (hwnd == IntPtr.Zero) return "";
        var sb = new StringBuilder(256);
        GetClassName(hwnd, sb, sb.Capacity);
        return sb.ToString();
    }

    public static List<Win32ChildInfo> EnumChildren(IntPtr root) {
        var list = new List<Win32ChildInfo>();
        if (root == IntPtr.Zero) return list;
        EnumChildWindows(root, (h, p) => {
            try {
                var info = new Win32ChildInfo { Hwnd = h };
                info.Text = GetWndText(h);
                info.ClassName = GetWndClass(h);
                info.Visible = IsWindowVisible(h);
                info.Enabled = IsWindowEnabled(h);
                RECT r;
                if (GetWindowRect(h, out r)) info.Rect = r;
                try { info.Style = GetWindowLong(h, -16); } catch { info.Style = 0; }
                try { info.ExStyle = GetWindowLong(h, -20); } catch { info.ExStyle = 0; }
                try {
                    var par = GetParent(h);
                    info.ParentHwnd = par != IntPtr.Zero ? par.ToInt64() : 0;
                } catch { info.ParentHwnd = 0; }
                try { info.ControlId = GetDlgCtrlID(h); } catch { info.ControlId = 0; }
                var cls = info.ClassName ?? "";
                if (cls.IndexOf("Button", StringComparison.OrdinalIgnoreCase) >= 0) {
                    try { info.CheckState = (int)SendMessage(h, BM_GETCHECK, IntPtr.Zero, IntPtr.Zero); } catch { }
                }
                list.Add(info);
            } catch { }
            return true;
        }, IntPtr.Zero);
        return list;
    }

    static bool NameIsCustom(string name) {
        return !string.IsNullOrEmpty(name) && CustomNameRx.IsMatch(name);
    }

    static bool NameIsNext(string name) {
        if (string.IsNullOrEmpty(name)) return false;
        var t = name.Trim();
        return NextNameRx.IsMatch(t) || t.Equals("Suivant", StringComparison.OrdinalIgnoreCase) || t.Equals("Next", StringComparison.OrdinalIgnoreCase);
    }

    static string FormatLocation(IAccessible acc, object child) {
        try {
            int l, t, w, h;
            acc.accLocation(out l, out t, out w, out h, child);
            return string.Format("L{0},T{1},W{2},H{3}", l, t, w, h);
        } catch { return ""; }
    }

    static IAccessible TryGetRootAccessible(IntPtr hwnd) {
        object obj;
        Guid guid = IID_IAccessible;
        int hr = AccessibleObjectFromWindow(hwnd, OBJID_CLIENT, ref guid, out obj);
        if (hr != 0 || obj == null) return null;
        return obj as IAccessible;
    }

    static bool WalkMsaaSelect(IAccessible acc, object child, int depth, int maxDepth, out string foundName, out string foundRole) {
        foundName = "";
        foundRole = "";
        if (acc == null || depth > maxDepth) return false;
        object id = child ?? (object)0;
        string name = "";
        try { name = acc.get_accName(id) ?? ""; } catch { }
        int role = 0;
        try { role = acc.get_accRole(id); } catch { }
        if (NameIsCustom(name)) {
            foundName = name;
            foundRole = role.ToString();
            try { acc.accDoDefaultAction(id); return true; } catch { }
            try { acc.accSelect(SELFLAG_SELECT, id); return true; } catch { }
        }
        int count = 0;
        try { acc.accChildCount(out count); } catch { count = 0; }
        for (int i = 1; i <= count; i++) {
            object ch = null;
            try { ch = acc.get_accChild((object)i); } catch { ch = null; }
            IAccessible sub = ch as IAccessible;
            if (sub != null) {
                if (WalkMsaaSelect(sub, null, depth + 1, maxDepth, out foundName, out foundRole)) return true;
            } else if (ch != null) {
                if (WalkMsaaSelect(acc, ch, depth + 1, maxDepth, out foundName, out foundRole)) return true;
            }
        }
        return false;
    }

    public static bool TryMsaaSelectCustom(IntPtr hwnd, out string foundName, out string foundRole) {
        foundName = "";
        foundRole = "";
        var root = TryGetRootAccessible(hwnd);
        if (root == null) return false;
        return WalkMsaaSelect(root, null, 0, 24, out foundName, out foundRole);
    }

    public static void CollectMsaaNodes(IntPtr hwnd, List<MsaaNodeInfo> nodes, int maxNodes) {
        var root = TryGetRootAccessible(hwnd);
        if (root == null) return;
        CollectMsaaWalk(root, null, 0, 20, nodes, maxNodes);
    }

    static void CollectMsaaWalk(IAccessible acc, object child, int depth, int maxDepth, List<MsaaNodeInfo> nodes, int maxNodes) {
        if (acc == null || depth > maxDepth || nodes.Count >= maxNodes) return;
        object id = child ?? (object)0;
        string name = "";
        try { name = acc.get_accName(id) ?? ""; } catch { }
        if (!string.IsNullOrEmpty(name) && (NameIsCustom(name) || name.IndexOf("Express", StringComparison.OrdinalIgnoreCase) >= 0 || NameIsNext(name))) {
            int role = 0, state = 0;
            string def = "";
            try { role = acc.get_accRole(id); } catch { }
            try { state = acc.get_accState(id); } catch { }
            try { def = acc.get_accDefaultAction(id) ?? ""; } catch { }
            nodes.Add(new MsaaNodeInfo {
                Name = name, Role = role, State = state,
                DefaultAction = def, Location = FormatLocation(acc, id), Depth = depth
            });
        }
        int count = 0;
        try { acc.accChildCount(out count); } catch { count = 0; }
        for (int i = 1; i <= count && nodes.Count < maxNodes; i++) {
            object ch = null;
            try { ch = acc.get_accChild((object)i); } catch { }
            IAccessible sub = ch as IAccessible;
            if (sub != null) CollectMsaaWalk(sub, null, depth + 1, maxDepth, nodes, maxNodes);
            else if (ch != null) CollectMsaaWalk(acc, ch, depth + 1, maxDepth, nodes, maxNodes);
        }
    }

    static bool IsButtonClass(string cls) {
        if (string.IsNullOrEmpty(cls)) return false;
        return cls.IndexOf("Button", StringComparison.OrdinalIgnoreCase) >= 0;
    }

    public static bool TryWin32SelectCustom(IntPtr rootHwnd, out IntPtr labelHwnd, out IntPtr radioHwnd) {
        labelHwnd = IntPtr.Zero;
        radioHwnd = IntPtr.Zero;
        var children = EnumChildren(rootHwnd);
        Win32ChildInfo labelInfo = null;
        foreach (var c in children) {
            if (!c.Visible || !c.Enabled) continue;
            if (!NameIsCustom(c.Text ?? "")) continue;
            if (labelInfo == null || (c.Text ?? "").Length > (labelInfo.Text ?? "").Length) labelInfo = c;
        }
        if (labelInfo == null) return false;
        labelHwnd = labelInfo.Hwnd;
        if (IsButtonClass(labelInfo.ClassName)) {
            radioHwnd = labelInfo.Hwnd;
            return true;
        }
        int labelMidY = (labelInfo.Rect.Top + labelInfo.Rect.Bottom) / 2;
        Win32ChildInfo bestRadio = null;
        int bestDx = int.MaxValue;
        foreach (var c in children) {
            if (!c.Visible || !c.Enabled) continue;
            if (!IsButtonClass(c.ClassName)) continue;
            int midY = (c.Rect.Top + c.Rect.Bottom) / 2;
            if (Math.Abs(midY - labelMidY) > 18) continue;
            if (c.Rect.Right > labelInfo.Rect.Left + 8) continue;
            int dx = labelInfo.Rect.Left - c.Rect.Right;
            if (dx < 0) dx = labelInfo.Rect.Left - c.Rect.Left;
            if (dx < bestDx) { bestDx = dx; bestRadio = c; }
        }
        if (bestRadio != null) { radioHwnd = bestRadio.Hwnd; return true; }
        foreach (var c in children) {
            if (!c.Visible || !c.Enabled) continue;
            if (!IsButtonClass(c.ClassName)) continue;
            if (!NameIsCustom(c.Text ?? "")) continue;
            radioHwnd = c.Hwnd;
            return true;
        }
        return false;
    }

    public static bool ClickWin32Button(IntPtr hwnd, IntPtr parentHwnd) {
        if (hwnd == IntPtr.Zero) return false;
        var cls = GetWndClass(hwnd);
        if (!IsButtonClass(cls)) return false;
        try {
            int chk = (int)SendMessage(hwnd, BM_GETCHECK, IntPtr.Zero, IntPtr.Zero);
            if (chk == 0) SendMessage(hwnd, BM_SETCHECK, new IntPtr(BST_CHECKED), IntPtr.Zero);
        } catch { }
        SendMessage(hwnd, BM_CLICK, IntPtr.Zero, IntPtr.Zero);
        if (parentHwnd != IntPtr.Zero) {
            try {
                int id = GetWindowLong(hwnd, -12) & 0xFFFF;
                if (id > 0) {
                    int code = BN_CLICKED | (id << 16);
                    SendMessage(parentHwnd, WM_COMMAND, new IntPtr(code), hwnd);
                }
            } catch { }
        }
        return true;
    }

    public static IntPtr FindNextButtonHwnd(IntPtr rootHwnd) {
        foreach (var c in EnumChildren(rootHwnd)) {
            if (!c.Visible || !c.Enabled) continue;
            if (NameIsNext(c.Text ?? "")) return c.Hwnd;
        }
        return IntPtr.Zero;
    }

    static string NormalizeTitle(string title) {
        if (string.IsNullOrEmpty(title)) return "";
        var t = title.ToLowerInvariant();
        t = t.Replace("\u2019", "").Replace("'", "").Replace("`", "");
        while (t.Contains("  ")) t = t.Replace("  ", " ");
        return t.Trim();
    }

    static bool TitleIsNvcleanstall(string title) {
        if (string.IsNullOrEmpty(title)) return false;
        return title.IndexOf("NVCleanstall", StringComparison.OrdinalIgnoreCase) >= 0
            || title.IndexOf("NVCleanInstall", StringComparison.OrdinalIgnoreCase) >= 0
            || title.IndexOf("TechPowerUp", StringComparison.OrdinalIgnoreCase) >= 0;
    }

    static bool TitleIsNvidiaInstallerRoot(string title) {
        if (string.IsNullOrEmpty(title) || TitleIsNvcleanstall(title)) return false;
        var n = NormalizeTitle(title);
        return n.IndexOf("programme d installation nvidia", StringComparison.Ordinal) >= 0
            || n.IndexOf("programme dinstallation nvidia", StringComparison.Ordinal) >= 0
            || n.IndexOf("nvidia installer", StringComparison.Ordinal) >= 0
            || n.IndexOf("pilote graphique nvidia", StringComparison.Ordinal) >= 0;
    }

    public static IntPtr FindNvidiaInstallerRootHwnd() {
        IntPtr found = IntPtr.Zero;
        EnumWindows((h, p) => {
            if (!IsWindowVisible(h)) return true;
            var title = GetWndText(h);
            if (!TitleIsNvidiaInstallerRoot(title)) return true;
            found = h;
            return false;
        }, IntPtr.Zero);
        return found;
    }

    public static void InvokeControlClick(IntPtr controlHwnd, IntPtr parentHwnd) {
        if (controlHwnd == IntPtr.Zero) return;
        SendMessage(controlHwnd, BM_CLICK, IntPtr.Zero, IntPtr.Zero);
        if (parentHwnd == IntPtr.Zero) return;
        int id = GetDlgCtrlID(controlHwnd);
        if (id <= 0) {
            try { id = GetWindowLong(controlHwnd, -12) & 0xFFFF; } catch { id = 0; }
        }
        if (id > 0) {
            int code = BN_CLICKED | (id << 16);
            SendMessage(parentHwnd, WM_COMMAND, new IntPtr(code), controlHwnd);
        }
    }

    static string NormalizeButtonText(string text) {
        if (string.IsNullOrEmpty(text)) return "";
        var t = text.Trim();
        if (t.StartsWith("&", StringComparison.Ordinal)) t = t.Substring(1).Trim();
        return NormalizeTitle(t);
    }

    public static Win32ChildInfo FindChildByTextContains(IntPtr rootHwnd, string[] needles) {
        if (rootHwnd == IntPtr.Zero || needles == null) return null;
        Win32ChildInfo best = null;
        int bestLen = 0;
        foreach (var c in EnumChildren(rootHwnd)) {
            if (!c.Visible || !c.Enabled) continue;
            var text = c.Text ?? "";
            var norm = NormalizeButtonText(text);
            foreach (var needle in needles) {
                if (string.IsNullOrEmpty(needle)) continue;
                var n = NormalizeButtonText(needle);
                if (norm.IndexOf(n, StringComparison.Ordinal) >= 0 || text.IndexOf(needle, StringComparison.OrdinalIgnoreCase) >= 0) {
                    if (text.Length > bestLen) {
                        best = c;
                        bestLen = text.Length;
                    }
                }
            }
        }
        return best;
    }

    public static Win32ChildInfo FindLicenseAcceptButton(IntPtr rootHwnd) {
        return FindChildByTextContains(rootHwnd, LicenseAcceptNeedles);
    }
}
