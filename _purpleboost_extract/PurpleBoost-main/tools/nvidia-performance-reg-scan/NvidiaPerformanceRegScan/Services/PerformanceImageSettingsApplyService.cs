using System.Diagnostics;
using System.Text;
using System.Text.Json;
using Microsoft.Win32;
using NvidiaPerformanceRegScan.Models;

namespace NvidiaPerformanceRegScan.Services;

public sealed class PerformanceImageSettingsApplyService
{
    private const string DevicesRelativePath = @"Software\NVIDIA Corporation\Global\NVTweak\Devices";
    private const string ValueName = "ImageSettings";
    /// <summary>Test cible : 1=équilibré (observé), 0=non confirmé panneau, 2=à valider manuellement.</summary>
    private const int TargetValue = 2;

    public ApplyImageSettingsResult Run(string purpleBoostRoot)
    {
        var logsDir = Path.Combine(purpleBoostRoot, "logs");
        Directory.CreateDirectory(logsDir);
        var applyLogPath = Path.Combine(logsDir, "nvidia-performance-apply.log");
        var backupPath = Path.Combine(logsDir, "nvidia-performance-backup.json");

        var entries = new List<ApplyEntry>();
        var logLines = new List<string>
        {
            "=== NVIDIA Performance ImageSettings Apply ===",
            "Date: " + DateTime.Now.ToString("O"),
            "Target: HKCU\\" + DevicesRelativePath + "\\*\\" + ValueName + " = " + TargetValue,
            "Note: ImageSettings=0 non confirmé panneau — test valeur 2",
            ""
        };

        try
        {
            using var hkcu = RegistryKey.OpenBaseKey(RegistryHive.CurrentUser, RegistryView.Default);
            using var devicesRoot = hkcu.OpenSubKey(DevicesRelativePath, writable: true);
            if (devicesRoot == null)
            {
                logLines.Add("Statut final: not_found — racine Devices introuvable");
                WriteApplyLog(applyLogPath, logLines);
                return NotFound(applyLogPath, backupPath);
            }

            foreach (var deviceKey in devicesRoot.GetSubKeyNames())
            {
                try
                {
                    using var device = devicesRoot.OpenSubKey(deviceKey, writable: true);
                    if (device == null) continue;

                    if (!HasImageSettings(device)) continue;

                    var fullPath = DevicesRelativePath + "\\" + deviceKey;
                    var entry = ApplyOnDevice(device, fullPath, deviceKey, logLines);
                    entries.Add(entry);
                }
                catch (Exception exDev)
                {
                    logLines.Add("Device " + deviceKey + " : erreur " + exDev.Message);
                }
            }

            if (entries.Count == 0)
            {
                logLines.Add("Statut final: not_found — aucune valeur ImageSettings");
                WriteApplyLog(applyLogPath, logLines);
                WriteBackup(backupPath, entries);
                return NotFound(applyLogPath, backupPath);
            }

            var (wasRunning, closed) = TryCloseNvcplui(logLines);
            logLines.Add("");

            WriteBackup(backupPath, entries);

            var readbackOk = entries.Count(e => e.Verified);
            if (readbackOk > 0)
            {
                var evidence = BuildEvidence(entries.Where(e => e.Verified).ToList());
                logLines.Add("Statut final: registry_written — " + readbackOk + " relu(s) à " + TargetValue + " (confirmation panneau requise)");
                WriteApplyLog(applyLogPath, logLines);
                return new ApplyImageSettingsResult
                {
                    Success = true,
                    UiStatus = "registry_written",
                    Verified = false,
                    Method = "registry_image_settings",
                    Evidence = evidence,
                    Message = "Mode performance NVIDIA : registre écrit à 2 — confirmation panneau requise",
                    FoundCount = entries.Count,
                    ModifiedCount = entries.Count(e => e.OldValue != TargetValue),
                    VerifiedCount = readbackOk,
                    ApplyLogPath = applyLogPath,
                    BackupPath = backupPath,
                    NvcpluiWasRunning = wasRunning,
                    NvcpluiClosed = closed,
                    Entries = entries
                };
            }

            logLines.Add("Statut final: error — écriture ou relecture échouée");
            WriteApplyLog(applyLogPath, logLines);
            return Error(applyLogPath, backupPath, entries, wasRunning, closed);
        }
        catch (UnauthorizedAccessException)
        {
            logLines.Add("Statut final: error — accès refusé");
            WriteApplyLog(applyLogPath, logLines);
            return Error(applyLogPath, backupPath, entries, false, false);
        }
        catch (Exception ex)
        {
            logLines.Add("Statut final: error — " + ex.Message);
            WriteApplyLog(applyLogPath, logLines);
            return Error(applyLogPath, backupPath, entries, false, false);
        }
    }

