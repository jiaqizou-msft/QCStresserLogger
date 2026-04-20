# ============================================================================
# QCMonitor - Platform-Agnostic Keyboard/Touchpad Anomaly Detector
# Continuously monitors input device health and detects loss/interruption.
# Works on any Windows platform (Intel, AMD, Qualcomm ARM64).
#
# - Only Keyboard and Mouse/Touchpad class devices determine KB/TP status
# - HID devices are tracked but don't affect the KB:OK/TP:OK headline
# - Unknown status is treated as alive (normal for some HID children)
# - Self-recovery after stress-induced failure is logged green (success)
# - Only persistent failures (no recovery within grace period) are red
# ============================================================================
param(
    [int]$PollIntervalSec = 2,
    [string]$LogDir = "C:\QCLogger\monitor",
    [switch]$Beep,
    [int]$RecoveryGraceSec = 10
)

$ErrorActionPreference = 'SilentlyContinue'
$Host.UI.RawUI.WindowTitle = "QCMonitor - Input Device Watchdog"

if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }

$logFile = Join-Path $LogDir "monitor_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$eventsFile = Join-Path $LogDir "anomalies_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"

Set-Content -Path $eventsFile -Value "Timestamp,Event,DeviceClass,DeviceName,InstanceId,Status,ProblemCode,Detail"

# ---- Logging ----
function Log {
    param([string]$Msg, [string]$Level = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $line = "[$ts] [$Level] $Msg"
    $color = switch ($Level) {
        "FAIL"     { "Red" }
        "ALERT"    { "Red" }
        "WARN"     { "Yellow" }
        "OK"       { "Green" }
        "RECOVERY" { "Green" }
        default    { "Gray" }
    }
    Write-Host $line -ForegroundColor $color
    Add-Content -Path $logFile -Value $line
}

function LogAnomaly {
    param([string]$Event, [string]$Class, [string]$Name, [string]$Id, [string]$Status, [string]$Problem, [string]$Detail)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $safeName = $Name -replace ',', ';'
    $safeDetail = $Detail -replace ',', ';'
    Add-Content -Path $eventsFile -Value "$ts,$Event,$Class,$safeName,$Id,$Status,$Problem,$safeDetail"
}

# ---- Device status helpers ----
function Test-DeviceAlive {
    # A device is "alive" if status is OK or Unknown (Unknown = normal for some HID children)
    param($Status)
    return ($Status -eq 'OK' -or $Status -eq 'Unknown' -or $null -eq $Status)
}

function Test-DeviceFailed {
    # A device has genuinely failed if status is Error, Degraded, or it's gone
    param($Status)
    return ($Status -eq 'Error' -or $Status -eq 'Degraded')
}

# ---- Device Snapshot ----
function Get-DeviceSnapshot {
    $snapshot = @{}

    # Keyboards (these determine KB:OK/KB:DEAD)
    foreach ($d in (Get-PnpDevice -Class Keyboard -ErrorAction SilentlyContinue)) {
        $snapshot[$d.InstanceId] = [PSCustomObject]@{
            Class = "Keyboard"; Name = $d.FriendlyName; InstanceId = $d.InstanceId
            Status = $d.Status; Problem = $d.Problem; ConfigFlags = $d.ConfigManagerErrorCode
        }
    }

    # Mouse / Touchpad (these determine TP:OK/TP:DEAD)
    foreach ($d in (Get-PnpDevice -Class Mouse -ErrorAction SilentlyContinue)) {
        $snapshot[$d.InstanceId] = [PSCustomObject]@{
            Class = "Mouse/Touchpad"; Name = $d.FriendlyName; InstanceId = $d.InstanceId
            Status = $d.Status; Problem = $d.Problem; ConfigFlags = $d.ConfigManagerErrorCode
        }
    }

    # HID devices (tracked for awareness, but don't drive KB/TP headline status)
    $hids = Get-PnpDevice -Class HIDClass -ErrorAction SilentlyContinue |
        Where-Object { $_.FriendlyName -match 'keyboard|mouse|touchpad|touch pad|trackpad|pen|Surface.*HID|Surface.*Touch|Surface.*Keyboard' -or
                       $_.InstanceId -match 'VID_04F3|VID_045E.*PID_0855' }
    foreach ($d in $hids) {
        if (-not $snapshot.ContainsKey($d.InstanceId)) {
            $snapshot[$d.InstanceId] = [PSCustomObject]@{
                Class = "HID"; Name = $d.FriendlyName; InstanceId = $d.InstanceId
                Status = $d.Status; Problem = $d.Problem; ConfigFlags = $d.ConfigManagerErrorCode
            }
        }
    }

    return $snapshot
}

# ---- Input idle detection via Win32 API ----
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public struct LASTINPUTINFO {
    public uint cbSize;
    public uint dwTime;
}
public class InputDetector {
    [DllImport("user32.dll")]
    static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);
    public static uint GetIdleMs() {
        LASTINPUTINFO lii = new LASTINPUTINFO();
        lii.cbSize = (uint)Marshal.SizeOf(typeof(LASTINPUTINFO));
        if (GetLastInputInfo(ref lii)) {
            return (uint)Environment.TickCount - lii.dwTime;
        }
        return 0;
    }
}
"@ -ErrorAction SilentlyContinue

