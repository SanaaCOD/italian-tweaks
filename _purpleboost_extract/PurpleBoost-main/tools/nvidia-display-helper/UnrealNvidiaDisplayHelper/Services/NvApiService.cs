using System.Runtime.InteropServices;
using UnrealNvidiaDisplayHelper.Models;

namespace UnrealNvidiaDisplayHelper.Services;

/// <summary>
/// NVAPI via nvapi64.dll (chargement dynamique). Pas d'automatisation panneau NVIDIA.
/// </summary>
public sealed class NvApiService : IDisposable
{
    private const int NvapiOk = 0;
    private const int TargetVibrancePercent = 80;

    // NV_SCALING — GPU scanout to native ≈ « Pas de mise à l'échelle »
    private const int NvScalingGpuScanoutToNative = 5;

    private delegate IntPtr NvapiQueryInterfaceDelegate(uint id);
    private delegate int NvapiInitializeDelegate();
    private delegate int NvapiUnloadDelegate();
    private delegate int NvapiEnumNvidiaDisplayHandleDelegate(int thisEnum, out IntPtr displayHandle);
    private delegate int NvapiGetAssociatedNvidiaDisplayHandleDelegate([MarshalAs(UnmanagedType.LPStr)] string displayName, out IntPtr displayHandle);
    private delegate int NvapiDispGetDisplayIdByDisplayNameDelegate([MarshalAs(UnmanagedType.LPStr)] string displayName, out uint displayId);
    private delegate int NvapiGetDvcInfoDelegate(IntPtr displayHandle, int outputId, ref NvDisplayDvcInfo info);
    private delegate int NvapiSetDvcLevelDelegate(IntPtr displayHandle, int outputId, int level);
    private delegate int NvapiDispGetAdaptiveSyncDataDelegate(uint displayId, ref NvGetAdaptiveSyncData data);
    private delegate int NvapiDispSetAdaptiveSyncDataDelegate(uint displayId, ref NvSetAdaptiveSyncData data);
    private delegate int NvapiDispGetDisplayConfigDelegate(ref uint pathCount, IntPtr pathInfo);
    private delegate int NvapiDispSetDisplayConfigDelegate(uint pathCount, IntPtr pathInfo, uint flags);

