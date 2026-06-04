#requires -Version 5.1
# ==============================================================================
# Module: Events.UI.Effects.ps1
# Purpose: Wire visual effects, hover animations, custom drawing, drawer transitions,
#          and visibility syncing for setup sub-tabs.
# Inputs: Form controls and global theme variables.
# Outputs: None (applies custom UI drawing and changes control styles).
# Error Handling: Handles drawing and transition errors gracefully.
# ==============================================================================
# ---------- UI wiring ----------

# ---------- Custom DrawItem event for ComboBoxes (SAMISH Cyan Highlight) ----------
$global:comboDrawItem = {
    param($sender, $e)
    if ($e.Index -lt 0 -or $e.Index -ge $sender.Items.Count) { return }

    $itemText = $sender.Items[$e.Index].ToString()
    
    $isFocused = ($e.State -band [System.Windows.Forms.DrawItemState]::Focus) -eq [System.Windows.Forms.DrawItemState]::Focus
    $isActive = $false
    try {
        $parentForm = $sender.FindForm()
        if ($parentForm) {
            $isActive = ($parentForm.ActiveControl -eq $sender)
        }
    } catch {}
    
    $isEditArea = ($e.State -band [System.Windows.Forms.DrawItemState]::ComboBoxEdit) -eq [System.Windows.Forms.DrawItemState]::ComboBoxEdit
    if ($isEditArea) {
        $isHighlighted = (($e.State -band [System.Windows.Forms.DrawItemState]::Focus) -eq [System.Windows.Forms.DrawItemState]::Focus) -or $isActive
    } else {
        $isHighlighted = ($e.State -band [System.Windows.Forms.DrawItemState]::Selected) -eq [System.Windows.Forms.DrawItemState]::Selected
    }

    $highlightColor = if ($global:ThemeCustomActive) { $global:ThemeCustomPrimary } else { $script:BrandCyan }
    if ($null -eq $highlightColor) { $highlightColor = [System.Drawing.Color]::FromArgb(0, 245, 212) }

    if ($isHighlighted) {
        $brushBack = New-Object System.Drawing.SolidBrush($highlightColor)
        $e.Graphics.FillRectangle($brushBack, $e.Bounds)
        $brushBack.Dispose()
    }
    else {
        $brushBack = New-Object System.Drawing.SolidBrush($sender.BackColor)
        $e.Graphics.FillRectangle($brushBack, $e.Bounds)
        $brushBack.Dispose()
    }

    $foreColor = if ($isHighlighted) {
        [System.Drawing.Color]::Black
    }
    elseif (-not $sender.Enabled) { [System.Drawing.Color]::Gray }
    else { $sender.ForeColor }
    if ($null -eq $foreColor) { $foreColor = [System.Drawing.Color]::Black }
    $brushFore = New-Object System.Drawing.SolidBrush($foreColor)
    
    $rect = New-Object System.Drawing.RectangleF($e.Bounds.X, $e.Bounds.Y, $e.Bounds.Width, $e.Bounds.Height)
    $textFormat = New-Object System.Drawing.StringFormat
    $textFormat.LineAlignment = [System.Drawing.StringAlignment]::Center

    $e.Graphics.DrawString($itemText, $e.Font, $brushFore, $rect, $textFormat)

    $brushFore.Dispose()
    $textFormat.Dispose()
    $e.DrawFocusRectangle()
}

$logCtrl = if ($script:ddLogInterval) { $script:ddLogInterval } else { $ddLogInterval }
if ($logCtrl) { $logCtrl.add_DrawItem($global:comboDrawItem) }

$hkCtrl = if ($script:ddHotkey) { $script:ddHotkey } else { $ddHotkey }
if ($hkCtrl) { $hkCtrl.add_DrawItem($global:comboDrawItem) }

$wakeCtrl = if ($script:ddDiagOnWakeAction) { $script:ddDiagOnWakeAction } else { $ddOnWakeAction }
if ($wakeCtrl) { $wakeCtrl.add_DrawItem($global:comboDrawItem) }

$testCtrl = if ($script:ddTestTarget) { $script:ddTestTarget } else { $ddTestTarget }
if ($testCtrl) { $testCtrl.add_DrawItem($global:comboDrawItem) }



# ---------- Custom Focus Borders for TextBoxes ----------
$tbLogSingle = $null
$arrLogSingle = @($tbLogCustom | Where-Object { $_ -is [System.Windows.Forms.Control] })
if ($arrLogSingle.Count -gt 0) { $tbLogSingle = $arrLogSingle[-1] }

