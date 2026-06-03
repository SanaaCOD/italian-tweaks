$ErrorActionPreference = "Stop"

$PlanFile = Join-Path $PSScriptRoot "BitsumHighestPerformance.pow"

if (-not (Test-Path $PlanFile)) {
    Write-Output "ERROR: POW_FILE_NOT_FOUND"
    exit 1
}

$importResult = powercfg -import "$PlanFile" 2>&1 | Out-String

$guid = $null

if ($importResult -match "([a-fA-F0-9-]{36})") {
    $guid = $matches[1]
}

if (-not $guid) {
    foreach ($line in (powercfg /list)) {
        if ($line -match "Bitsum Highest Performance" -and $line -match "([a-fA-F0-9-]{36})") {
            $guid = $matches[1]
            break
        }
    }
}

if (-not $guid) {
    Write-Output "ERROR: BITSUM_GUID_NOT_FOUND"
    exit 1
}

powercfg /setactive $guid | Out-Null
Start-Sleep -Milliseconds 300

$active = powercfg /getactivescheme

if ($active -match $guid) {
    Write-Output "OK: POWERPLAN_ENABLED"
    exit 0
}

Write-Output "ERROR: POWERPLAN_ENABLE_FAILED"
exit 1