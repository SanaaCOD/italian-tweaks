using System.Diagnostics;
using System.Globalization;
using System.Management;
using PurpleBoost.Models;

namespace PurpleBoost.Services;

public sealed class HardwareService : IHardwareService
{
    public Task<HardwareSnapshot> GetSnapshotAsync(CancellationToken cancellationToken = default) =>
        Task.Run(() => BuildSnapshot(cancellationToken), cancellationToken);

    private static HardwareSnapshot BuildSnapshot(CancellationToken ct)
    {
        ct.ThrowIfCancellationRequested();

        var cpuName = QueryFirst("Win32_Processor", "Name") ?? "—";
        var gpuName = PickGpuName() ?? "—";

        var ramTotal = TryGetTotalRamBytes(out var ramBytes)
            ? FormatBytes(ramBytes!.Value)
            : "—";

        var cpuUsage = TryGetCpuUsagePercent(out var cpuPct)
            ? $"{cpuPct!.Value.ToString("0.#", CultureInfo.CurrentCulture)} %"
            : HardwareSnapshot.MissingLabel;

        var ramUsage = TryGetRamUsagePercent(out var ramPct)
            ? $"{ramPct!.Value.ToString("0.#", CultureInfo.CurrentCulture)} %"
            : HardwareSnapshot.MissingLabel;

        var gpuUsage = TryGetGpuUsagePercent(out var gpuPct)
            ? $"{gpuPct!.Value.ToString("0.#", CultureInfo.CurrentCulture)} %"
            : HardwareSnapshot.MissingLabel;

        var cpuTemp = TryGetCpuTemperatureCelsius(out var cTmp)
            ? $"{cTmp!.Value.ToString("0.#", CultureInfo.CurrentCulture)} °C"
            : HardwareSnapshot.MissingLabel;

        var gpuTemp = TryGetGpuTemperatureCelsius(out var gTmp)
            ? $"{gTmp!.Value.ToString("0.#", CultureInfo.CurrentCulture)} °C"
            : HardwareSnapshot.MissingLabel;

        return new HardwareSnapshot
        {
            CpuName = cpuName,
            CpuUsage = cpuUsage,
            GpuName = gpuName,
            GpuUsage = gpuUsage,
            RamTotal = ramTotal,
            RamUsage = ramUsage,
            CpuTemperature = cpuTemp,
            GpuTemperature = gpuTemp,
        };
    }

    private static string? PickGpuName()
    {
        try
        {
            using var searcher = new ManagementObjectSearcher("SELECT Name FROM Win32_VideoController");
            string? any = null;
            foreach (var o in searcher.Get())
            {
                using (o)
                {
                    var name = o["Name"]?.ToString();
                    if (string.IsNullOrWhiteSpace(name))
                        continue;

                    any ??= name;
                    if (!name.Contains("Microsoft", StringComparison.OrdinalIgnoreCase))
                        return name;
                }
            }

            return any;
        }
        catch
        {
            return null;
        }
    }

    private static bool TryGetTotalRamBytes(out ulong? bytes)
    {
        bytes = null;
        try
        {
            var v = QueryFirst("Win32_ComputerSystem", "TotalPhysicalMemory");
            if (ulong.TryParse(v, NumberStyles.Integer, CultureInfo.InvariantCulture, out var b))
            {
                bytes = b;
                return true;
            }
        }
        catch
        {
            // ignore
        }

        return false;
    }

    private static bool TryGetCpuUsagePercent(out double? value)
    {
        value = null;
        try
        {
            using var searcher = new ManagementObjectSearcher("SELECT LoadPercentage FROM Win32_Processor");
            var loads = new List<double>();
            foreach (var o in searcher.Get())
            {
                using (o)
                {
                    var lp = o["LoadPercentage"];
                    switch (lp)
                    {
                        case ushort u:
                            loads.Add(u);
                            break;
                        case uint ui:
                            loads.Add(ui);
                            break;
                        case int i:
                            loads.Add(i);
                            break;
                    }
                }
            }

            if (loads.Count == 0)
                return TryPerfCpu(out value);

            value = loads.Average();
            return true;
        }
        catch
        {
            return TryPerfCpu(out value);
        }
    }

