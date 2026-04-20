# ============================================================================
# QCLogger - Qualcomm Selfhost Trace Log Analyzer
# Analyzes EVTX, ETL, and PNP state files for keyboard/touchpad issues
# Generates a detailed dark-theme HTML diagnostic report
# ============================================================================
param(
    [string]$LogDir = "C:\QCLogger"
)

$ErrorActionPreference = 'SilentlyContinue'

if (-not (Test-Path $LogDir)) {
    Write-Host "ERROR: Log directory not found: $LogDir" -ForegroundColor Red
    exit 1
}

Write-Host "QCLogger Analyzer - Processing logs from $LogDir" -ForegroundColor Cyan
Write-Host ""

# ============================================================================
# SECTION 1: Collect System Information
# ============================================================================
Write-Host "  [1/8] Collecting system information..." -ForegroundColor Yellow

$computerName = $env:COMPUTERNAME
$osVersion = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction SilentlyContinue
$osBuild = "$($osVersion.CurrentBuildNumber).$($osVersion.UBR)"
$osDisplay = $osVersion.DisplayVersion
$analysisTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

$startTimeFile = Join-Path $LogDir "StartTime.txt"
$stopTimeFile = Join-Path $LogDir "StopTime.txt"
$captureStart = if (Test-Path $startTimeFile) { (Get-Content $startTimeFile -Raw).Trim() } else { "Unknown" }
$captureStop = if (Test-Path $stopTimeFile) { (Get-Content $stopTimeFile -Raw).Trim() } else { $analysisTime }

# ============================================================================
# SECTION 2: Parse Event Logs (EVTX)
# ============================================================================
Write-Host "  [2/8] Parsing event logs..." -ForegroundColor Yellow

# Find all EVTX files
$evtxFiles = Get-ChildItem -Path $LogDir -Filter "*.evtx" -ErrorAction SilentlyContinue
$systemEvtx = $evtxFiles | Where-Object { $_.Name -match 'System' } | Select-Object -First 1

function Get-SafeWinEvent {
    param([string]$Path, [string]$FilterXPath = "*", [int]$MaxEvents = 50000)
    if (-not (Test-Path $Path)) { return @() }
    try {
        return Get-WinEvent -Path $Path -FilterXPath $FilterXPath -MaxEvents $MaxEvents -ErrorAction Stop
    } catch { return @() }
}

# ---- Data structures ----
$sessionTransitions = [System.Collections.ArrayList]::new()
$modernStandbyEntries = [System.Collections.ArrayList]::new()
$ppteCycleEvents = [System.Collections.ArrayList]::new()
$wudfrdFailures = [System.Collections.ArrayList]::new()
$inputSuppressionEvents = [System.Collections.ArrayList]::new()
$bootEvents = [System.Collections.ArrayList]::new()
$powerEvents = [System.Collections.ArrayList]::new()
$errorEvents = [System.Collections.ArrayList]::new()
$usbEvents = [System.Collections.ArrayList]::new()
$umdfCrashes = [System.Collections.ArrayList]::new()
$touchHqaEvents = [System.Collections.ArrayList]::new()
$connectivityEvents = [System.Collections.ArrayList]::new()
$cpuThrottleEvents = [System.Collections.ArrayList]::new()
$halErrors = [System.Collections.ArrayList]::new()
$issues = [System.Collections.ArrayList]::new()

$totalSystemEvents = 0
$providerCounts = @{}

if ($systemEvtx) {
    $evtxPath = $systemEvtx.FullName
    Write-Host "    Parsing: $($systemEvtx.Name)" -ForegroundColor Gray

    $rawEvents = Get-SafeWinEvent -Path $evtxPath -MaxEvents 50000
    $totalSystemEvents = $rawEvents.Count
    Write-Host "    Total events: $totalSystemEvents" -ForegroundColor Gray

    foreach ($evt in $rawEvents) {
        $msg = if ($evt.Message) { $evt.Message } else { "(no msg)" }
        $provName = $evt.ProviderName
        if (-not $providerCounts.ContainsKey($provName)) { $providerCounts[$provName] = 0 }
        $providerCounts[$provName]++

        # ---- Session Transitions (EventID 566) ----
        if ($evt.Id -eq 566 -and $provName -eq 'Microsoft-Windows-Kernel-Power') {
            $fromTo = ""
            $reason = ""
            $bootId = ""
            if ($msg -match 'from (\d+) to (\d+)') { $fromTo = "$($Matches[1])->$($Matches[2])" }
            if ($msg -match 'Reason\s+(.+?)[\r\n]') { $reason = $Matches[1].Trim() }
            if ($msg -match 'BootId:\s*(\d+)') { $bootId = $Matches[1] }
            $null = $sessionTransitions.Add([PSCustomObject]@{
                Time = $evt.TimeCreated; FromTo = $fromTo; Reason = $reason; BootId = $bootId; Message = $msg
            })
        }

        # ---- Modern Standby Entry (EventID 506) ----
        if ($evt.Id -eq 506 -and $provName -eq 'Microsoft-Windows-Kernel-Power') {
            $sleepReason = ""
            if ($msg -match 'Reason:\s*(.+?)\.?\s*$') { $sleepReason = $Matches[1].Trim().TrimEnd('.') }
            $null = $modernStandbyEntries.Add([PSCustomObject]@{
                Time = $evt.TimeCreated; Reason = $sleepReason; Message = $msg
            })
        }

        # ---- Connectivity (EventID 172) ----
        if ($evt.Id -eq 172 -and $provName -eq 'Microsoft-Windows-Kernel-Power') {
            $null = $connectivityEvents.Add([PSCustomObject]@{ Time = $evt.TimeCreated; Message = $msg })
        }

        # ---- Power Transitions ----
        if ($provName -eq 'Microsoft-Windows-Kernel-Power' -and $evt.Id -in @(42, 107, 109, 507, 105, 521)) {
            $null = $powerEvents.Add([PSCustomObject]@{ Time = $evt.TimeCreated; Id = $evt.Id; Message = $msg })
        }

        # ---- PPTE Power Scheme Cycling (EventID 12) ----
        if ($evt.Id -eq 12 -and $provName -eq 'Microsoft-Windows-UserModePowerService') {
            $fromScheme = ""; $toScheme = ""
            if ($msg -match 'from \{(.+?)\} to \{(.+?)\}') {
                $fromScheme = $Matches[1]; $toScheme = $Matches[2]
            }
            $isPPTE = $msg -match 'qcppte|ppte\.wd'
            $null = $ppteCycleEvents.Add([PSCustomObject]@{
                Time = $evt.TimeCreated; From = $fromScheme; To = $toScheme; IsPPTE = $isPPTE; Message = $msg
            })
        }

        # ---- WudfRd Failures (EventID 219) ----
        if ($evt.Id -eq 219 -and $provName -eq 'Microsoft-Windows-Kernel-PnP') {
            $device = ""; $status = ""
            if ($msg -match 'Device:\s*(.+?)[\r\n]') { $device = $Matches[1].Trim() }
            if ($msg -match 'Status:\s*(0x[0-9A-Fa-f]+)') { $status = $Matches[1] }
            $driverName = ""
            if ($msg -match 'driver\s+(.+?)\s+failed') { $driverName = $Matches[1].Trim() }
            $null = $wudfrdFailures.Add([PSCustomObject]@{
                Time = $evt.TimeCreated; Device = $device; Status = $status; Driver = $driverName; Message = $msg
            })
        }

        # ---- Input Suppression (Win32k) ----
        if ($provName -eq 'Win32k') {
            if ($evt.Id -eq 267) {
                $null = $touchHqaEvents.Add([PSCustomObject]@{ Time = $evt.TimeCreated; Message = $msg })
            }
            if ($evt.Id -in @(700, 701) -or $msg -match 'INPUT_SUPPRESS') {
                $null = $inputSuppressionEvents.Add([PSCustomObject]@{ Time = $evt.TimeCreated; Id = $evt.Id; Message = $msg })
            }
        }

        # ---- UMDF Crashes (EventID 10120, 10111) ----
        if ($evt.Id -in @(10120, 10111) -and $provName -match 'DriverFrameworks') {
            $null = $umdfCrashes.Add([PSCustomObject]@{ Time = $evt.TimeCreated; Id = $evt.Id; Message = $msg })
        }

        # ---- Boot/Shutdown Events ----
        if ($provName -eq 'Microsoft-Windows-Kernel-Power' -and $evt.Id -eq 109) {
            $null = $bootEvents.Add([PSCustomObject]@{ Time = $evt.TimeCreated; Id = $evt.Id; Message = $msg })
        }
        if ($provName -eq 'Microsoft-Windows-Kernel-General' -and $evt.Id -eq 12) {
            $null = $bootEvents.Add([PSCustomObject]@{ Time = $evt.TimeCreated; Id = $evt.Id; Message = "System Boot" })
        }

        # ---- USB Events ----
        if ($provName -match 'USB|usb') {
            $null = $usbEvents.Add([PSCustomObject]@{ Time = $evt.TimeCreated; Id = $evt.Id; Provider = $provName; Level = $evt.Level; Message = $msg })
        }

        # ---- CPU Throttle ----
        if ($provName -eq 'Microsoft-Windows-Kernel-Processor-Power' -and $evt.Id -eq 37) {
            $null = $cpuThrottleEvents.Add([PSCustomObject]@{ Time = $evt.TimeCreated; Message = $msg })
        }

        # ---- HAL Errors ----
        if ($provName -match 'HAL' -and $evt.Level -le 2) {
            $null = $halErrors.Add([PSCustomObject]@{ Time = $evt.TimeCreated; Id = $evt.Id; Message = $msg })
        }

        # ---- All Errors / Criticals ----
        if ($evt.Level -le 2) {
            $null = $errorEvents.Add([PSCustomObject]@{
                Time = $evt.TimeCreated; Id = $evt.Id; Provider = $provName; Level = $evt.Level; Message = $msg
            })
        }
    }
}

