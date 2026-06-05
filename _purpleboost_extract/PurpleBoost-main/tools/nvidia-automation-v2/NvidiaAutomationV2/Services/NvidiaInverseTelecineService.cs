using System.Text.Json;
using Microsoft.Win32;
using NvidiaAutomationV2.Models;

namespace NvidiaAutomationV2.Services;

/// <summary>
/// Désactive la téléciné inversée via registre Video (valeur XALG_Cadence = 8 octets à zéro).
/// </summary>
public sealed class NvidiaInverseTelecineService
{
    private const string VideoRegistryPath = @"SYSTEM\CurrentControlSet\Control\Video";
    private static readonly byte[] TelecineOffBytes = { 0, 0, 0, 0, 0, 0, 0, 0 };

    private const string MethodId = "registry_xalg_cadence";
    private const string ZeroEvidence = "00 00 00 00 00 00 00 00";

    private readonly string _purpleBoostRoot;

    public NvidiaInverseTelecineService(string purpleBoostRoot) =>
        _purpleBoostRoot = purpleBoostRoot.TrimEnd('\\', '/');

    public StepResult DisableInverseTelecine()
    {
        FileLogger.Info("NvidiaInverseTelecineService: starting (Registry64, scan récursif)");

        var backupPath = Path.Combine(_purpleBoostRoot, "backup", "nvidia_inverse_telecine_backup.json");
        var backup = new List<Dictionary<string, object?>>();
        var proofLines = new List<string>();
        var modified = 0;
        var writeVerified = 0;
        var found = 0;
        var alreadyOff = 0;
        var accessDenied = 0;

        try
        {
            using var hklm = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64);
            using var videoRoot = hklm.OpenSubKey(VideoRegistryPath, writable: true);
            if (videoRoot == null)
            {
                FileLogger.Warn("Registry Video root not found");
                return StepResult.Fail("Clé Video introuvable (admin requis ?)", MethodId);
            }

            ScanKeyRecursive(videoRoot, VideoRegistryPath, backup, proofLines, ref found, ref alreadyOff, ref modified, ref writeVerified, ref accessDenied);

            WriteBackup(backupPath, backup, found, modified, writeVerified);

            if (found == 0)
                return StepResult.Skip("Aucune valeur XALG_Cadence trouvée", MethodId);

            if (accessDenied > 0 && (modified == 0 || writeVerified < modified))
                return StepResult.Fail("Accès registre refusé : action non lancée en administrateur (" + accessDenied + " refus)", MethodId);

            if (modified == 0)
            {
                var ev = "XALG_Cadence déjà " + ZeroEvidence + " (" + alreadyOff + "/" + found + " valeurs, aucune écriture)";
                return new StepResult
                {
                    Status = StepStatus.Skipped.ToString(),
                    Message = "Déjà à zéro dans le registre, aucune preuve de changement utilisateur",
                    Verified = false,
                    Method = MethodId,
                    Evidence = ev,
                    UiStatus = "ignored",
                    RegistryChanged = false,
                    Changed = false,
                    ModifiedCount = 0
                };
            }

            if (writeVerified == modified)
            {
                var evidence = "XALG_Cadence relu à " + ZeroEvidence + " après écriture (" + writeVerified + " modification(s))";
                if (proofLines.Count > 0)
                    evidence += " — " + string.Join("; ", proofLines.Take(6));
                return StepResult.OkVerified(
                    "Téléciné inversée désactivée (" + writeVerified + " écriture(s) confirmée(s))",
                    MethodId,
                    evidence,
                    modified);
            }

            return StepResult.Fail("Relecture non confirmée après écriture (" + writeVerified + "/" + modified + ")", MethodId);
        }
        catch (UnauthorizedAccessException ex)
        {
            FileLogger.Warn("UnauthorizedAccessException: " + ex.Message);
            return StepResult.Fail("Accès registre refusé : action non lancée en administrateur", MethodId);
        }
        catch (Exception ex)
        {
            FileLogger.Warn("NvidiaInverseTelecineService exception: " + ex.Message);
            return StepResult.Fail("Téléciné inversée : " + ex.Message, MethodId);
        }
    }

    private static void ScanKeyRecursive(
        RegistryKey key, string path, List<Dictionary<string, object?>> backup, List<string> proofLines,
        ref int found, ref int alreadyOff, ref int modified, ref int writeVerified, ref int accessDenied)
    {
        foreach (var valueName in key.GetValueNames())
        {
            if (!IsCadenceValueName(valueName)) continue;

            found++;
            var fullPath = @"HKLM\" + path;
            byte[]? before;
            try
            {
                before = ReadValueBytes(key, valueName);
            }
            catch (UnauthorizedAccessException)
            {
                accessDenied++;
                FileLogger.Warn("Read denied: " + fullPath + "\\" + valueName);
                continue;
            }

            backup.Add(new Dictionary<string, object?>
            {
                ["registryPath"] = fullPath,
                ["valueName"] = valueName,
                ["beforeHex"] = BytesToHex(before),
                ["kind"] = key.GetValueKind(valueName).ToString()
            });

            if (IsOffValue(before))
            {
                alreadyOff++;
                proofLines.Add(fullPath + "\\" + valueName + " déjà " + ZeroEvidence);
                FileLogger.Info("Cadence déjà OFF: " + fullPath + " " + valueName);
                continue;
            }

            try
            {
                key.SetValue(valueName, (byte[])TelecineOffBytes.Clone(), RegistryValueKind.Binary);
                modified++;
            }
            catch (UnauthorizedAccessException)
            {
                accessDenied++;
                FileLogger.Warn("Write denied: " + fullPath + "\\" + valueName);
                continue;
            }
            catch (Exception ex)
            {
                FileLogger.Warn("SetValue failed " + fullPath + "\\" + valueName + ": " + ex.Message);
                continue;
            }

            var after = ReadValueBytes(key, valueName);
            if (IsOffValue(after))
            {
                writeVerified++;
                proofLines.Add(fullPath + "\\" + valueName + " relu " + ZeroEvidence + " après écriture");
                FileLogger.Info("Cadence OFF verified: " + fullPath + " " + valueName);
            }
            else
            {
                FileLogger.Warn("Cadence readback not zero: " + fullPath + " " + valueName + " hex=" + BytesToHex(after));
            }
        }

        foreach (var subName in key.GetSubKeyNames())
        {
            try
            {
                using var sub = key.OpenSubKey(subName, writable: true);
                if (sub == null) continue;
                ScanKeyRecursive(sub, path + "\\" + subName, backup, proofLines, ref found, ref alreadyOff, ref modified, ref writeVerified, ref accessDenied);
            }
            catch (UnauthorizedAccessException)
            {
                accessDenied++;
                FileLogger.Warn("SubKey access denied: " + path + "\\" + subName);
            }
            catch (Exception ex)
            {
                FileLogger.Warn("SubKey skip " + path + "\\" + subName + ": " + ex.Message);
            }
        }
    }

    private static bool IsCadenceValueName(string name)
    {
        if (string.IsNullOrWhiteSpace(name)) return false;
        return name.Contains("XALG_Cadence", StringComparison.OrdinalIgnoreCase);
    }

    private static byte[]? ReadValueBytes(RegistryKey key, string valueName)
    {
        var val = key.GetValue(valueName, null, RegistryValueOptions.DoNotExpandEnvironmentNames);
        return val as byte[];
    }

    private static bool IsOffValue(byte[]? bytes)
    {
        if (bytes == null || bytes.Length == 0) return true;
        if (bytes.Length != 8) return false;
        foreach (var b in bytes)
            if (b != 0) return false;
        return true;
    }

    private static string BytesToHex(byte[]? bytes)
    {
        if (bytes == null || bytes.Length == 0) return "";
        return BitConverter.ToString(bytes).Replace("-", " ", StringComparison.Ordinal);
    }

    private static void WriteBackup(string path, List<Dictionary<string, object?>> entries, int found, int modified, int writeVerified)
    {
        try
        {
            var dir = Path.GetDirectoryName(path);
            if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
            var doc = new
            {
                savedAt = DateTime.UtcNow.ToString("o"),
                foundCount = found,
                modifiedCount = modified,
                writeVerifiedCount = writeVerified,
                entries
            };
            File.WriteAllText(path, JsonSerializer.Serialize(doc, new JsonSerializerOptions { WriteIndented = true }));
            FileLogger.Info("Backup written: " + path);
        }
        catch (Exception ex)
        {
            FileLogger.Warn("Backup failed: " + ex.Message);
        }
    }
}