$tbKeySingle = $null
$arrKeySingle = @($tbCustomKey | Where-Object { $_ -is [System.Windows.Forms.Control] })
if ($arrKeySingle.Count -gt 0) { $tbKeySingle = $arrKeySingle[-1] }

if ($cfgGroup) {
    $cfgGroup.add_Paint({
            param($sender, $e)
            try {
                $tbLog = $null
                $arrLog = @($tbLogCustom | Where-Object { $_ -is [System.Windows.Forms.Control] })
                if ($arrLog.Count -gt 0) { $tbLog = $arrLog[-1] }
            
                $tbKey = $null
                $arrKey = @($tbCustomKey | Where-Object { $_ -is [System.Windows.Forms.Control] })
                if ($arrKey.Count -gt 0) { $tbKey = $arrKey[-1] }

                if ($tbLog -is [System.Windows.Forms.Control] -and $tbLog.Focused) {
                    $rect = New-Object System.Drawing.Rectangle($tbLog.Location.X - 1, $tbLog.Location.Y - 1, $tbLog.Width + 1, $tbLog.Height + 1)
                    $pen = New-Object System.Drawing.Pen($BrandCyan, 2)
                    $e.Graphics.DrawRectangle($pen, $rect)
                    $pen.Dispose()
                }
                if ($tbKey -is [System.Windows.Forms.Control] -and $tbKey.Focused) {
                    $rect = New-Object System.Drawing.Rectangle($tbKey.Location.X - 1, $tbKey.Location.Y - 1, $tbKey.Width + 1, $tbKey.Height + 1)
                    $pen = New-Object System.Drawing.Pen($BrandCyan, 2)
                    $e.Graphics.DrawRectangle($pen, $rect)
                    $pen.Dispose()
                }
            }
            catch {
                # Silently suppress any drawing exceptions (like legacy array indexing bugs)
            }
        })

    $tbLogSingle.add_GotFocus({ $cfgGroup.Invalidate() })
    $tbLogSingle.add_LostFocus({ $cfgGroup.Invalidate() })
    $tbKeySingle.add_GotFocus({ $cfgGroup.Invalidate() })
    $tbKeySingle.add_LostFocus({ $cfgGroup.Invalidate() })
}



# =====================================================================
# CUSTOM TAB UNDERLINE AND HOVER DECORATORS
# =====================================================================

function Update-TabIndicator {
    if (-not $script:tabIndicatorLine) { return }
    $isExpanded = $script:IsWindowExpanded
    
    if ($global:ThemeCustomActive) {
        $btnTabSetup.BackColor = [System.Drawing.Color]::FromArgb(35, 35, 40)
        $btnTabDiag.BackColor = [System.Drawing.Color]::FromArgb(35, 35, 40)
    }
    else {
        $btnTabSetup.BackColor = [System.Drawing.SystemColors]::Control
        $btnTabDiag.BackColor = [System.Drawing.SystemColors]::Control
    }

    if ($tabControl.SelectedIndex -eq 0) {
        if ($global:ThemeCustomActive) {
            $btnTabSetup.ForeColor = if ($global:ThemeCustomPrimary) { $global:ThemeCustomPrimary } else { [System.Drawing.Color]::FromArgb(0, 245, 212) }
            $btnTabDiag.ForeColor = [System.Drawing.Color]::FromArgb(130, 155, 160) # Option A #829BA0
        }
        else {
            $btnTabSetup.ForeColor = [System.Drawing.SystemColors]::ControlText
            $btnTabDiag.ForeColor = [System.Drawing.Color]::DimGray
        }

        # Setup tab is active
        if ($isExpanded) {
            $script:tabIndicatorLine.Location = New-Object System.Drawing.Point([int](330 * $script:DpiScale), [int](81 * $script:DpiScale))
            $script:tabIndicatorLine.Size = New-Object System.Drawing.Size([int](190 * $script:DpiScale), [int](2 * $script:DpiScale))
        }
        else {
            $script:tabIndicatorLine.Location = New-Object System.Drawing.Point([int](330 * $script:DpiScale), [int](81 * $script:DpiScale))
            $script:tabIndicatorLine.Size = New-Object System.Drawing.Size([int](145 * $script:DpiScale), [int](2 * $script:DpiScale))
        }
    }
    else {
        if ($global:ThemeCustomActive) {
            $btnTabDiag.ForeColor = if ($global:ThemeCustomPrimary) { $global:ThemeCustomPrimary } else { [System.Drawing.Color]::FromArgb(0, 245, 212) }
            $btnTabSetup.ForeColor = [System.Drawing.Color]::FromArgb(130, 155, 160) # Option A #829BA0
        }
        else {
            $btnTabDiag.ForeColor = [System.Drawing.SystemColors]::ControlText
            $btnTabSetup.ForeColor = [System.Drawing.Color]::DimGray
        }

        # Diagnostics tab is active
        if ($isExpanded) {
            $script:tabIndicatorLine.Location = New-Object System.Drawing.Point([int](530 * $script:DpiScale), [int](81 * $script:DpiScale))
            $script:tabIndicatorLine.Size = New-Object System.Drawing.Size([int](260 * $script:DpiScale), [int](2 * $script:DpiScale))
        }
        else {
            $script:tabIndicatorLine.Location = New-Object System.Drawing.Point([int](485 * $script:DpiScale), [int](81 * $script:DpiScale))
            $script:tabIndicatorLine.Size = New-Object System.Drawing.Size([int](180 * $script:DpiScale), [int](2 * $script:DpiScale))
        }
    }
    Update-SecondaryTabStyles
}