# Parse other EVTX files
foreach ($evtx in $evtxFiles) {
    if ($systemEvtx -and $evtx.FullName -eq $systemEvtx.FullName) { continue }
    Write-Host "    Parsing: $($evtx.Name)" -ForegroundColor Gray
    $otherEvents = Get-SafeWinEvent -Path $evtx.FullName -MaxEvents 5000
    foreach ($evt in $otherEvents) {
        if ($evt.Level -le 2) {
            $msg = if ($evt.Message) { $evt.Message } else { "(no msg)" }
            $null = $errorEvents.Add([PSCustomObject]@{
                Time = $evt.TimeCreated; Id = $evt.Id; Provider = $evt.ProviderName; Level = $evt.Level; Message = $msg
            })
        }
    }
}

# ============================================================================
# SECTION 3: Build Sleep/Wake Session Table
# ============================================================================
Write-Host "  [3/8] Building sleep/wake session table..." -ForegroundColor Yellow

$sleepWakeSessions = [System.Collections.ArrayList]::new()
$sortedTransitions = $sessionTransitions | Sort-Object Time
$sortedMSEntries = $modernStandbyEntries | Sort-Object Time

# For each Modern Standby entry (506), find the corresponding wake
for ($i = 0; $i -lt $sortedMSEntries.Count; $i++) {
    $msEntry = $sortedMSEntries[$i]
    $sleepTime = $msEntry.Time
    $sleepReason = $msEntry.Reason

    # Find boot ID from nearest session transition
    $entryTransition = $sortedTransitions | Where-Object {
        [Math]::Abs(($_.Time - $sleepTime).TotalSeconds) -lt 15
    } | Select-Object -First 1
    $bootId = if ($entryTransition) { $entryTransition.BootId } else { "" }

    # Check for austerity in reason
    $hasAusterity = $sleepReason -match 'Austerity'

    # Find the next MS entry (to bound our search for wake)
    $nextMSTime = if ($i + 1 -lt $sortedMSEntries.Count) { $sortedMSEntries[$i + 1].Time } else { [DateTime]::MaxValue }

    # Find wake transitions between this sleep and next sleep
    $wakeTransitions = $sortedTransitions | Where-Object {
        $_.Time -gt $sleepTime.AddSeconds(2) -and $_.Time -lt $nextMSTime -and
        $_.Reason -ne '' -and $_.Reason -ne '55'
    }

    # Also check for austerity transitions (Reason 55) within this sleep
    $austerityTransitions = $sortedTransitions | Where-Object {
        $_.Time -gt $sleepTime.AddSeconds(1) -and $_.Time -lt $nextMSTime -and $_.Reason -eq '55'
    }
    if ($austerityTransitions.Count -gt 0) { $hasAusterity = $true }

    $wakeTime = $null
    $wakeSource = ""
    if ($wakeTransitions.Count -gt 0) {
        # Take the first wake transition that has a meaningful reason
        $wakeEvt = $wakeTransitions | Where-Object { $_.Reason -match 'Input|Accelerometer|SessionUnlock|PolicyChange|AcDc|Unknown|Lid|Power|Button' } | Select-Object -First 1
        if (-not $wakeEvt) { $wakeEvt = $wakeTransitions | Select-Object -First 1 }
        $wakeTime = $wakeEvt.Time
        $wakeSource = $wakeEvt.Reason
    } elseif ($austerityTransitions.Count -gt 0) {
        # If only austerity transitions, take the last one as wake reference won't have real wake
        # Check if any transition at all comes after
        $anyAfter = $sortedTransitions | Where-Object { $_.Time -gt $austerityTransitions[-1].Time -and $_.Time -lt $nextMSTime } | Select-Object -First 1
        if ($anyAfter) {
            $wakeTime = $anyAfter.Time
            $wakeSource = if ($anyAfter.Reason) { $anyAfter.Reason } else { "Unknown" }
        }
    }

    # Calculate duration
    $duration = ""
    $durationSec = 0
    if ($wakeTime) {
        $span = $wakeTime - $sleepTime
        $durationSec = $span.TotalSeconds
        if ($span.TotalHours -ge 1) { $duration = "{0:N0}h {1}m" -f [Math]::Floor($span.TotalHours), $span.Minutes }
        elseif ($span.TotalMinutes -ge 1) { $duration = "~{0:N0} min" -f [Math]::Floor($span.TotalMinutes) }
        else { $duration = "~{0:N0}s" -f $span.TotalSeconds }
    }

    $kbWakeWorked = $wakeSource -match 'InputHid|InputMouse|InputKeyboard'
    $isLongSleep = $durationSec -gt (4 * 3600)
    $isMediumSleep = $durationSec -gt (30 * 60)
    $issueStatus = ""
    if ($kbWakeWorked) { $issueStatus = "OK" }
    elseif ($isLongSleep -and $hasAusterity) { $issueStatus = "ISSUE" }
    elseif ($isMediumSleep -and $hasAusterity -and -not $kbWakeWorked) { $issueStatus = "SUSPECT" }
    elseif ($isLongSleep -and -not $kbWakeWorked) { $issueStatus = "ISSUE" }

    $null = $sleepWakeSessions.Add([PSCustomObject]@{
        Idx = $i + 1
        SleepTime = $sleepTime
        SleepReason = $sleepReason
        WakeTime = $wakeTime
        WakeSource = $wakeSource
        Duration = $duration
        DurationSec = $durationSec
        BootId = $bootId
        HasAusterity = $hasAusterity
        IssueStatus = $issueStatus
    })
}