    private static bool TryPerfCpu(out double? value)
    {
        value = null;
        try
        {
            using var pc = new PerformanceCounter("Processor", "% Processor Time", "_Total", true);
            _ = pc.NextValue();
            Thread.Sleep(200);
            value = Math.Clamp(pc.NextValue(), 0, 100);
            return true;
        }
        catch
        {
            return false;
        }
    }

    private static bool TryGetRamUsagePercent(out double? value)
    {
        value = null;
        try
        {
            using var searcher = new ManagementObjectSearcher(
                "SELECT TotalVisibleMemorySize, FreePhysicalMemory FROM Win32_OperatingSystem");
            foreach (var o in searcher.Get())
            {
                using (o)
                {
                    var total = Convert.ToUInt64(o["TotalVisibleMemorySize"]);
                    var free = Convert.ToUInt64(o["FreePhysicalMemory"]);
                    if (total == 0)
                        return false;

                    var used = total - free;
                    value = used * 100.0 / total;
                    return true;
                }
            }
        }
        catch
        {
            // ignore
        }

        return false;
    }

    private static bool TryGetGpuUsagePercent(out double? value)
    {
        value = null;
        var counters = new List<PerformanceCounter>();
        try
        {
            var category = new PerformanceCounterCategory("GPU Engine");
            var instances = category.GetInstanceNames();
            if (instances.Length == 0)
                return false;

            foreach (var instance in instances)
            {
                try
                {
                    counters.Add(new PerformanceCounter("GPU Engine", "Utilization Percentage", instance, true));
                }
                catch
                {
                    // ignore
                }
            }

            if (counters.Count == 0)
                return false;

            foreach (var c in counters)
            {
                try
                {
                    _ = c.NextValue();
                }
                catch
                {
                    // ignore
                }
            }

            Thread.Sleep(220);

            var max = 0.0;
            foreach (var c in counters)
            {
                try
                {
                    max = Math.Max(max, c.NextValue());
                }
                catch
                {
                    // ignore
                }
            }

            if (max <= 0)
                return false;

            value = Math.Clamp(max, 0, 100);
            return true;
        }
        catch
        {
            return false;
        }
        finally
        {
            foreach (var c in counters)
            {
                try
                {
                    c.Dispose();
                }
                catch
                {
                    // ignore
                }
            }
        }
    }

    private static bool TryGetCpuTemperatureCelsius(out double? celsius)
    {
        celsius = null;
        try
        {
            using var searcher =
                new ManagementObjectSearcher(@"root\WMI", "SELECT CurrentTemperature FROM MSAcpi_ThermalZoneTemperature");
            foreach (var o in searcher.Get())
            {
                using (o)
                {
                    var t = o["CurrentTemperature"];
                    if (t is int tenthsKelvin)
                    {
                        celsius = tenthsKelvin / 10.0 - 273.15;
                        return true;
                    }
                }
            }
        }
        catch
        {
            // ignore
        }

        return false;
    }

    private static bool TryGetGpuTemperatureCelsius(out double? celsius)
    {
        celsius = null;
        return false;
    }

    private static string? QueryFirst(string wmiClass, string property)
    {
        try
        {
            using var searcher = new ManagementObjectSearcher($"SELECT {property} FROM {wmiClass}");
            foreach (var o in searcher.Get())
            {
                using (o)
                {
                    return o[property]?.ToString();
                }
            }
        }
        catch
        {
            // ignore
        }

        return null;
    }

    private static string FormatBytes(ulong bytes)
    {
        var gb = bytes / (1024.0 * 1024.0 * 1024.0);
        return gb >= 1 ? $"{gb.ToString("0.0", CultureInfo.CurrentCulture)} Go" : $"{bytes / (1024.0 * 1024.0):0} Mo";
    }
}
