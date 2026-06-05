#Requires AutoHotkey v2.0
#SingleInstance Force

vendor := (A_Args.Length >= 1 && A_Args[1] != "") ? A_Args[1] : "NVIDIA"
appRoot := (A_Args.Length >= 2 && A_Args[2] != "") ? A_Args[2] : (A_ScriptDir "\..")

global logFile := appRoot "\logs\ddu-auto-clean.log"
global liveFile := appRoot "\logs\ddu-auto-clean-live.txt"
global uiaScript := A_ScriptDir "\ddu-auto-clean-uia.ps1"

WriteLive(msg) {
    global liveFile
    try FileAppend("STATUS=" msg "`n", liveFile, "UTF-8")
}

AppendLog(line) {
    global logFile
    try FileAppend(line "`n", logFile, "UTF-8")
}

TrySafeModeOkOnHwnd(hwnd) {
    try {
        txt := WinGetText("ahk_id " hwnd)
    } catch as err {
        return false
    }
    if !RegExMatch(txt, "i)safe mode|mode sans .?chec|not in safe mode|vous n.?.?tes pas en mode")
        return false
    if !RegExMatch(txt, "i)Display Driver Uninstaller|DDU|Driver Uninstaller|Guru3D")
        && !RegExMatch(WinGetTitle("ahk_id " hwnd), "i)Display Driver Uninstaller|DDU")
        return false
    try {
        ControlClick("OK", "ahk_id " hwnd,,,, "NA")
        AppendLog("SAFE_MODE_POPUP_FOUND=oui")
        AppendLog("SAFE_MODE_OK_CLICKED=oui")
        WriteLive("Message mode sans échec validé.")
        return true
    } catch as err1 {
        try {
            ControlClick("&OK", "ahk_id " hwnd,,,, "NA")
            AppendLog("SAFE_MODE_POPUP_FOUND=oui")
            AppendLog("SAFE_MODE_OK_CLICKED=oui")
            WriteLive("Message mode sans échec validé.")
            return true
        } catch as err2 {
            AppendLog("SAFE_MODE_POPUP_FOUND=oui")
            AppendLog("SAFE_MODE_OK_CLICKED=non")
            return false
        }
    }
}

TryDismissSafeModePopup() {
    for hwnd in WinGetList("ahk_exe Display Driver Uninstaller.exe") {
        if TrySafeModeOkOnHwnd(hwnd)
            return true
    }
    for hwnd in WinGetList() {
        try {
            title := WinGetTitle("ahk_id " hwnd)
        } catch as err {
            continue
        }
        if !RegExMatch(title, "i)Display Driver Uninstaller|^\s*DDU\s*$")
            continue
        if TrySafeModeOkOnHwnd(hwnd)
            return true
    }
    return false
}

WaitDismissSafeModePopup(maxMs := 1500) {
    t0 := A_TickCount
    safeModeSeen := false
    clicked := false
    while (A_TickCount - t0 < maxMs) {
        if TryDismissSafeModePopup() {
            safeModeSeen := true
            clicked := true
            AppendLog("TIME_AFTER_SAFE_MODE_OK_MS=" (A_TickCount - t0))
            Sleep(300)
            return true
        }
        Sleep(125)
    }
    AppendLog("SAFE_MODE_POPUP_FOUND=" (safeModeSeen ? "oui" : "non"))
    if !safeModeSeen
        AppendLog("SAFE_MODE_OK_CLICKED=non")
    return clicked
}

; ---------- Main ----------
try FileDelete(liveFile)

AppendLog("DATE=" FormatTime(, "yyyy-MM-dd HH:mm:ss"))
AppendLog("ACTION=auto_clean")
AppendLog("GPU_SELECTED=" vendor)
AppendLog("LONG_SLEEP_REMOVED=oui")
AppendLog("AHK_VERSION_MODE=v2")
AppendLog("FINAL_QUIT_WATCHER=disabled")

WriteLive("[DDU] Ouverture DDU...")
AppendLog("[DDU] Ouverture DDU...")
dduOpenT0 := A_TickCount
if !WinWait("Display Driver Uninstaller",, 5) {
    if !WinWait("DDU",, 5) {
        AppendLog("RESULT=ddu_window_timeout")
        AppendLog("ERROR=ddu_window_timeout")
        WriteLive("DDU semble prendre trop de temps, vérifie la fenêtre DDU")
        ExitApp(3)
    }
}
openMs := A_TickCount - dduOpenT0
AppendLog("[DDU] Fenêtre détectée.")
AppendLog("[DDU Timing] Fenêtre DDU détectée en " openMs " ms.")
WriteLive("[DDU] Fenêtre détectée.")
Sleep(200)

if !FileExist(uiaScript) {
    AppendLog("RESULT=uia_script_missing")
    AppendLog("ERROR=uia_script_missing")
    WriteLive("DDU lancé — surveillance du nettoyage en cours...")
    ExitApp(5)
}

psExe := A_WinDir "\System32\WindowsPowerShell\v1.0\powershell.exe"
if !FileExist(psExe)
    psExe := "powershell.exe"

cmd := '"' psExe '" -NoProfile -STA -ExecutionPolicy Bypass -File "' uiaScript '" -Vendor ' vendor ' -NoSafeModeArg oui -LiveStatusPath "' liveFile '" -LogPath "' logFile '"'
exitCode := RunWait(cmd, , "Hide")

resultTag := "fail"
if FileExist(liveFile) {
    try {
        liveBody := FileRead(liveFile, "UTF-8")
        if InStr(liveBody, "DDU fermé") || InStr(liveBody, "Nettoyage lancé")
            resultTag := "ok"
        else if InStr(liveBody, "introuvable") || InStr(liveBody, "impossible")
            resultTag := "partial"
    } catch as err {
    }
}

if (exitCode = 0 || resultTag = "ok") {
    AppendLog("RESULT=ok")
    ExitApp(0)
}

if (resultTag = "partial" || exitCode = 6) {
    AppendLog("RESULT=partial")
    ExitApp(4)
}

if (exitCode = 7) {
    AppendLog("RESULT=manual_required")
    ExitApp(7)
}

AppendLog("RESULT=automation_failed")
AppendLog("ERROR=exit_code_" exitCode)
WriteLive("DDU lancé — surveillance du nettoyage en cours...")
ExitApp(exitCode)