function global:Update-SecondaryTabStyles {
    if ($global:ThemeCustomActive) {
        $secTabBg = [System.Drawing.Color]::FromArgb(35, 35, 40)
        $activeColor = if ($global:ThemeCustomPrimary) { $global:ThemeCustomPrimary } else { [System.Drawing.Color]::FromArgb(0, 245, 212) }
        $inactiveColor = [System.Drawing.Color]::FromArgb(130, 155, 160) # Option A #829BA0 -- inactive tab text
    }
    else {
        $secTabBg = [System.Drawing.SystemColors]::Control
        $activeColor = [System.Drawing.SystemColors]::ControlText
        $inactiveColor = [System.Drawing.Color]::FromArgb(80, 80, 80)
    }

    # Drawer 2 tab buttons (System vs Hardware telemetry)
    if ($script:btnDrawer2TabSystem -and $script:btnDrawer2TabHardware) {
        $script:btnDrawer2TabSystem.BackColor = $secTabBg
        $script:btnDrawer2TabHardware.BackColor = $secTabBg
        if ($script:pnlTelemetryHardware -and $script:pnlTelemetryHardware.Visible) {
            $script:btnDrawer2TabHardware.ForeColor = $activeColor
            $script:btnDrawer2TabSystem.ForeColor = $inactiveColor
            $script:btnDrawer2TabHardware.Font = $boldFont
            $script:btnDrawer2TabSystem.Font = $font
        }
        else {
            $script:btnDrawer2TabSystem.ForeColor = $activeColor
            $script:btnDrawer2TabHardware.ForeColor = $inactiveColor
            $script:btnDrawer2TabSystem.Font = $boldFont
            $script:btnDrawer2TabHardware.Font = $font
        }
    }

    # Tools / Live Log tabs
    if ($script:btnSubTabTools -and $script:btnSubTabLive) {
        $script:btnSubTabTools.BackColor = $secTabBg
        $script:btnSubTabLive.BackColor = $secTabBg
        if ($script:IsLiveLogMode) {
            $script:btnSubTabLive.ForeColor = $activeColor
            $script:btnSubTabTools.ForeColor = $inactiveColor
        }
        else {
            $script:btnSubTabTools.ForeColor = $activeColor
            $script:btnSubTabLive.ForeColor = $inactiveColor
        }
    }
}

# (Removed Register-ButtonHoverBorder helper function and event hooks - hover background is natively handled by FlatAppearance in UI.ps1)


# =====================================================================
#NAVIGATION & DRAWER EVENT HANDLERS
# =====================================================================

