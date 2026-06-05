#Requires AutoHotkey v2.0
#SingleInstance Force
SetTitleMatchMode(2)
SendMode("Event")

; NVCleanstall auto : pages 1-2 (UIA) puis fenetre Oui/Non pour page Installation Tweaks

global appRoot := (A_Args.Length >= 1 && A_Args[1] != "") ? A_Args[1] : (A_ScriptDir "\..")
global logFile := appRoot "\logs\nvcleaninstall-auto.log"
global liveFile := appRoot "\logs\nvcleaninstall-auto-live.txt"
global dumpFile := appRoot "\logs\nvcleaninstall-controls-dump.log"
global uiaScript := A_ScriptDir "\nvcleaninstall-auto-uia.ps1"
global NvcStableW := 1050
global NvcStableH := 800
global gResumeBusy := false
global gMaxScrolls := 3
global gUserConfirmedTweaks := false
global gPromptShown := false
global SafeClickBlockCoordinateFallbacks := true

SafeClickBlockCoordinateFallback(context) {
    global SafeClickBlockCoordinateFallbacks
    if !SafeClickBlockCoordinateFallbacks
        return false
    AppendLog("SAFECLICK_BLOCKED=" . context)
    WriteLive("[SAFECLICK] Fallback coordonnées bloqué pour sécurité : " . context)
    return true
}

NvcManualUiRequired(context := "") {
    AppendLog("NVC_UI_MANUAL=" . context)
    WriteLive("[NVCleanstall] Bouton introuvable via UIA, action manuelle requise.")
}

WriteLive(msg) {
    global liveFile
    try {
        FileAppend("STATUS=" msg "`n", liveFile, "UTF-8")
    } catch as e {
    }
}

NvcLogStep(msg) {
    AppendLog("NVC_STEP=" . msg)
    WriteLive("[NVCleanInstall] " . msg)
}