    [StructLayout(LayoutKind.Sequential)]
    private struct NvDisplayDvcInfo
    {
        public uint version;
        public int currentLevel;
        public int maxLevel;
        public int minLevel;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NvGetAdaptiveSyncData
    {
        public uint version;
        public uint flags;
        public uint enable;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NvSetAdaptiveSyncData
    {
        public uint version;
        public uint flags;
        public uint enable;
    }

    // Structures minimales pour NV_DISPLAYCONFIG_PATH_INFO (win7+)
    [StructLayout(LayoutKind.Sequential)]
    private struct NvDisplayconfigPathInfo
    {
        public uint version;
        public uint sourceId;
        public uint targetInfoCount;
        public IntPtr targetInfo;
        public IntPtr sourceModeInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NvDisplayconfigTargetInfo
    {
        public uint version;
        public uint displayId;
        public uint details;
        public uint targetId;
        public uint refreshRate1;
        public uint refreshRate2;
        public int rotation;
        public uint scaling;
        public uint connector;
        public uint timingOverride;
        public uint primary;
    }

    private IntPtr _module;
    private NvapiQueryInterfaceDelegate? _queryInterface;
    private NvapiInitializeDelegate? _initialize;
    private NvapiUnloadDelegate? _unload;
    private NvapiGetAssociatedNvidiaDisplayHandleDelegate? _getAssociatedDisplay;
    private NvapiDispGetDisplayIdByDisplayNameDelegate? _getDisplayIdByName;
    private NvapiGetDvcInfoDelegate? _getDvcInfo;
    private NvapiSetDvcLevelDelegate? _setDvcLevel;
    private NvapiDispGetAdaptiveSyncDataDelegate? _getAdaptiveSync;
    private NvapiDispSetAdaptiveSyncDataDelegate? _setAdaptiveSync;
    private NvapiDispGetDisplayConfigDelegate? _getDisplayConfig;
    private NvapiDispSetDisplayConfigDelegate? _setDisplayConfig;

    private IntPtr _displayHandle;
    private uint _displayId;
    private bool _initialized;

    public bool IsAvailable => _initialized && (_displayHandle != IntPtr.Zero || _displayId != 0);

    public bool TryInitialize(string primaryDeviceName)
    {
        if (!LoadNvApiModule()) return false;
        if (_initialize == null) return false;

        var init = _initialize();
        if (init != NvapiOk)
        {
            FileLogger.Warn("NvAPI_Initialize code=" + init);
            return false;
        }
        _initialized = true;

        if (_getAssociatedDisplay != null)
        {
            var st = _getAssociatedDisplay(primaryDeviceName, out _displayHandle);
            if (st == NvapiOk && _displayHandle != IntPtr.Zero)
                FileLogger.Info("NVAPI handle associé : " + primaryDeviceName);
        }

        if (_displayHandle == IntPtr.Zero)
        {
            var enumFn = GetDelegate<NvapiEnumNvidiaDisplayHandleDelegate>(0x9ABDD40D);
            if (enumFn != null)
                enumFn(0, out _displayHandle);
        }

        if (_getDisplayIdByName != null)
        {
            var idSt = _getDisplayIdByName(primaryDeviceName, out _displayId);
            if (idSt == NvapiOk && _displayId != 0)
                FileLogger.Info("NVAPI displayId=" + _displayId);
        }

        return _displayHandle != IntPtr.Zero || _displayId != 0;
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

        if (_module == IntPtr.Zero)
        {
            FileLogger.Warn("nvapi64.dll introuvable");
            return false;
        }

        _queryInterface = GetProc<NvapiQueryInterfaceDelegate>("nvapi_QueryInterface");
        if (_queryInterface == null) return false;

        _initialize = GetDelegate<NvapiInitializeDelegate>(0x0150E828);
        _unload = GetDelegate<NvapiUnloadDelegate>(0xD22BDD7E);
        _getAssociatedDisplay = GetDelegate<NvapiGetAssociatedNvidiaDisplayHandleDelegate>(0x35C29134);
        _getDisplayIdByName = GetDelegate<NvapiDispGetDisplayIdByDisplayNameDelegate>(0xAE457190);
        _getDvcInfo = GetDelegate<NvapiGetDvcInfoDelegate>(0x4085DE45);
        _setDvcLevel = GetDelegate<NvapiSetDvcLevelDelegate>(0x172409B4);
        _getAdaptiveSync = GetDelegate<NvapiDispGetAdaptiveSyncDataDelegate>(0xB73D1EE9);
        _setAdaptiveSync = GetDelegate<NvapiDispSetAdaptiveSyncDataDelegate>(0x3EEBBA1D);
        _getDisplayConfig = GetDelegate<NvapiDispGetDisplayConfigDelegate>(0x11ABCCF8);
        _setDisplayConfig = GetDelegate<NvapiDispSetDisplayConfigDelegate>(0x5D8CF8DE);

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

    private T? GetProc<T>(string name) where T : Delegate
    {
        if (_module == IntPtr.Zero) return null;
        if (!NativeLibrary.TryGetExport(_module, name, out var ptr) || ptr == IntPtr.Zero) return null;
        return Marshal.GetDelegateForFunctionPointer<T>(ptr);
    }

    private static int LevelFromPercent(NvDisplayDvcInfo info, int percent)
    {
        var range = info.maxLevel - info.minLevel;
        if (range <= 0) return 50;
        return info.minLevel + (range * Math.Clamp(percent, 0, 100) / 100);
    }

    private static uint MakeVersion(int version, uint size) => (uint)version | (size << 16);

    public void ApplyScaling(HelperResult result, bool dryRun)
    {
        result.Scaling.Mode = "No scaling";
        if (!IsAvailable || _getDisplayConfig == null || _setDisplayConfig == null)
        {
            result.Scaling.Applied = false;
            result.Scaling.Verified = false;
            result.Scaling.UiStatus = "not_implemented";
            result.Messages.Add("Pas de mise à l'échelle non vérifiable dans le helper actuel (NVAPI indisponible)");
            return;
        }

        if (dryRun)
        {
            result.Scaling.Applied = false;
            result.Scaling.Verified = false;
            result.Messages.Add("Scaling : dry-run, non modifié");
            return;
        }

        try
        {
            uint pathCount = 0;
            var st = _getDisplayConfig(ref pathCount, IntPtr.Zero);
            if (st != NvapiOk || pathCount == 0)
            {
                FailScaling(result, "GetDisplayConfig (count) code=" + st);
                return;
            }

            var pathSize = Marshal.SizeOf<NvDisplayconfigPathInfo>();
            var pathsPtr = Marshal.AllocHGlobal((int)(pathCount * pathSize));
            try
            {
                for (var i = 0; i < pathCount; i++)
                {
                    var pi = new NvDisplayconfigPathInfo
                    {
                        version = MakeVersion(1, (uint)pathSize),
                        targetInfoCount = 0,
                        targetInfo = IntPtr.Zero,
                        sourceModeInfo = IntPtr.Zero
                    };
                    Marshal.StructureToPtr(pi, pathsPtr + (int)(i * pathSize), false);
                }

                st = _getDisplayConfig(ref pathCount, pathsPtr);
                if (st != NvapiOk)
                {
                    FailScaling(result, "GetDisplayConfig code=" + st);
                    return;
                }

                var changed = false;
                for (var i = 0; i < pathCount; i++)
                {
                    var path = Marshal.PtrToStructure<NvDisplayconfigPathInfo>(pathsPtr + (int)(i * pathSize));
                    if (path.targetInfoCount == 0 || path.targetInfo == IntPtr.Zero) continue;

                    var targetSize = Marshal.SizeOf<NvDisplayconfigTargetInfo>();
                    for (var t = 0; t < path.targetInfoCount; t++)
                    {
                        var tPtr = path.targetInfo + (int)(t * targetSize);
                        var target = Marshal.PtrToStructure<NvDisplayconfigTargetInfo>(tPtr);
                        if (_displayId != 0 && target.displayId != _displayId) continue;
                        if (target.scaling == NvScalingGpuScanoutToNative) continue;
                        target.scaling = NvScalingGpuScanoutToNative;
                        Marshal.StructureToPtr(target, tPtr, false);
                        changed = true;
                    }
                }

                if (!changed)
                {
                    result.Scaling.Applied = false;
                    result.Scaling.ScalingChanged = false;
                    result.Scaling.Verified = TryVerifyScaling(out var alreadyEvidence);
                    if (result.Scaling.Verified)
                    {
                        result.Scaling.Evidence = alreadyEvidence;
                        result.Scaling.UiStatus = "ignored";
                        result.Scaling.Mode = "No change — scaling déjà natif (relecture seulement)";
                        result.Messages.Add("Pas de changement : scaling déjà GPU scanout native");
                    }
                    else
                    {
                        result.Scaling.UiStatus = "not_implemented";
                        result.Scaling.Mode = "No scaling";
                        result.Messages.Add("Pas de mise à l'échelle non vérifiable (déjà natif non confirmé par relecture)");
                    }
                    return;
                }

                const uint NvDisplayconfigSaveToPersistence = 1;
                st = _setDisplayConfig(pathCount, pathsPtr, NvDisplayconfigSaveToPersistence);
                if (st != NvapiOk)
                {
                    FailScaling(result, "SetDisplayConfig code=" + st);
                    return;
                }

                result.Scaling.Applied = true;
                result.Scaling.ScalingChanged = true;
                Thread.Sleep(400);
                result.Scaling.Verified = TryVerifyScaling(out var evidence);
                if (result.Scaling.Verified)
                {
                    result.Scaling.Evidence = evidence;
                    result.Scaling.UiStatus = "applied";
                    result.Scaling.Mode = "No scaling";
                }
                else
                {
                    result.Scaling.UiStatus = "error";
                    result.Scaling.Mode = "Scaling apply failed verify";
                    result.Messages.Add("Scaling appliqué mais non vérifiable par relecture NVAPI");
                }
            }
            finally
            {
                Marshal.FreeHGlobal(pathsPtr);
            }
        }
        catch (Exception ex)
        {
            FileLogger.Warn("Scaling exception: " + ex.Message);
            FailScaling(result, ex.Message);
        }
    }

    private bool TryVerifyScaling(out string evidence)
    {
        evidence = "";
        if (_getDisplayConfig == null) return false;
        uint pathCount = 0;
        if (_getDisplayConfig(ref pathCount, IntPtr.Zero) != NvapiOk || pathCount == 0) return false;

        var pathSize = Marshal.SizeOf<NvDisplayconfigPathInfo>();
        var pathsPtr = Marshal.AllocHGlobal((int)(pathCount * pathSize));
        try
        {
            for (var i = 0; i < pathCount; i++)
            {
                var pi = new NvDisplayconfigPathInfo { version = MakeVersion(1, (uint)pathSize) };
                Marshal.StructureToPtr(pi, pathsPtr + (int)(i * pathSize), false);
            }
            if (_getDisplayConfig(ref pathCount, pathsPtr) != NvapiOk) return false;

            var targetSize = Marshal.SizeOf<NvDisplayconfigTargetInfo>();
            for (var i = 0; i < pathCount; i++)
            {
                var path = Marshal.PtrToStructure<NvDisplayconfigPathInfo>(pathsPtr + (int)(i * pathSize));
                if (path.targetInfo == IntPtr.Zero) continue;
                for (var t = 0; t < path.targetInfoCount; t++)
                {
                    var target = Marshal.PtrToStructure<NvDisplayconfigTargetInfo>(path.targetInfo + (int)(t * targetSize));
                    if (_displayId != 0 && target.displayId != _displayId) continue;
                    if (target.scaling == NvScalingGpuScanoutToNative)
                    {
                        evidence = "Scaling relu après application = GPU scanout native (5)";
                        return true;
                    }
                }
            }
            return false;
        }
        finally
        {
            Marshal.FreeHGlobal(pathsPtr);
        }
    }

    private static void FailScaling(HelperResult result, string detail)
    {
        result.Scaling.Applied = false;
        result.Scaling.UiStatus = "error";
        result.Scaling.Verified = false;
        result.Messages.Add("Scaling NVIDIA non disponible sur cette configuration (" + detail + ")");
        FileLogger.Warn("Scaling: " + detail);
    }

    public void ApplyDigitalVibrance(HelperResult result, bool dryRun)
    {
        result.DigitalVibrance.Value = "80%";
        if (!IsAvailable || _displayHandle == IntPtr.Zero || _getDvcInfo == null || _setDvcLevel == null)
        {
            result.DigitalVibrance.Applied = false;
            result.DigitalVibrance.Verified = false;
            result.Messages.Add("Digital Vibrance non disponible via NVAPI");
            return;
        }

        var info = new NvDisplayDvcInfo { version = MakeVersion(1, (uint)Marshal.SizeOf<NvDisplayDvcInfo>()) };
        var readOk = false;
        foreach (var outputId in new[] { 0, 1, -1 })
        {
            if (_getDvcInfo(_displayHandle, outputId, ref info) == NvapiOk)
            {
                readOk = true;
                break;
            }
        }
        if (!readOk)
        {
            result.DigitalVibrance.Applied = false;
            result.DigitalVibrance.Verified = false;
            result.Messages.Add("Digital Vibrance : lecture impossible");
            return;
        }

        var targetLevel = LevelFromPercent(info, TargetVibrancePercent);
        if (dryRun)
        {
            result.DigitalVibrance.Applied = false;
            result.DigitalVibrance.Verified = false;
            result.Messages.Add("Digital Vibrance : dry-run");
            return;
        }

        var setOk = false;
        foreach (var outputId in new[] { 0, 1, -1 })
        {
            if (_setDvcLevel(_displayHandle, outputId, targetLevel) == NvapiOk)
            {
                setOk = true;
                break;
            }
        }
        if (!setOk)
        {
            result.DigitalVibrance.Applied = false;
            result.DigitalVibrance.Verified = false;
            result.Messages.Add("Digital Vibrance : échec application");
            return;
        }

        result.DigitalVibrance.Applied = true;
        Thread.Sleep(300);
        var verify = new NvDisplayDvcInfo { version = info.version };
        var verifyOk = false;
        foreach (var outputId in new[] { 0, 1, -1 })
        {
            if (_getDvcInfo(_displayHandle, outputId, ref verify) == NvapiOk)
            {
                verifyOk = true;
                break;
            }
        }
        if (verifyOk)
        {
            result.DigitalVibrance.Verified = Math.Abs(verify.currentLevel - targetLevel) <= 1;
            if (!result.DigitalVibrance.Verified)
                result.Messages.Add("Digital Vibrance appliqué mais non vérifiable");
        }
        else
        {
            result.DigitalVibrance.Verified = false;
            result.Messages.Add("Digital Vibrance appliqué mais non vérifiable");
        }
    }

    public void ApplyGsyncVrr(HelperResult result, bool dryRun)
    {
        if (_displayId == 0 || _setAdaptiveSync == null || _getAdaptiveSync == null)
        {
            result.Gsync.Applied = false;
            result.Gsync.Verified = false;
            result.Gsync.State = "Unknown";
            result.Messages.Add("Désactivation G-Sync/VRR non disponible via API sur cette configuration");
            return;
        }

        if (dryRun)
        {
            result.Gsync.Applied = false;
            result.Gsync.Verified = false;
            result.Gsync.State = "Unknown";
            result.Messages.Add("G-Sync/VRR : dry-run");
            return;
        }

        var setData = new NvSetAdaptiveSyncData
        {
            version = MakeVersion(1, (uint)Marshal.SizeOf<NvSetAdaptiveSyncData>()),
            flags = 0,
            enable = 0
        };

        if (_setAdaptiveSync(_displayId, ref setData) != NvapiOk)
        {
            result.Gsync.Applied = false;
            result.Gsync.Verified = false;
            result.Gsync.State = "Unknown";
            result.Messages.Add("G-Sync/VRR : échec NVAPI");
            return;
        }

        result.Gsync.Applied = true;
        result.Gsync.State = "Disabled";
        Thread.Sleep(300);
        var getData = new NvGetAdaptiveSyncData
        {
            version = MakeVersion(1, (uint)Marshal.SizeOf<NvGetAdaptiveSyncData>())
        };
        if (_getAdaptiveSync(_displayId, ref getData) == NvapiOk)
        {
            result.Gsync.Verified = getData.enable == 0;
            if (!result.Gsync.Verified)
                result.Messages.Add("G-Sync/VRR désactivé mais non vérifiable");
        }
        else
        {
            result.Gsync.Verified = false;
            result.Messages.Add("G-Sync/VRR désactivé mais non vérifiable");
        }
    }

    public void ReadStatus(HelperResult result)
    {
        if (_displayHandle != IntPtr.Zero && _getDvcInfo != null)
        {
            var info = new NvDisplayDvcInfo { version = MakeVersion(1, (uint)Marshal.SizeOf<NvDisplayDvcInfo>()) };
            if (_getDvcInfo(_displayHandle, 0, ref info) == NvapiOk)
            {
                var pct = info.maxLevel > info.minLevel
                    ? (info.currentLevel - info.minLevel) * 100 / (info.maxLevel - info.minLevel)
                    : 0;
                result.DigitalVibrance.Value = pct + "%";
                result.DigitalVibrance.Verified = true;
            }
        }
    }

    public void Dispose()
    {
        if (_initialized && _unload != null)
        {
            try { _unload(); } catch { /* ignore */ }
        }
        if (_module != IntPtr.Zero)
        {
            try { NativeLibrary.Free(_module); } catch { /* ignore */ }
            _module = IntPtr.Zero;
        }
    }
}