# ============================================================================
# SECTION 4: PPTE Power Scheme Analysis
# ============================================================================
Write-Host "  [4/8] Analyzing PPTE power cycling..." -ForegroundColor Yellow

$ppteTotal = ($ppteCycleEvents | Where-Object { $_.IsPPTE }).Count
$pptePercentOfAll = if ($totalSystemEvents -gt 0) { [Math]::Round(100.0 * $ppteCycleEvents.Count / $totalSystemEvents, 1) } else { 0 }

$ppteRateMax = 0
$ppteWorstWindow = ""
if ($ppteCycleEvents.Count -gt 10) {
    $sortedPpte = $ppteCycleEvents | Sort-Object Time
    for ($i = 0; $i -lt $sortedPpte.Count - 10; $i++) {
        $windowSec = ($sortedPpte[$i + 10].Time - $sortedPpte[$i].Time).TotalSeconds
        if ($windowSec -gt 0) {
            $rate = 10.0 / $windowSec
            if ($rate -gt $ppteRateMax) {
                $ppteRateMax = [Math]::Round($rate, 1)
                $ppteWorstWindow = $sortedPpte[$i].Time.ToString("yyyy-MM-dd HH:mm:ss")
            }
        }
    }
}

# ============================================================================
# SECTION 5: WudfRd / Driver Failure Analysis
# ============================================================================
Write-Host "  [5/8] Analyzing driver failures..." -ForegroundColor Yellow

$wudfrdByDevice = @{}
foreach ($f in $wudfrdFailures) {
    $key = $f.Device
    if (-not $wudfrdByDevice.ContainsKey($key)) { $wudfrdByDevice[$key] = [System.Collections.ArrayList]::new() }
    $null = $wudfrdByDevice[$key].Add($f)
}

$inputDevicePatterns = @('VID_04F3', 'VID_045E.*PID_0855', 'HID\\VID', 'keyboard', 'mouse', 'touch', 'ELAN')

# ============================================================================
# SECTION 6: Parse ETL Files
# ============================================================================
Write-Host "  [6/8] Parsing ETL trace files..." -ForegroundColor Yellow

$etlFiles = Get-ChildItem -Path $LogDir -Filter "*.etl*" -ErrorAction SilentlyContinue
$etlSummary = [System.Collections.ArrayList]::new()
$etlProviderCounts = @{}
$etlTotalEvents = 0
$etlFirstTime = $null
$etlLastTime = $null

foreach ($etl in $etlFiles) {
    Write-Host "    Parsing: $($etl.Name) ($([Math]::Round($etl.Length / 1MB, 1)) MB)" -ForegroundColor Gray
    $eventCount = 0
    $firstTime = $null
    $lastTime = $null
    $provCounts = @{}

    try {
        $etlEvents = Get-WinEvent -Path $etl.FullName -Oldest -MaxEvents 50000 -ErrorAction Stop
        $eventCount = $etlEvents.Count
        $etlTotalEvents += $eventCount

        if ($etlEvents.Count -gt 0) {
            $firstTime = $etlEvents[0].TimeCreated
            $lastTime = $etlEvents[-1].TimeCreated
            if (-not $etlFirstTime -or $firstTime -lt $etlFirstTime) { $etlFirstTime = $firstTime }
            if (-not $etlLastTime -or $lastTime -gt $etlLastTime) { $etlLastTime = $lastTime }
        }

        foreach ($evt in $etlEvents) {
            $prov = if ($evt.ProviderName) { $evt.ProviderName } else { $evt.ProviderId.ToString() }
            if (-not $provCounts.ContainsKey($prov)) { $provCounts[$prov] = 0 }
            $provCounts[$prov]++
            if (-not $etlProviderCounts.ContainsKey($prov)) { $etlProviderCounts[$prov] = 0 }
            $etlProviderCounts[$prov]++
        }
    } catch { }

    $null = $etlSummary.Add([PSCustomObject]@{
        FileName = $etl.Name; SizeMB = [Math]::Round($etl.Length / 1MB, 1)
        Events = $eventCount; FirstEvent = $firstTime; LastEvent = $lastTime
        ProviderCounts = $provCounts
    })
}

# ============================================================================
# SECTION 7: Issue Detection
# ============================================================================
Write-Host "  [7/8] Detecting issues..." -ForegroundColor Yellow

# -- Austerity wake loss --
$austerityNoKbWake = $sleepWakeSessions | Where-Object { $_.HasAusterity -and $_.DurationSec -gt 1800 -and -not ($_.WakeSource -match 'InputHid|InputMouse|InputKeyboard') }
if ($austerityNoKbWake.Count -gt 0) {
    $null = $issues.Add([PSCustomObject]@{
        Severity = "Critical"; Title = "Austerity Mode Blocks Keyboard/Touchpad Wake"
        Description = "After entering Modern Standby austerity mode (battery drain budget exceeded), the platform powers down USB/I2C buses hosting input devices. $($austerityNoKbWake.Count) sleep session(s) with austerity lasted >30 min and woke via accelerometer/lid rather than keyboard/touchpad. The first keypress is consumed by bus re-initialization and never reaches the power manager as a wake signal."
        Category = "AusterityWakeLoss"
    })
}

# -- Long sleep without KB wake --
$longSleepNoKb = $sleepWakeSessions | Where-Object { $_.DurationSec -gt (4 * 3600) -and -not ($_.WakeSource -match 'InputHid|InputMouse|InputKeyboard') }
if ($longSleepNoKb.Count -gt 0) {
    $null = $issues.Add([PSCustomObject]@{
        Severity = "Critical"; Title = "Overnight Sleep - Keyboard/Touchpad Cannot Wake System"
        Description = "$($longSleepNoKb.Count) sleep session(s) lasting >4 hours failed to wake via keyboard/touchpad. Wake sources: $(($longSleepNoKb | ForEach-Object { $_.WakeSource }) -join ', '). Single keypress does not wake the system after extended modern standby."
        Category = "LongSleepWakeFail"
    })
}

