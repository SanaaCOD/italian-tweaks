# Kojo — contrat JSON standard pour les scripts PowerShell
# Les fonctions Write-ItalianTweaks* sont des alias internes (compat scripts existants).

function Write-KojoJson {
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

function Write-KojoStub {
    param(
        [Parameter(Mandatory)][string]$Action,
        [string]$Message = 'Script prêt à remplacer — implémentez la logique ici.'
    )
    Write-KojoJson -Ok $false -Status 'not_implemented' -Message $Message -Action $Action -Data @{}
}

function Write-KojoError {
    param([string]$Action, [string]$Message)
    Write-KojoJson -Ok $false -Status 'error' -Message $Message -Action $Action -Data @{}
}

function Resolve-KojoRoot {
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

function Get-KojoProgramDataRoot {
    $kojo = Join-Path $env:ProgramData 'Kojo'
    $legacy = Join-Path $env:ProgramData 'ItalianTweaks'
    if (Test-Path -LiteralPath $legacy) { return $legacy }
    if (-not (Test-Path -LiteralPath $kojo)) {
        New-Item -ItemType Directory -Path $kojo -Force | Out-Null
    }
    return $kojo
}

function Write-KojoLog {
    param([string]$LogDir, [string]$Name, [string]$Line)
    if (-not $LogDir) { return }
    $file = Join-Path $LogDir "$Name.log"
    $dir = Split-Path -Parent $file
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Add-Content -LiteralPath $file -Value ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Line) -Encoding UTF8
}

function Write-ItalianTweaksJson { Write-KojoJson @args }
function Write-ItalianTweaksStub { Write-KojoStub @args }
function Write-ItalianTweaksError { Write-KojoError @args }
function Resolve-ItalianTweaksRoot { Resolve-KojoRoot @args }
function Write-ItalianTweaksLog { Write-KojoLog @args }
