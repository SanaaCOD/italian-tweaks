using System.Collections.ObjectModel;
using System.Windows;
using System.Windows.Threading;
using PurpleBoost.Models;

namespace PurpleBoost.Services;

public sealed class LogService : ILogService
{
    private readonly ObservableCollection<LogEntry> _entries = new();
    private readonly Dispatcher _dispatcher;

    public LogService()
    {
        _dispatcher = Application.Current?.Dispatcher ?? Dispatcher.CurrentDispatcher;
        Entries = new ReadOnlyObservableCollection<LogEntry>(_entries);
    }

    public ReadOnlyObservableCollection<LogEntry> Entries { get; }

    public void Append(LogLevel level, string message)
    {
        var entry = new LogEntry
        {
            Timestamp = DateTimeOffset.Now,
            Level = level,
            Message = message,
        };

        void Add()
        {
            _entries.Insert(0, entry);
            while (_entries.Count > 300)
                _entries.RemoveAt(_entries.Count - 1);
        }

        if (_dispatcher.CheckAccess())
            Add();
        else
            _dispatcher.Invoke(Add);
    }

    public void Clear()
    {
        void ClearInner()
        {
            _entries.Clear();
        }

        if (_dispatcher.CheckAccess())
            ClearInner();
        else
            _dispatcher.Invoke(ClearInner);
    }

    public string ExportText()
    {
        // Lecture thread-safe “best effort” : snapshot sur le dispatcher UI.
        return _dispatcher.Invoke(() =>
            string.Join(
                Environment.NewLine,
                _entries.Select(e => $"{e.Timestamp:O}\t{e.Level}\t{e.Message}")));
    }
}
