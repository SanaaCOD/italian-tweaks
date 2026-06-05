using System.Collections.ObjectModel;
using PurpleBoost.Models;

namespace PurpleBoost.Services;

public interface ILogService
{
    ReadOnlyObservableCollection<LogEntry> Entries { get; }

    void Append(LogLevel level, string message);

    void Clear();

    string ExportText();
}