function Get-InputIdleMs {
    try { return [InputDetector]::GetIdleMs() } catch { return 0 }
}

# ============================================================================
# Main Monitor Loop
# ============================================================================

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  QCMonitor - Input Device Anomaly Detector" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Poll interval   : ${PollIntervalSec}s" -ForegroundColor White
Write-Host "  Recovery grace   : ${RecoveryGraceSec}s" -ForegroundColor White
Write-Host "  Beep on failure : $Beep" -ForegroundColor White
Write-Host "  Log             : $logFile" -ForegroundColor DarkGray
Write-Host "  Anomalies CSV   : $eventsFile" -ForegroundColor DarkGray
Write-Host ""

# Take initial baseline — only track devices that are alive at start
$prevSnapshot = Get-DeviceSnapshot
$aliveAtStart = @{}
foreach ($d in $prevSnapshot.Values) {
    $aliveAtStart[$d.InstanceId] = (Test-DeviceAlive $d.Status)
}

$kbDevs = ($prevSnapshot.Values | Where-Object { $_.Class -eq 'Keyboard' })
$tpDevs = ($prevSnapshot.Values | Where-Object { $_.Class -eq 'Mouse/Touchpad' })
$kbAliveCount = ($kbDevs | Where-Object { Test-DeviceAlive $_.Status }).Count
$tpAliveCount = ($tpDevs | Where-Object { Test-DeviceAlive $_.Status }).Count
$okCount = ($prevSnapshot.Values | Where-Object { $_.Status -eq 'OK' }).Count

Log "Monitoring: $($kbDevs.Count) keyboard(s), $($tpDevs.Count) touchpad/mice, $($prevSnapshot.Count) total input devices"
Log "Status: $kbAliveCount KB alive, $tpAliveCount TP alive, $okCount total OK"
foreach ($d in $prevSnapshot.Values) {
    $tag = if ($d.Status -eq 'OK') { '[OK]' } elseif ($d.Status -eq 'Unknown') { '[--]' } else { "[!!$($d.Status)]" }
    $color = if ($d.Status -eq 'OK') { "OK" } elseif ($d.Status -eq 'Unknown') { "INFO" } else { "WARN" }
    Log "  $($d.Class): $($d.Name) $tag" $color
}

# State tracking
$failedDevices = @{}      # InstanceId -> [PSCustomObject]@{ FailTime; Class; Name; Alerted }
$selfRecoveries = 0
$persistentFailures = 0
$checkCount = 0
$noInputAlerted = $false
$noInputThresholdMs = 120000

Log ""
Log "Watching for anomalies... Press Ctrl+C to stop."
Log "================================================================"
Write-Host ""