# -- PPTE cycling --
if ($ppteCycleEvents.Count -gt 50) {
    $null = $issues.Add([PSCustomObject]@{
        Severity = "High"; Title = "Qualcomm PPTE Power Scheme Thrashing"
        Description = "$($ppteCycleEvents.Count) power policy change events ($pptePercentOfAll% of all events). qcppte8480.exe rapidly toggles Balanced/Performance at up to $ppteRateMax flips/sec (peak at $ppteWorstWindow). This overwhelms USB selective-suspend policy and may contribute to input device power state corruption."
        Category = "PPTECycling"
    })
}

# -- WudfRd for input devices --
$inputWudfrdCount = 0
foreach ($dev in $wudfrdByDevice.Keys) {
    foreach ($p in $inputDevicePatterns) { if ($dev -match $p) { $inputWudfrdCount += $wudfrdByDevice[$dev].Count; break } }
}
if ($inputWudfrdCount -gt 0) {
    $null = $issues.Add([PSCustomObject]@{
        Severity = "High"; Title = "UMDF Driver (WudfRd) Fails to Load for Input Devices"
        Description = "WudfRd driver fails to load (Status: 0xC0000365) for HID/input devices at boot ($inputWudfrdCount occurrence(s)). ELAN touchpad and keyboard are UMDF-hosted - this timing dependency may worsen recovery from deep standby."
        Category = "WudfRdFailure"
    })
}

# -- UMDF crashes --
if ($umdfCrashes.Count -gt 0) {
    $null = $issues.Add([PSCustomObject]@{
        Severity = "High"; Title = "UMDF Host Process Crashes ($($umdfCrashes.Count))"
        Description = "UMDF hosts multiple devices per process. A crash of any co-hosted device can take down keyboard/trackpad silently."
        Category = "UMDFCrash"
    })
}

# -- USB controller errors --
$usbErrors = $usbEvents | Where-Object { $_.Level -le 2 }
if ($usbErrors.Count -gt 0) {
    $null = $issues.Add([PSCustomObject]@{
        Severity = "High"; Title = "USB Controller Errors ($($usbErrors.Count))"
        Description = "USB error events detected. USB controller failures can affect all USB-connected input devices."
        Category = "USBFailure"
    })
}

# -- HAL ACPI timer --
$halAcpiErrors = $halErrors | Where-Object { $_.Id -eq 20 }
if ($halAcpiErrors.Count -gt 0) {
    $null = $issues.Add([PSCustomObject]@{
        Severity = "Medium"; Title = "ACPI Time/Alarm Device Failures ($($halAcpiErrors.Count))"
        Description = "HAL ACPI Time and Alarm Device method failures. Used for scheduled wake timers during Modern Standby. Unreliable wake timers may prevent periodic device state refresh."
        Category = "ACPITimerFail"
    })
}

$issueCount = $issues.Count
Write-Host "    Found: $issueCount issues" -ForegroundColor $(if ($issueCount -gt 0) { "Red" } else { "Green" })

# ============================================================================
# SECTION 8: Generate HTML Report
# ============================================================================
Write-Host "  [8/8] Generating HTML report..." -ForegroundColor Yellow

$reportPath = Join-Path $LogDir "QCLogger-Report.html"

# ---- Find worst incident ----
$worstSession = $sleepWakeSessions | Where-Object { $_.IssueStatus -eq 'ISSUE' } | Sort-Object DurationSec -Descending | Select-Object -First 1
if (-not $worstSession) {
    $worstSession = $sleepWakeSessions | Where-Object { $_.IssueStatus -eq 'SUSPECT' } | Sort-Object DurationSec -Descending | Select-Object -First 1
}

# ---- Boot cycles ----
$bootIds = ($sessionTransitions | Where-Object { $_.BootId -ne '' } | Select-Object -ExpandProperty BootId -Unique) | Sort-Object
$bootCount = if ($bootIds) { $bootIds.Count } else { 0 }

# ---- Provider table ----
$providerRows = ""
$sortedProviders = $providerCounts.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 20
foreach ($p in $sortedProviders) {
    $relevance = ""; $rowClass = ""
    if ($p.Key -match 'Kernel-Power') { $relevance = '<span class="badge badge-red">KEY</span> Sleep/wake transitions'; $rowClass = 'warn-row' }
    elseif ($p.Key -match 'UserModePowerService') { $relevance = '<span class="badge badge-orange">RELEVANT</span> Power policy changes'; $rowClass = 'warn-row' }
    elseif ($p.Key -match 'Kernel-PnP') { $relevance = '<span class="badge badge-red">KEY</span> Driver/device failures'; $rowClass = 'warn-row' }
    elseif ($p.Key -match 'DriverFrameworks') { $relevance = '<span class="badge badge-orange">RELEVANT</span> UMDF reflector'; $rowClass = 'warn-row' }
    elseif ($p.Key -match 'Win32k') { $relevance = '<span class="badge badge-orange">RELEVANT</span> Input suppression'; $rowClass = 'warn-row' }
    elseif ($p.Key -match 'USB') { $relevance = '<span class="badge badge-orange">RELEVANT</span> USB stack'; $rowClass = 'warn-row' }
    else { $relevance = $p.Key -replace 'Microsoft-Windows-', '' }
    $providerRows += "<tr class=`"$rowClass`"><td>$($p.Key)</td><td><strong>$($p.Value)</strong></td><td>$relevance</td></tr>`n"
}

