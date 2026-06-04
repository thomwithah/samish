#requires -Version 5.1
# =============================================================================
# SAMISH First-Run Wizard
# =============================================================================
# Purpose:  Walks a new user through 4 setup questions on first launch.
#           Persists answers to config.json and sets WizardCompleted = $true.
#
# Inputs:   $ConfigPath   (string) - path to config.json (caller's scope)
#           $PackageDir   (string) - path to App/ folder (caller's scope)
#
# Outputs:  Returns a hashtable of wizard answers, or $null if skipped/cancelled.
#
# Error handling: Wrapped in try/catch; wizard failure does not block Setup from
#                 launching. WizardCompleted is set only on successful completion.
# =============================================================================

function Show-FirstRunWizard {
    <#
    .SYNOPSIS
        Displays a stepped first-run wizard modal.

    .DESCRIPTION
        Presents 3 questions:
          1. Detect running mixer - ask to manage during sleep
          2. Detect common browsers - ask to pause media
          3. UI mode selection (Simple / Full)
          4. Installation & Recovery settings (Hidden / Interactive)

        Includes a "Skip Wizard" button that closes and opens in Simple mode.

    .PARAMETER ConfigPath
        Full path to config.json.

    .PARAMETER PackageDir
        Full path to the App/ directory (for loading icons/assets).

    .OUTPUTS
        [hashtable] with keys: MixerDetected, ManageMixer, BrowsersDetected,
        PauseBrowsers, UI_Mode, WizardCompleted. Returns $null if cancelled.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath,

        [Parameter(Mandatory = $true)]
        [string]$PackageDir
    )

    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
    }
    catch {}

    # ---- Detect mixers and browsers ----
    $knownMixers = @(
        @{ Name = "BEACN";       Process = "BEACN" }
        @{ Name = "Voicemeeter"; Process = "voicemeeter" }
        @{ Name = "GoXLR";      Process = "GoXLR" }
        @{ Name = "Wave Link";   Process = "WaveLink" }
    )

    $knownBrowsers = @(
        @{ Name = "Microsoft Edge"; Process = "msedge" }
        @{ Name = "Google Chrome";  Process = "chrome" }
        @{ Name = "Firefox";        Process = "firefox" }
        @{ Name = "Brave";          Process = "brave" }
        @{ Name = "Vivaldi";        Process = "vivaldi" }
        @{ Name = "Opera";          Process = "opera" }
    )

    $detectedMixers = @()
    foreach ($m in $knownMixers) {
        if (Get-Process -Name $m.Process -ErrorAction SilentlyContinue) {
            $detectedMixers += $m.Name
        }
    }

    $detectedBrowsers = @()
    foreach ($b in $knownBrowsers) {
        if (Get-Process -Name $b.Process -ErrorAction SilentlyContinue) {
            $detectedBrowsers += $b
        }
    }

    # ---- Build wizard form ----
    $wizForm = New-Object System.Windows.Forms.Form
    $wizForm.Text = "SAMISH - First-Run Setup"
    $wizForm.StartPosition = "CenterScreen"
    $wizForm.FormBorderStyle = "FixedDialog"
    $wizForm.MaximizeBox = $false
    $wizForm.MinimizeBox = $false
    $wizForm.ClientSize = New-Object System.Drawing.Size(520, 380)
    $wizForm.BackColor = [System.Drawing.Color]::FromArgb(250, 250, 252)

    # Try to load icon
    try {
        $iconPath = Join-Path $PackageDir "Assets\128x128.ico"
        if (Test-Path -LiteralPath $iconPath) {
            $wizForm.Icon = New-Object System.Drawing.Icon($iconPath)
        }
    }
    catch {}

    $fontNormal = New-Object System.Drawing.Font("Segoe UI", [float](9 * $script:DpiScale))
    $fontBold = New-Object System.Drawing.Font("Segoe UI", [float](9 * $script:DpiScale), [System.Drawing.FontStyle]::Bold)
    $fontTitle = New-Object System.Drawing.Font("Segoe UI", [float](14 * $script:DpiScale), [System.Drawing.FontStyle]::Bold)
    $fontSubtitle = New-Object System.Drawing.Font("Segoe UI", [float](10 * $script:DpiScale))
    $brandPurple = [System.Drawing.Color]::FromArgb(120, 81, 169)
    $brandCyan = [System.Drawing.Color]::FromArgb(0, 188, 212)

    # ---- Title area ----
    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = "Welcome to SAMISH"
    $lblTitle.Font = $fontTitle
    $lblTitle.ForeColor = $brandPurple
    $lblTitle.AutoSize = $true
    $lblTitle.Location = New-Object System.Drawing.Point(20, 15)
    $wizForm.Controls.Add($lblTitle)

    # Step indicator
    $lblStep = New-Object System.Windows.Forms.Label
    $lblStep.Name = "lblStep"
    $lblStep.Font = $fontSubtitle
    $lblStep.ForeColor = $brandCyan
    $lblStep.AutoSize = $true
    $lblStep.Location = New-Object System.Drawing.Point(20, 45)
    $wizForm.Controls.Add($lblStep)

    # Separator
    $sep = New-Object System.Windows.Forms.Label
    $sep.Size = New-Object System.Drawing.Size(480, 2)
    $sep.Location = New-Object System.Drawing.Point(20, 70)
    $sep.BackColor = $brandCyan
    $wizForm.Controls.Add($sep)

    # ---- Content panels (one per step, toggled) ----
    $panelStep1 = New-Object System.Windows.Forms.Panel
    $panelStep1.Location = New-Object System.Drawing.Point(20, 80)
    $panelStep1.Size = New-Object System.Drawing.Size(480, 230)
    $panelStep1.Visible = $true
    $wizForm.Controls.Add($panelStep1)

    $panelStep2 = New-Object System.Windows.Forms.Panel
    $panelStep2.Location = New-Object System.Drawing.Point(20, 80)
    $panelStep2.Size = New-Object System.Drawing.Size(480, 230)
    $panelStep2.Visible = $false
    $wizForm.Controls.Add($panelStep2)

    $panelStep3 = New-Object System.Windows.Forms.Panel
    $panelStep3.Location = New-Object System.Drawing.Point(20, 80)
    $panelStep3.Size = New-Object System.Drawing.Size(480, 230)
    $panelStep3.Visible = $false
    $wizForm.Controls.Add($panelStep3)

    $panelStep4 = New-Object System.Windows.Forms.Panel
    $panelStep4.Location = New-Object System.Drawing.Point(20, 80)
    $panelStep4.Size = New-Object System.Drawing.Size(480, 230)
    $panelStep4.Visible = $false
    $wizForm.Controls.Add($panelStep4)

    # ---- Step 1: Mixer detection ----
    $lbl1 = New-Object System.Windows.Forms.Label
    $lbl1.Font = $fontBold
    $lbl1.AutoSize = $false
    $lbl1.Size = New-Object System.Drawing.Size(460, 25)
    $lbl1.Location = New-Object System.Drawing.Point(0, 10)

    if ($detectedMixers.Count -gt 0) {
        $lbl1.Text = "Detected audio mixer: $($detectedMixers -join ', ')"
        $lbl1.ForeColor = [System.Drawing.Color]::FromArgb(0, 120, 0)
    }
    else {
        $lbl1.Text = "No supported audio mixer detected."
        $lbl1.ForeColor = [System.Drawing.Color]::FromArgb(180, 120, 0)
    }
    $panelStep1.Controls.Add($lbl1)

    $lbl1Desc = New-Object System.Windows.Forms.Label
    $lbl1Desc.Font = $fontNormal
    $lbl1Desc.Text = "SAMISH can automatically stop and restart your mixer application`r`nwhen Windows enters and exits sleep. This prevents audio routing`r`nproblems that occur when USB audio devices power-cycle."
    $lbl1Desc.AutoSize = $false
    $lbl1Desc.Size = New-Object System.Drawing.Size(460, 60)
    $lbl1Desc.Location = New-Object System.Drawing.Point(0, 45)
    $panelStep1.Controls.Add($lbl1Desc)

    $cbManageMixer = New-Object System.Windows.Forms.CheckBox
    $cbManageMixer.Font = $fontNormal
    $cbManageMixer.Text = "Yes, manage my mixer during sleep/wake cycles"
    $cbManageMixer.AutoSize = $true
    $cbManageMixer.Checked = ($detectedMixers.Count -gt 0)
    $cbManageMixer.Location = New-Object System.Drawing.Point(10, 120)
    $panelStep1.Controls.Add($cbManageMixer)

    # ---- Step 2: Browser detection ----
    $lbl2 = New-Object System.Windows.Forms.Label
    $lbl2.Font = $fontBold
    $lbl2.AutoSize = $false
    $lbl2.Size = New-Object System.Drawing.Size(460, 25)
    $lbl2.Location = New-Object System.Drawing.Point(0, 10)

    if ($detectedBrowsers.Count -gt 0) {
        $browserNames = ($detectedBrowsers | ForEach-Object { $_.Name }) -join ", "
        $lbl2.Text = "Detected browser(s): $browserNames"
        $lbl2.ForeColor = [System.Drawing.Color]::FromArgb(0, 120, 0)
    }
    else {
        $lbl2.Text = "No supported browsers detected."
        $lbl2.ForeColor = [System.Drawing.Color]::FromArgb(180, 120, 0)
    }
    $panelStep2.Controls.Add($lbl2)

    $lbl2Desc = New-Object System.Windows.Forms.Label
    $lbl2Desc.Font = $fontNormal
    $lbl2Desc.Text = "SAMISH can pause media playback in browsers before sleep and`r`nrestore it on wake. This prevents unexpected audio from playing`r`nthrough your mixer after the system wakes up."
    $lbl2Desc.AutoSize = $false
    $lbl2Desc.Size = New-Object System.Drawing.Size(460, 60)
    $lbl2Desc.Location = New-Object System.Drawing.Point(0, 45)
    $panelStep2.Controls.Add($lbl2Desc)

    $cbPauseBrowsers = New-Object System.Windows.Forms.CheckBox
    $cbPauseBrowsers.Font = $fontNormal
    $cbPauseBrowsers.Text = "Yes, pause/resume browser media during sleep cycles"
    $cbPauseBrowsers.AutoSize = $true
    $cbPauseBrowsers.Checked = ($detectedBrowsers.Count -gt 0)
    $cbPauseBrowsers.Location = New-Object System.Drawing.Point(10, 120)
    $panelStep2.Controls.Add($cbPauseBrowsers)

    # ---- Step 3: UI Mode ----
    $lbl3 = New-Object System.Windows.Forms.Label
    $lbl3.Font = $fontBold
    $lbl3.Text = "Choose your experience level"
    $lbl3.AutoSize = $true
    $lbl3.Location = New-Object System.Drawing.Point(0, 10)
    $panelStep3.Controls.Add($lbl3)

    $rbSimple = New-Object System.Windows.Forms.RadioButton
    $rbSimple.Font = $fontNormal
    $rbSimple.Text = "Simple - Streamlined interface showing only essential configuration settings"
    $rbSimple.AutoSize = $true
    $rbSimple.Checked = $true
    $rbSimple.Location = New-Object System.Drawing.Point(10, 50)
    $panelStep3.Controls.Add($rbSimple)

    $rbFull = New-Object System.Windows.Forms.RadioButton
    $rbFull.Font = $fontNormal
    $rbFull.Text = "Full - All controls, diagnostics, and advanced tools"
    $rbFull.AutoSize = $true
    $rbFull.Checked = $false
    $rbFull.Location = New-Object System.Drawing.Point(10, 90)
    $panelStep3.Controls.Add($rbFull)

    $lbl3Tip = New-Object System.Windows.Forms.Label
    $lbl3Tip.Font = $fontNormal
    $lbl3Tip.ForeColor = [System.Drawing.Color]::Gray
    $lbl3Tip.Text = "You can change this anytime from the View dropdown in the bottom-left corner."
    $lbl3Tip.AutoSize = $true
    $lbl3Tip.Location = New-Object System.Drawing.Point(10, 140)
    $panelStep3.Controls.Add($lbl3Tip)

    # ---- Step 4: Install & Recovery ----
    $lbl4 = New-Object System.Windows.Forms.Label
    $lbl4.Font = $fontBold
    $lbl4.Text = "Install & Recovery Settings"
    $lbl4.AutoSize = $true
    $lbl4.Location = New-Object System.Drawing.Point(0, 10)
    $panelStep4.Controls.Add($lbl4)

    $rbWizHidden = New-Object System.Windows.Forms.RadioButton
    $rbWizHidden.Font = $fontNormal
    $rbWizHidden.Text = "Hidden (recommended) - runs silently in the background"
    $rbWizHidden.AutoSize = $true
    $rbWizHidden.Checked = $true
    $rbWizHidden.Location = New-Object System.Drawing.Point(10, 45)
    $panelStep4.Controls.Add($rbWizHidden)

    $rbWizInteractive = New-Object System.Windows.Forms.RadioButton
    $rbWizInteractive.Font = $fontNormal
    $rbWizInteractive.Text = "Interactive - needed for system tray icon"
    $rbWizInteractive.AutoSize = $true
    $rbWizInteractive.Checked = $false
    $rbWizInteractive.Location = New-Object System.Drawing.Point(10, 75)
    $panelStep4.Controls.Add($rbWizInteractive)

    $lblWizRecoveryDesc = New-Object System.Windows.Forms.Label
    $lblWizRecoveryDesc.Font = $fontNormal
    $lblWizRecoveryDesc.ForeColor = [System.Drawing.Color]::Gray
    $lblWizRecoveryDesc.Text = "Auto-Recovery runs in the background to automatically restart your main audio mixer software if it crashes or fails to recover on system wake. (Detailed browser and application recovery settings are available in Full mode)."
    $lblWizRecoveryDesc.AutoSize = $false
    $lblWizRecoveryDesc.Size = New-Object System.Drawing.Size(460, 55)
    $lblWizRecoveryDesc.Location = New-Object System.Drawing.Point(10, 110)
    $panelStep4.Controls.Add($lblWizRecoveryDesc)

    $lblWizInstallPrompt = New-Object System.Windows.Forms.Label
    $lblWizInstallPrompt.Font = $fontBold
    $lblWizInstallPrompt.ForeColor = $brandPurple
    $lblWizInstallPrompt.Text = "Setup Complete! Next, click the 'Install / Update' button on the dashboard to register SAMISH as a background task."
    $lblWizInstallPrompt.AutoSize = $false
    $lblWizInstallPrompt.Size = New-Object System.Drawing.Size(460, 45)
    $lblWizInstallPrompt.Location = New-Object System.Drawing.Point(10, 175)
    $panelStep4.Controls.Add($lblWizInstallPrompt)

    # ---- Navigation buttons ----
    $btnBack = New-Object System.Windows.Forms.Button
    $btnBack.Text = "< Back"
    $btnBack.Font = $fontNormal
    $btnBack.Size = New-Object System.Drawing.Size(90, 32)
    $btnBack.Location = New-Object System.Drawing.Point(220, 335)
    $btnBack.Enabled = $false
    $btnBack.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnBack.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(180, 180, 180)
    $wizForm.Controls.Add($btnBack)

    $btnNext = New-Object System.Windows.Forms.Button
    $btnNext.Text = "Next >"
    $btnNext.Font = $fontBold
    $btnNext.Size = New-Object System.Drawing.Size(90, 32)
    $btnNext.Location = New-Object System.Drawing.Point(320, 335)
    $btnNext.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnNext.BackColor = $brandPurple
    $btnNext.ForeColor = [System.Drawing.Color]::White
    $btnNext.FlatAppearance.BorderSize = 0
    $wizForm.Controls.Add($btnNext)

    $btnSkip = New-Object System.Windows.Forms.Button
    $btnSkip.Text = "Skip Wizard"
    $btnSkip.Font = $fontNormal
    $btnSkip.Size = New-Object System.Drawing.Size(90, 32)
    $btnSkip.Location = New-Object System.Drawing.Point(420, 335)
    $btnSkip.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnSkip.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(180, 180, 180)
    $wizForm.Controls.Add($btnSkip)

    # ---- State machine ----
    $wizState = @{ Step = 1; Result = $null }
    $panels = @($panelStep1, $panelStep2, $panelStep3, $panelStep4)
    $stepLabels = @("Step 1 of 4 - Audio Mixer", "Step 2 of 4 - Browser Media", "Step 3 of 4 - Experience Level", "Step 4 of 4 - Install & Recovery")

    $updateStepUI = {
        $s = $wizState.Step
        $lblStep.Text = $stepLabels[$s - 1]

        for ($i = 0; $i -lt $panels.Count; $i++) {
            $panels[$i].Visible = ($i -eq ($s - 1))
        }

        $btnBack.Enabled = ($s -gt 1)
        $btnNext.Text = if ($s -eq 4) { "Finish" } else { "Next >" }
    }

    & $updateStepUI

    $btnBack.add_Click({
        if ($wizState.Step -gt 1) {
            $wizState.Step--
            & $updateStepUI
        }
    })

    $btnNext.add_Click({
        if ($wizState.Step -lt 4) {
            $wizState.Step++
            & $updateStepUI
        }
        else {
            # Finish - collect results
            $uiMode = "Full"
            if ($rbSimple.Checked) { $uiMode = "Simple" }

            $installMode = "Hidden"
            if ($rbWizInteractive.Checked) { $installMode = "Interactive" }

            $wizState.Result = @{
                MixerDetected    = ($detectedMixers.Count -gt 0)
                DetectedMixers   = $detectedMixers
                ManageMixer      = $cbManageMixer.Checked
                BrowsersDetected = @($detectedBrowsers | ForEach-Object { $_ })
                PauseBrowsers    = $cbPauseBrowsers.Checked
                UI_Mode          = $uiMode
                InstallMode      = $installMode
                WizardCompleted  = $true
            }

            $wizForm.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $wizForm.Close()
        }
    })

    $btnSkip.add_Click({
        # Skip sets WizardCompleted so it doesn't show again, but uses defaults
        $wizState.Result = @{
            MixerDetected    = ($detectedMixers.Count -gt 0)
            DetectedMixers   = $detectedMixers
            ManageMixer      = $false
            BrowsersDetected = @()
            PauseBrowsers    = $false
            UI_Mode          = "Simple"
            InstallMode      = "Hidden"
            WizardCompleted  = $true
        }

        $wizForm.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $wizForm.Close()
    })

    # ---- Show wizard ----
    $dialogResult = $wizForm.ShowDialog()

    # Dispose GDI resources
    try {
        $fontNormal.Dispose()
        $fontBold.Dispose()
        $fontTitle.Dispose()
        $fontSubtitle.Dispose()
        $wizForm.Dispose()
    }
    catch {}

    if ($dialogResult -eq [System.Windows.Forms.DialogResult]::OK -and $wizState.Result) {
        return $wizState.Result
    }

    return $null
}