try {
    while ($true) {
        Start-Sleep -Seconds $PollIntervalSec
        $checkCount++

        $currentSnapshot = Get-DeviceSnapshot
        $now = Get-Date -Format "HH:mm:ss"
        $idleMs = Get-InputIdleMs
        $idleSec = [Math]::Round($idleMs / 1000, 0)

        # ---- Check each previously-known device ----
        foreach ($id in @($prevSnapshot.Keys)) {
            $prev = $prevSnapshot[$id]
            $curr = $currentSnapshot[$id]
            $wasAlive = Test-DeviceAlive $prev.Status

            if (-not $curr) {
                # Device disappeared
                if ($wasAlive -and -not $failedDevices.ContainsKey($id)) {
                    $failedDevices[$id] = [PSCustomObject]@{
                        FailTime = Get-Date; Class = $prev.Class; Name = $prev.Name; Alerted = $false
                    }
                    Log "DEVICE DISRUPTED: $($prev.Class) '$($prev.Name)' - disappeared (waiting ${RecoveryGraceSec}s for recovery...)" "WARN"
                    LogAnomaly "DEVICE_DISRUPTED" $prev.Class $prev.Name $id "Gone" "" "Disappeared - grace period"
                }
            } elseif ((Test-DeviceFailed $curr.Status) -and $wasAlive) {
                # Device went from alive to Error/Degraded
                if (-not $failedDevices.ContainsKey($id)) {
                    $failedDevices[$id] = [PSCustomObject]@{
                        FailTime = Get-Date; Class = $curr.Class; Name = $curr.Name; Alerted = $false
                    }
                    Log "DEVICE DISRUPTED: $($curr.Class) '$($curr.Name)' Status=$($curr.Status) Problem=$($curr.Problem) (waiting for recovery...)" "WARN"
                    LogAnomaly "DEVICE_DISRUPTED" $curr.Class $curr.Name $id $curr.Status "$($curr.Problem)" "Failed - grace period"
                }
            } elseif ($curr -and (Test-DeviceAlive $curr.Status) -and $failedDevices.ContainsKey($id)) {
                # Device was in failed state but has recovered!
                $fail = $failedDevices[$id]
                $recoveryMs = [Math]::Round(((Get-Date) - $fail.FailTime).TotalMilliseconds)
                $selfRecoveries++
                Log "SELF-RECOVERED: $($curr.Class) '$($curr.Name)' recovered in ${recoveryMs}ms" "RECOVERY"
                LogAnomaly "SELF_RECOVERED" $curr.Class $curr.Name $id "OK" "" "Recovered in ${recoveryMs}ms"
                $failedDevices.Remove($id)
            }
        }

        # ---- Check grace period expiry — promote to persistent failure ----
        $expiredIds = @()
        foreach ($id in @($failedDevices.Keys)) {
            $fail = $failedDevices[$id]
            if (-not $fail.Alerted) {
                $elapsed = ((Get-Date) - $fail.FailTime).TotalSeconds
                if ($elapsed -ge $RecoveryGraceSec) {
                    # Grace period expired — this is a REAL failure
                    $persistentFailures++
                    $fail.Alerted = $true
                    Log "PERSISTENT FAILURE: $($fail.Class) '$($fail.Name)' did NOT recover after ${RecoveryGraceSec}s!" "FAIL"
                    LogAnomaly "PERSISTENT_FAILURE" $fail.Class $fail.Name $id "Dead" "" "No recovery after ${RecoveryGraceSec}s"
                    if ($Beep) { [Console]::Beep(1000, 500); [Console]::Beep(800, 500) }
                }
            }
        }

        # ---- Detect NEW devices ----
        foreach ($id in $currentSnapshot.Keys) {
            if (-not $prevSnapshot.ContainsKey($id)) {
                $d = $currentSnapshot[$id]
                if ($d.Status -eq 'OK') {
                    Log "NEW DEVICE: $($d.Class) '$($d.Name)' appeared" "OK"
                } else {
                    Log "NEW DEVICE: $($d.Class) '$($d.Name)' appeared (Status=$($d.Status))" "INFO"
                }
                LogAnomaly "DEVICE_ARRIVED" $d.Class $d.Name $id $d.Status "" "Newly enumerated"
            }
        }

        # ---- Input idle heartbeat ----
        if ($idleMs -gt $noInputThresholdMs -and $checkCount -gt 5) {
            if (-not $noInputAlerted) {
                $noInputAlerted = $true
                Log "NO INPUT for ${idleSec}s - KB/TP may be unresponsive (or user away)" "WARN"
                LogAnomaly "INPUT_IDLE" "System" "AllInput" "N/A" "Idle" "" "No input for ${idleSec}s"
            }
        } else {
            $noInputAlerted = $false
        }

        # ---- KB/TP alive = at least one Keyboard/Mouse class device is OK ----
        # Only Keyboard and Mouse/Touchpad classes drive the headline status
        # Unknown status counts as alive (normal for some composite device children)
        $kbAlive = ($currentSnapshot.Values | Where-Object { $_.Class -eq 'Keyboard' -and (Test-DeviceAlive $_.Status) }).Count -gt 0
        $tpAlive = ($currentSnapshot.Values | Where-Object { $_.Class -eq 'Mouse/Touchpad' -and (Test-DeviceAlive $_.Status) }).Count -gt 0

        # ---- Status line ----
        $okNow = ($currentSnapshot.Values | Where-Object { $_.Status -eq 'OK' }).Count
        $kbTag = if ($kbAlive) { "KB:OK" } else { "KB:DEAD" }
        $tpTag = if ($tpAlive) { "TP:OK" } else { "TP:DEAD" }
        $kbColor = if ($kbAlive) { "Green" } else { "Red" }
        $tpColor = if ($tpAlive) { "Green" } else { "Red" }
        $idleColor = if ($idleSec -gt 120) { "Red" } elseif ($idleSec -gt 30) { "Yellow" } else { "DarkGray" }
        $recColor = if ($selfRecoveries -gt 0) { "Green" } else { "DarkGray" }
        $failColor = if ($persistentFailures -gt 0) { "Red" } else { "Green" }

        Write-Host "`r  [$now] " -NoNewline -ForegroundColor DarkGray
        Write-Host "$kbTag " -NoNewline -ForegroundColor $kbColor
        Write-Host "$tpTag " -NoNewline -ForegroundColor $tpColor
        Write-Host "Devs:$okNow/$($currentSnapshot.Count) " -NoNewline -ForegroundColor Gray
        Write-Host "Idle:${idleSec}s " -NoNewline -ForegroundColor $idleColor
        Write-Host "Recovered:$selfRecoveries " -NoNewline -ForegroundColor $recColor
        Write-Host "Failed:$persistentFailures " -NoNewline -ForegroundColor $failColor
        Write-Host "  " -NoNewline

        $prevSnapshot = $currentSnapshot
    }
} finally {
    Write-Host ""
    Log ""
    Log "================================================================"
    Log "Monitor stopped. Checks: $checkCount"
    Log "  Self-recoveries (stress-induced, came back): $selfRecoveries" "OK"
    if ($persistentFailures -gt 0) {
        Log "  PERSISTENT FAILURES (did not recover): $persistentFailures" "FAIL"
    } else {
        Log "  Persistent failures: 0" "OK"
    }

    $final = Get-DeviceSnapshot
    foreach ($d in $final.Values) {
        $tag = if ($d.Status -eq 'OK') { 'OK' } elseif ($d.Status -eq 'Unknown') { '--' } else { "!!$($d.Status)" }
        $lvl = if ($d.Status -eq 'OK') { "OK" } elseif ($d.Status -eq 'Unknown') { "INFO" } else { "FAIL" }
        Log "  $($d.Class): $($d.Name) [$tag]" $lvl
    }

    Log "Log: $logFile"
    Log "Anomalies CSV: $eventsFile"
}
