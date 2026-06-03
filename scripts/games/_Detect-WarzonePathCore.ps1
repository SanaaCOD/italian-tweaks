function Get-WarzoneDetection {
    param([string]$AppRoot)
    $files = @('s.1.0.cod25.txt0', 's.1.0.cod25.txt1')
    $embed = Join-Path $AppRoot 'assets\game\warzone'
    $roots = @(
        (Join-Path $env:USERPROFILE 'Documents\Call of Duty\players'),
        (Join-Path $env:USERPROFILE 'Documents\Call of Duty HQ\players'),
        (Join-Path $env:LOCALAPPDATA 'Activision\Call of Duty\players')
    )
    $foundDir = $null
    foreach ($root in $roots) {
        if (-not (Test-Path $root)) { continue }
        Get-ChildItem $root -Directory -Recurse -Depth 4 -ErrorAction SilentlyContinue | ForEach-Object {
            if ($foundDir) { return }
            $ok = $true
            foreach ($f in $files) {
                if (-not (Test-Path (Join-Path $_.FullName $f))) { $ok = $false; break }
            }
            if ($ok) { $foundDir = $_.FullName }
        }
    }
    $embeddedReady = ($files | ForEach-Object { Test-Path (Join-Path $embed $_) }) -notcontains $false
    return @{
        installed = [bool]$foundDir
        playersDir = $foundDir
        embeddedReady = $embeddedReady
        embeddedPath = $embed
        message = if ($foundDir) { "Config trouvée: $foundDir" } else { 'Dossier joueur non détecté' }
    }
}