function Invoke-FirstRunWizardIfNeeded {
    <#
    .SYNOPSIS
        Shows the first-run wizard if WizardCompleted is not true in config.

    .DESCRIPTION
        Reads config.json, checks WizardCompleted flag. If false or missing,
        shows the wizard and persists answers. Called from Setup.ps1 at startup.

    .PARAMETER ConfigPath
        Full path to config.json.

    .PARAMETER PackageDir
        Full path to the App/ directory.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath,

        [Parameter(Mandatory = $true)]
        [string]$PackageDir
    )

    # Check if wizard already completed
    $wizardDone = $false
    if (Test-Path -LiteralPath $ConfigPath) {
        try {
            $raw = Get-Content -LiteralPath $ConfigPath -Raw -ErrorAction Stop
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                $cfg = $raw | ConvertFrom-Json -ErrorAction Stop
                if ($cfg.PSObject.Properties.Name -contains "WizardCompleted") {
                    $wizardDone = [bool]$cfg.WizardCompleted
                }
            }
        }
        catch {
            # Config unreadable - show wizard
        }
    }

    if ($wizardDone) { return $null }

    # Show wizard
    $answers = Show-FirstRunWizard -ConfigPath $ConfigPath -PackageDir $PackageDir

    if ($null -eq $answers) {
        # User closed wizard without finishing - don't set WizardCompleted so it shows again
        return $null
    }

    # Persist answers to config
    try {
        $cfg = $null
        if (Test-Path -LiteralPath $ConfigPath) {
            $raw = Get-Content -LiteralPath $ConfigPath -Raw -ErrorAction SilentlyContinue
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                $cfg = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue
            }
        }

        if ($null -eq $cfg) {
            $cfg = [PSCustomObject]@{}
        }

        # Map ActiveProfileId and ProfilesEnabled
        $activeProfile = "BEACN"
        if ($answers.ManageMixer) {
            if ($answers.MixerDetected -and $answers.DetectedMixers -and $answers.DetectedMixers.Count -gt 0) {
                $firstMixer = $answers.DetectedMixers[0]
                if ($firstMixer -eq "Wave Link") {
                    $activeProfile = "WaveLink"
                } else {
                    $activeProfile = $firstMixer
                }
            }
        } else {
            $activeProfile = "DEMO"
        }

        # Set wizard answers
        $propsToSet = @{
            WizardCompleted = $true
            UI_Mode         = $answers.UI_Mode
            ActiveProfileId = $activeProfile
            ProfilesEnabled = @($activeProfile)
        }

        if ($answers.InstallMode -eq "Hidden") {
            $propsToSet["EnableTrayIcon"] = $false
            $propsToSet["EnableHotkey"] = $false
        } else {
            $propsToSet["EnableTrayIcon"] = $true
            $propsToSet["EnableHotkey"] = $true
        }

        # Build MonitoredApps from browser detections if user opted in
        if ($answers.PauseBrowsers -and $answers.BrowsersDetected.Count -gt 0) {
            $monitoredBrowsers = @()
            foreach ($b in $answers.BrowsersDetected) {
                $exePath = ""
                # Attempt to find executable path
                try {
                    $proc = Get-Process -Name $b.Process -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($proc -and $proc.MainModule) {
                        $exePath = $proc.MainModule.FileName
                    }
                }
                catch {}

                $monitoredBrowsers += [PSCustomObject]@{
                    ProcessName    = $b.Process
                    ExecutablePath = $exePath
                    RecoveryMode   = "PauseMedia"
                    OnWakeAction   = "Smart"
                }
            }

            # Merge with existing MonitoredApps (avoid duplicates)
            $existingApps = @()
            if ($cfg.PSObject.Properties.Name -contains "MonitoredApps" -and $cfg.MonitoredApps) {
                $existingApps = @($cfg.MonitoredApps)
            }

            foreach ($newApp in $monitoredBrowsers) {
                $isDuplicate = $false
                foreach ($existing in $existingApps) {
                    if ($existing.ProcessName -eq $newApp.ProcessName) {
                        $isDuplicate = $true
                        break
                    }
                }
                if (-not $isDuplicate) {
                    $existingApps += $newApp
                }
            }

            $propsToSet["MonitoredApps"] = $existingApps
        }

        foreach ($key in $propsToSet.Keys) {
            if ($cfg.PSObject.Properties.Name -contains $key) {
                $cfg.$key = $propsToSet[$key]
            }
            else {
                $cfg | Add-Member -MemberType NoteProperty -Name $key -Value $propsToSet[$key] -Force
            }
        }

        $json = $cfg | ConvertTo-Json -Depth 6
        if (Get-Command Save-ContentAtomic -ErrorAction SilentlyContinue) {
            Save-ContentAtomic -Path $ConfigPath -Content $json
        }
        else {
            # Ensure directory exists
            $dir = Split-Path -Parent $ConfigPath
            if ($dir -and -not (Test-Path -LiteralPath $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }
            Set-Content -LiteralPath $ConfigPath -Value $json -Encoding UTF8
        }
    }
    catch {
        # Fail-forward: wizard results couldn't be saved but Setup should still open
        try {
            if (Get-Command Write-SetupLog -ErrorAction SilentlyContinue) {
                Write-SetupLog "First-run wizard: failed to persist answers: $($_.Exception.Message)"
            }
        }
        catch {}
    }

    return $answers
}
