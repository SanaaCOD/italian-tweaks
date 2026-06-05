namespace UnrealNvidiaDisplayHelper;

public sealed class CliOptions
{
    public bool ApplyFull { get; set; }
    public bool JsonOutput { get; set; }
    public bool StatusOnly { get; set; }
    public bool DryRun { get; set; }
    public bool SkipDigitalVibrance { get; set; }
    public bool ScalingOnly { get; set; }

    public static bool TryParse(string[] args, out CliOptions options, out string error)
    {
        options = new CliOptions();
        error = "";

        if (args.Length == 0)
        {
            error = "Aucun argument. Utilisez --apply-full --json ou --status --json";
            return false;
        }

        foreach (var arg in args)
        {
            switch (arg.Trim().ToLowerInvariant())
            {
                case "--apply-full":
                    options.ApplyFull = true;
                    break;
                case "--json":
                    options.JsonOutput = true;
                    break;
                case "--status":
                    options.StatusOnly = true;
                    break;
                case "--dry-run":
                    options.DryRun = true;
                    break;
                case "--skip-digital-vibrance":
                    options.SkipDigitalVibrance = true;
                    break;
                case "--scaling-only":
                    options.ScalingOnly = true;
                    break;
                default:
                    error = "Argument inconnu : " + arg;
                    return false;
            }
        }

        if (!options.JsonOutput)
        {
            error = "--json est requis pour la sortie JSON sur stdout";
            return false;
        }

        if (!options.ApplyFull && !options.StatusOnly && !options.ScalingOnly)
        {
            error = "Spécifiez --apply-full, --scaling-only ou --status";
            return false;
        }

        if (options.ScalingOnly && options.ApplyFull)
        {
            error = "--scaling-only ne peut pas être combiné avec --apply-full";
            return false;
        }

        return true;
    }
}
