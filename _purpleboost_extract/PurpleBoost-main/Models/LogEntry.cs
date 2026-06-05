namespace PurpleBoost.Models;

public enum LogLevel
{
    Info,
    Pending,
    Success,
    Error,
}

public sealed class LogEntry
{
    public required DateTimeOffset Timestamp { get; init; }
    public required LogLevel Level { get; init; }
    public required string Message { get; init; }
}