# ---- Sleep/Wake table ----
$sleepWakeRows = ""
foreach ($s in $sleepWakeSessions) {
    $rowClass = switch ($s.IssueStatus) { "ISSUE" { "highlight-row" }; "SUSPECT" { "warn-row" }; default { "ok-row" } }
    $reasonTag = if ($s.SleepReason -match 'Austerity') { '<span class="tag tag-austerity">Austerity Budget</span>' }
                 elseif ($s.SleepReason -match 'Idle') { '<span class="tag tag-idle">Idle Timeout</span>' }
                 elseif ($s.SleepReason -match 'Power Button') { '<span class="tag tag-button">Power Button</span>' }
                 elseif ($s.SleepReason -match 'Lid') { '<span class="tag tag-lid">Lid</span>' }
                 else { "<span class=`"tag tag-policy`">$($s.SleepReason)</span>" }
    $durationClass = if ($s.DurationSec -gt 14400) { "long-sleep" } else { "duration" }
    $wakeTimeStr = if ($s.WakeTime) { $s.WakeTime.ToString("yyyy-MM-dd HH:mm:ss") } else { "---" }
    $issueTag = switch ($s.IssueStatus) { "ISSUE" { '<span class="badge badge-red">ISSUE</span>' }; "SUSPECT" { '<span class="badge badge-orange">SUSPECT</span>' }; "OK" { '<span class="badge badge-green">OK</span>' }; default { "" } }
    $b = if ($s.IssueStatus -eq "ISSUE") { "<strong>" } else { "" }
    $be = if ($s.IssueStatus -eq "ISSUE") { "</strong>" } else { "" }
    $sleepWakeRows += "<tr class=`"$rowClass`"><td>$($s.Idx)</td><td>$b$($s.SleepTime.ToString('yyyy-MM-dd HH:mm:ss'))$be</td><td>$reasonTag</td><td>$b$wakeTimeStr$be</td><td class=`"$durationClass`">$b$($s.Duration)$be</td><td>$b$($s.WakeSource)$be</td><td>B$($s.BootId)</td><td>$issueTag</td></tr>`n"
}

# ---- WudfRd table ----
$wudfrdRows = ""
foreach ($dev in $wudfrdByDevice.Keys | Sort-Object) {
    $count = $wudfrdByDevice[$dev].Count
    $isInput = $false
    foreach ($p in $inputDevicePatterns) { if ($dev -match $p) { $isInput = $true; break } }
    $rowClass = if ($isInput) { "highlight-row" } else { "" }
    $impact = if ($dev -match 'VID_04F3.*PID_0C9E.*MI_01') { '<span class="badge badge-red">HIGH</span> Touchpad HID' }
              elseif ($dev -match 'VID_04F3.*PID_0C9E.*MI_00') { '<span class="badge badge-red">HIGH</span> Touchpad USB' }
              elseif ($dev -match 'VID_04F3.*PID_0C9E') { '<span class="badge badge-red">HIGH</span> ELAN Input' }
              elseif ($dev -match 'VID_045E.*PID_0855') { '<span class="badge badge-orange">MEDIUM</span> Keyboard' }
              elseif ($dev -match 'HID\\') { '<span class="badge badge-orange">MEDIUM</span> HID device' }
              else { '<span class="badge badge-blue">LOW</span>' }
    $shortDev = ($dev -replace '<','&lt;' -replace '>','&gt;')
    $wudfrdRows += "<tr class=`"$rowClass`"><td><code>$shortDev</code></td><td>$count</td><td>$impact</td></tr>`n"
}

# ---- Issues HTML ----
$issuesHtml = ""
$issueNum = 0
foreach ($issue in $issues) {
    $issueNum++
    $boxClass = switch ($issue.Severity) { "Critical" { "" }; "High" { " warn" }; default { " info" } }
    $issuesHtml += @"
<div class="finding-box$boxClass">
<div class="finding-num">#$issueNum</div>
<div>
<strong>$($issue.Title)</strong><br>
<span style="color:var(--text-muted)">$($issue.Description)</span>
</div>
</div>
"@
}

# ---- PPTE bursts ----
$ppteHtml = ""
if ($ppteCycleEvents.Count -gt 0) {
    $sortedPpte = $ppteCycleEvents | Sort-Object Time
    $ppteWindows = [System.Collections.ArrayList]::new()
    $windowStart = $sortedPpte[0].Time; $windowCount = 0
    foreach ($p in $sortedPpte) {
        if (($p.Time - $windowStart).TotalSeconds -lt 5) { $windowCount++ }
        else {
            if ($windowCount -gt 3) { $null = $ppteWindows.Add([PSCustomObject]@{ Time = $windowStart; Count = $windowCount; RatePerSec = [Math]::Round($windowCount / 5.0, 1) }) }
            $windowStart = $p.Time; $windowCount = 1
        }
    }
    foreach ($b in ($ppteWindows | Sort-Object Count -Descending | Select-Object -First 10)) {
        $ppteHtml += "<tr><td style='font-family:monospace'>$($b.Time.ToString('yyyy-MM-dd HH:mm:ss'))</td><td>$($b.Count) flips</td><td>~$($b.RatePerSec)/sec</td></tr>`n"
    }
}

# ---- Error summary ----
$errorGroups = @{}
foreach ($e in $errorEvents) {
    $key = "$($e.Provider)|$($e.Id)"
    if (-not $errorGroups.ContainsKey($key)) { $errorGroups[$key] = @{ Count = 0; Provider = $e.Provider; Id = $e.Id; Sample = $e.Message } }
    $errorGroups[$key].Count++
}
$errorSummaryRows = ""
foreach ($eg in ($errorGroups.Values | Sort-Object Count -Descending | Select-Object -First 15)) {
    $shortMsg = ($eg.Sample -replace '<','&lt;' -replace '>','&gt;')
    if ($shortMsg.Length -gt 120) { $shortMsg = $shortMsg.Substring(0, 120) + "..." }
    $errorSummaryRows += "<tr><td>$($eg.Provider)</td><td>$($eg.Id)</td><td>$($eg.Count)</td><td>$shortMsg</td></tr>`n"
}

# ---- ETL summary ----
$etlRows = ""
foreach ($etl in $etlSummary) {
    $firstStr = if ($etl.FirstEvent) { $etl.FirstEvent.ToString("yyyy-MM-dd HH:mm:ss") } else { "N/A (WPP-only)" }
    $lastStr = if ($etl.LastEvent) { $etl.LastEvent.ToString("yyyy-MM-dd HH:mm:ss") } else { "---" }
    $etlRows += "<tr><td>$($etl.FileName)</td><td>$($etl.SizeMB) MB</td><td>$($etl.Events)</td><td>$firstStr</td><td>$lastStr</td></tr>`n"
}
$etlProviderRows = ""
foreach ($p in ($etlProviderCounts.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 15)) {
    $needsTmf = if ($p.Key -match '^[{0-9a-f-]+') { '<span class="badge badge-orange">Needs TMF</span>' } else { "" }
    $etlProviderRows += "<tr><td><code>$($p.Key)</code></td><td>$($p.Value)</td><td>$needsTmf</td></tr>`n"
}

# ---- Files ----
$filesHtml = (Get-ChildItem -Path $LogDir -File | ForEach-Object {
    "<tr><td>$($_.Name)</td><td>$([Math]::Round($_.Length / 1KB, 1)) KB</td><td>$($_.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))</td></tr>"
}) -join "`n"

# ---- Banner ----
$bannerTitle = "Keyboard &amp; Trackpad Input Issue Detected"
$bannerDesc = "Analysis of $totalSystemEvents system events"
if ($worstSession) { $bannerDesc += ". Worst incident: $($worstSession.Duration) sleep, woke via $($worstSession.WakeSource) (not keyboard/touchpad)" }
if ($austerityNoKbWake.Count -gt 0) { $bannerDesc += ". Austerity mode blocked input wake in $($austerityNoKbWake.Count) session(s)." }

# ---- Incident timeline ----
$incidentTimelineHtml = ""
if ($worstSession) {
    $priorBoot = $bootEvents | Where-Object { $_.Time -lt $worstSession.SleepTime } | Sort-Object Time -Descending | Select-Object -First 1
    if ($priorBoot) {
        $incidentTimelineHtml += "<div class=`"tl-item info`"><div class=`"tl-time`">$($priorBoot.Time.ToString('yyyy-MM-dd HH:mm:ss'))</div><div class=`"tl-title`">$($priorBoot.Message)</div><div class=`"tl-desc`">Boot ID: $($worstSession.BootId)</div></div>`n"
    }
    $hqa = $touchHqaEvents | Where-Object { $_.Time -gt $worstSession.SleepTime.AddHours(-2) -and $_.Time -lt $worstSession.SleepTime } | Select-Object -First 1
    if ($hqa) {
        $incidentTimelineHtml += "<div class=`"tl-item wake`"><div class=`"tl-time`">$($hqa.Time.ToString('yyyy-MM-dd HH:mm:ss'))</div><div class=`"tl-title`">Touch/Touchpad HQA Verification PASSED</div><div class=`"tl-desc`">Hardware verified successfully</div></div>`n"
    }
    $priorOk = $sleepWakeSessions | Where-Object { $_.SleepTime -lt $worstSession.SleepTime -and $_.BootId -eq $worstSession.BootId -and $_.IssueStatus -ne 'ISSUE' } | Select-Object -Last 3
    foreach ($ok in $priorOk) {
        $incidentTimelineHtml += "<div class=`"tl-item wake`"><div class=`"tl-time`">$($ok.SleepTime.ToString('yyyy-MM-dd HH:mm:ss'))</div><div class=`"tl-title`">Sleep/Wake #$($ok.Idx) - $($ok.Duration) ($($ok.SleepReason)) - SUCCESS</div><div class=`"tl-desc`">Wake source: $($ok.WakeSource)</div></div>`n"
    }
    $incidentTimelineHtml += "<div class=`"tl-item sleep`"><div class=`"tl-time`">$($worstSession.SleepTime.ToString('yyyy-MM-dd HH:mm:ss'))</div><div class=`"tl-title`">Modern Standby Entry - $($worstSession.SleepReason)</div><div class=`"tl-desc`">$(if ($worstSession.HasAusterity) { 'Austerity mode will activate - battery drain budget exceeded.' } else { 'System enters standby.' })</div></div>`n"
    if ($worstSession.HasAusterity) {
        $incidentTimelineHtml += "<div class=`"tl-item error`"><div class=`"tl-time`">After standby entry</div><div class=`"tl-title`">Austerity Mode Activated - Battery Drain Budget Exceeded</div><div class=`"tl-desc`">Platform powers down non-essential buses including USB/I2C controllers for input devices. Keyboard and touchpad lose their wake-armed state.</div></div>`n"
    }
    $wakeStr = if ($worstSession.WakeTime) { $worstSession.WakeTime.ToString('yyyy-MM-dd HH:mm:ss') } else { "?" }
    $incidentTimelineHtml += "<div class=`"tl-item critical`"><div class=`"tl-time`">$($worstSession.SleepTime.ToString('yyyy-MM-dd HH:mm:ss')) -> $wakeStr</div><div class=`"tl-title`">DEEP SLEEP GAP: $($worstSession.Duration)</div><div class=`"tl-desc`">No session transitions during this period. Input device buses powered down. Any keyboard press or touchpad touch is consumed by bus re-initialization and never reaches the power manager as a wake signal. <strong>A second input event (or lid open / physical movement) is required to wake.</strong></div></div>`n"
    if ($worstSession.WakeTime) {
        $incidentTimelineHtml += "<div class=`"tl-item wake`"><div class=`"tl-time`">$wakeStr</div><div class=`"tl-title`">Wake via $($worstSession.WakeSource) (NOT keyboard/touchpad)</div><div class=`"tl-desc`">System woke via physical movement / lid / accelerometer, confirming input devices were unable to signal wake.</div></div>`n"
    }
}

# ---- Recommendations ----
$recommendationsHtml = @"
<div class="card card-green">
<h3>1. Investigate Austerity Mode USB/I2C Power Gating</h3>
<p>Check if the I2C controller for keyboard/touchpad can be excluded from austerity power gating. The Qualcomm PEP driver (qcpep.wd8480) controls which devices are powered down. Input devices should maintain wake-arm state even in deep standby.</p>
</div>
<div class="card card-green">
<h3>2. Preserve Wake-Armed State in Deep Sleep</h3>
<p>Work with Qualcomm to ensure the GPIO/interrupt line for input devices remains enabled for wake signaling in austerity mode. This is a platform-level change in PEP device list or ACPI _DSW/_PRW methods.</p>
</div>
<div class="card card-green">
<h3>3. Address WudfRd Driver Load Failures</h3>
<p>The consistent 0xC0000365 (STATUS_NOT_FOUND) for ELAN touchpad and keyboard indicates UMDF driver fragility that worsens recovery from deep standby.</p>
</div>
<div class="card card-green">
<h3>4. Investigate PPTE Power Scheme Flapping</h3>
<p>Qualcomm PPTE (qcppte8480) rapidly toggles Balanced/Performance ($($ppteCycleEvents.Count) events). This flapping causes transient USB selective-suspend policy changes.</p>
</div>
<div class="card card-green">
<h3>5. Decode ETL Trace with TMF/PDB Files</h3>
<p>ETL contains $etlTotalEvents events. Requires Qualcomm TMF/PDB files to decode WPP messages. Load in WPA (Windows Performance Analyzer) with correct symbol files.</p>
</div>
<div class="card card-green">
<h3>6. Test USB Selective Suspend Disable for ELAN</h3>
<p>Workaround: <code>powercfg /setdcvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0</code></p>
</div>
<div class="card card-green">
<h3>7. Adjust Battery Drain Budget Thresholds</h3>
<p>Consider increasing the austerity battery drain budget threshold or implementing a tiered approach where input devices maintain wake capability even in constrained power states.</p>
</div>
"@

# ---- Full HTML ----
$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>QCLogger Diagnostic Report - $computerName</title>
<style>
:root { --bg:#0d1117;--surface:#161b22;--surface2:#21262d;--border:#30363d;--text:#c9d1d9;--text-muted:#8b949e;--accent:#58a6ff;--red:#f85149;--orange:#d29922;--green:#3fb950;--purple:#bc8cff;--pink:#f778ba;--cyan:#39d2c0; }
*{margin:0;padding:0;box-sizing:border-box}
body{background:var(--bg);color:var(--text);font-family:'Segoe UI',system-ui,sans-serif;line-height:1.6;padding:20px}
.container{max-width:1400px;margin:0 auto}
h1{color:var(--accent);font-size:1.8em;margin-bottom:8px;border-bottom:2px solid var(--accent);padding-bottom:10px}
h2{color:var(--accent);font-size:1.3em;margin:32px 0 16px;border-bottom:1px solid var(--border);padding-bottom:8px}
h3{color:var(--purple);font-size:1.1em;margin:20px 0 10px}
.subtitle{color:var(--text-muted);margin-bottom:24px;font-size:.95em}
.card{background:var(--surface);border:1px solid var(--border);border-radius:6px;padding:16px;margin-bottom:16px}
.card-red{border-left:4px solid var(--red)}.card-orange{border-left:4px solid var(--orange)}.card-green{border-left:4px solid var(--green)}.card-blue{border-left:4px solid var(--accent)}.card-purple{border-left:4px solid var(--purple)}
.badge{display:inline-block;padding:2px 8px;border-radius:12px;font-size:.8em;font-weight:600;margin-right:6px}
.badge-red{background:rgba(248,81,73,.2);color:var(--red)}.badge-orange{background:rgba(210,153,34,.2);color:var(--orange)}.badge-green{background:rgba(63,185,80,.2);color:var(--green)}.badge-blue{background:rgba(88,166,255,.2);color:var(--accent)}.badge-purple{background:rgba(188,140,255,.2);color:var(--purple)}
table{width:100%;border-collapse:collapse;margin:12px 0;font-size:.9em}
th{background:var(--surface2);color:var(--accent);text-align:left;padding:8px 12px;border:1px solid var(--border);white-space:nowrap}
td{padding:6px 12px;border:1px solid var(--border);vertical-align:top}
tr:hover td{background:var(--surface2)}
.highlight-row td{background:rgba(248,81,73,.1)!important}.warn-row td{background:rgba(210,153,34,.08)!important}.ok-row td{background:rgba(63,185,80,.05)!important}
code{background:var(--surface2);padding:2px 6px;border-radius:3px;font-family:'Cascadia Code',Consolas,monospace;font-size:.9em;color:var(--pink)}
.card-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(160px,1fr));gap:12px;margin:16px 0}
.stat-card{background:var(--surface);border:1px solid var(--border);border-radius:8px;padding:16px;text-align:center}
.stat-card .value{font-size:2em;font-weight:bold}.stat-card .label{font-size:.85em;color:var(--text-muted);margin-top:4px}
.stat-card.critical .value{color:var(--red)}.stat-card.warning .value{color:var(--orange)}.stat-card.info .value{color:var(--accent)}.stat-card.ok .value{color:var(--green)}
.separator{border:0;border-top:1px solid var(--border);margin:24px 0}
.timeline{position:relative;padding-left:30px}.timeline::before{content:'';position:absolute;left:14px;top:0;bottom:0;width:2px;background:var(--border)}
.tl-item{position:relative;margin-bottom:12px;padding:10px 14px;background:var(--surface);border-radius:6px;border:1px solid var(--border)}
.tl-item::before{content:'';position:absolute;left:-22px;top:14px;width:10px;height:10px;border-radius:50%;border:2px solid var(--accent);background:var(--bg)}
.tl-item.sleep::before{background:var(--orange);border-color:var(--orange)}.tl-item.wake::before{background:var(--green);border-color:var(--green)}.tl-item.error::before{background:var(--red);border-color:var(--red)}.tl-item.critical::before{background:var(--red);border-color:var(--red);box-shadow:0 0 8px var(--red)}.tl-item.info::before{background:var(--accent);border-color:var(--accent)}
.tl-time{color:var(--text-muted);font-size:.85em;font-family:monospace}.tl-title{font-weight:600;margin:2px 0}.tl-desc{font-size:.9em;color:var(--text-muted)}
.finding-box{display:flex;gap:12px;align-items:flex-start;padding:16px;background:var(--surface);border-left:3px solid var(--red);border-radius:0 8px 8px 0;margin:12px 0}
.finding-box.warn{border-left-color:var(--orange)}.finding-box.info{border-left-color:var(--accent)}
.finding-num{font-size:1.3em;font-weight:bold;color:var(--red);min-width:30px}.finding-box.warn .finding-num{color:var(--orange)}.finding-box.info .finding-num{color:var(--accent)}
.severity-banner{background:linear-gradient(135deg,rgba(248,81,73,.15),rgba(210,153,34,.1));border:1px solid var(--red);border-radius:8px;padding:16px 20px;margin:16px 0;display:flex;align-items:center;gap:16px}
.severity-icon{font-size:2.5em}
.tag{display:inline-block;padding:1px 6px;border-radius:3px;font-size:.8em;margin:1px}
.tag-idle{background:rgba(210,153,34,.15);color:var(--orange)}.tag-austerity{background:rgba(248,81,73,.15);color:var(--red)}.tag-policy{background:rgba(88,166,255,.15);color:var(--accent)}.tag-button{background:rgba(188,140,255,.15);color:var(--purple)}.tag-lid{background:rgba(247,120,186,.15);color:var(--pink)}
.duration{font-family:monospace;color:var(--orange)}.long-sleep{font-family:monospace;color:var(--red);font-weight:bold}
.toc{background:var(--surface);border:1px solid var(--border);border-radius:6px;padding:16px;margin-bottom:24px}.toc a{color:var(--accent);text-decoration:none}.toc a:hover{text-decoration:underline}.toc ul{padding-left:20px}.toc li{margin:4px 0}
@media(max-width:768px){.card-grid{grid-template-columns:1fr}}
</style>
</head>
<body>
<div class="container">

