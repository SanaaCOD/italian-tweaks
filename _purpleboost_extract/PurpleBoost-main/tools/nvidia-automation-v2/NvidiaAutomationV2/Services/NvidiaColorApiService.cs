using System.Runtime.InteropServices;
using System.Text;
using NvidiaAutomationV2.Models;

namespace NvidiaAutomationV2.Services;

/// <summary>
/// Digital Vibrance via NVAPI (nvapi64.dll) — diagnostic displayId + DVC (Get/SetDVCLevel).
/// </summary>
public sealed class NvidiaColorApiService : IDisposable
{
    public const int TargetDigitalVibrancePanelPercent = 80;

    /// <summary>Valeur brute NVAPI calibrée : PanelPercent ≈ 50 + Raw * 0.8 → 80 % panneau.</summary>
    public const int TargetDigitalVibranceRawCalibrated = 38;

    /// <summary>Alias conservé pour compatibilité.</summary>
    public const int TargetVibrancePercent = TargetDigitalVibrancePanelPercent;

    private const int NvApiRawTolerance = 1;

    private const int NvapiOk = 0;
    private const int MaxPhysicalGpus = 64;
    private const int MaxDisplayEnum = 32;
    private const int NvColorCmdGet = 1;
    private const int NvColorCmdSet = 2;

    private delegate IntPtr NvapiQueryInterfaceDelegate(uint id);
    private delegate int NvapiInitializeDelegate();
    private delegate int NvapiUnloadDelegate();
    private delegate int NvapiGetErrorMessageDelegate(int nvapiStatus, [MarshalAs(UnmanagedType.LPStr)] StringBuilder message);
    private delegate int NvapiEnumPhysicalGpusDelegate([Out] IntPtr[] gpuHandles, out uint gpuCount);
    private delegate int NvapiGpuGetConnectedDisplayIdsDelegate(IntPtr gpuHandle, IntPtr displayIds, ref uint displayIdCount, uint flags);
    private delegate int NvapiEnumNvidiaDisplayHandleDelegate(int thisEnum, out IntPtr displayHandle);
    private delegate int NvapiGetAssociatedNvidiaDisplayHandleDelegate([MarshalAs(UnmanagedType.LPStr)] string displayName, out IntPtr displayHandle);
    private delegate int NvapiGetAssociatedNvidiaDisplayNameDelegate(IntPtr displayHandle, [MarshalAs(UnmanagedType.LPStr)] StringBuilder displayName);
    private delegate int NvapiDispGetDisplayIdByDisplayNameDelegate([MarshalAs(UnmanagedType.LPStr)] string displayName, out uint displayId);
    private delegate int NvapiDispGetGdiPrimaryDisplayIdDelegate(out uint displayId);
    private delegate int NvapiGetAssociatedDisplayOutputIdDelegate(IntPtr displayHandle, out int outputId);
    private delegate int NvapiGetDvcInfoDelegate(IntPtr displayHandle, int outputId, ref NvDisplayDvcInfo info);
    private delegate int NvapiSetDvcLevelDelegate(IntPtr displayHandle, int outputId, int level);
    private delegate int NvapiGetDvcInfoExDelegate(IntPtr displayHandle, int outputId, ref NvDisplayDvcInfoEx info);
    private delegate int NvapiSetDvcLevelExDelegate(IntPtr displayHandle, int outputId, ref NvDisplayDvcInfoEx info);
    private delegate int NvapiDispColorControlDelegate(uint displayId, ref NvColorDataV5 colorData);

