$ErrorActionPreference = 'Stop'
$hta = 'C:\Users\Sanaa\.cursor\projects\empty-window\PurpleBoost\Unreal.hta'
$wd = 'C:\Users\Sanaa\.cursor\projects\empty-window\PurpleBoost'
Start-Process -FilePath 'mshta.exe' -ArgumentList @('"'+$hta+'"','--base-dir',$wd) -WorkingDirectory $wd -Verb RunAs