function Hide-All-Drawers {
    if ($script:grpAdvancedTools) { $script:grpAdvancedTools.Visible = $false }
    if ($script:grpAdvancedDiag) { $script:grpAdvancedDiag.Visible = $false }
    $script:IsResizingProgrammatically = $true
    $form.ClientSize = New-Object System.Drawing.Size([int](800 * $script:DpiScale), [int](640 * $script:DpiScale))
    $script:IsResizingProgrammatically = $false
    if ($script:pnlTabWrapper) {
        $script:pnlTabWrapper.Size = New-Object System.Drawing.Size([int](780 * $script:DpiScale), [int](490 * $script:DpiScale))
    }
    $tabControl.Size = New-Object System.Drawing.Size([int](788 * $script:DpiScale), [int](498 * $script:DpiScale))

    # Reset drawer button labels so they never show stale "Close X" state
    if ($btnToolsAdvanced) {
        $btnToolsAdvanced.Text = "Advanced Tools >>"
        $btnToolsAdvanced.ForeColor = if ($global:ThemeCustomActive) { $global:ThemeCustomPrimary } else { [System.Drawing.SystemColors]::ControlText }
    }
    if ($btnDiagAdvanced) {
        $btnDiagAdvanced.Text = "Diagnostics >>"
        $btnDiagAdvanced.ForeColor = if ($global:ThemeCustomActive) { $global:ThemeCustomPrimary } else { [System.Drawing.SystemColors]::ControlText }
    }

    if ($script:toolsDrawerSep) { $script:toolsDrawerSep.Visible = $false }
    if ($script:diagDrawerSep) { $script:diagDrawerSep.Visible = $false }

    # Return logo to its home position
    if ($script:logo) { $script:logo.Location = New-Object System.Drawing.Point([int](718 * $script:DpiScale), [int](12 * $script:DpiScale)) }

    # Hide live log controls if active
    if ($script:IsLiveLogMode) { Exit-LiveLogMode }

    # Stop telemetry if running
    if ($script:TelemetryTimer) {
        $script:TelemetryTimer.Stop()
        $script:TelemetryTimer.Dispose()
        $script:TelemetryTimer = $null
    }

    # Reset telemetry list selections and action button when drawer closes
    if ($script:listArmedDevices) { $script:listArmedDevices.ClearSelected() }
    if ($script:listHardwareScans) { $script:listHardwareScans.ClearSelected() }
    if ($script:listWakeTimers) { $script:listWakeTimers.ClearSelected() }
    if ($script:btnTelemetryAction) {
        $script:btnTelemetryAction.Text = "Select Item..."
        if (Get-Command Set-ButtonVisualState -ErrorAction SilentlyContinue) {
            Set-ButtonVisualState -Button $script:btnTelemetryAction -Active $false
        }
    }

    if ($script:mainSep) { $script:mainSep.Width = [int](764 * $script:DpiScale) }
    if ($script:bottomMetadata) {
        $script:bottomMetadata.Location = New-Object System.Drawing.Point([int](480 * $script:DpiScale), [int](606 * $script:DpiScale))
        $script:bottomMetadata.BringToFront()
    }

    # Contract tab buttons to default names/sizes
    if ($btnTabSetup) {
        $btnTabSetup.Text = "1. Setup && Install"
        $btnTabSetup.Location = New-Object System.Drawing.Point([int](330 * $script:DpiScale), [int](48 * $script:DpiScale))
        $btnTabSetup.Size = New-Object System.Drawing.Size([int](145 * $script:DpiScale), [int](30 * $script:DpiScale))
    }
    if ($btnTabDiag) {
        $btnTabDiag.Text = "2. Sleep Automation"
        $btnTabDiag.Location = New-Object System.Drawing.Point([int](485 * $script:DpiScale), [int](48 * $script:DpiScale))
        $btnTabDiag.Size = New-Object System.Drawing.Size([int](180 * $script:DpiScale), [int](30 * $script:DpiScale))
    }

    # Hide and reset Advanced Tools sub-tabs
    if ($btnSubTabTools) {
        $btnSubTabTools.Visible = $false
        $btnSubTabTools.Font = $boldFont
        $btnSubTabTools.ForeColor = [System.Drawing.SystemColors]::ControlText
    }
    if ($btnSubTabLive) {
        $btnSubTabLive.Visible = $false
        $btnSubTabLive.Font = $font
        $btnSubTabLive.ForeColor = [System.Drawing.Color]::FromArgb(80, 80, 80)
    }
    if ($script:advancedTabIndicator) {
        $script:advancedTabIndicator.Visible = $false
    }
    $script:IsWindowExpanded = $false
    Update-TabIndicator
}

$btnTabSetup.add_Click({
        $WM_SETREDRAW = [uint32]0x000B
        try { [void][SamishWin32]::SendMessage($form.Handle, $WM_SETREDRAW, [IntPtr]::Zero, [IntPtr]::Zero) } catch {}

        $tabControl.SelectedIndex = 0
        $btnTabSetup.Font = $boldFont
        $btnTabDiag.Font = $font
        $wasExpanded = $script:IsWindowExpanded
        Hide-All-Drawers
        # If the window was expanded on the other tab, keep it expanded by opening this tab's drawer
        if ($wasExpanded -and $btnToolsAdvanced) { $btnToolsAdvanced.PerformClick() }
        Update-TabIndicator

        try {
            [void][SamishWin32]::SendMessage($form.Handle, $WM_SETREDRAW, [IntPtr]1, [IntPtr]::Zero)
            $form.Refresh()
        } catch {}
    })

