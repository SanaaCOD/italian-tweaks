#Requires AutoHotkey v2.0
#SingleInstance Off

; Attend la page Installation Tweaks puis signale l'UI (ne coche rien)

appRoot := (A_Args.Length >= 1 && A_Args[1] != "") ? A_Args[1] : (A_ScriptDir "\..")
liveFile := appRoot "\logs\nvcleaninstall-auto-live.txt"
logFile := appRoot "\logs\nvcleaninstall-auto.log"

WriteLive(msg) {
    global liveFile
    try FileAppend("STATUS=" msg "`n", liveFile, "UTF-8")
}

AppendLog(line) {
    global logFile
    try FileAppend(line "`n", logFile, "UTF-8")
}

FindNvcWindow() {
    if hwnd := WinExist("ahk_exe NVCleanstall.exe")
        return hwnd
    for hwnd in WinGetList() {
        try {
            title := WinGetTitle("ahk_id " hwnd)
        } catch as err {
            continue
        }
        if RegExMatch(title, "i)NVCleanstall|NVCleanInstall|TechPowerUp.*Clean")
            return hwnd
    }
    return 0
}

IsPreparingPhaseText(txt) {
    if !txt
        return false
    if RegExMatch(txt, "i)Show Expert Tweaks|Disable Installer Telemetry|Perform a Clean Installation|Installation Tweaks")
        return false
    if RegExMatch(txt, "i)Preparing source|Copying install files|Extracting|Downloading|Please wait|Processing")
        return true
    if RegExMatch(txt, "i)Preparing|Copying install")
        return true
    return false
}

IsTweaksPageReady(txt) {
    if !txt || IsPreparingPhaseText(txt)
        return false
    if RegExMatch(txt, "i)Installation Tweaks")
        return true
    if RegExMatch(txt, "i)Show Expert Tweaks")
        return true
    if RegExMatch(txt, "i)Disable Installer Telemetry")
        return true
    if RegExMatch(txt, "i)Perform a Clean Installation")
        return true
    if RegExMatch(txt, "i)Disable Multiplane Overlay")
        return true
    return false
}

WriteLive("Préparation des fichiers NVIDIA en cours...")
AppendLog("TWEAKS_PAGE_WATCHER_STARTED=oui")
AppendLog("PHASE=1")

deadline := A_TickCount + 600000
lastPrepStatus := 0

while (A_TickCount < deadline) {
    hwnd := FindNvcWindow()
    if hwnd {
        try {
            txt := WinGetText("ahk_id " hwnd)
        } catch as err {
            txt := ""
        }
        if RegExMatch(txt, "i)Copying install files") && (A_TickCount - lastPrepStatus > 4000) {
            WriteLive("NVCleanstall copie les fichiers, merci de patienter...")
            lastPrepStatus := A_TickCount
        } else if IsPreparingPhaseText(txt) && (A_TickCount - lastPrepStatus > 4000) {
            WriteLive("Préparation des fichiers NVIDIA en cours...")
            lastPrepStatus := A_TickCount
        }
        if IsTweaksPageReady(txt) {
            Sleep(800)
            try {
                txt2 := WinGetText("ahk_id " hwnd)
            } catch as err {
                txt2 := txt
            }
            if IsTweaksPageReady(txt2) {
                AppendLog("INSTALLATION_TWEAKS_DETECTED=oui")
                AppendLog("TWEAKS_PAGE_READY=oui")
                WriteLive("Page des réglages NVIDIA détectée.")
                Sleep(300)
                WriteLive("Clique sur Continuer les réglages NVIDIA.")
                ExitApp(0)
            }
        }
    }
    Sleep(500)
}

AppendLog("TWEAKS_PAGE_READY=non")
AppendLog("TWEAKS_PAGE_WATCHER_TIMEOUT=oui")
ExitApp(1)
