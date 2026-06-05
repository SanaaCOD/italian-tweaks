#Requires AutoHotkey v2.0
#SingleInstance Off

; Watcher final DDU — clic Yes/Oui sur « voulez-vous quitter ? » uniquement (isolé, AHK v2).

appRoot := (A_Args.Length >= 1 && A_Args[1] != "") ? A_Args[1] : (A_ScriptDir "\..")
logFile := appRoot "\logs\ddu-final-quit.log"

LogMsg(msg) {
    global logFile
    try {
        SplitPath(logFile, , &logDir)
        if (logDir && !DirExist(logDir))
            DirCreate(logDir)
        FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " " msg "`n", logFile, "UTF-8")
    } catch as err {
    }
}

ContainsAny(text, words) {
    if !text
        return false
    textLower := StrLower(text)
    for word in words {
        if InStr(textLower, StrLower(word))
            return true
    }
    return false
}

FindButtonByText(hwnd, labels) {
    winId := "ahk_id " hwnd
    try {
        controls := WinGetControls(winId)
        for ctrl in controls {
            try {
                txt := ControlGetText(ctrl, winId)
                for label in labels {
                    if (txt = label || InStr(txt, label)) {
                        return ctrl
                    }
                }
            } catch as err {
            }
        }
    } catch as err {
    }
    return ""
}

; ---------- Main ----------
try {
    if FileExist(logFile)
        FileDelete(logFile)
} catch as err {
}

LogMsg("WATCHER_STARTED=oui")

quitWords := [
    "voulez-vous quitter",
    "quitter maintenant",
    "quitter ddu",
    "do you want to quit",
    "do you want to exit",
    "exit now",
    "want to quit",
    "want to exit"
]

doneWords := [
    "désinstallation",
    "desinstallation",
    "terminée",
    "terminee",
    "uninstall complete",
    "completed",
    "finished",
    "parfaite terminée"
]

restartWords := [
    "restart",
    "reboot",
    "redémarrer",
    "redemarrer",
    "redémarrage",
    "redemarrage",
    "shutdown",
    "éteindre",
    "eteindre"
]

yesLabels := ["Yes", "&Yes", "Oui", "&Oui"]

endTime := A_TickCount + 600000
finalPopupSeen := false
yesBtnSeen := false
yesClicked := false
restartSeen := false
popupSnippet := ""
watcherTimedOut := false

while (A_TickCount < endTime) {
    try {
        for hwnd in WinGetList() {
            title := ""
            body := ""
            try {
                title := WinGetTitle("ahk_id " hwnd)
            } catch as err {
            }
            try {
                body := WinGetText("ahk_id " hwnd)
            } catch as err {
            }

            allText := title "`n" body
            if !ContainsAny(allText, ["Display Driver Uninstaller", "DDU", "Driver Uninstaller", "Guru3D"])
                continue

            if !ContainsAny(allText, quitWords)
                continue
            if !ContainsAny(allText, doneWords)
                continue

            finalPopupSeen := true
            snippet := StrReplace(allText, "`n", " | ")
            if (StrLen(snippet) > 500)
                snippet := SubStr(snippet, 1, 500)
            popupSnippet := snippet

            LogMsg("FINAL_POPUP_FOUND=oui")
            LogMsg("FINAL_POPUP_TEXT=" snippet)

            if ContainsAny(allText, restartWords) {
                restartSeen := true
                LogMsg("FINAL_RESTART_TEXT_DETECTED=oui")
                LogMsg("ACTION=manual_required")
                LogMsg("YES_BUTTON_FOUND=non")
                LogMsg("YES_CLICKED=non")
                LogMsg("WATCHER_TIMEOUT=non")
                LogMsg("WATCHER_ERROR=")
                ExitApp(2)
            }

            btn := FindButtonByText(hwnd, yesLabels)
            if (btn != "") {
                yesBtnSeen := true
                try {
                    ControlClick(btn, "ahk_id " hwnd,,,, "NA")
                    yesClicked := true
                    LogMsg("YES_BUTTON_FOUND=oui")
                    LogMsg("YES_CLICKED=oui")
                    LogMsg("FINAL_RESTART_TEXT_DETECTED=non")
                    LogMsg("WATCHER_TIMEOUT=non")
                    LogMsg("WATCHER_ERROR=")
                    ExitApp(0)
                } catch as err {
                    LogMsg("WATCHER_ERROR=" err.Message)
                }
            } else {
                LogMsg("YES_BUTTON_FOUND=non")
                try {
                    WinActivate("ahk_id " hwnd)
                    Sleep(200)
                    Send("{Enter}")
                    yesClicked := true
                    LogMsg("YES_CLICKED=enter_fallback")
                    LogMsg("FINAL_RESTART_TEXT_DETECTED=non")
                    LogMsg("WATCHER_TIMEOUT=non")
                    LogMsg("WATCHER_ERROR=")
                    ExitApp(0)
                } catch as err {
                    LogMsg("ENTER_FALLBACK_ERROR=" err.Message)
                    LogMsg("WATCHER_ERROR=" err.Message)
                }
            }
        }
    } catch as err {
        LogMsg("WATCHER_ERROR=" err.Message)
    }
    Sleep(500)
}

watcherTimedOut := true
LogMsg("FINAL_POPUP_FOUND=" . (finalPopupSeen ? "oui" : "non"))
if (popupSnippet != "")
    LogMsg("FINAL_POPUP_TEXT=" popupSnippet)
LogMsg("FINAL_RESTART_TEXT_DETECTED=" . (restartSeen ? "oui" : "non"))
LogMsg("YES_BUTTON_FOUND=" . (yesBtnSeen ? "oui" : "non"))
LogMsg("YES_CLICKED=" . (yesClicked ? "oui" : "non"))
LogMsg("WATCHER_TIMEOUT=oui")
if !yesClicked
    LogMsg("WATCHER_ERROR=")
ExitApp(1)