$btnTabDiag.add_Click({
        $WM_SETREDRAW = [uint32]0x000B
        try { [void][SamishWin32]::SendMessage($form.Handle, $WM_SETREDRAW, [IntPtr]::Zero, [IntPtr]::Zero) } catch {}

        $tabControl.SelectedIndex = 1
        $btnTabDiag.Font = $boldFont
        $btnTabSetup.Font = $font
        $wasExpanded = $script:IsWindowExpanded
        Hide-All-Drawers
        # Initialize Page 2 handlers on first visit (was never called - root cause of all Page 2 bugs)
        if (-not $script:diagInitialized) {
            $script:diagInitialized = $true
            Init-SleepDiagnosticsEventHandlers
        }
        # If the window was expanded on the other tab, keep it expanded by opening this tab's drawer
        if ($wasExpanded -and $btnDiagAdvanced) { $btnDiagAdvanced.PerformClick() }
        Update-TabIndicator

        try {
            [void][SamishWin32]::SendMessage($form.Handle, $WM_SETREDRAW, [IntPtr]1, [IntPtr]::Zero)
            $form.Refresh()
        } catch {}
    })

$btnToolsAdvanced.add_Click({
        $WM_SETREDRAW = [uint32]0x000B
        try { [void][SamishWin32]::SendMessage($form.Handle, $WM_SETREDRAW, [IntPtr]::Zero, [IntPtr]::Zero) } catch {}

        try {
            # In Simple mode, this button is repurposed as "Restore Original Settings"
            if ($btnToolsAdvanced.Tag -eq "SimpleRestoreDisabled") {
                # Visually dimmed, no backup exists -- do nothing
                return
            }
            if ($btnToolsAdvanced.Tag -eq "SimpleRestore") {
                # Delegate to the same restore logic used by Verify & Restore Settings
                if ($btnPowerPlan) {
                    $btnPowerPlan.PerformClick()
                }
                return
            }
            if (-not $script:IsWindowExpanded) {
                # Expand - slide logo to far right of new header space
                if ($script:pnlTabWrapper) {
                    $script:pnlTabWrapper.Size = New-Object System.Drawing.Size([int](1160 * $script:DpiScale), [int](490 * $script:DpiScale))
                }
                $tabControl.Size = New-Object System.Drawing.Size([int](1168 * $script:DpiScale), [int](498 * $script:DpiScale))
                $script:IsResizingProgrammatically = $true
                $form.ClientSize = New-Object System.Drawing.Size([int](1180 * $script:DpiScale), [int](640 * $script:DpiScale))
                $script:IsResizingProgrammatically = $false
                if ($script:grpAdvancedTools) {
                    $script:grpAdvancedTools.Visible = $true
                    $script:grpAdvancedTools.Invalidate()
                }
                if ($script:logo) { $script:logo.Location = New-Object System.Drawing.Point([int](1098 * $script:DpiScale), [int](12 * $script:DpiScale)) }
                $btnToolsAdvanced.Text = "<< Close Tools"
                $btnToolsAdvanced.ForeColor = if ($global:ThemeCustomActive) { $global:ThemeCustomPrimary } else { [System.Drawing.SystemColors]::ControlText }
                if ($script:toolsDrawerSep) { $script:toolsDrawerSep.Visible = $true }
                if ($script:mainSep) { $script:mainSep.Width = [int](1144 * $script:DpiScale) }
                if ($script:bottomMetadata) {
                    $script:bottomMetadata.Location = New-Object System.Drawing.Point([int](860 * $script:DpiScale), [int](606 * $script:DpiScale))
                    $script:bottomMetadata.BringToFront()
                }

                # Expand tab buttons to long names/sizes (Setup anchored at X=330)
                if ($btnTabSetup) {
                    $btnTabSetup.Text = "1. Setup && Installation"
                    $btnTabSetup.Location = New-Object System.Drawing.Point([int](330 * $script:DpiScale), [int](48 * $script:DpiScale))
                    $btnTabSetup.Size = New-Object System.Drawing.Size([int](190 * $script:DpiScale), [int](30 * $script:DpiScale))
                }
                if ($btnTabDiag) {
                    $btnTabDiag.Text = "2. Sleep Automation && Diagnostics"
                    $btnTabDiag.Location = New-Object System.Drawing.Point([int](530 * $script:DpiScale), [int](48 * $script:DpiScale))
                    $btnTabDiag.Size = New-Object System.Drawing.Size([int](260 * $script:DpiScale), [int](30 * $script:DpiScale))
                }

                # Show sub-tabs
                if ($btnSubTabTools) { $btnSubTabTools.Visible = $true }
                if ($btnSubTabLive) { $btnSubTabLive.Visible = $true }
                if ($script:advancedTabIndicator) {
                    if ($script:IsLiveLogMode) {
                        $script:advancedTabIndicator.Location = New-Object System.Drawing.Point([int](270 * $script:DpiScale), [int](38 * $script:DpiScale))
                    }
                    else {
                        $script:advancedTabIndicator.Location = New-Object System.Drawing.Point([int](190 * $script:DpiScale), [int](38 * $script:DpiScale))
                    }
                    $script:advancedTabIndicator.Visible = $true
                }
                $script:IsWindowExpanded = $true
                Update-TabIndicator
            }
            else {
                # Collapse (Hide-All-Drawers resets text and logo)
                Hide-All-Drawers
            }
        }
        finally {
            try {
                [void][SamishWin32]::SendMessage($form.Handle, $WM_SETREDRAW, [IntPtr]1, [IntPtr]::Zero)
                $form.Refresh()
            } catch {}
        }
    })