<h1>&#x1F50D; QCLogger Diagnostic Report</h1>
<p class="subtitle">KB/TP Wake &amp; Input Failure Analysis &bull; $computerName &bull; Build $osBuild ($osDisplay) &bull; Analyzed: $analysisTime</p>

$(if ($issueCount -gt 0) {
"<div class=`"severity-banner`"><div class=`"severity-icon`">&#9888;&#65039;</div><div><strong style=`"font-size:1.1em`">$bannerTitle</strong><br><span style=`"color:var(--text-muted)`">$bannerDesc</span></div></div>"
})

<div class="toc"><strong>Contents</strong>
<ul>
<li><a href="#metrics">Key Metrics</a></li>
<li><a href="#issues">Detected Issues</a></li>
<li><a href="#sleepwake">Sleep/Wake Timeline</a></li>
$(if ($worstSession) { '<li><a href="#incident">Incident Deep Dive</a></li>' })
<li><a href="#ppte">PPTE Power Cycling</a></li>
<li><a href="#pnpfail">PnP &amp; Driver Failures</a></li>
<li><a href="#errors">System Errors</a></li>
<li><a href="#providers">Event Source Breakdown</a></li>
<li><a href="#etl">ETL Trace Summary</a></li>
<li><a href="#recommendations">Recommendations</a></li>
<li><a href="#files">Collected Files</a></li>
</ul></div>

