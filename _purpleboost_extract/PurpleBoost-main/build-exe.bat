@echo off
setlocal EnableExtensions
cd /d "%~dp0"

if exist "%~dp0assets\images\unreal-logo.bak.png" (
  echo [Unreal] Restauration du logo U original...
  copy /Y "%~dp0assets\images\unreal-logo.bak.png" "%~dp0assets\images\unreal-logo.png" >nul
)

echo [Unreal] Conversion icon.ico depuis unreal-logo.png...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Launcher\tools\Convert-LogoToIcon.ps1"
if errorlevel 1 (
  echo Echec conversion icon.ico.
  exit /b 1
)

set "PUBLISH=%~dp0dist"
if not exist "%PUBLISH%" mkdir "%PUBLISH%"

echo.
echo [Unreal] Compilation du lanceur natif (1280x800 centre, single-instance process)...
dotnet publish "%~dp0UnrealLauncher\UnrealLauncher.csproj" ^
  -c Release ^
  -r win-x64 ^
  -p:PublishSingleFile=true ^
  -p:IncludeNativeLibrariesForSelfExtract=true ^
  --self-contained true ^
  -o "%PUBLISH%"

if errorlevel 1 (
  echo.
  echo Echec de la compilation. Verifiez que le SDK .NET 8 est installe.
  exit /b 1
)

set "EXE=%PUBLISH%\Unreal Gaming Optimizer.exe"

echo.
echo [Unreal] Raccourci Bureau (CreateDesktopShortcut.ps1)...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0CreateDesktopShortcut.ps1" -ProjectRoot "%~dp0"

echo.
echo ========================================
echo  Build termine
echo ========================================
echo  EXE      : %EXE%
echo  Logo PNG : %~dp0assets\images\unreal-logo.png
echo  Raccourci: %USERPROFILE%\Desktop\Unreal Gaming Optimizer.lnk
echo.
echo  Lancer : double-clic sur le raccourci Bureau uniquement
echo           (ne pas copier l'EXE seul hors du dossier projet)
echo  (Unreal.hta, Scripts/, assets/ a la racine PurpleBoost)
echo ========================================
echo.
echo [Unreal] Deploiement vers dist\ (Deploy-DistExe.ps1)...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Scripts\Deploy-DistExe.ps1" -ProjectRoot "%~dp0"
if errorlevel 1 (
  echo.
  echo ATTENTION: dist\ non mis a jour. Fermez Unreal puis relancez build-exe.bat
)
echo.
pause