$btnDiagAdvanced.add_Click({
        $WM_SETREDRAW = [uint32]0x000B
        try { [void][SamishWin32]::SendMessage($form.Handle, $WM_SETREDRAW, [IntPtr]::Zero, [IntPtr]::Zero) } catch {}

        $triggerRefresh = $false
        try {
            if (-not $script:IsWindowExpanded) {
                # Expand - slide logo to far right of new header space
                if ($script:pnlTabWrapper) {
                    $script:pnlTabWrapper.Size = New-Object System.Drawing.Size([int](1160 * $script:DpiScale), [int](490 * $script:DpiScale))
                }
                $tabControl.Size = New-Object System.Drawing.Size([int](1168 * $script:DpiScale), [int](498 * $script:DpiScale))
                $script:IsResizingProgrammatically = $true
                $form.ClientSize = New-Object System.Drawing.Size([int](1180 * $script:DpiScale), [int](640 * $script:DpiScale))
                $script:IsResizingProgrammatically = $false
                if ($script:grpAdvancedDiag) {
                    $script:grpAdvancedDiag.Visible = $true
                    $script:grpAdvancedDiag.Invalidate()
                }
                if ($script:logo) { $script:logo.Location = New-Object System.Drawing.Point([int](1098 * $script:DpiScale), [int](12 * $script:DpiScale)) }
                $btnDiagAdvanced.Text = "<< Close Diagnostics"
                $btnDiagAdvanced.ForeColor = if ($global:ThemeCustomActive) { $global:ThemeCustomPrimary } else { [System.Drawing.SystemColors]::ControlText }
                if ($script:diagDrawerSep) { $script:diagDrawerSep.Visible = $true }
                if ($script:mainSep) { $script:mainSep.Width = [int](1144 * $script:DpiScale) }
                if ($script:bottomMetadata) {
                    $script:bottomMetadata.Location = New-Object System.Drawing.Point([int](860 * $script:DpiScale), [int](606 * $script:DpiScale))
                    $script:bottomMetadata.BringToFront()
                }

                # Expand tab buttons to long names/sizes (Setup anchored at X=330)
                if ($btnTabSetup) {
                    $btnTabSetup.Text = "1. Setup && Installation"
                    $btnTabSetup.Location = New-Object System.Drawing.Point([int](330 * $script:DpiScale), [int](48 * $script:DpiScale))
                    $btnTabSetup.Size = New-Object System.Drawing.Size([int](190 * $script:DpiScale), [int](30 * $script:DpiScale))
                }
                if ($btnTabDiag) {
                    $btnTabDiag.Text = "2. Sleep Automation && Diagnostics"
                    $btnTabDiag.Location = New-Object System.Drawing.Point([int](530 * $script:DpiScale), [int](48 * $script:DpiScale))
                    $btnTabDiag.Size = New-Object System.Drawing.Size([int](260 * $script:DpiScale), [int](30 * $script:DpiScale))
                }

                # Set flag to trigger telemetry refresh after redraw is enabled
                $triggerRefresh = $true
                $script:IsWindowExpanded = $true
                Update-TabIndicator
            }
            else {
                # Collapse (Hide-All-Drawers resets text and logo)
                Hide-All-Drawers
            }
        }
        finally {
            try {
                [void][SamishWin32]::SendMessage($form.Handle, $WM_SETREDRAW, [IntPtr]1, [IntPtr]::Zero)
                $form.Refresh()
            } catch {}
        }

        # Trigger telemetry refresh only after the window has been repainted
        if ($triggerRefresh -and $script:btnTelemetryRefresh) {
            $script:btnTelemetryRefresh.PerformClick()
        }
    })