    private static (bool WasRunning, bool Closed) TryCloseNvcplui(List<string> logLines)
    {
        var wasRunning = false;
        var closed = false;
        try
        {
            foreach (var proc in Process.GetProcessesByName("nvcplui"))
            {
                wasRunning = true;
                try
                {
                    if (!proc.HasExited)
                    {
                        proc.Kill(entireProcessTree: true);
                        proc.WaitForExit(3000);
                        closed = true;
                    }
                }
                catch
                {
                    /* continue other instances */
                }
                finally
                {
                    proc.Dispose();
                }
            }
        }
        catch (Exception ex)
        {
            logLines.Add("nvcplui.exe fermé: non (erreur " + ex.Message + ")");
            return (wasRunning, false);
        }

        if (!wasRunning)
            logLines.Add("nvcplui.exe fermé: non (pas ouvert)");
        else if (closed)
            logLines.Add("nvcplui.exe fermé: oui");
        else
            logLines.Add("nvcplui.exe fermé: non (échec fermeture)");

        return (wasRunning, closed);
    }

    private static bool HasImageSettings(RegistryKey device)
    {
        try
        {
            return device.GetValue(ValueName) != null;
        }
        catch
        {
            return false;
        }
    }

    private static ApplyEntry ApplyOnDevice(RegistryKey device, string fullPath, string deviceKey, List<string> logLines)
    {
        var entry = new ApplyEntry
        {
            DeviceKey = deviceKey,
            RegistryPath = "HKCU\\" + fullPath,
            NewValue = TargetValue,
            Status = "pending"
        };

        logLines.Add("Clé trouvée: HKCU\\" + fullPath);
        logLines.Add("  Valeur: " + ValueName);

        int? oldVal = null;
        try
        {
            var raw = device.GetValue(ValueName);
            oldVal = CoerceDword(raw);
            entry.OldValue = oldVal;
            logLines.Add("  Ancienne valeur: " + (oldVal.HasValue ? oldVal.Value.ToString() : "(illisible)"));
        }
        catch (Exception exRead)
        {
            logLines.Add("  Ancienne valeur: erreur lecture " + exRead.Message);
        }

        try
        {
            device.SetValue(ValueName, TargetValue, RegistryValueKind.DWord);
            entry.WriteOk = true;
            logLines.Add("  Valeur écrite: " + TargetValue);
        }
        catch (Exception exWrite)
        {
            entry.WriteOk = false;
            entry.Status = "write_failed";
            logLines.Add("  Valeur écrite: échec — " + exWrite.Message);
            logLines.Add("  Valeur relue: (non effectuée)");
            return entry;
        }

        try
        {
            var readBack = CoerceDword(device.GetValue(ValueName));
            entry.ReadBackValue = readBack;
            logLines.Add("  Valeur relue: " + (readBack.HasValue ? readBack.Value.ToString() : "(null)"));

            if (readBack == TargetValue)
            {
                entry.Verified = true;
                entry.Status = "readback_ok";
            }
            else
            {
                entry.Verified = false;
                entry.Status = "readback_mismatch";
            }
        }
        catch (Exception exRb)
        {
            entry.Verified = false;
            entry.Status = "readback_failed";
            logLines.Add("  Valeur relue: erreur — " + exRb.Message);
        }

        return entry;
    }

    private static int? CoerceDword(object? raw)
    {
        if (raw == null) return null;
        return raw switch
        {
            int i => i,
            uint u => (int)u,
            long l => (int)l,
            byte b => b,
            string s when int.TryParse(s, out var n) => n,
            _ => Convert.ToInt32(raw)
        };
    }

    private static string BuildEvidence(List<ApplyEntry> verified)
    {
        var parts = verified.Select(e =>
            e.RegistryPath + "\\" + ValueName + " relu à " + TargetValue + " après écriture (confirmation panneau requise)");
        return string.Join("; ", parts.Take(6));
    }

    private static void WriteApplyLog(string path, List<string> lines)
    {
        File.WriteAllText(path, string.Join(Environment.NewLine, lines) + Environment.NewLine, Encoding.UTF8);
    }

    private static void WriteBackup(string path, List<ApplyEntry> entries)
    {
        var doc = new
        {
            timestamp = DateTime.Now.ToString("O"),
            valueName = ValueName,
            targetValue = TargetValue,
            entries = entries.Select(e => new
            {
                e.DeviceKey,
                e.RegistryPath,
                e.OldValue,
                e.NewValue,
                e.ReadBackValue,
                e.WriteOk,
                e.Verified,
                e.Status
            })
        };
        File.WriteAllText(path, JsonSerializer.Serialize(doc, new JsonSerializerOptions { WriteIndented = true }), Encoding.UTF8);
    }

    private static ApplyImageSettingsResult NotFound(string applyLog, string backup) =>
        new()
        {
            Success = true,
            UiStatus = "not_found",
            Verified = false,
            Message = "Mode performance NVIDIA : clé ImageSettings introuvable",
            ApplyLogPath = applyLog,
            BackupPath = backup
        };

    private static ApplyImageSettingsResult Error(string applyLog, string backup, List<ApplyEntry> entries, bool wasRunning, bool closed) =>
        new()
        {
            Success = false,
            UiStatus = "error",
            Verified = false,
            Message = "Mode performance NVIDIA : erreur — écriture registre impossible",
            ApplyLogPath = applyLog,
            BackupPath = backup,
            Entries = entries,
            FoundCount = entries.Count,
            NvcpluiWasRunning = wasRunning,
            NvcpluiClosed = closed
        };
}
