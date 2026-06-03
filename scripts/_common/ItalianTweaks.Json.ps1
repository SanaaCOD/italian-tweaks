# ITALIAN TWEAKS — contrat JSON standard pour tous les scripts
# Usage: . (Join-Path $PSScriptRoot '..\_common\ItalianTweaks.Json.ps1')  # ajuster niveau

function Write-ItalianTweaksJson {
    param(
        [bool]$Ok = $true,
        [string]$Status = 'success',
        [string]$Message = '',
        [string]$Action = '',
        [object]$Data = $null,
        [hashtable]$Extra = $null
    )
    $payload = [ordered]@{
        ok      = $Ok
        status  = $Status
        message = $Message
        action  = $Action
        data    = $Data
    }
    if ($Extra) {
        foreach ($k in $Extra.Keys) { $payload[$k] = $Extra[$k] }
    }
    Write-Output ($payload | ConvertTo-Json -Depth 12 -Compress)
    exit 0
}

function Write-ItalianTweaksStub {
    param(
        [Parameter(Mandatory)][string]$Action,
        [string]$Message = 'Script prêt à remplacer — implémentez la logique ici.'
    )
    Write-ItalianTweaksJson -Ok $false -Status 'not_implemented' -Message $Message -Action $Action -Data @{}
}

function Write-ItalianTweaksError {
    param([string]$Action, [string]$Message)
    Write-ItalianTweaksJson -Ok $false -Status 'error' -Message $Message -Action $Action -Data @{}
}

function Resolve-ItalianTweaksRoot {
    param([string]$AppRoot)
    if ($AppRoot -and (Test-Path -LiteralPath $AppRoot)) {
        return (Resolve-Path -LiteralPath $AppRoot).Path
    }
    $here = $PSScriptRoot
    for ($i = 0; $i -lt 6; $i++) {
        if (-not $here) { break }
        if (Test-Path -LiteralPath (Join-Path $here 'package.json')) {
            return (Resolve-Path -LiteralPath $here).Path
        }
        $here = Split-Path -Parent $here
    }
    return (Get-Location).Path
}

function Write-ItalianTweaksLog {
    param([string]$LogDir, [string]$Name, [string]$Line)
    if (-not $LogDir) { return }
    $file = Join-Path $LogDir "$Name.log"
    $dir = Split-Path -Parent $file
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Add-Content -LiteralPath $file -Value ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Line) -Encoding UTF8
}