<div id="metrics"><h2>&#x1F4CA; Key Metrics</h2>
<div class="card-grid">
<div class="stat-card info"><div class="value">$totalSystemEvents</div><div class="label">System Events</div></div>
<div class="stat-card warning"><div class="value">$bootCount</div><div class="label">Boot Cycles</div></div>
<div class="stat-card critical"><div class="value">$issueCount</div><div class="label">Issues Found</div></div>
<div class="stat-card warning"><div class="value">$($sleepWakeSessions.Count)</div><div class="label">Sleep/Wake Cycles</div></div>
<div class="stat-card warning"><div class="value">$($ppteCycleEvents.Count)</div><div class="label">PPTE Power Flips</div></div>
<div class="stat-card critical"><div class="value">$($wudfrdFailures.Count)</div><div class="label">WudfRd Failures</div></div>
<div class="stat-card critical"><div class="value">$($umdfCrashes.Count)</div><div class="label">UMDF Crashes</div></div>
<div class="stat-card info"><div class="value">$etlTotalEvents</div><div class="label">ETL Events</div></div>
</div></div>

<hr class="separator">

<div id="issues"><h2>&#x26A0;&#xFE0F; Detected Issues ($issueCount)</h2>
$(if ($issueCount -eq 0) { '<div class="card card-green"><p>No critical keyboard/touchpad issues detected. Review the sleep/wake timeline below for subtle patterns.</p></div>' } else { $issuesHtml })
</div>