# ----- Live Log Sub-Tab Handlers -----
function Show-SubTabTools {
    if ($btnSubTabTools) {
        $btnSubTabTools.Font = $boldFont
    }
    if ($btnSubTabLive) {
        $btnSubTabLive.Font = $font
    }

    # Hide live log and controls
    if ($txtLiveLog) { $txtLiveLog.Visible = $false }
    if ($script:liveLogSep) { $script:liveLogSep.Visible = $false }
    if ($btnLivePause) { $btnLivePause.Visible = $false }
    if ($btnLiveCopy) { $btnLiveCopy.Visible = $false }
    if ($btnLiveClear) { $btnLiveClear.Visible = $false }

    if ($script:LiveLogTimer) {
        $script:LiveLogTimer.Stop()
        $script:LiveLogTimer.Dispose()
        $script:LiveLogTimer = $null
    }
    $script:IsLiveLogMode = $false

    # Show utility buttons
    if ($btnPowerPlan) { $btnPowerPlan.Visible = $true }
    if ($btnOpenTS) { $btnOpenTS.Visible = $true }
    if ($btnCleanReset) { $btnCleanReset.Visible = $true }
    if ($btnReadSetup) { $btnReadSetup.Visible = $true }
    if ($btnOpenLog) { $btnOpenLog.Visible = $true }
    if ($btnPreferredAudio) { $btnPreferredAudio.Visible = $true }
    if ($btnGameMode) { $btnGameMode.Visible = $true }
    if ($btnSubmitReport) { $btnSubmitReport.Visible = $true }

    if ($script:advancedTabIndicator) {
        $script:advancedTabIndicator.Location = New-Object System.Drawing.Point(190, 38)
        $script:advancedTabIndicator.Visible = $true
    }
    Update-SecondaryTabStyles
}

function Show-SubTabLive {
    if ($btnSubTabLive) {
        $btnSubTabLive.Font = $boldFont
    }
    if ($btnSubTabTools) {
        $btnSubTabTools.Font = $font
    }

    if (-not $script:LiveLogPath) { $script:LiveLogPath = Get-VerifiedPreferredLogPathOrShowMessageBox }
    $path = $script:LiveLogPath
    if (-not $path -or -not (Test-Path -LiteralPath $path)) {
        # Switch back to tools if log path isn't valid
        Show-SubTabTools
        return
    }

    $script:IsLiveLogMode = $true
    $script:IsLiveLogPaused = $false
    if ($btnLivePause) { $btnLivePause.Text = "Pause" }

    # Hide utility buttons
    if ($btnPowerPlan) { $btnPowerPlan.Visible = $false }
    if ($btnOpenTS) { $btnOpenTS.Visible = $false }
    if ($btnCleanReset) { $btnCleanReset.Visible = $false }
    if ($btnReadSetup) { $btnReadSetup.Visible = $false }
    if ($btnOpenLog) { $btnOpenLog.Visible = $false }
    if ($btnPreferredAudio) { $btnPreferredAudio.Visible = $false }
    if ($btnGameMode) { $btnGameMode.Visible = $false }
    if ($btnSubmitReport) { $btnSubmitReport.Visible = $false }



    # Show live log controls
    if ($txtLiveLog) { $txtLiveLog.Visible = $true }
    if ($script:liveLogSep) { $script:liveLogSep.Visible = $true }
    if ($btnLivePause) { $btnLivePause.Visible = $true }
    if ($btnLiveCopy) { $btnLiveCopy.Visible = $true }
    if ($btnLiveClear) { $btnLiveClear.Visible = $true }

    if ($txtLiveLog) {
        $txtLiveLog.Clear()
        $tail = Read-LogTailText -Path $path -MaxChars 100000
        if (-not [string]::IsNullOrEmpty($tail)) {
            $txtLiveLog.AppendText($tail)
            if (-not $tail.EndsWith("`n")) {
                $txtLiveLog.AppendText("`r`n")
            }
        }
    }

    try {
        $fi = Get-Item -LiteralPath $path
        $script:LiveLogPosition = [int64]$fi.Length
    }
    catch { $script:LiveLogPosition = 0 }

    if ($script:LiveLogTimer) {
        $script:LiveLogTimer.Stop()
        $script:LiveLogTimer.Dispose()
        $script:LiveLogTimer = $null
    }

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 350
    $timer.Add_Tick({
            if ($script:IsLiveLogPaused) { return }

            $fi = Get-Item -LiteralPath $script:LiveLogPath -ErrorAction SilentlyContinue
            if ($fi -and $fi.Length -gt $script:LiveLogPosition) {
                $fs = [System.IO.File]::Open($script:LiveLogPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                $fs.Seek($script:LiveLogPosition, [System.IO.SeekOrigin]::Begin) | Out-Null
                $reader = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8)
                $newText = $reader.ReadToEnd()
                $script:LiveLogPosition = $fi.Length
                $reader.Dispose()
                $fs.Dispose()

                if (![string]::IsNullOrEmpty($newText)) {
                    $txtLiveLog.AppendText($newText)
                    $txtLiveLog.SelectionStart = $txtLiveLog.TextLength
                    $txtLiveLog.ScrollToCaret()
                }
            }
        })
    $script:LiveLogTimer = $timer
    $timer.Start()

    if ($script:advancedTabIndicator) {
        $script:advancedTabIndicator.Location = New-Object System.Drawing.Point(270, 38)
        $script:advancedTabIndicator.Visible = $true
    }
    Update-SecondaryTabStyles
}

