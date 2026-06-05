namespace NvidiaPerformanceRegScan.Models;

public sealed class RegCandidate
{
    public string Hive { get; set; } = "";
    public string Path { get; set; } = "";
    public string ValueName { get; set; } = "";
    public string ValueKind { get; set; } = "";
    public string ValuePreview { get; set; } = "";
    public string MatchReason { get; set; } = "";
}

public sealed class ScanResult
{
    public bool Success { get; set; }
    public int CandidateCount { get; set; }
    public List<RegCandidate> Candidates { get; set; } = new();
    public string CandidatesLogPath { get; set; } = "";
    public string Message { get; set; } = "";
    public List<string> ScanNotes { get; set; } = new();
}
