#Requires AutoHotkey v2.0
#SingleInstance Force

; NVCleanstall — Phase 2 only : page Installation Tweaks déjà ouverte

global NvcStableW := 1050
global NvcStableH := 800

appRoot := (A_Args.Length >= 1 && A_Args[1] != "") ? A_Args[1] : (A_ScriptDir "\..")
global logFile := appRoot "\logs\nvcleaninstall-auto.log"
global liveFile := appRoot "\logs\nvcleaninstall-auto-live.txt"
global dumpFile := appRoot "\logs\nvcleaninstall-controls-dump.log"
global uiaScript := A_ScriptDir "\nvcleaninstall-auto-uia.ps1"
global SafeClickBlockCoordinateFallbacks := true

SafeClickBlockCoordinateFallback(context) {
    global SafeClickBlockCoordinateFallbacks
    if !SafeClickBlockCoordinateFallbacks
        return false
    AppendLog("SAFECLICK_BLOCKED=" . context)
    WriteLive("[SAFECLICK] Fallback coordonnées bloqué pour sécurité : " . context)
    return true
}

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
        } catch as e {
            continue
        }
        if RegExMatch(title, "i)NVCleanstall|NVCleanInstall|TechPowerUp.*Clean")
            return hwnd
    }
    return 0
}

