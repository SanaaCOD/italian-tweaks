$path = 'C:\Users\Sanaa\.cursor\projects\empty-window\PurpleBoost\Unreal.hta'
$lines = Get-Content -LiteralPath $path
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match 'id="controllerOverclockerStatus"') {
        Write-Output "BEFORE: $($lines[$i])"
        $lines[$i] = '    <div id="controllerOverclockerStatus" class="tool-status tool-status--info" style="display:none;margin-top:10px;"></div>'
        Write-Output "AFTER:  $($lines[$i])"
    }
}
Set-Content -LiteralPath $path -Value $lines -Encoding UTF8
