$ErrorActionPreference = "Stop"

$BalancedGuid = "381b4222-f694-41f0-9685-ff5bb260df2e"

powercfg /setactive $BalancedGuid | Out-Null
Start-Sleep -Milliseconds 300

$active = powercfg /getactivescheme

if ($active -match $BalancedGuid) {
    Write-Output "OK: POWERPLAN_DISABLED"
    exit 0
}

Write-Output "ERROR: POWERPLAN_DISABLE_FAILED"
exit 1