IsInstallationTweaksPageReady(txt) {
    if !txt
        return false
    if RegExMatch(txt, "i)Preparing source|Copying install files|Extracting|Downloading")
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

WaitForTweaksPageQuick(maxMs := 8000) {
    deadline := A_TickCount + maxMs
    while (A_TickCount < deadline) {
        hwnd := FindNvcWindow()
        if hwnd {
            try {
                txt := WinGetText("ahk_id " hwnd)
            } catch as e {
                txt := ""
            }
            if IsInstallationTweaksPageReady(txt)
                return hwnd
        }
        Sleep(400)
    }
    return 0
}

PrepareNvcWindow(hwnd) {
    try {
        WinActivate("ahk_id " hwnd)
        WinMove(100, 100, NvcStableW, NvcStableH, "ahk_id " hwnd)
        Sleep(400)
        return true
    } catch as e {
        return false
    }
}

TweakVisibleInWindow(hwnd, findList) {
    try {
        body := WinGetText("ahk_id " hwnd)
    } catch as e {
        return false
    }
    for label in findList {
        if InStr(body, label)
            return true
    }
    return false
}

ClickCheckboxNearLabel(hwnd, label) {
    winId := "ahk_id " hwnd
    for ctrl in WinGetControls(winId) {
        txt := ""
        try {
            txt := ControlGetText(ctrl, winId)
        } catch as e {
            txt := ""
        }
        if (txt = "" || !InStr(txt, label))
            continue
        if RegExMatch(txt, "i)^(Back|Cancel|Next|Install|Restart|Reboot|Shutdown)$")
            continue
        try {
            ControlClick(ctrl, winId,,,, "NA")
            Sleep(120)
            return true
        } catch as e1 {
        }
    }
    return false
}

TryClickTweakByText(hwnd, findList, timeoutMs := 2000) {
    deadline := A_TickCount + timeoutMs
    while (A_TickCount < deadline) {
        for label in findList {
            if ClickCheckboxNearLabel(hwnd, label)
                return "clicked"
        }
        Sleep(100)
    }
    return "not_found"
}

DoControlledScroll(hwnd, &scrollCount) {
    if (scrollCount >= 2)
        return
    if SafeClickBlockCoordinateFallback("scroll 0.38/0.55") {
        WriteLive("[NVCleanstall] Fallback coordonnées désactivé pour sécurité.")
        return
    }
    winId := "ahk_id " hwnd
    try {
        ControlFocus("", winId)
    } catch as eF {
    }
    Sleep(80)
    Loop 3
        Send("{WheelDown}")
    scrollCount += 1
    AppendLog("SCROLL_USED=oui")
    Sleep(250)
}

DumpControlsDiagnostic(hwnd, failedOption, lastClicked) {
    global dumpFile
    try {
        SplitPath(dumpFile, , &dir)
        if (dir && !DirExist(dir))
            DirCreate(dir)
    } catch as e {
    }

    title := ""
    body := ""
    try {
        title := WinGetTitle("ahk_id " hwnd)
        body := WinGetText("ahk_id " hwnd)
    } catch as e {
    }

    lines := "DATE=" FormatTime(, "yyyy-MM-dd HH:mm:ss") "`n"
    lines .= "FAILED_OPTION=" failedOption "`n"
    lines .= "LAST_CONTROL_CLICKED=" lastClicked "`n"
    lines .= "WINDOW_TITLE=" title "`n"
    lines .= "WINDOW_TEXT_BEGIN`n" body "`nWINDOW_TEXT_END`n"
    lines .= "CONTROLS:`n"

    winId := "ahk_id " hwnd
    try {
        for ctrl in WinGetControls(winId) {
            cls := ""
            txt := ""
            try {
                cls := ControlGetClassNN(ctrl, winId)
                txt := ControlGetText(ctrl, winId)
            } catch as e {
            }
            if (txt != "" || RegExMatch(cls, "i)Button|Check|Radio|Progress"))
                lines .= "  [" cls "] " txt "`n"
        }
    } catch as e {
        lines .= "  ERROR=" e.Message "`n"
    }

    lines .= "CHECKBOXES_CANDIDATES:`n"
    try {
        for ctrl in WinGetControls(winId) {
            txt := ""
            cls := ""
            try {
                cls := ControlGetClassNN(ctrl, winId)
                txt := ControlGetText(ctrl, winId)
            } catch as e {
            }
            if RegExMatch(cls, "i)Check|Button") || RegExMatch(txt, "i)Tweak|Disable|Enable|Show|Perform|Clean|Anti")
                lines .= "  " cls " | " txt "`n"
        }
    } catch as e {
    }

    lines .= "BUTTONS:`n"
    for btn in ["Next", "&Next", "Back", "Cancel", "Install"] {
        try {
            if ControlGetHwnd(btn, winId)
                lines .= "  " btn "=present`n"
        } catch as e {
        }
    }

    try {
        if FileExist(dumpFile)
            FileDelete(dumpFile)
        FileAppend(lines, dumpFile, "UTF-8")
    } catch as e {
        AppendLog("DUMP_ERROR=" e.Message)
    }
}

ApplyOneTweak(hwnd, t, &scrollCount, &lastClicked) {
    AppendLog("CURRENT_OPTION=" t.name)
    AppendLog("OPTION_FOUND=non")
    AppendLog("OPTION_CLICKED=non")
    AppendLog("OPTION_ALREADY_CHECKED=non")
    AppendLog("OPTION_NOT_FOUND_CONTINUED=non")

    if !TweakVisibleInWindow(hwnd, t.find) && scrollCount < 2 {
        DoControlledScroll(hwnd, &scrollCount)
    }

    if TweakVisibleInWindow(hwnd, t.find) {
        AppendLog("OPTION_FOUND=oui")
        r := TryClickTweakByText(hwnd, t.find, 2000)
        if (r = "clicked") {
            AppendLog("OPTION_CLICKED=oui")
            lastClicked := t.name
            return "ok"
        }
    } else if scrollCount < 2 {
        DoControlledScroll(hwnd, &scrollCount)
        if TweakVisibleInWindow(hwnd, t.find) {
            AppendLog("OPTION_FOUND=oui")
            r := TryClickTweakByText(hwnd, t.find, 2000)
            if (r = "clicked") {
                AppendLog("OPTION_CLICKED=oui")
                lastClicked := t.name
                return "ok"
            }
        }
    }

    AppendLog("OPTION_NOT_FOUND_CONTINUED=oui")
    return "not_found"
}

ClickTweaksNext(hwnd) {
    winId := "ahk_id " hwnd
    try {
        txt := WinGetText(winId)
    } catch as e {
        return false
    }
    if RegExMatch(txt, "i)(Restart|Reboot|Shutdown)")
        return false
    for btn in ["&Next", "Next"] {
        try {
            ControlClick(btn, winId,,,, "NA")
            Sleep(400)
            try {
                txt2 := WinGetText(winId)
                if !RegExMatch(txt2, "i)Installation Tweaks|Show Expert Tweaks")
                    return true
            } catch as e {
                return true
            }
        } catch as e {
        }
    }
    return false
}

; ---------- Main ----------
try FileDelete(liveFile)

AppendLog("DATE=" FormatTime(, "yyyy-MM-dd HH:mm:ss"))
AppendLog("ACTION=nvcleaninstall_tweaks_only")
AppendLog("PHASE=2_TWEAKS_ONLY")

WriteLive("Application des réglages NVIDIA…")

hwnd := FindNvcWindow()
AppendLog("WINDOW_FOUND=" . (hwnd ? "oui" : "non"))

if !hwnd {
    WriteLive("Page des réglages NVIDIA introuvable. Laisse NVCleanstall sur Installation Tweaks puis reclique sur Continuer.")
    AppendLog("INSTALLATION_TWEAKS_PAGE_FOUND=non")
    AppendLog("RESULT=no_window")
    ExitApp(0)
}

hwnd := WaitForTweaksPageQuick(8000)
if !hwnd {
    WriteLive("Page des réglages NVIDIA introuvable. Laisse NVCleanstall sur Installation Tweaks puis reclique sur Continuer.")
    AppendLog("INSTALLATION_TWEAKS_PAGE_FOUND=non")
    AppendLog("RESULT=not_on_tweaks_page")
    ExitApp(0)
}

AppendLog("INSTALLATION_TWEAKS_PAGE_FOUND=oui")
PrepareNvcWindow(hwnd)
hwnd := FindNvcWindow()

tweaks := [
    { name: "Show Expert Tweaks", find: ["Show Expert Tweaks"] },
    { name: "Disable Installer Telemetry & Advertising", find: ["Disable Installer Telemetry & Advertising", "Disable Installer Telemetry"] },
    { name: "Perform a Clean Installation", find: ["Perform a Clean Installation"] },
    { name: "Disable Multiplane Overlay (MPO)", find: ["Disable Multiplane Overlay (MPO)", "Disable Multiplane Overlay"] },
    { name: "Disable Ansel", find: ["Disable Ansel"] },
    { name: "Disable Driver Telemetry", find: ["Disable Driver Telemetry"] },
    { name: "Enable Message Signaled Interrupts", find: ["Enable Message Signaled Interrupts"] },
    { name: "Disable HDCP", find: ["Disable HDCP"] },
    { name: "Use method compatible with Easy Anti-Cheat", find: ["Use method compatible with Easy Anti-Cheat", "Easy Anti-Cheat"] },
    { name: "Automatically accept the driver unsigned warning", find: ["Automatically accept the driver unsigned warning", "driver unsigned"] }
]

scrollCount := 0
lastClicked := ""
anyNotFound := false
failedOption := ""

for i, t in tweaks {
    st := ApplyOneTweak(hwnd, t, &scrollCount, &lastClicked)
    if (st = "not_found") {
        anyNotFound := true
        failedOption := t.name
    }
    if (i = 1)
        Sleep(500)
    else
        Sleep(60)
    hwnd := FindNvcWindow()
    if !hwnd
        break
}

if anyNotFound && hwnd
    DumpControlsDiagnostic(hwnd, failedOption, lastClicked)

hwnd := FindNvcWindow()
nextOk := hwnd && ClickTweaksNext(hwnd)
AppendLog("NEXT_CLICKED=" . (nextOk ? "oui" : "non"))

if !nextOk {
    WriteLive("Bouton Next introuvable. Continue manuellement.")
    AppendLog("RESULT=next_not_found")
    ExitApp(0)
}

if anyNotFound {
    WriteLive("Impossible d'appliquer tous les réglages NVIDIA. Action manuelle requise.")
    AppendLog("RESULT=partial")
    ExitApp(0)
}

WriteLive("Réglages appliqués.")
AppendLog("RESULT=ok")

if FileExist(uiaScript) {
    psExe := A_WinDir "\System32\WindowsPowerShell\v1.0\powershell.exe"
    if !FileExist(psExe)
        psExe := "powershell.exe"
    cmdPost := '"' psExe '" -NoProfile -STA -ExecutionPolicy Bypass -File "' uiaScript '" -Phase postinstall -LiveStatusPath "' liveFile '" -LogPath "' logFile '"'
    exitCode := RunWait(cmdPost, , "Hide")
    if (exitCode = 0) {
        AppendLog("POSTINSTALL=ok")
        WriteLive("Installation lancée.")
    } else {
        AppendLog("POSTINSTALL=exit_" exitCode)
    }
}

ExitApp(0)
