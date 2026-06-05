# PurpleBoost Gaming Optimizer (WPF / .NET 8)

Application Windows **native** (C# + WPF + **.NET 8**).  
Aucun Electron, aucun Node.js, aucun npm.

## Prérequis (développeur / build)

- [SDK .NET 8](https://dotnet.microsoft.com/download/dotnet/8.0) (Windows)

## Lancer en debug

```bash
dotnet run
```

## Publier un `.exe` **self-contained** + **single-file**

```bash
dotnet publish -c Release -r win-x64 --self-contained true /p:PublishSingleFile=true /p:IncludeNativeLibrariesForSelfExtract=true /p:EnableCompressionInSingleFile=true /p:DebugType=None /p:DebugSymbols=false
```

Sortie typique :

`bin/Release/net8.0-windows/win-x64/publish/PurpleBoostGamingOptimizer.exe`

L’utilisateur final **n’a pas besoin d’installer le runtime .NET** (self-contained).

## Notes

- Détection matérielle : `HardwareService` (WMI + compteurs de performance Windows).
- Les scripts PowerShell ne sont **pas** exécutés automatiquement dans cette base : `PowerShellService` est un stub.