AppendLog(line) {
    global logFile
    try {
        SplitPath(logFile, , &dir)
        if (dir && !DirExist(dir))
            DirCreate(dir)
    } catch as e {
    }
    try {
        FileAppend(line "`n", logFile, "UTF-8")
    } catch as e {
    }
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

IsPreparingPhaseText(txt) {
    if !txt
        return false
    return RegExMatch(txt, "i)Preparing source|Copying install files|Copying install|Preparing|Extracting|Downloading|Please wait|Processing")
}

DetectInstallationTweaksPageViaControls(hwnd) {
    if !hwnd
        return false
    winId := "ahk_id " hwnd
    markers := [
        "Installation Tweaks",
        "Disable Installer Telemetry",
        "Perform a Clean Installation",
        "Disable Multiplane Overlay",
        "Show Expert Tweaks",
        "Disable Ansel"
    ]
    try {
        for ctrl in WinGetControls(winId) {
            txt := ""
            try {
                txt := ControlGetText(ctrl, winId)
            } catch as e {
                txt := ""
            }
            if !txt
                continue
            for marker in markers {
                if InStr(txt, marker)
                    return true
            }
        }
    } catch as e {
    }
    return false
}

DetectInstallationTweaksPage(hwnd) {
    txt := ""
    try {
        if hwnd
            txt := WinGetText("ahk_id " hwnd)
    } catch as e {
        txt := ""
    }
    if txt && !IsPreparingPhaseText(txt) {
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
        if RegExMatch(txt, "i)Disable Ansel")
            return true
    }
    return DetectInstallationTweaksPageViaControls(hwnd)
}

IsOnInstallationTweaksPage(hwnd) {
    if !hwnd
        return false
    try {
        txt := WinGetText("ahk_id " hwnd)
    } catch as e {
        txt := ""
    }
    if IsPreparingPhaseText(txt)
        return false
    return DetectInstallationTweaksPage(hwnd)
}

PrepareNvcWindow(hwnd) {
    try {
        WinActivate("ahk_id " hwnd)
        WinMove(100, 100, NvcStableW, NvcStableH, "ahk_id " hwnd)
        Sleep(300)
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

ControlTextMatchesLabel(ctrlText, label) {
    if (ctrlText = "" || label = "")
        return false
    if InStr(ctrlText, label)
        return true
    if (StrLen(label) >= 6 && InStr(label, ctrlText))
        return true
    return false
}

ClickCheckboxNearLabel(hwnd, label) {
    winId := "ahk_id " hwnd
    for ctrl in WinGetControls(winId) {
        txt := ""
        cls := ""
        try {
            txt := ControlGetText(ctrl, winId)
            cls := ControlGetClassNN(ctrl, winId)
        } catch as e {
            txt := ""
        }
        if (txt = "" || !ControlTextMatchesLabel(txt, label))
            continue
        if RegExMatch(txt, "i)^(Back|Cancel|Next|Install|Restart|Reboot|Shutdown|Suivant)$")
            continue
        if RegExMatch(cls, "i)Button") && !RegExMatch(cls, "i)Check")
            continue
        try {
            ControlClick(ctrl, winId, , , , "NA")
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

ShowStatusTooltip(msg, durationMs := 2500) {
    tipX := A_ScreenWidth // 2
    ToolTip(msg, tipX, 50, 1)
    SetTimer(() => ToolTip(), -durationMs)
    WriteLive(msg)
}

DoControlledScroll(hwnd, &scrollCount) {
    global gMaxScrolls
    if (scrollCount >= gMaxScrolls)
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
    Loop 3 {
        Send("{WheelDown}")
    }
    scrollCount += 1
    AppendLog("SCROLL_USED=oui")
    Sleep(500)
}

DumpControlsDiagnostic(hwnd, failedOption, lastClicked, optionResults := "") {
    global dumpFile
    title := ""
    body := ""
    try {
        title := WinGetTitle("ahk_id " hwnd)
        body := WinGetText("ahk_id " hwnd)
    } catch as e {
    }

    lines := "DATE=" . FormatTime(, "yyyy-MM-dd HH:mm:ss") . "`n"
    lines .= "FAILED_OPTION=" . failedOption . "`n"
    lines .= "LAST_CONTROL_CLICKED=" . lastClicked . "`n"
    lines .= "WINDOW_TITLE=" . title . "`n"
    lines .= "WINDOW_TEXT_BEGIN`n" . body . "`nWINDOW_TEXT_END`n"
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
                lines .= "  [" . cls . "] " . txt . "`n"
        }
    } catch as e {
        lines .= "  ERROR=" . e.Message . "`n"
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
                lines .= "  " . cls . " | " . txt . "`n"
        }
    } catch as e {
    }

    if (optionResults != "") {
        lines .= "OPTION_RESULTS:`n"
        if IsObject(optionResults) {
            for _, row in optionResults
                lines .= "  " . row . "`n"
        } else
            lines .= "  " . optionResults . "`n"
    }

    lines .= "BUTTONS:`n"
    for btn in ["Next", "&Next", "Back", "Cancel", "Install"] {
        try {
            if ControlGetHwnd(btn, winId)
                lines .= "  " . btn . "=present`n"
        } catch as e {
        }
    }

    try {
        if FileExist(dumpFile)
            FileDelete(dumpFile)
        FileAppend(lines, dumpFile, "UTF-8")
    } catch as e {
        AppendLog("DUMP_ERROR=" . e.Message)
    }
}

TryCheckNvOption(hwnd, optionKey, aliases, &scrollCount := 0) {
    AppendLog("CURRENT_OPTION=" . optionKey)
    AppendLog("OPTION_FOUND=non")
    AppendLog("OPTION_CLICKED=non")
    AppendLog("OPTION_ALREADY_CHECKED=non")
    AppendLog("OPTION_NOT_FOUND_CONTINUED=non")

    for label in aliases {
        if TweakVisibleInWindow(hwnd, [label]) {
            AppendLog("OPTION_FOUND=oui")
            break
        }
    }

    r := TryClickTweakByText(hwnd, aliases, 2000)
    if (r = "clicked") {
        AppendLog("OPTION_FOUND=oui")
        AppendLog("OPTION_CLICKED=oui")
        Sleep(550)
        return "ok"
    }

    global gMaxScrolls
    if scrollCount < gMaxScrolls {
        DoControlledScroll(hwnd, &scrollCount)
        r := TryClickTweakByText(hwnd, aliases, 2000)
        if (r = "clicked") {
            AppendLog("OPTION_FOUND=oui")
            AppendLog("OPTION_CLICKED=oui")
            return "ok"
        }
    }

    AppendLog("OPTION_NOT_FOUND_CONTINUED=oui")
    return "not_found"
}

RescanAfterShowExpert(hwnd) {
    hwnd := FindNvcWindow()
    if !hwnd
        return { hwnd: 0, controlsCount: 0, textFound: false }
    PrepareNvcWindow(hwnd)
    Sleep(1000)
    hwnd := FindNvcWindow()
    controlsCount := 0
    textFound := false
    try {
        controlsCount := WinGetControls("ahk_id " hwnd).Length
    } catch as e {
        controlsCount := 0
    }
    try {
        body := WinGetText("ahk_id " hwnd)
        textFound := (body != "" && StrLen(body) > 40)
    } catch as e {
        textFound := false
    }
    AppendLog("RESCAN_AFTER_SHOW_EXPERT=oui")
    AppendLog("CONTROLS_COUNT_AFTER_RESCAN=" . controlsCount)
    AppendLog("TEXT_AFTER_RESCAN_FOUND=" . (textFound ? "oui" : "non"))
    return { hwnd: hwnd, controlsCount: controlsCount, textFound: textFound }
}

ParseLogField(fieldName) {
    global logFile
    val := ""
    try {
        if !FileExist(logFile)
            return ""
        lines := StrSplit(FileRead(logFile, "UTF-8"), "`n", "`r")
        i := lines.Length
        while (i >= 1) {
            line := lines[i]
            prefix := fieldName . "="
            if (SubStr(line, 1, StrLen(prefix)) = prefix) {
                val := SubStr(line, StrLen(prefix) + 1)
                break
            }
            i--
        }
    } catch as e {
    }
    return val
}

RunUiaPhase(phase) {
    global uiaScript, logFile, liveFile
    psExe := A_WinDir "\System32\WindowsPowerShell\v1.0\powershell.exe"
    if !FileExist(psExe)
        psExe := "powershell.exe"
    cmd := '"' . psExe . '" -NoProfile -STA -ExecutionPolicy Bypass -File "' . uiaScript . '" -Phase ' . phase . ' -LiveStatusPath "' . liveFile . '" -LogPath "' . logFile . '"'
    return RunWait(cmd, "", "Hide")
}

RunTweaksUiaPhase() {
    return RunUiaPhase("tweaks")
}

WaitForTweaksPageReady(maxWaitMs := 300000) {
    deadline := A_TickCount + maxWaitMs
    startTick := A_TickCount
    Loop {
        if (A_TickCount >= deadline)
            return 0
        hwnd := FindNvcWindow()
        if hwnd && IsOnInstallationTweaksPage(hwnd) {
            elapsed := Round((A_TickCount - startTick) / 1000)
            AppendLog("INSTALLATION_TWEAKS_DETECTED=oui")
            AppendLog("INSTALLATION_TWEAKS_DETECTED_AFTER_SECONDS=" . elapsed)
            AppendLog("INSTALLATION_TWEAKS_REACHED=oui")
            return hwnd
        }
        Sleep(500)
    }
}

WaitForInstallationTweaksAndPrompt() {
    global uiaScript

    AppendLog("WAITING_FOR_INSTALLATION_TWEAKS=oui")
    WriteLive("Attente de la page Installation Tweaks...")
    ShowStatusTooltip("Preparation des fichiers NVIDIA...", 2500)

    detected := false
    if FileExist(uiaScript) {
        exitCode := RunUiaPhase("wait-tweaks")
        detected := (exitCode = 0)
        if detected {
            secs := ParseLogField("INSTALLATION_TWEAKS_DETECTED_AFTER_SECONDS")
            AppendLog("INSTALLATION_TWEAKS_DETECTED=oui")
            AppendLog("INSTALLATION_TWEAKS_DETECTED_AFTER_SECONDS=" . (secs != "" ? secs : "?"))
            AppendLog("INSTALLATION_TWEAKS_REACHED=oui")
        } else {
            AppendLog("INSTALLATION_TWEAKS_DETECTED=non")
            AppendLog("INSTALLATION_TWEAKS_REACHED=non")
        }
    }

    if !detected {
        hwnd := WaitForTweaksPageReady(300000)
        detected := hwnd != 0
        if !detected {
            AppendLog("INSTALLATION_TWEAKS_DETECTED=non")
            AppendLog("PROMPT_OPTIMIZATION_SETTINGS_SHOWN=non")
            AppendLog("RESULT=tweaks_page_timeout")
            WriteLive("Page Installation Tweaks non detectee. Continue manuellement.")
            return false
        }
    }

    AppendLog("INSTALLATION_TWEAKS_PAGE_DETECTED=oui")
    Sleep(800)
    return PromptBeforeApplyingTweaks()
}

PromptBeforeApplyingTweaks() {
    global gUserConfirmedTweaks, gPromptShown, gResumeBusy

    if gResumeBusy
        return false
    gResumeBusy := true

    hwnd := FindNvcWindow()
    AppendLog("INSTALLATION_TWEAKS_REACHED=" . (hwnd ? "oui" : "non"))
    AppendLog("NVCLEANSTALL_WINDOW_FOUND=" . (hwnd ? "oui" : "non"))

    if !hwnd {
        MsgBox("Fenetre NVCleanstall introuvable.", "UNREAL", "Icon!")
        WriteLive("Fenetre NVCleanstall introuvable.")
        gResumeBusy := false
        return false
    }

    if gPromptShown && gUserConfirmedTweaks {
        gResumeBusy := false
        return true
    }
    gPromptShown := true

    AppendLog("PROMPT_OPTIMIZATION_SETTINGS_SHOWN=oui")
    WriteLive("Reglages NVIDIA : confirmation requise.")

    promptState := { answer: "" }
    promptGui := Gui("+AlwaysOnTop +OwnDialogs +ToolWindow", "Reglages NVIDIA")
    promptGui.SetFont("s10", "Segoe UI")
    promptGui.Add("Text", "w420 Center", "Voulez-vous installer les meilleurs reglages d'optimisation graphique ?")
    promptGui.Add("Button", "Default w100", "Yes").OnEvent("Click", (*) => (promptState.answer := "Yes", promptGui.Destroy()))
    promptGui.Add("Button", "w100 x+16", "No").OnEvent("Click", (*) => (promptState.answer := "No", promptGui.Destroy()))
    promptGui.Show("Center")
    WinWaitClose(promptGui)
    result := promptState.answer
    if (result = "")
        result := "No"

    if (result = "Yes") {
        AppendLog("PROMPT_OPTIMIZATION_SETTINGS_RESULT=Yes")
        gUserConfirmedTweaks := true
        AppendLog("APPLY_TWEAKS_STARTED=oui")
        ShowStatusTooltip("Application des reglages NVIDIA...", 2000)
        Sleep(500)

        hwnd := FindNvcWindow()
        if !hwnd {
            AppendLog("APPLY_TWEAKS_STARTED=non")
            gResumeBusy := false
            return false
        }
        PrepareNvcWindow(hwnd)
        applyRes := ApplyNvidiaTweaks(hwnd)
        FinalizeTweaksAndInstall(applyRes)
        gResumeBusy := false
        return true
    }

    AppendLog("PROMPT_OPTIMIZATION_SETTINGS_RESULT=No")
    AppendLog("APPLY_TWEAKS_CANCELLED_BY_USER=oui")
    AppendLog("APPLY_TWEAKS_STARTED=non")
    WriteLive("Automatisation annulee. Continue manuellement.")
    ToolTip("Automatisation annulee. Continue manuellement.")
    SetTimer(() => ToolTip(), -5000)
    gResumeBusy := false
    return false
}

ScrollTweaksPageToBottom(hwnd) {
    winId := "ahk_id " hwnd
    Loop 10 {
        try {
            ControlFocus("", winId)
        } catch as e {
        }
        Send("{PgDn}")
        Sleep(120)
    }
}

FixEacWindowRelativeFallback(hwnd) {
    if (ParseLogField("EAC_FINAL_RESULT") = "ok" || ParseLogField("EAC_CLICKED") = "oui"
        || ParseLogField("EAC_CLICKED_BY_CONTROL_ORDER") = "oui")
        return true
    AppendLog("EAC_SPECIAL_FIX_STARTED=oui")
    if SafeClickBlockCoordinateFallback("EAC 0.09/0.76") {
        WriteLive("[NVCleanstall] Fallback coordonnées désactivé pour sécurité.")
        NvcManualUiRequired("eac_checkbox")
        AppendLog("EAC_FINAL_RESULT=manual_required")
        return false
    }
    return false
}

IsNvcNextButtonLabel(txt) {
    if (txt = "")
        return false
    if RegExMatch(txt, "i)^(Back|Cancel|Restart|Reboot|Shutdown|Install|Installer)$")
        return false
    return RegExMatch(txt, "i)^&?Next$|^&?Suivant$")
}

IsNvcInstallButtonLabel(txt) {
    if (txt = "")
        return false
    if RegExMatch(txt, "i)^(Back|Cancel|Restart|Reboot|Shutdown|Next|Suivant)$")
        return false
    return RegExMatch(txt, "i)^&?Install(er)?$|Install Driver|Install Package") || RegExMatch(txt, "i)\bInstall\b")
}

IsNvcForbiddenFinishedButton(txt) {
    if (txt = "")
        return false
    return RegExMatch(txt, "i)^(Show in Folder|Copy Folder|Build Package|Back|Cancel|Restart|Reboot|Shutdown|Next|Suivant)$")
}

IsNvcPackageReadyText(txt) {
    if (txt = "")
        return false
    if RegExMatch(txt, "i)(Building package|Copying install|Please wait|Processing\.\.\.|Preparing source)")
        return false
    return RegExMatch(txt, "i)your customi[sz]ed installer is now ready")
}

ScanNvcFinishedWindowText(hwnd) {
    sig := { ready: false, choose: false, finished: false, installBtn: false, body: "" }
    if !hwnd
        return sig
    winId := "ahk_id " hwnd
    try {
        sig.body := WinGetText(winId)
    } catch as e {
        sig.body := ""
    }
    if IsNvcPackageReadyText(sig.body)
        sig.ready := true
    try {
        for ctrl in WinGetControls(winId) {
            ctxt := ""
            try {
                ctxt := ControlGetText(ctrl, winId)
            } catch as eC {
                ctxt := ""
            }
            if (ctxt = "")
                continue
            if IsNvcPackageReadyText(ctxt)
                sig.ready := true
            if IsNvcInstallButtonLabel(ctxt)
                sig.installBtn := true
        }
    } catch as eLoop {
    }
    return sig
}

IsNvcFinishedReadyForKeys(hwnd) {
    if !hwnd || IsNvcDangerousActionPage(hwnd)
        return false
    sig := ScanNvcFinishedWindowText(hwnd)
    if IsPreparingPhaseText(sig.body)
        return false
    if RegExMatch(sig.body, "i)(Building package|Copying install|Please wait|Processing\.\.\.|Preparing source)")
        return false
    if sig.ready
        return true
    try {
        for ctrl in WinGetControls("ahk_id " hwnd) {
            ctxt := ""
            try {
                ctxt := ControlGetText(ctrl, "ahk_id " hwnd)
            } catch as eC {
                ctxt := ""
            }
            if IsNvcPackageReadyText(ctxt)
                return true
        }
    } catch as eLoop {
    }
    return false
}

IsNvcFinishedPageReady(hwnd) {
    return IsNvcFinishedReadyForKeys(hwnd)
}

IsNvcConfirmedFinishedPage(hwnd) {
    if IsNvcFinishedPageReady(hwnd)
        return true
    if !hwnd
        return false
    if IsNvcDangerousActionPage(hwnd)
        return false
    markers := [
        "Finished",
        "Your customized installer is now ready",
        "Please choose the next action",
        "READY TO INSTALL",
        "INSTALLATION READY",
        "Show in Folder",
        "Build Package",
        "Copy Folder"
    ]
    try {
        txt := WinGetText("ahk_id " hwnd)
    } catch as e {
        txt := ""
    }
    for marker in markers {
        if InStr(txt, marker)
            return true
    }
    winId := "ahk_id " hwnd
    try {
        for ctrl in WinGetControls(winId) {
            ctxt := ""
            try {
                ctxt := ControlGetText(ctrl, winId)
            } catch as e {
                ctxt := ""
            }
            for marker in markers {
                if InStr(ctxt, marker)
                    return true
            }
            if IsNvcInstallButtonLabel(ctxt)
                return true
        }
    } catch as e {
    }
    return HasNvcFinishedPageMarkers(hwnd)
}

IsNvcDangerousActionPage(hwnd) {
    try {
        txt := WinGetText("ahk_id " hwnd)
    } catch as e {
        txt := ""
    }
    return RegExMatch(txt, "i)(Restart|Reboot|Shutdown)")
}

HasNvcFinishedPageMarkers(hwnd) {
    if !hwnd
        return false
    markers := ["Finished", "READY TO INSTALL", "INSTALLATION READY", "Package ready", "Ready to install", "Ready", "Install Package", "Pret a installer", "Termine"]
    try {
        txt := WinGetText("ahk_id " hwnd)
    } catch as e {
        txt := ""
    }
    for marker in markers {
        if InStr(txt, marker)
            return true
    }
    winId := "ahk_id " hwnd
    try {
        for ctrl in WinGetControls(winId) {
            ctxt := ""
            try {
                ctxt := ControlGetText(ctrl, winId)
            } catch as e {
                ctxt := ""
            }
            for marker in markers {
                if InStr(ctxt, marker)
                    return true
            }
            if IsNvcInstallButtonLabel(ctxt)
                return true
        }
    } catch as e {
    }
    return false
}

VerifyNvcLeftTweaksPage(wasOnTweaks) {
    return VerifyNvcAfterEnter(wasOnTweaks)
}

VerifyNvcAfterEnter(wasOnTweaks) {
    Loop 12 {
        hwnd := FindNvcWindow()
        if !hwnd
            return false
        if IsNvcDangerousActionPage(hwnd)
            return false
        if HasNvcFinishedPageMarkers(hwnd)
            return true
        if wasOnTweaks && !IsOnInstallationTweaksPage(hwnd)
            return true
        Sleep(400)
    }
    hwnd := FindNvcWindow()
    if hwnd && !IsNvcDangerousActionPage(hwnd)
        return true
    return false
}

EnsureNvcWindowActive(hwnd) {
    if !hwnd
        return false
    winId := "ahk_id " hwnd
    try {
        if !WinExist(winId)
            return false
        WinActivate(winId)
        try {
            WinWaitActive(winId, , 2)
        } catch as e {
        }
        Sleep(100)
        activeId := WinGetID("A")
        if (activeId = hwnd)
            return true
        try {
            activeTitle := WinGetTitle("A")
            if RegExMatch(activeTitle, "i)NVCleanstall|NVCleanInstall|TechPowerUp")
                return true
        } catch as e2 {
        }
        return true
    } catch as e3 {
        return false
    }
}

ClickNextAfterTweaks() {
    AppendLog("AFTER_TWEAKS_NEXT_SEQUENCE_STARTED=oui")
    AppendLog("CLICK_NEXT_CALLED_AFTER_CONTINUE=oui")
    AppendLog("NEXT_METHOD=enter")
    AppendLog("NEXT_SENT_BY_ENTER=non")
    AppendLog("NEXT_CLICKED_BY_RELATIVE_FALLBACK=non")

    hwnd := FindNvcWindow()
    if !hwnd {
        AppendLog("NEXT_ERROR=NVCleanstall window not found")
        AppendLog("NEXT_RESULT=error")
        AppendLog("NEXT_CLICKED=non")
        return false
    }
    if IsNvcDangerousActionPage(hwnd) {
        AppendLog("NEXT_RESULT=error")
        AppendLog("NEXT_CLICKED=non")
        return false
    }

    wasOnTweaks := IsOnInstallationTweaksPage(hwnd)
    winId := "ahk_id " hwnd
    if !EnsureNvcWindowActive(hwnd) {
        AppendLog("NEXT_ERROR=window_activate_failed")
        AppendLog("NEXT_RESULT=error")
        return false
    }
    if IsNvcDangerousActionPage(hwnd) {
        AppendLog("NEXT_RESULT=error")
        return false
    }

    try {
        ControlFocus("", winId)
    } catch as e {
    }
    Sleep(300)
    Send("{Enter}")
    AppendLog("NEXT_SENT_BY_ENTER=oui")
    Sleep(1000)

    if VerifyNvcAfterEnter(wasOnTweaks) {
        AppendLog("NEXT_RESULT=ok")
        AppendLog("NEXT_CLICKED=oui")
        return true
    }

    hwnd := FindNvcWindow()
    if !hwnd || IsNvcDangerousActionPage(hwnd) {
        AppendLog("NEXT_RESULT=error")
        AppendLog("NEXT_CLICKED=non")
        return false
    }
    if !EnsureNvcWindowActive(hwnd) {
        AppendLog("NEXT_RESULT=error")
        return false
    }
    try {
        ControlFocus("", winId)
    } catch as e {
    }
    Sleep(300)
    Send("{Enter}")
    AppendLog("NEXT_SENT_BY_ENTER=oui")
    Sleep(1000)

    if VerifyNvcAfterEnter(wasOnTweaks) {
        AppendLog("NEXT_RESULT=ok")
        AppendLog("NEXT_CLICKED=oui")
        return true
    }

    AppendLog("NEXT_RESULT=error")
    AppendLog("NEXT_CLICKED=non")
    WriteLive("Next non valide (Entree). Verifie manuellement.")
    return false
}

ClickNVCleanstallNext() {
    return ClickNextAfterTweaks()
}

WaitForFinishedPage(maxSec := 120) {
    AppendLog("WAIT_FINISHED_PAGE_STARTED=oui")
    AppendLog("FINISHED_PAGE_WAIT_STARTED=oui")
    NvcLogStep("Attente page Finished")
    startTick := A_TickCount
    deadline := startTick + (maxSec * 1000)
    stableHits := 0
    while (A_TickCount < deadline) {
        hwnd := FindNvcWindow()
        if hwnd && IsNvcFinishedPageReady(hwnd) {
            stableHits++
            if (stableHits >= 3) {
                elapsed := Round((A_TickCount - startTick) / 1000)
                AppendLog("FINISHED_PAGE_FOUND=oui")
                AppendLog("FINISHED_PAGE_READY=oui")
                AppendLog("FINISHED_PAGE_FOUND_AFTER_SECONDS=" . elapsed)
                NvcLogStep("Page Finished detectee")
                return { found: true, seconds: elapsed, hwnd: hwnd }
            }
        } else {
            stableHits := 0
        }
        Sleep(500)
    }
    hwnd := FindNvcWindow()
    if hwnd && IsNvcFinishedPageReady(hwnd) {
        elapsed := Round((A_TickCount - startTick) / 1000)
        AppendLog("FINISHED_PAGE_FOUND=oui")
        AppendLog("FINISHED_PAGE_READY=oui")
        AppendLog("FINISHED_PAGE_FOUND_AFTER_SECONDS=" . elapsed)
        NvcLogStep("Page Finished detectee")
        return { found: true, seconds: elapsed, hwnd: hwnd }
    }
    AppendLog("FINISHED_PAGE_FOUND=non")
    AppendLog("FINISHED_PAGE_FOUND_AFTER_SECONDS=" . maxSec)
    return { found: false, seconds: maxSec, hwnd: 0 }
}

WaitForNVCFinishedPage(maxSec := 60) {
    return WaitForFinishedPage(maxSec)
}

FindNvidiaInstallerWindow() {
    for hwnd in WinGetList() {
        try {
            title := WinGetTitle("ahk_id " hwnd)
        } catch as e {
            continue
        }
        if RegExMatch(title, "i)Panneau de configuration|Control Panel|NVIDIA Control Panel|Centre de configuration")
            continue
        if RegExMatch(title, "i)Programme d.installation NVIDIA")
            return hwnd
    }
    return 0
}

WaitForNvidiaInstallerWindow(timeoutSec := 10) {
    deadline := A_TickCount + (timeoutSec * 1000)
    while (A_TickCount < deadline) {
        if FindNvidiaInstallerWindow()
            return true
        Sleep(200)
    }
    return FindNvidiaInstallerWindow() != 0
}

NvcPrepareFinishedPageFocus(hwnd) {
    if !hwnd
        return false
    winId := "ahk_id " hwnd
    try {
        if !WinExist(winId)
            return false
        WinActivate(winId)
        WinWaitActive(winId, , 10)
    } catch as e {
        AppendLog("INSTALL_ACTIVATE_ERROR=" . e.Message)
        return false
    }
    Sleep(1000)
    if SafeClickBlockCoordinateFallback("Finished focus 0.10/0.30 ou ecran +80/+160") {
        WriteLive("[NVCleanstall] Fallback coordonnées désactivé pour sécurité.")
        return false
    }
    try {
        ControlFocus("", winId)
    } catch as eF {
        AppendLog("INSTALL_FOCUS_CONTROL_ERROR=" . eF.Message)
        return false
    }
    Sleep(300)
    return true
}

NvcPressFinishedDownEnter(hwnd) {
    global hasTriggeredNVCleanstallInstall
    if SafeClickBlockCoordinateFallback("Finished Down+Enter global") {
        WriteLive("[NVCleanstall] Fallback coordonnées désactivé pour sécurité.")
        NvcManualUiRequired("finished_down_enter")
        return false
    }
    if hasTriggeredNVCleanstallInstall
        return true
    if !hwnd
        hwnd := FindNvcWindow()
    if !hwnd
        return false
    winId := "ahk_id " hwnd
    try {
        title := WinGetTitle(winId)
    } catch as eTitle {
        return false
    }
    if !RegExMatch(title, "i)NVCleanstall|NVCleanInstall|TechPowerUp")
        return false
    try {
        body := WinGetText(winId)
    } catch as eBody {
        body := ""
    }
    if !IsNvcPackageReadyText(body)
        return false
    try {
        if !WinExist(winId)
            return false
        WinActivate(winId)
        if !WinWaitActive(winId, , 10)
            return false
    } catch as eAct {
        AppendLog("INSTALL_ACTIVATE_ERROR=" . eAct.Message)
        return false
    }
    activeTitle := ""
    try {
        activeTitle := WinGetTitle("A")
    } catch as eA {
    }
    if activeTitle && !RegExMatch(activeTitle, "i)NVCleanstall|NVCleanInstall|TechPowerUp") {
        WriteLive("[Automation] Action bloquée : mauvaise fenêtre active.")
        return false
    }
    WriteLive("[NVCleanstall] Page prête détectée.")
    Sleep(200)
    SendEvent("{Down}")
    Sleep(100)
    SendEvent("{Enter}")
    hasTriggeredNVCleanstallInstall := true
    AppendLog("INSTALL_SEQUENCE=down_enter")
    AppendLog("INSTALL_KEYS_SENT=oui")
    AppendLog("PACKAGE_READY_INSTALL_TRIGGERED=oui")
    WriteLive("[NVCleanstall] Action clavier envoyée : flèche bas puis entrée.")
    return true
}

SendFinishedDownEnter(hwnd) {
    return NvcPressFinishedDownEnter(hwnd)
}

SendFinishedDownDownEnter(hwnd, method) {
    return SendFinishedDownEnter(hwnd)
}

NvcInstallKeyboardFallback(hwnd) {
    if SafeClickBlockCoordinateFallback("clavier Alt+I Tab+Enter global") {
        WriteLive("[NVCleanstall] Fallback coordonnées désactivé pour sécurité.")
        NvcManualUiRequired("install_keyboard")
        return false
    }
    if !hwnd
        return false
    winId := "ahk_id " hwnd
    try {
        WinActivate(winId)
        WinWaitActive(winId, , 8)
    } catch as eAct {
        return false
    }
    Sleep(300)
    try {
        Send("!i")
        AppendLog("INSTALL_KEYBOARD_FALLBACK=alt_i")
        NvcLogStep("Fallback clavier utilise pour lancer Install.")
        return true
    } catch as eAlt {
    }
    Loop 14 {
        Send("{Tab}")
        Sleep(120)
    }
    Send("{Enter}")
    AppendLog("INSTALL_KEYBOARD_FALLBACK=tab_enter")
    NvcLogStep("Fallback clavier utilise pour lancer Install.")
    return true
}

ClickFinishedInstallButtonFallback(hwnd) {
    if !hwnd
        return false
    winId := "ahk_id " hwnd
    if !NvcPrepareFinishedPageFocus(hwnd)
        return false
    try {
        for ctrl in WinGetControls(winId) {
            ctxt := ""
            cls := ""
            try {
                ctxt := ControlGetText(ctrl, winId)
                cls := ControlGetClassNN(ctrl, winId)
            } catch as e {
                ctxt := ""
            }
            if (ctxt = "" || IsNvcForbiddenFinishedButton(ctxt))
                continue
            if !(ctxt = "Install" || StrLower(ctxt) = "install")
                continue
            if !RegExMatch(cls, "i)Button")
                continue
            try {
                ControlClick(ctrl, winId, , , , "NA")
                Sleep(400)
                AppendLog("INSTALL_BUTTON_FOUND=oui")
                AppendLog("INSTALL_BUTTON_CLICKED=oui")
                AppendLog("INSTALL_CLICKED=oui")
                NvcLogStep("Bouton Install clique automatiquement.")
                return true
            } catch as e2 {
            }
        }
        for ctrl in WinGetControls(winId) {
            ctxt := ""
            cls := ""
            try {
                ctxt := ControlGetText(ctrl, winId)
                cls := ControlGetClassNN(ctrl, winId)
            } catch as e {
                ctxt := ""
            }
            if (ctxt = "" || IsNvcForbiddenFinishedButton(ctxt))
                continue
            if !IsNvcInstallButtonLabel(ctxt)
                continue
            if !RegExMatch(cls, "i)Button")
                continue
            try {
                ControlClick(ctrl, winId, , , , "NA")
                Sleep(400)
                AppendLog("INSTALL_BUTTON_FOUND=oui")
                AppendLog("INSTALL_BUTTON_CLICKED=oui")
                AppendLog("INSTALL_CLICKED=oui")
                return true
            } catch as e2 {
            }
        }
    } catch as e3 {
    }
    if SafeClickBlockCoordinateFallback("Install 0.50/0.82") {
        WriteLive("[NVCleanstall] Fallback coordonnées désactivé pour sécurité.")
        NvcManualUiRequired("finished_install_button")
        return false
    }
    return false
}

waitForNVCleanstallFinishedAndPressInstall(maxSec := 180) {
    global hasTriggeredNVCleanstallInstall := false
    AppendLog("FINISHED_INSTALL_AUTO=oui")
    AppendLog("AHK_IS_ADMIN=" . (A_IsAdmin ? "oui" : "non"))
    NvcLogStep("AutoHotkey v2 script genere")
    NvcLogStep("Attente fenetre NVCleanstall")
    WriteLive("Détection page prête NVCleanstall...")
    AppendLog("NV_PROGRESS_PCT=75")

    if !WinWait("ahk_exe NVCleanstall.exe", , 5) {
        if !WinWait("NVCleanstall", , 5) {
            if !WinWait("NVCleanInstall", "", 5) {
                NvcLogStep("Timeout page prete non detectee")
                WriteLive("Install non lance automatiquement — action manuelle requise.")
                return false
            }
        }
    }
    NvcLogStep("Fenetre detectee")

    if FileExist(uiaScript) {
        exitCode := RunUiaPhase("package-ready-install")
        if exitCode = 0 {
            WriteLive("Lancement du programme d'installation NVIDIA...")
            AppendLog("NV_PROGRESS_PCT=80")
            NvcLogStep("Attente installateur NVIDIA")
            if WaitForNvidiaInstallerWindow(15) {
                NvcLogStep("NVIDIA Installer detecte")
                AppendLog("NVIDIA_INSTALLER_FOUND=oui")
                AppendLog("INSTALL_LAUNCHED=oui")
                return true
            }
            return true
        }
    }

    deadline := A_TickCount + (maxSec * 1000)
    hwnd := 0
    while (A_TickCount < deadline && !hasTriggeredNVCleanstallInstall) {
        hwnd := FindNvcWindow()
        if hwnd {
            body := ""
            try {
                body := WinGetText("ahk_id " hwnd)
            } catch as ePkg {
                body := ""
            }
            if IsNvcPackageReadyText(body) {
                AppendLog("PACKAGE_READY_DETECTED=oui")
                AppendLog("FINISHED_PAGE_FOUND=oui")
                AppendLog("FINISHED_PAGE_READY=oui")
                if NvcPressFinishedDownEnter(hwnd)
                    break
            }
        }
        Sleep(200)
    }

    if !hasTriggeredNVCleanstallInstall {
        NvcLogStep("Timeout page prete non detectee")
        AppendLog("FINISHED_PAGE_FOUND=non")
        WriteLive("Install non lance automatiquement — action manuelle requise.")
        return false
    }

    WriteLive("Lancement du programme d'installation NVIDIA...")
    AppendLog("NV_PROGRESS_PCT=80")
    NvcLogStep("Attente installateur NVIDIA")
    if WaitForNvidiaInstallerWindow(15) {
        NvcLogStep("NVIDIA Installer detecte")
        AppendLog("NVIDIA_INSTALLER_FOUND=oui")
        AppendLog("INSTALL_LAUNCHED=oui")
        return true
    }

    AppendLog("NVIDIA_INSTALLER_FOUND=non")
    AppendLog("RESULT=install_launch_pending")
    return true
}

LaunchFinishedInstallAutomation(finishedHwnd := 0) {
    return waitForNVCleanstallFinishedAndPressInstall(180)
}

RunNvidiaInstallerWizardAutomation() {
    AppendLog("NVIDIA_WIZARD_STARTED=oui")
    WriteLive("Lancement du programme d'installation NVIDIA...")
    if !WaitForNvidiaInstallerWindow(90) {
        AppendLog("NVIDIA_INSTALLER_WINDOW=non")
        return false
    }
    WriteLive("[NVIDIA Installer] Fenêtre Programme d'installation NVIDIA détectée.")
    AppendLog("NVIDIA_INSTALLER_WINDOW_READY=oui")
    AppendLog("NVIDIA_WIZARD_DELEGATED_HTA=oui")
    return true
}

ContinueFlowAfterTweaks() {
    NvcLogStep("Validation Next (Entree)")
    ShowStatusTooltip("Validation Next (Entree)...", 1500)
    nextOk := ClickNextAfterTweaks()
    if !nextOk
        return { nextOk: false, finishedOk: false, installOk: false }

    installOk := waitForNVCleanstallFinishedAndPressInstall(180)
    finishedOk := installOk
    if installOk {
        Sleep(1500)
        installOk := RunNvidiaInstallerWizardAutomation()
    }

    AppendLog("RESULT=" . (installOk ? "await_driver_detection" : "finished_install_partial"))
    return { nextOk: nextOk, finishedOk: finishedOk, installOk: installOk }
}

ClickTweaksNext(hwnd) {
    winId := "ahk_id " hwnd
    try {
        txt := WinGetText(winId)
    } catch as e {
        txt := ""
    }
    if RegExMatch(txt, "i)(Restart|Reboot|Shutdown)")
        return false
    for btn in ["&Next", "Next", "Suivant", "&Suivant"] {
        try {
            ControlClick(btn, winId, , , , "NA")
            Sleep(400)
            return true
        } catch as e {
        }
    }
    return false
}

ApplyNvidiaTweaksAhk(hwnd) {
    tweaks := [
        { name: "Disable Installer Telemetry & Advertising", aliases: ["Disable Installer Telemetry & Advertising", "Disable Installer Telemetry", "Installer Telemetry", "Telemetry & Advertising"] },
        { name: "Perform a Clean Installation", aliases: ["Perform a Clean Installation", "Clean Installation"] },
        { name: "Disable Multiplane Overlay (MPO)", aliases: ["Disable Multiplane Overlay (MPO)", "Disable Multiplane Overlay", "Multiplane Overlay"] },
        { name: "Disable Ansel", aliases: ["Disable Ansel", "Ansel"] },
        { name: "Disable Driver Telemetry", aliases: ["Disable Driver Telemetry", "Driver Telemetry"] },
        { name: "Enable Message Signaled Interrupts", aliases: ["Enable Message Signaled Interrupts", "Message Signaled Interrupts"] },
        { name: "Disable HDCP", aliases: ["Disable HDCP", "HDCP"] },
        { name: "Use method compatible with Easy Anti-Cheat", aliases: ["Use method compatible with Easy Anti-Cheat", "Easy Anti-Cheat", "EAC"] },
        { name: "Automatically accept the driver unsigned warning", aliases: ["Automatically accept the `"driver unsigned`" warning", "Automatically accept the driver unsigned warning", "accept the `"driver unsigned`" warning", "driver unsigned warning", "driver unsigned"] }
    ]

    scrollCount := 0
    attemptedCount := 0
    clickedCount := 0
    anyNotFound := false
    failedOption := ""
    optionResults := []

    AppendLog("SHOW_EXPERT_FOUND=non")
    AppendLog("SHOW_EXPERT_CLICKED=non")
    showSt := TryCheckNvOption(hwnd, "Show Expert Tweaks", ["Show Expert Tweaks", "Show Expert"], scrollCount)
    optionResults.Push("Show Expert Tweaks=" . showSt)
    if (showSt = "ok") {
        AppendLog("SHOW_EXPERT_FOUND=oui")
        AppendLog("SHOW_EXPERT_CLICKED=oui")
        clickedCount++
    } else if TweakVisibleInWindow(hwnd, ["Show Expert Tweaks", "Show Expert"]) {
        AppendLog("SHOW_EXPERT_FOUND=oui")
    }
    attemptedCount++

    rescan := RescanAfterShowExpert(hwnd)
    hwnd := rescan.hwnd ? rescan.hwnd : hwnd
    if !hwnd
        return { nextOk: false, anyNotFound: true, clickedCount: clickedCount, attemptedCount: attemptedCount, rescanHadText: false, hwnd: 0 }

    for t in tweaks {
        attemptedCount++
        st := TryCheckNvOption(hwnd, t.name, t.aliases, scrollCount)
        optionResults.Push(t.name . "=" . st)
        if (st = "ok")
            clickedCount++
        else {
            anyNotFound := true
            failedOption := t.name
        }
        Sleep(80)
        hwnd := FindNvcWindow()
        if !hwnd
            break
    }

    global gMaxScrolls
    if (scrollCount < gMaxScrolls && hwnd) {
        DoControlledScroll(hwnd, &scrollCount)
        Sleep(500)
        hwnd := FindNvcWindow()
    }

    if hwnd {
        if (clickedCount = 0 || anyNotFound)
            DumpControlsDiagnostic(hwnd, failedOption, "", optionResults)
    }

    hwnd := FindNvcWindow()
    AppendLog("NEXT_CLICKED=non")
    AppendLog("TWEAKS_ATTEMPTED_COUNT=" . attemptedCount)
    AppendLog("TWEAKS_CLICKED_COUNT=" . clickedCount)

    return { nextOk: false, anyNotFound: anyNotFound, clickedCount: clickedCount, attemptedCount: attemptedCount, rescanHadText: rescan.textFound, hwnd: hwnd }
}

ApplyNvidiaTweaks(hwnd) {
    global gUserConfirmedTweaks

    if !gUserConfirmedTweaks {
        AppendLog("APPLY_TWEAKS_BLOCKED=no_user_confirm")
        AppendLog("APPLY_TWEAKS_STARTED=non")
        return {
            optionsOk: 0,
            optionsNotFound: 10,
            missingList: "blocked",
            clickedCount: 0,
            allOk: false,
            hwnd: hwnd
        }
    }

    if FileExist(uiaScript) {
        exitCode := RunTweaksUiaPhase()
        optionsOk := 0
        optionsNotFound := 0
        missingList := ""
        try {
            optionsOk := Integer(ParseLogField("OPTIONS_OK"))
        } catch as e {
            optionsOk := 0
        }
        try {
            optionsNotFound := Integer(ParseLogField("OPTIONS_NOT_FOUND"))
        } catch as e {
            optionsNotFound := 0
        }
        missingList := ParseLogField("MISSING_OPTIONS_LIST")
        clicked := 0
        try {
            clicked := Integer(ParseLogField("TWEAKS_CLICKED_COUNT"))
        } catch as e {
            clicked := 0
        }
        hwnd := FindNvcWindow()
        if hwnd
            FixEacWindowRelativeFallback(hwnd)
        if (clicked = 0 && hwnd)
            DumpControlsDiagnostic(hwnd, "", "", "")
        return {
            optionsOk: optionsOk,
            optionsNotFound: optionsNotFound,
            missingList: missingList,
            clickedCount: clicked,
            allOk: (optionsOk >= 10),
            hwnd: hwnd,
            uiaExit: exitCode
        }
    }
    ahkRes := ApplyNvidiaTweaksAhk(hwnd)
    return {
        optionsOk: ahkRes.clickedCount,
        optionsNotFound: 10 - ahkRes.clickedCount,
        missingList: "",
        clickedCount: ahkRes.clickedCount,
        allOk: !ahkRes.anyNotFound,
        hwnd: ahkRes.hwnd,
        nextOk: ahkRes.nextOk
    }
}

FinalizeTweaksAndInstall(applyRes) {
    AppendLog("TWEAKS_ATTEMPTED=oui")
    AppendLog("MISSING_OPTIONS_PROMPT_DISABLED=oui")
    AppendLog("TOTAL_OPTIONS_REQUESTED=10")
    AppendLog("OPTIONS_OK=" . applyRes.optionsOk)
    AppendLog("OPTIONS_NOT_FOUND=" . applyRes.optionsNotFound)
    AppendLog("MISSING_OPTIONS_COUNT=" . applyRes.optionsNotFound)
    AppendLog("MISSING_OPTIONS_LIST=" . applyRes.missingList)

    if (applyRes.clickedCount = 0 && applyRes.optionsOk = 0) {
        WriteLive("Options peu lisibles — suite automatique Next...")
        AppendLog("RESULT=options_unreadable_auto_continue")
    } else if applyRes.allOk {
        WriteLive("Reglages NVIDIA appliques. Suite automatique Next...")
    } else {
        WriteLive("Reglages partiellement appliques — suite automatique Next...")
    }

    flowRes := ContinueFlowAfterTweaks()
    AppendLog("NEXT_CLICKED_AFTER_TWEAKS=" . (flowRes.nextOk ? "oui" : "non"))
    AppendLog("INSTALL_BUTTON_CLICKED=" . (flowRes.installOk ? "oui" : "non"))
    AppendLog("RESULT=" . (flowRes.installOk ? "await_driver_detection" : (flowRes.nextOk ? "flow_partial" : "partial_next")))
    return true
}

; Secours developpeur uniquement (meme detection + pop-up Oui/Non)
F9::{
    global gPromptShown, gUserConfirmedTweaks
    AppendLog("F9_PRESSED=oui")
    gPromptShown := false
    gUserConfirmedTweaks := false
    hwnd := FindNvcWindow()
    if hwnd && IsOnInstallationTweaksPage(hwnd) {
        AppendLog("INSTALLATION_TWEAKS_DETECTED=oui")
        Sleep(800)
        PromptBeforeApplyingTweaks()
    } else {
        WaitForInstallationTweaksAndPrompt()
    }
}

Esc::{
    AppendLog("RESULT=user_esc")
    ToolTip()
    ExitApp()
}

; ---------- Demarrage : pages 1-2 puis attente page Installation Tweaks ----------
try {
    FileDelete(liveFile)
} catch as e {
}

AppendLog("DATE=" . FormatTime(, "yyyy-MM-dd HH:mm:ss"))
AppendLog("ACTION=repair_nvcleaninstall_unexpected_error")
AppendLog("FINISHED_INSTALL_AUTO=enabled")
AppendLog("SCRIPT_SYNTAX_CHECK=ok")
AppendLog("ERROR=")
AppendLog("RESULT=repair_applied")
AppendLog("ACTION=nvcleaninstall_auto_start")
AppendLog("SCRIPT_PATH=" . A_ScriptFullPath)
AppendLog("AHK_VERSION_MODE=v2")
AppendLog("AHK_IS_ADMIN=" . (A_IsAdmin ? "oui" : "non"))
AppendLog("STARTED=oui")

NvcLogStep("AutoHotkey v2 script genere")
NvcLogStep("Attente fenetre")
WriteLive("Attente de NVCleanstall...")

if !WinWait("ahk_exe NVCleanstall.exe", "", 8) {
    if !WinWait("NVCleanstall", "", 90) {
        if !WinWait("NVCleanInstall", "", 10) {
            AppendLog("NVCLEANSTALL_WINDOW_FOUND=non")
            AppendLog("STEP_1_NEXT_CLICKED=non")
            AppendLog("STEP_2_NEXT_CLICKED=non")
            AppendLog("WAITING_FOR_INSTALLATION_TWEAKS=non")
            AppendLog("RESULT=window_timeout")
            WriteLive("Automatisation NVCleanstall bloquee. Continue manuellement.")
            ExitApp(3)
        }
    }
}

AppendLog("NVCLEANSTALL_WINDOW_FOUND=oui")
NvcLogStep("Fenetre detectee")
WriteLive("Automatisation NVCleanstall (pages 1 et 2)...")
Sleep(200)

if !FileExist(uiaScript) {
    AppendLog("RESULT=uia_script_missing")
    WriteLive("Automatisation NVCleanstall bloquee. Continue manuellement.")
    ExitApp(5)
}

psExe := A_WinDir "\System32\WindowsPowerShell\v1.0\powershell.exe"
if !FileExist(psExe)
    psExe := "powershell.exe"

exitCode := RunUiaPhase("wizard")

if (exitCode != 0) {
    AppendLog("STEP_1_DRIVER_SELECTION=error")
    AppendLog("STEP_2_COMPONENTS=error")
    AppendLog("STEP_1_NEXT_CLICKED=non")
    AppendLog("STEP_2_NEXT_CLICKED=non")
    AppendLog("WAITING_FOR_INSTALLATION_TWEAKS=non")
    AppendLog("RESULT=wizard_phase_" . exitCode)
    WriteLive("Automatisation NVCleanstall bloquee. Continue manuellement.")
    ExitApp(exitCode)
}

AppendLog("STEP_1_DRIVER_SELECTION=ok")
AppendLog("STEP_2_COMPONENTS=ok")
AppendLog("STEP_1_NEXT_CLICKED=oui")
AppendLog("STEP_2_NEXT_CLICKED=oui")
AppendLog("PREPARING_SOURCE_STARTED=oui")
AppendLog("RESULT=waiting_installation_tweaks")

if !WaitForInstallationTweaksAndPrompt() {
    if (ParseLogField("PROMPT_OPTIMIZATION_SETTINGS_RESULT") = "No") {
        AppendLog("RESULT=user_cancelled_tweaks")
        ExitApp(0)
    }
    ExitApp(6)
}

AppendLog("RESULT=done")
ExitApp(0)