    [StructLayout(LayoutKind.Sequential)]
    private struct NvDisplayDvcInfo
    {
        public uint version;
        public int currentLevel;
        public int minLevel;
        public int maxLevel;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NvDisplayDvcInfoEx
    {
        public uint version;
        public int currentLevel;
        public int minLevel;
        public int maxLevel;
        public int defaultLevel;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NvGpuDisplayIds
    {
        public uint version;
        public int connectorType;
        public uint displayId;
        public uint flags;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NvColorDataV5
    {
        public uint version;
        public ushort size;
        public byte cmd;
        public byte colorFormat;
        public byte colorimetry;
        public byte dynamicRange;
        public byte bpc;
        public byte colorSelectionPolicy;
        public byte depth;
    }

    private sealed class NvidiaDisplayCandidate
    {
        public uint DisplayId { get; init; }
        public IntPtr DisplayHandle { get; init; }
        public string Source { get; init; } = "";
        public string Name { get; init; } = "";
        public bool Active { get; init; }
        public bool Connected { get; init; }
        public bool GdiPrimary { get; init; }
        public int GpuIndex { get; init; } = -1;
    }

    /// <summary>Estimation panneau calibrée (logs uniquement) : PanelPercent ≈ 50 + Raw * 0.8.</summary>
    public static int EstimatePanelPercentFromCalibratedRaw(int raw)
    {
        raw = Math.Clamp(raw, -100, 100);
        return Math.Clamp((int)Math.Round(50 + raw * 0.8, MidpointRounding.AwayFromZero), 0, 100);
    }

    private sealed class DvcReadResult
    {
        public bool Ok { get; init; }
        public int RawValue { get; init; }
        public int PanelPercent { get; init; }
        public NvDisplayDvcInfo LegacyInfo { get; init; }
        public NvDisplayDvcInfoEx ExInfo { get; init; }
        public bool UseEx { get; init; }
        public IntPtr Handle { get; init; }
        public int OutputId { get; init; }
        public uint DisplayId { get; init; }
        public string Path { get; init; } = "";
        public uint DvcStructVersion { get; init; }
    }

    private IntPtr _module;
    private NvapiQueryInterfaceDelegate? _queryInterface;
    private NvapiInitializeDelegate? _initialize;
    private NvapiUnloadDelegate? _unload;
    private NvapiGetErrorMessageDelegate? _getErrorMessage;
    private NvapiEnumPhysicalGpusDelegate? _enumPhysicalGpus;
    private NvapiGpuGetConnectedDisplayIdsDelegate? _getConnectedDisplayIds;
    private NvapiEnumNvidiaDisplayHandleDelegate? _enumDisplay;
    private NvapiGetAssociatedNvidiaDisplayHandleDelegate? _getAssociatedDisplay;
    private NvapiGetAssociatedNvidiaDisplayNameDelegate? _getAssociatedDisplayName;
    private NvapiDispGetDisplayIdByDisplayNameDelegate? _getDisplayIdByName;
    private NvapiDispGetGdiPrimaryDisplayIdDelegate? _getGdiPrimaryDisplayId;
    private NvapiGetAssociatedDisplayOutputIdDelegate? _getAssociatedOutputId;
    private NvapiGetDvcInfoDelegate? _getDvcInfo;
    private NvapiSetDvcLevelDelegate? _setDvcLevel;
    private NvapiGetDvcInfoExDelegate? _getDvcInfoEx;
    private NvapiSetDvcLevelExDelegate? _setDvcLevelEx;
    private NvapiDispColorControlDelegate? _dispColorControl;

    private bool _initialized;
    private uint _gdiPrimaryDisplayId;
    private readonly List<NvidiaDisplayCandidate> _displays = new();

    /// <summary>Applique l'éclat numérique calibré 80 % panneau (raw 38 fixe, verrouillé).</summary>
    public StepResult ApplyDigitalVibrance80()
    {
        FileLogger.Info("Digital Vibrance calibrated mode");
        FileLogger.Info("Calling ApplyDigitalVibrance80()");
        FileLogger.Info("Target panel percent: " + TargetDigitalVibrancePanelPercent);
        FileLogger.Info("Digital Vibrance final raw value sent: " + TargetDigitalVibranceRawCalibrated);

        var step = SetDigitalVibranceRawForTest(TargetDigitalVibranceRawCalibrated);
        if (step.Status == StepStatus.Success.ToString() && step.Verified)
        {
            FileLogger.Info("Digital Vibrance 80 applied");
            return StepResult.Ok("Éclat numérique 80%", true);
        }

        return step;
    }

    public StepResult ApplyDigitalVibrance() => ApplyDigitalVibrance80();

    /// <summary>Envoi brut NVAPI (SetDVCLevel) — valeur exacte, sans conversion. Appelé uniquement par ApplyDigitalVibrance80.</summary>
    public StepResult SetDigitalVibranceRawForTest(int rawValue)
    {
        if (rawValue != TargetDigitalVibranceRawCalibrated)
            return StepResult.Fail("Digital Vibrance : seule la valeur calibrée " + TargetDigitalVibranceRawCalibrated + " est autorisée");

        var requestedRaw = TargetDigitalVibranceRawCalibrated;

        if (!EnsureNvApiInitialized())
            return _lastInitFail ?? StepResult.Fail("NVAPI non initialisé");

        EnumerateNvidiaDisplays();
        if (_displays.Count == 0)
            return FailNvapi("Aucun écran Nvidia détecté", -3);

        if (!TryResolveDvcApplyTarget(out var handle, out var outputId, out var path))
            return FailNvapi("Impossible de résoudre la cible DVC Nvidia", _lastDvcErrorCode);

        var finalRaw = requestedRaw;
        FileLogger.Info("Final raw value sent to NVAPI: " + finalRaw);

        if (finalRaw != requestedRaw)
        {
            FileLogger.Info("ERREUR: finalRaw modifié (" + finalRaw + " != " + requestedRaw + ")");
            return StepResult.Fail("Digital Vibrance : valeur brute modifiée avant envoi");
        }

        if (_setDvcLevel == null)
            return StepResult.Fail("SetDVCLevel non disponible");

        var code = _setDvcLevel(handle, outputId, finalRaw);
        FileLogger.Info("SetDVCLevel path=" + path + " status=" + code + " raw=" + finalRaw + " " + FormatNvapi(code));
        if (code != NvapiOk)
            return FailNvapi("SetDVCLevel échec", code);

        if (finalRaw == TargetDigitalVibranceRawCalibrated)
            FileLogger.Info("Digital Vibrance RAW 38 sent");

        Thread.Sleep(300);
        LogOptionalReadback(handle, outputId, requestedRaw);

        return StepResult.Ok("Éclat numérique 80%", true);
    }

    private StepResult? _lastInitFail;

    private bool EnsureNvApiInitialized()
    {
        if (_initialized && _setDvcLevel != null)
            return true;

        if (!LoadNvApiModule())
        {
            _lastInitFail = FailNvapi("nvapi64.dll introuvable", -1);
            return false;
        }

        if (_initialize == null)
        {
            _lastInitFail = FailNvapi("NvAPI_Initialize absent", -2);
            return false;
        }

        var initCode = _initialize();
        if (initCode != NvapiOk)
        {
            _lastInitFail = FailNvapi("NvAPI_Initialize", initCode);
            return false;
        }

        _initialized = true;
        FileLogger.Info("NVAPI initialized");
        return true;
    }

    private bool TryResolveDvcApplyTarget(out IntPtr handle, out int outputId, out string path)
    {
        handle = IntPtr.Zero;
        outputId = 0;
        path = "";

        foreach (var candidate in OrderCandidatesForDvc())
        {
            if (candidate.DisplayId != 0)
            {
                handle = IntPtr.Zero;
                outputId = unchecked((int)candidate.DisplayId);
                path = candidate.Source + " displayId=0x" + candidate.DisplayId.ToString("X8");
                FileLogger.Info("DVC apply target: " + path);
                return true;
            }

            if (candidate.DisplayHandle != IntPtr.Zero)
            {
                handle = candidate.DisplayHandle;
                outputId = 0;
                path = candidate.Source + " handle=0x" + handle.ToInt64();
                FileLogger.Info("DVC apply target: " + path);
                return true;
            }
        }

        return false;
    }

    private void LogOptionalReadback(IntPtr handle, int outputId, int expectedRaw)
    {
        if (_getDvcInfo == null) return;

        var info = new NvDisplayDvcInfo { version = MakeNvapiVersionAlt(1, (uint)Marshal.SizeOf<NvDisplayDvcInfo>()) };
        var code = _getDvcInfo(handle, outputId, ref info);
        if (code != NvapiOk)
        {
            info.version = MakeNvapiVersion(1, (uint)Marshal.SizeOf<NvDisplayDvcInfo>());
            code = _getDvcInfo(handle, outputId, ref info);
        }

        if (code == NvapiOk)
            FileLogger.Info("Readback optional apiLevel=" + info.currentLevel + " (expected " + expectedRaw + ")");
    }

    private int _lastDvcErrorCode = -4;

    private void EnumerateNvidiaDisplays()
    {
        _displays.Clear();
        _gdiPrimaryDisplayId = 0;

        if (_getGdiPrimaryDisplayId != null)
        {
            var st = _getGdiPrimaryDisplayId(out _gdiPrimaryDisplayId);
            FileLogger.Info("GDI primary displayId: 0x" + _gdiPrimaryDisplayId.ToString("X8") + " status=" + st + " " + FormatNvapi(st));
            if (st == NvapiOk && _gdiPrimaryDisplayId != 0)
            {
                AddDisplay(_gdiPrimaryDisplayId, IntPtr.Zero, "GDI primary", "", true, true, true);
            }
        }
        else
        {
            FileLogger.Info("GDI primary displayId: NvAPI_DISP_GetGDIPrimaryDisplayId non résolu");
        }

        var display = new DisplayModeService();
        display.FindPrimaryDisplay();
        var primaryName = display.PrimaryDeviceName;
        FileLogger.Info("Windows primary device: " + primaryName);

        if (_getDisplayIdByName != null)
        {
            var idSt = _getDisplayIdByName(primaryName, out var byNameId);
            FileLogger.Info("GetDisplayIdByDisplayName(" + primaryName + ") id=0x" + byNameId.ToString("X8") + " status=" + idSt + " " + FormatNvapi(idSt));
            if (idSt == NvapiOk && byNameId != 0)
                AddDisplay(byNameId, IntPtr.Zero, "display name", primaryName, true, true, byNameId == _gdiPrimaryDisplayId);
        }

        if (_enumPhysicalGpus != null && _getConnectedDisplayIds != null)
        {
            var gpuHandles = new IntPtr[MaxPhysicalGpus];
            var gpuSt = _enumPhysicalGpus(gpuHandles, out var gpuCount);
            FileLogger.Info("EnumPhysicalGPUs status=" + gpuSt + " count=" + gpuCount + " " + FormatNvapi(gpuSt));
            if (gpuSt == NvapiOk)
            {
                for (var g = 0; g < gpuCount && g < MaxPhysicalGpus; g++)
                {
                    var gpu = gpuHandles[g];
                    if (gpu == IntPtr.Zero) continue;
                    EnumerateGpuDisplays(gpu, (int)g);
                }
            }
        }

        if (_enumDisplay != null)
        {
            for (var i = 0; i < MaxDisplayEnum; i++)
            {
                if (_enumDisplay(i, out var h) != NvapiOk || h == IntPtr.Zero) break;
                var name = GetDisplayName(h);
                AddHandleDisplay(h, "enum " + i, name, _gdiPrimaryDisplayId);
            }
        }

        if (_getAssociatedDisplay != null)
        {
            var st = _getAssociatedDisplay(primaryName, out var associated);
            FileLogger.Info("GetAssociatedNvidiaDisplayHandle status=" + st + " handle=" + associated.ToInt64());
            if (st == NvapiOk && associated != IntPtr.Zero)
                AddHandleDisplay(associated, "associated " + primaryName, primaryName, _gdiPrimaryDisplayId);
        }

        var summary = string.Join(", ", _displays.Select(d =>
            "0x" + d.DisplayId.ToString("X8") +
            (d.GdiPrimary ? "[primary]" : "") +
            (d.Active ? "[active]" : "") +
            (d.Connected ? "[connected]" : "") +
            " src=" + d.Source));
        FileLogger.Info("Enumerated Nvidia displayIds: " + summary);
    }

    private void EnumerateGpuDisplays(IntPtr gpuHandle, int gpuIndex)
    {
        uint count = 0;
        var st = _getConnectedDisplayIds!(gpuHandle, IntPtr.Zero, ref count, 0);
        if (st != NvapiOk || count == 0)
        {
            FileLogger.Info("GPU[" + gpuIndex + "] GetConnectedDisplayIds(count) status=" + st + " " + FormatNvapi(st));
            return;
        }

        var structSize = Marshal.SizeOf<NvGpuDisplayIds>();
        var bytes = (int)(count * structSize);
        var ptr = Marshal.AllocHGlobal(bytes);
        try
        {
            var ver = MakeNvapiVersion(3, (uint)structSize);
            for (var i = 0; i < count; i++)
            {
                var blank = new NvGpuDisplayIds { version = ver };
                Marshal.StructureToPtr(blank, ptr + i * structSize, false);
            }

            st = _getConnectedDisplayIds(gpuHandle, ptr, ref count, 0);
            if (st != NvapiOk)
            {
                FileLogger.Info("GPU[" + gpuIndex + "] GetConnectedDisplayIds status=" + st + " " + FormatNvapi(st));
                return;
            }

            for (var i = 0; i < count; i++)
            {
                var entry = Marshal.PtrToStructure<NvGpuDisplayIds>(ptr + i * Marshal.SizeOf<NvGpuDisplayIds>());
                var active = (entry.flags & 0x4) != 0;
                var connected = (entry.flags & 0x40) != 0;
                var osVisible = (entry.flags & 0x10) != 0;
                FileLogger.Info(
                    "displayId=0x" + entry.displayId.ToString("X8") +
                    " gpu=" + gpuIndex +
                    " active=" + active +
                    " connected=" + connected +
                    " osVisible=" + osVisible +
                    " connector=" + entry.connectorType);

                if (entry.displayId != 0)
                {
                    AddDisplay(entry.displayId, IntPtr.Zero, "GPU[" + gpuIndex + "] connected", "",
                        active, connected || osVisible, entry.displayId == _gdiPrimaryDisplayId, gpuIndex);
                }
            }
        }
        finally
        {
            Marshal.FreeHGlobal(ptr);
        }
    }

    private void AddHandleDisplay(IntPtr handle, string source, string name, uint gdiPrimaryId)
    {
        uint displayId = 0;
        if (_getDisplayIdByName != null && !string.IsNullOrEmpty(name))
        {
            var st = _getDisplayIdByName(name, out displayId);
            if (st != NvapiOk) displayId = 0;
        }

        if (displayId == 0 && _getAssociatedOutputId != null && _getAssociatedOutputId(handle, out var outputId) == NvapiOk)
            displayId = unchecked((uint)outputId);

        if (displayId != 0)
            AddDisplay(displayId, handle, source, name, true, true, displayId == gdiPrimaryId);
        else if (handle != IntPtr.Zero && !_displays.Any(d => d.DisplayHandle == handle))
        {
            _displays.Add(new NvidiaDisplayCandidate
            {
                DisplayId = 0,
                DisplayHandle = handle,
                Source = source + " (handle only)",
                Name = name,
                Active = true,
                Connected = true,
                GdiPrimary = false
            });
            FileLogger.Info("display handle=0x" + handle.ToInt64() + " (no displayId) source=" + source);
        }
        else
            FileLogger.Info("Handle 0x" + handle.ToInt64() + " (" + source + ") sans displayId résolu");
    }

    private void AddDisplay(uint displayId, IntPtr handle, string source, string name, bool active, bool connected, bool gdiPrimary, int gpuIndex = -1)
    {
        if (displayId == 0) return;
        if (_displays.Any(d => d.DisplayId == displayId))
            return;

        _displays.Add(new NvidiaDisplayCandidate
        {
            DisplayId = displayId,
            DisplayHandle = handle,
            Source = source,
            Name = name,
            Active = active,
            Connected = connected,
            GdiPrimary = gdiPrimary,
            GpuIndex = gpuIndex
        });

        FileLogger.Info(
            "displayId=0x" + displayId.ToString("X8") +
            " name=" + (string.IsNullOrEmpty(name) ? "-" : name) +
            " active=" + active +
            " primary=" + gdiPrimary +
            " source=" + source);
    }

    private string GetDisplayName(IntPtr handle)
    {
        if (_getAssociatedDisplayName == null) return "";
        var sb = new StringBuilder(128);
        return _getAssociatedDisplayName(handle, sb) == NvapiOk ? sb.ToString() : "";
    }

    private IEnumerable<NvidiaDisplayCandidate> OrderCandidatesForDvc()
    {
        return _displays
            .OrderByDescending(d => d.DisplayHandle != IntPtr.Zero)
            .ThenByDescending(d => d.GdiPrimary)
            .ThenByDescending(d => d.Active && d.Connected)
            .ThenBy(d => d.GpuIndex < 0 ? 1 : 0);
    }

    private NvidiaDisplayCandidate? FindCandidate(uint displayId) =>
        _displays.FirstOrDefault(d => d.DisplayId == displayId);

    private void TryColorControlGet(uint displayId)
    {
        if (_dispColorControl == null || displayId == 0) return;

        var color = CreateColorDataGet();
        var code = _dispColorControl(displayId, ref color);
        FileLogger.Info("NvAPI_Disp_ColorControl status: " + code + " " + FormatNvapi(code));
        if (code != NvapiOk)
            FileLogger.Info("NvAPI error message: " + GetNvapiErrorMessage(code));
    }

    private DvcReadResult? TryReadDvc(NvidiaDisplayCandidate candidate, uint preferredVersion = 0)
    {
        if (_getDvcInfo != null)
        {
            foreach (var (handle, outputId, path) in EnumerateDvcTargets(candidate))
            {
                foreach (var ver in BuildDvcVersionCandidates<NvDisplayDvcInfo>(1, preferredVersion))
                {
                    var copy = new NvDisplayDvcInfo { version = ver };
                    var code = _getDvcInfo(handle, outputId, ref copy);
                    FileLogger.Info("GetDVCInfo " + path + " ver=0x" + ver.ToString("X") + " status=" + code + " " + FormatNvapi(code));
                    if (code == NvapiOk)
                        return BuildDvcReadResult(copy, handle, outputId, candidate.DisplayId, path, ver, useEx: false);
                    _lastDvcErrorCode = code;
                    if (code != -9) break;
                }
            }
        }

        if (_getDvcInfoEx != null)
        {
            foreach (var (handle, outputId, path) in EnumerateDvcTargets(candidate))
            {
                foreach (var ver in BuildDvcVersionCandidates<NvDisplayDvcInfoEx>(2, preferredVersion))
                {
                    var copy = new NvDisplayDvcInfoEx { version = ver };
                    var code = _getDvcInfoEx(handle, outputId, ref copy);
                    FileLogger.Info("GetDVCInfoEx " + path + " ver=0x" + ver.ToString("X") + " status=" + code + " " + FormatNvapi(code));
                    if (code == NvapiOk)
                        return BuildDvcReadResult(copy, handle, outputId, candidate.DisplayId, path, ver, useEx: true);
                    _lastDvcErrorCode = code;
                    if (code != -9) break;
                }
            }
        }

        return null;
    }

    private static DvcReadResult BuildDvcReadResult(
        NvDisplayDvcInfo info,
        IntPtr handle,
        int outputId,
        uint displayId,
        string path,
        uint structVersion,
        bool useEx)
    {
        var panel = EstimatePanelPercentFromCalibratedRaw(info.currentLevel);
        return new DvcReadResult
        {
            Ok = true,
            RawValue = info.currentLevel,
            PanelPercent = panel,
            LegacyInfo = info,
            UseEx = useEx,
            Handle = handle,
            OutputId = outputId,
            DisplayId = displayId,
            Path = path,
            DvcStructVersion = structVersion
        };
    }

    private static DvcReadResult BuildDvcReadResult(
        NvDisplayDvcInfoEx infoEx,
        IntPtr handle,
        int outputId,
        uint displayId,
        string path,
        uint structVersion,
        bool useEx)
    {
        var scale = new NvDisplayDvcInfo
        {
            minLevel = infoEx.minLevel,
            maxLevel = infoEx.maxLevel,
            currentLevel = infoEx.currentLevel
        };
        var panel = EstimatePanelPercentFromCalibratedRaw(infoEx.currentLevel);
        return new DvcReadResult
        {
            Ok = true,
            RawValue = infoEx.currentLevel,
            PanelPercent = panel,
            ExInfo = infoEx,
            LegacyInfo = scale,
            UseEx = useEx,
            Handle = handle,
            OutputId = outputId,
            DisplayId = displayId,
            Path = path,
            DvcStructVersion = structVersion
        };
    }

    private IEnumerable<(IntPtr Handle, int OutputId, string Path)> EnumerateDvcTargets(NvidiaDisplayCandidate candidate)
    {
        if (candidate.DisplayHandle != IntPtr.Zero)
        {
            foreach (var id in new[] { 0, 1, 2, 3 })
                yield return (candidate.DisplayHandle, id, "handle+output" + id);
            if (_getAssociatedOutputId != null && _getAssociatedOutputId(candidate.DisplayHandle, out var assocOut) == NvapiOk)
                yield return (candidate.DisplayHandle, assocOut, "handle+associatedOutputId");
        }

        yield return (IntPtr.Zero, unchecked((int)candidate.DisplayId), "displayId-as-outputId");
    }


    private static NvColorDataV5 CreateColorDataGet()
    {
        var size = (ushort)Marshal.SizeOf<NvColorDataV5>();
        return new NvColorDataV5
        {
            version = MakeNvapiVersion(5, size),
            size = size,
            cmd = NvColorCmdGet
        };
    }

    private static IEnumerable<uint> BuildDvcVersionCandidates<T>(int structVer, uint preferredVersion = 0) where T : struct
    {
        var sz = (uint)Marshal.SizeOf<T>();
        if (preferredVersion != 0)
            yield return preferredVersion;
        yield return MakeNvapiVersion(structVer, sz);
        yield return MakeNvapiVersionAlt(structVer, sz);
    }

    private static uint MakeNvapiVersion(int ver, uint size) => (uint)ver | (size << 16);

    private static uint MakeNvapiVersionAlt(int ver, uint size) => size | ((uint)ver << 16);

    private string FormatNvapi(int code)
    {
        if (code == NvapiOk) return "(OK)";
        return "(" + code + ") " + GetNvapiErrorMessage(code);
    }

    private string GetNvapiErrorMessage(int code)
    {
        if (_getErrorMessage == null) return "code=" + code;
        var sb = new StringBuilder(256);
        try
        {
            _getErrorMessage(code, sb);
            var msg = sb.ToString().Trim();
            if (!string.IsNullOrEmpty(msg))
            {
                FileLogger.Info("NvAPI error message: " + msg);
                return msg;
            }
        }
        catch { /* ignore */ }
        return "code=" + code;
    }

    private StepResult FailNvapi(string context, int code)
    {
        var msg = GetNvapiErrorMessage(code);
        FileLogger.Info(context + " — NVAPI " + code + ": " + msg);
        return StepResult.Fail(context + " — NVAPI " + code + ": " + msg);
    }

    private bool LoadNvApiModule()
    {
        var paths = new[]
        {
            Path.Combine(Environment.SystemDirectory, "nvapi64.dll"),
            Path.Combine(AppContext.BaseDirectory, "nvapi64.dll"),
            "nvapi64.dll"
        };

        foreach (var path in paths)
        {
            if (path != "nvapi64.dll" && !File.Exists(path)) continue;
            try
            {
                _module = NativeLibrary.Load(path);
                if (_module != IntPtr.Zero) break;
            }
            catch { /* next */ }
        }

        if (_module == IntPtr.Zero) return false;

        _queryInterface = GetProc<NvapiQueryInterfaceDelegate>("nvapi_QueryInterface");
        if (_queryInterface == null) return false;

        _initialize = GetDelegate<NvapiInitializeDelegate>(0x0150E828);
        _unload = GetDelegate<NvapiUnloadDelegate>(0xD22BDD7E);
        _getErrorMessage = GetDelegate<NvapiGetErrorMessageDelegate>(0x6C2D048C);
        _enumPhysicalGpus = GetDelegate<NvapiEnumPhysicalGpusDelegate>(0xE5AC921F);
        _getConnectedDisplayIds = GetDelegate<NvapiGpuGetConnectedDisplayIdsDelegate>(0x0078DBA2);
        _enumDisplay = GetDelegate<NvapiEnumNvidiaDisplayHandleDelegate>(0x9ABDD40D);
        _getAssociatedDisplay = GetDelegate<NvapiGetAssociatedNvidiaDisplayHandleDelegate>(0x35C29134);
        _getAssociatedDisplayName = GetDelegate<NvapiGetAssociatedNvidiaDisplayNameDelegate>(0x22A78B05);
        _getDisplayIdByName = GetDelegate<NvapiDispGetDisplayIdByDisplayNameDelegate>(0xAE457190);
        _getGdiPrimaryDisplayId = ResolveDelegate<NvapiDispGetGdiPrimaryDisplayIdDelegate>(
            new[] { 0x1E9D8A31u, 0x3BAFDFE5u }, "DISP_GetGDIPrimaryDisplayId");
        _getAssociatedOutputId = GetDelegate<NvapiGetAssociatedDisplayOutputIdDelegate>(0x120167E8);
        _getDvcInfo = GetDelegate<NvapiGetDvcInfoDelegate>(0x4085DE45);
        _setDvcLevel = GetDelegate<NvapiSetDvcLevelDelegate>(0x172409B4);
        _getDvcInfoEx = GetDelegate<NvapiGetDvcInfoExDelegate>(0x0E45002D);
        _setDvcLevelEx = GetDelegate<NvapiSetDvcLevelExDelegate>(0x4A82C2B1);
        _dispColorControl = GetDelegate<NvapiDispColorControlDelegate>(0x92F9D80D);

        FileLogger.Info("NVAPI delegates: DVC=" + (_getDvcInfo != null) +
                        " DVCex=" + (_getDvcInfoEx != null) +
                        " ColorControl=" + (_dispColorControl != null) +
                        " GDIprimary=" + (_getGdiPrimaryDisplayId != null) +
                        " GPUdisplays=" + (_getConnectedDisplayIds != null));

        return _initialize != null;
    }

    private T? GetDelegate<T>(uint id) where T : Delegate
    {
        if (_queryInterface == null) return null;
        var ptr = _queryInterface(id);
        if (ptr == IntPtr.Zero) return null;
        try { return Marshal.GetDelegateForFunctionPointer<T>(ptr); }
        catch { return null; }
    }

    private T? ResolveDelegate<T>(uint[] ids, string name) where T : Delegate
    {
        foreach (var id in ids)
        {
            var d = GetDelegate<T>(id);
            if (d != null)
            {
                FileLogger.Info("NVAPI " + name + " resolved id=0x" + id.ToString("X"));
                return d;
            }
        }
        FileLogger.Warn("NVAPI " + name + " not resolved");
        return null;
    }

    private T? GetProc<T>(string name) where T : Delegate
    {
        if (_module == IntPtr.Zero) return null;
        if (!NativeLibrary.TryGetExport(_module, name, out var ptr) || ptr == IntPtr.Zero) return null;
        return Marshal.GetDelegateForFunctionPointer<T>(ptr);
    }

    public void Dispose()
    {
        if (_initialized && _unload != null)
        {
            try { _unload(); } catch { /* ignore */ }
            _initialized = false;
        }
        if (_module != IntPtr.Zero)
        {
            try { NativeLibrary.Free(_module); } catch { /* ignore */ }
            _module = IntPtr.Zero;
        }
    }
}