function Enter-LiveLogMode {
    Show-SubTabLive
}

function Exit-LiveLogMode {
    Show-SubTabTools
}

# Wire sub-tab buttons
if ($btnSubTabTools) { $btnSubTabTools.add_Click({ Show-SubTabTools }) }
if ($btnSubTabLive) { $btnSubTabLive.add_Click({ Show-SubTabLive }) }

if ($btnLivePause) {
    $btnLivePause.add_Click({ 
            $script:IsLiveLogPaused = -not $script:IsLiveLogPaused
            if ($script:IsLiveLogPaused) { $btnLivePause.Text = "Resume" } else { $btnLivePause.Text = "Pause" }
        })
}
if ($btnLiveClear) { $btnLiveClear.add_Click({ if ($txtLiveLog) { $txtLiveLog.Clear() } }) }
if ($btnLiveCopy) {
    $btnLiveCopy.add_Click({ 
            if ($txtLiveLog -and $txtLiveLog.Text) { [System.Windows.Forms.Clipboard]::SetText($txtLiveLog.Text) }
        })
}

# Wire double-click on version label/metadata to open dialog for changelog or support
if ($bottomMetadata) {
    $bottomMetadata.add_DoubleClick({
            $title = "SAMISH - Support & Information"
            $msg = "Would you like to support the creator on Ko-fi?`r`n`r`n" +
                   "- Click 'Yes' to visit the Ko-fi support page (https://ko-fi.com/thomwithah).`r`n" +
                   "- Click 'No' to open the CHANGELOG.md file.`r`n" +
                   "- Click 'Cancel' to close this window."
            $buttons = [System.Windows.Forms.MessageBoxButtons]::YesNoCancel
            $icon = [System.Windows.Forms.MessageBoxIcon]::Question
            
            $dialogResult = [System.Windows.Forms.MessageBox]::Show($msg, $title, $buttons, $icon)
            
            if ($dialogResult -eq [System.Windows.Forms.DialogResult]::Yes) {
                try {
                    Start-Process "https://ko-fi.com/thomwithah" | Out-Null
                } catch {
                    Write-SetupLog "Error opening Ko-fi support URL: $($_.Exception.Message)"
                }
            }
            elseif ($dialogResult -eq [System.Windows.Forms.DialogResult]::No) {
                $changelogPath = Join-Path (Split-Path -Parent $global:PackageDir) "CHANGELOG.md"
                if (Test-Path -LiteralPath $changelogPath) {
                    Write-SetupLog "Changelog found at '$changelogPath'. Attempting to open."
                    try {
                        Start-Process $changelogPath | Out-Null
                    }
                    catch {
                        Write-SetupLog "Error opening changelog: $($_.Exception.Message)"
                    }
                }
                else {
                    Write-SetupLog "Changelog not found at expected path: '$changelogPath'"
                }
            }
        })
}

# Replace Set-StatusText to remove deferred logic


# --- Branding Interactions ---
if ($logo) {
    $logo.add_DoubleClick({
            if ($global:IsThemeAnimating) { return }
            . (Join-Path $global:PackageDir "Modules\Theme-Extension.ps1")
            Invoke-BrandSequence -Form $form
        })
}

# ---------- Resolution Auto-Layout ----------
# Automatically collapse drawers when resolution falls below 1080p width
if ($form) {
    $script:IsResizingProgrammatically = $false
    
    $script:ResolutionCheckHandler = {
        if ($script:IsWindowExpanded -and -not $script:IsResizingProgrammatically) {
            try {
                $screen = [System.Windows.Forms.Screen]::FromControl($form)
                if ($screen -and $screen.Bounds.Width -lt 1920) {
                    Write-SetupLog "Auto-collapsing drawers: screen width ($($screen.Bounds.Width)) is below 1920 (1080p)."
                    Hide-All-Drawers
                }
            } catch {}
        }
    }

    $form.add_LocationChanged($script:ResolutionCheckHandler)
    $form.add_Resize($script:ResolutionCheckHandler)
}