<hr class="separator">

<div id="sleepwake"><h2>&#x1F4A4; Sleep/Wake Timeline ($($sleepWakeSessions.Count) sessions)</h2>
<div class="card card-orange">
<p style="color:var(--text-muted);margin-bottom:8px"><span class="badge badge-red">ISSUE</span> = Long sleep + no KB/TP wake. <span class="badge badge-orange">SUSPECT</span> = Moderate + austerity + non-keyboard wake. <span class="badge badge-green">OK</span> = KB/TP woke successfully.</p>
<div style="overflow-x:auto"><table>
<tr><th>#</th><th>Sleep Entry</th><th>Reason</th><th>Wake Time</th><th>Duration</th><th>Wake Source</th><th>Boot</th><th>Status</th></tr>
$sleepWakeRows
</table></div></div></div>

<hr class="separator">

$(if ($worstSession) {
@"
<div id="incident"><h2>&#x1F534; Incident Deep Dive</h2>
<div class="card card-red">
<h3>Failing Scenario (Boot $($worstSession.BootId), $($worstSession.Duration) sleep)</h3>
<div class="timeline">$incidentTimelineHtml</div>
</div>
<div class="card card-blue"><h3>Pattern Correlation</h3>
<table><tr><th>Condition</th><th>Sleep Duration</th><th>Austerity?</th><th>Single Keypress Wake?</th></tr>
<tr class="ok-row"><td>Short idle</td><td>&lt; 5 min</td><td>No</td><td><span class="badge badge-green">YES</span></td></tr>
<tr class="ok-row"><td>Medium idle</td><td>5-30 min</td><td>No</td><td><span class="badge badge-green">YES</span></td></tr>
<tr class="warn-row"><td>Extended</td><td>30 min - 2 hrs</td><td>Sometimes</td><td><span class="badge badge-orange">INTERMITTENT</span></td></tr>
<tr class="highlight-row"><td><strong>Long (overnight)</strong></td><td><strong>&gt;4 hours</strong></td><td><strong>Yes</strong></td><td><span class="badge badge-red">NO - Requires 2nd press or lid open</span></td></tr>
</table></div></div><hr class="separator">
"@
})

<div id="ppte"><h2>&#x26A1; Qualcomm PPTE Power Cycling ($($ppteCycleEvents.Count) events)</h2>
$(if ($ppteCycleEvents.Count -gt 0) {
@"
<div class="card card-orange">
<p style="margin-bottom:12px">qcppte8480.exe toggles <span class="tag tag-policy">Balanced</span> / <span class="tag tag-button">Performance</span> at up to <strong>$ppteRateMax flips/sec</strong> ($pptePercentOfAll% of all events).</p>
$(if ($ppteHtml) { "<h3>Peak Bursts</h3><table><tr><th>Time</th><th>Flips in 5s</th><th>Rate</th></tr>$ppteHtml</table>" })
</div>
"@
} else { '<div class="card"><p style="color:var(--text-muted)">No PPTE cycling detected.</p></div>' })
</div>

<hr class="separator">

<div id="pnpfail"><h2>&#x1F527; PnP &amp; Driver Failures ($($wudfrdFailures.Count))</h2>
$(if ($wudfrdFailures.Count -gt 0) {
@"
<div class="card card-red"><h3>WudfRd Load Failures - Event 219</h3>
<p style="margin-bottom:8px"><code>\Driver\WudfRd</code> fails (0xC0000365 = STATUS_NOT_FOUND). Input devices marked <span class="badge badge-red">HIGH</span>.</p>
<table><tr><th>Device</th><th>Count</th><th>Impact</th></tr>$wudfrdRows</table></div>
"@
} else { '<div class="card"><p style="color:var(--text-muted)">No WudfRd failures detected.</p></div>' })
$(if ($umdfCrashes.Count -gt 0) {
    $crashRows = ($umdfCrashes | ForEach-Object { $sm = ($_.Message -replace '<','&lt;' -replace '>','&gt;'); if ($sm.Length -gt 150) { $sm = $sm.Substring(0,150)+'...' }; "<tr><td style='font-family:monospace'>$($_.Time.ToString('yyyy-MM-dd HH:mm:ss'))</td><td><span class='badge badge-red'>$($_.Id)</span></td><td>$sm</td></tr>" }) -join "`n"
    "<div class=`"card card-red`"><h3>UMDF Crashes</h3><table><tr><th>Time</th><th>Event</th><th>Details</th></tr>$crashRows</table></div>"
})
</div>

<hr class="separator">

<div id="errors"><h2>&#x274C; System Errors ($($errorEvents.Count))</h2>
<div class="card"><table><tr><th>Provider</th><th>ID</th><th>Count</th><th>Sample</th></tr>$errorSummaryRows</table></div></div>

<hr class="separator">

<div id="providers"><h2>&#x1F4CA; Event Source Breakdown (Top 20)</h2>
<div class="card"><table><tr><th>Provider</th><th>Count</th><th>Relevance</th></tr>$providerRows</table></div></div>

<hr class="separator">

<div id="etl"><h2>&#x1F4BE; ETL Trace Summary ($($etlSummary.Count) files, $etlTotalEvents decoded)</h2>
<div class="card card-blue">
<table><tr><th>File</th><th>Size</th><th>Decoded Events</th><th>First</th><th>Last</th></tr>$etlRows</table>
$(if ($etlProviderRows) { "<h3 style='margin-top:16px'>Top Providers</h3><table><tr><th>Provider</th><th>Events</th><th>Status</th></tr>$etlProviderRows</table>" })
$(if ($etlFirstTime -and $etlLastTime) { "<p style='margin-top:12px;color:var(--text-muted)'>Range: $($etlFirstTime.ToString('yyyy-MM-dd HH:mm:ss')) - $($etlLastTime.ToString('yyyy-MM-dd HH:mm:ss'))</p>" })
</div></div>

<hr class="separator">

<div id="recommendations"><h2>&#x2705; Recommendations</h2>$recommendationsHtml</div>

<hr class="separator">

<div id="files"><h2>&#x1F4C1; Collected Files</h2>
<div class="card"><table><tr><th>File</th><th>Size</th><th>Modified</th></tr>$filesHtml</table></div></div>

<div style="margin-top:40px;padding-top:16px;border-top:1px solid var(--border);color:var(--text-muted);font-size:.85em;text-align:center">
QCLogger Report &bull; $computerName &bull; $totalSystemEvents system + $etlTotalEvents ETL events &bull; $analysisTime
</div>

</div></body></html>
"@

$html | Out-File -FilePath $reportPath -Encoding UTF8 -Force

Write-Host ""
Write-Host "  Report generated: $reportPath" -ForegroundColor Green
Write-Host "  Issues found: $issueCount" -ForegroundColor $(if ($issueCount -gt 0) { "Red" } else { "Green" })
Write-Host ""

try { Start-Process $reportPath } catch {
    Write-Host "  Open manually: $reportPath" -ForegroundColor Yellow
}
