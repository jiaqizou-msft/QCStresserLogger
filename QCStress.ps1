# ============================================================================
# QCStress - PPTE + USB/HID/Sleep-Wake Stress Tool
# Discovers actual input devices, then stress-tests them via configurable
# scenarios: PPTE flipping, USB suspend cycling, HID device cycling,
# and sleep/wake (modern standby) transitions.
# ============================================================================
param(
    [ValidateSet("ppte", "usb", "hid", "sleep", "all", "scenario", "usbreset", "cascade", "activeuse", "wudf")]
    [string]$Mode = "all",

    [int]$DurationMinutes = 30,

    [ValidateSet("low", "medium", "high", "extreme")]
    [string]$Intensity = "medium",

    [string]$LogDir = "C:\QCLogger\stress",

    # Sleep/wake parameters
    [int]$SleepCycles = 0,
    [int]$SleepDurationSec = 15,
    [int]$WakeHoldSec = 10,

    # Scenario mode: comma-separated list of stressors with cycle counts
    # e.g. "ppte:200,usb:50,hid:10,sleep:5"
    [string]$Scenario = "",

    # Show available scenarios and exit
    [switch]$ListScenarios
)

$ErrorActionPreference = 'Continue'

# ---- Show scenarios and exit ----
if ($ListScenarios) {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  QCStress - Available Stress Scenarios" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  PRESET MODES (-Mode):" -ForegroundColor Yellow
    Write-Host "    all       Default. Runs PPTE + USB + HID cycling combined" -ForegroundColor Gray
    Write-Host "    ppte      PPTE power scheme flipping only" -ForegroundColor Gray
    Write-Host "    usb       USB selective suspend toggling only" -ForegroundColor Gray
    Write-Host "    hid       HID device disable/enable cycling only" -ForegroundColor Gray
    Write-Host "    sleep     Sleep/wake (modern standby) cycling only" -ForegroundColor Gray
    Write-Host "    usbreset  USB composite device restart (ELAN re-enumeration)" -ForegroundColor Gray
    Write-Host "    cascade   TP-first-then-KB cascading disable (mimics real failure)" -ForegroundColor Gray
    Write-Host "    wudf      UMDF/WudfRd driver stack restart for ELAN devices" -ForegroundColor Gray
    Write-Host "    activeuse Combined repro recipe: PPTE+USB+cascade+usbreset" -ForegroundColor Gray
    Write-Host "    scenario  Custom scenario string (see below)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  INTENSITY LEVELS (-Intensity):" -ForegroundColor Yellow
    Write-Host "    low       PPTE=2s    USB=10s   HID=15s" -ForegroundColor Gray
    Write-Host "    medium    PPTE=500ms USB=5s    HID=8s   (default)" -ForegroundColor Gray
    Write-Host "    high      PPTE=100ms USB=2s    HID=4s" -ForegroundColor Gray
    Write-Host "    extreme   PPTE=20ms  USB=500ms HID=2s" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  SLEEP/WAKE PARAMETERS:" -ForegroundColor Yellow
    Write-Host "    -SleepCycles 5         Number of sleep/wake cycles (0=disabled)" -ForegroundColor Gray
    Write-Host "    -SleepDurationSec 15   How long to stay asleep (seconds)" -ForegroundColor Gray
    Write-Host "    -WakeHoldSec 10        How long to stay awake between cycles" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  CUSTOM SCENARIO (-Mode scenario -Scenario `"...`"):" -ForegroundColor Yellow
    Write-Host "    Format: stressor:cycles,stressor:cycles,..." -ForegroundColor Gray
    Write-Host "    Stressors: ppte, usb, hid, sleep" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  EXAMPLE SCENARIOS:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "    # Quick smoke test: 50 PPTE flips + 3 sleep cycles" -ForegroundColor DarkCyan
    Write-Host '    -Mode scenario -Scenario "ppte:50,sleep:3"' -ForegroundColor White
    Write-Host ""
    Write-Host "    # Heavy PPTE + USB stress, no HID cycling" -ForegroundColor DarkCyan
    Write-Host '    -Mode scenario -Scenario "ppte:500,usb:100"' -ForegroundColor White
    Write-Host ""
    Write-Host "    # Full gauntlet: everything at high intensity" -ForegroundColor DarkCyan
    Write-Host '    -Mode scenario -Scenario "ppte:300,usb:60,hid:15,sleep:5" -Intensity high' -ForegroundColor White
    Write-Host ""
    Write-Host "    # Sleep soak: 20 sleep/wake cycles with 30s sleep" -ForegroundColor DarkCyan
    Write-Host '    -Mode sleep -SleepCycles 20 -SleepDurationSec 30 -WakeHoldSec 15' -ForegroundColor White
    Write-Host ""
    Write-Host "    # Default: just run everything for 30 min" -ForegroundColor DarkCyan
    Write-Host '    (no parameters needed)' -ForegroundColor White
    Write-Host ""
    Write-Host "    # Active-use repro: reproduces KB/TP loss during active use" -ForegroundColor DarkCyan
    Write-Host '    -Mode activeuse -Intensity extreme -DurationMinutes 60' -ForegroundColor White
    Write-Host ""
    Write-Host "    # Cascade test: TP dies first then KB, 20 cycles" -ForegroundColor DarkCyan
    Write-Host '    -Mode scenario -Scenario "cascade:20,ppte:200"' -ForegroundColor White
    Write-Host ""
    Write-Host "    # USB composite reset: force ELAN re-enumeration" -ForegroundColor DarkCyan
    Write-Host '    -Mode usbreset -DurationMinutes 30' -ForegroundColor White
    Write-Host ""
    Write-Host "    # UMDF restart: cycle ELAN WudfRd driver stack" -ForegroundColor DarkCyan
    Write-Host '    -Mode wudf -DurationMinutes 30' -ForegroundColor White
    Write-Host ""
    Write-Host "    # Full active-use gauntlet with sleep bursts" -ForegroundColor DarkCyan
    Write-Host '    -Mode scenario -Scenario "ppte:500,usbreset:30,cascade:20,wudf:10,sleep:3" -Intensity extreme' -ForegroundColor White
    Write-Host ""
    Write-Host "  EXAMPLES:" -ForegroundColor Yellow
    Write-Host "    powershell -ExecutionPolicy Bypass -File QCStress.ps1" -ForegroundColor Gray
    Write-Host "    powershell -ExecutionPolicy Bypass -File QCStress.ps1 -Mode ppte -Intensity extreme" -ForegroundColor Gray
    Write-Host "    powershell -ExecutionPolicy Bypass -File QCStress.ps1 -Mode sleep -SleepCycles 10" -ForegroundColor Gray
    Write-Host '    powershell -ExecutionPolicy Bypass -File QCStress.ps1 -Mode scenario -Scenario "ppte:200,sleep:5"' -ForegroundColor Gray
    Write-Host ""
    exit
}

$Host.UI.RawUI.WindowTitle = "QCStress - $Mode ($Intensity)"

# ---- Auto-elevate ----
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Relaunching as administrator..." -ForegroundColor Yellow
    $argStr = "-ExecutionPolicy Bypass -File `"$PSCommandPath`" -Mode $Mode -DurationMinutes $DurationMinutes -Intensity $Intensity -LogDir `"$LogDir`" -SleepCycles $SleepCycles -SleepDurationSec $SleepDurationSec -WakeHoldSec $WakeHoldSec"
    if ($Scenario) { $argStr += " -Scenario `"$Scenario`"" }
    Start-Process powershell.exe -Verb RunAs -ArgumentList $argStr
    exit
}

if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }

$logFile = Join-Path $LogDir "stress_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$csvFile = Join-Path $LogDir "stress_events_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"

# ---- Intensity settings ----
$settings = switch ($Intensity) {
    "low"     { @{ PpteDelayMs = 2000; UsbDelayMs = 10000; HidDelayMs = 15000 } }
    "medium"  { @{ PpteDelayMs = 500;  UsbDelayMs = 5000;  HidDelayMs = 8000  } }
    "high"    { @{ PpteDelayMs = 100;  UsbDelayMs = 2000;  HidDelayMs = 4000  } }
    "extreme" { @{ PpteDelayMs = 20;   UsbDelayMs = 500;   HidDelayMs = 2000  } }
}

# ---- Determine what to run ----
$ppteOn  = $Mode -in @("ppte","all","activeuse")
$usbOn   = $Mode -in @("usb","all","activeuse")
$hidOn   = $Mode -in @("hid","all")
$sleepOn = $Mode -eq "sleep" -or $SleepCycles -gt 0
$usbResetOn = $Mode -in @("usbreset","activeuse")
$cascadeOn  = $Mode -in @("cascade","activeuse")
$wudfOn     = $Mode -in @("wudf","activeuse")

# Parse scenario string
$scenarioCounts = @{ ppte = 0; usb = 0; hid = 0; sleep = 0; usbreset = 0; cascade = 0; wudf = 0 }
if ($Mode -eq "scenario" -and $Scenario) {
    $ppteOn = $false; $usbOn = $false; $hidOn = $false; $sleepOn = $false
    $usbResetOn = $false; $cascadeOn = $false; $wudfOn = $false
    foreach ($part in ($Scenario -split ',')) {
        $kv = $part.Trim() -split ':'
        if ($kv.Count -eq 2) {
            $key = $kv[0].Trim().ToLower()
            $val = [int]$kv[1].Trim()
            if ($scenarioCounts.ContainsKey($key)) {
                $scenarioCounts[$key] = $val
                if ($val -gt 0) {
                    switch ($key) {
                        "ppte"     { $ppteOn = $true }
                        "usb"      { $usbOn = $true }
                        "hid"      { $hidOn = $true }
                        "sleep"    { $sleepOn = $true; $SleepCycles = $val }
                        "usbreset" { $usbResetOn = $true }
                        "cascade"  { $cascadeOn = $true }
                        "wudf"     { $wudfOn = $true }
                    }
                }
            }
        }
    }
}

# ---- Power scheme GUIDs ----
$balanced    = "381b4222-f694-41f0-9685-ff5bb260df2e"
$performance = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
$qcPerf      = "7d9d2b1e-4865-4f82-a9a5-06367835a0aa"

# ---- Logging ----
function Log {
    param([string]$Msg, [string]$Level = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $line = "[$ts] [$Level] $Msg"
    $color = switch ($Level) { "ERROR" { "Red" }; "WARN" { "Yellow" }; "OK" { "Green" }; default { "Gray" } }
    Write-Host $line -ForegroundColor $color
    Add-Content -Path $logFile -Value $line
}
function LogCsv {
    param([string]$Action, [string]$Detail, [string]$Result)
    Add-Content -Path $csvFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'),$Action,$Detail,$Result"
}
Set-Content -Path $csvFile -Value "Timestamp,Action,Detail,Result"

function Get-ActiveScheme {
    $out = powercfg /getactivescheme 2>$null
    if ($out -match '\{(.+?)\}') { return $Matches[1] }
    return ""
}

# ============================================================================
# Device Discovery
# ============================================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  QCStress - Device Discovery" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# ---- Discover all input devices from Device Manager ----
Log "Enumerating input devices from Device Manager..."

$allKeyboards = Get-PnpDevice -Class Keyboard -ErrorAction SilentlyContinue
$allMice = Get-PnpDevice -Class Mouse -ErrorAction SilentlyContinue
$allHid = Get-PnpDevice -Class HIDClass -ErrorAction SilentlyContinue

# Identify the actual keyboard and touchpad devices
$script:kbDevices = @()
$script:tpDevices = @()
$script:hidCycleTargets = @()
$script:hidSkipList = @{}
$script:hidRecoveries = 0
$script:hidFailures = 0

Log ""
Log "=== KEYBOARDS ===" "INFO"
foreach ($d in $allKeyboards) {
    $tag = if ($d.Status -eq 'OK') { '[OK]' } else { "[$($d.Status)]" }
    $lvl = if ($d.Status -eq 'OK') { 'OK' } else { 'WARN' }
    Log "  $tag $($d.FriendlyName)  InstanceId=$($d.InstanceId)" $lvl
    if ($d.Status -eq 'OK') { $script:kbDevices += $d }
}

Log ""
Log "=== TOUCHPAD / MOUSE ===" "INFO"
foreach ($d in $allMice) {
    $tag = if ($d.Status -eq 'OK') { '[OK]' } else { "[$($d.Status)]" }
    $lvl = if ($d.Status -eq 'OK') { 'OK' } else { 'WARN' }
    Log "  $tag $($d.FriendlyName)  InstanceId=$($d.InstanceId)" $lvl
    if ($d.Status -eq 'OK') { $script:tpDevices += $d }
}

Log ""
Log "=== HID DEVICES (input-related) ===" "INFO"
$inputHids = $allHid | Where-Object {
    $_.FriendlyName -match 'keyboard|touchpad|touch pad|trackpad|mouse|Surface.*HID|Surface.*Touch|Surface.*Keyboard|I2C HID' -or
    $_.InstanceId -match 'VID_04F3|VID_045E'
}
foreach ($d in $inputHids) {
    $tag = if ($d.Status -eq 'OK') { '[OK]' } else { "[$($d.Status)]" }
    $lvl = if ($d.Status -eq 'OK') { 'OK' } else { 'WARN' }
    $cycleable = ""
    # Identify top-level devices that can be cycled (not child collections)
    if ($d.Status -eq 'OK' -and $d.InstanceId -notmatch 'COL\d+' -and $d.InstanceId -notmatch '&MI_0[2-9]') {
        $script:hidCycleTargets += $d
        $cycleable = " [CYCLE-TARGET]"
    }
    Log "  $tag $($d.FriendlyName)$cycleable  InstanceId=$($d.InstanceId)" $lvl
}

# Also find USB controllers hosting input devices
Log ""
Log "=== USB CONTROLLERS ===" "INFO"
$usbControllers = Get-PnpDevice -Class USB -Status OK -ErrorAction SilentlyContinue |
    Where-Object { $_.FriendlyName -match 'Hub|Host Controller|xHCI|EHCI' }
foreach ($d in $usbControllers) {
    Log "  [OK] $($d.FriendlyName)  InstanceId=$($d.InstanceId)" "OK"
}

# Discover ELAN USB composite parent devices (for usbreset/cascade/wudf modes)
$script:elanUsbParents = @()
$script:elanTpDevices = @()
$script:elanKbDevices = @()
Log ""
Log "=== ELAN USB COMPOSITE PARENTS ===" "INFO"
$allUsb = Get-PnpDevice -Class USB -ErrorAction SilentlyContinue |
    Where-Object { $_.InstanceId -match 'VID_04F3' -and $_.InstanceId -notmatch 'MI_' -and $_.Status -eq 'OK' }
foreach ($d in $allUsb) {
    $script:elanUsbParents += $d
    $tag = "USB-PARENT"
    if ($d.InstanceId -match 'PID_0C9E') { $tag = "USB-PARENT(TP/HID)"; $script:elanTpDevices += $d }
    if ($d.InstanceId -match 'PID_337A') { $tag = "USB-PARENT(KB)"; $script:elanKbDevices += $d }
    Log "  [OK] [$tag] $($d.FriendlyName)  InstanceId=$($d.InstanceId)" "OK"
}
if ($script:elanUsbParents.Count -eq 0) {
    # Fallback: look for any ELAN USB device including MI_ interfaces
    $allElanUsb = Get-PnpDevice -Class USB -ErrorAction SilentlyContinue |
        Where-Object { $_.InstanceId -match 'VID_04F3' -and $_.Status -eq 'OK' }
    foreach ($d in $allElanUsb) {
        $script:elanUsbParents += $d
        Log "  [OK] [FALLBACK] $($d.FriendlyName)  InstanceId=$($d.InstanceId)" "WARN"
    }
}
# Also identify ELAN HID child devices for cascade mode
$script:elanTpHid = @()
$script:elanKbHid = @()
$allHidDevs = Get-PnpDevice -Class HIDClass -ErrorAction SilentlyContinue
foreach ($d in ($allHidDevs | Where-Object { $_.InstanceId -match 'VID_04F3&PID_0C9E' -and $_.Status -eq 'OK' })) {
    $script:elanTpHid += $d
}
foreach ($d in ($allHidDevs | Where-Object { $_.InstanceId -match 'VID_04F3&PID_337A' -and $_.Status -eq 'OK' })) {
    $script:elanKbHid += $d
}
# Also grab the Keyboard/Mouse class devices that map to ELAN
foreach ($d in ($allKeyboards | Where-Object { $_.InstanceId -match 'VID_04F3&PID_337A' })) {
    if ($d -notin $script:elanKbHid) { $script:elanKbHid += $d }
}
foreach ($d in ($allMice | Where-Object { $_.InstanceId -match 'VID_04F3' })) {
    if ($d -notin $script:elanTpHid) { $script:elanTpHid += $d }
}
Log "  ELAN parents: $($script:elanUsbParents.Count)  TP-HID: $($script:elanTpHid.Count)  KB-HID: $($script:elanKbHid.Count)"

# Sleep model
Log ""
Log "=== POWER / SLEEP ===" "INFO"
$sleepModel = powercfg /availablesleepstates 2>$null
$hasModernStandby = $sleepModel -match 'Standby.*S0|Modern Standby|Connected Standby'
$sleepModelStr = if ($hasModernStandby) { "Modern Standby (S0)" } else { "Traditional (S3)" }
Log "  Sleep model: $sleepModelStr"
Log "  Active scheme: $(Get-ActiveScheme)"
$availSchemes = powercfg /list 2>$null
$hasQcPerf = $availSchemes -match $qcPerf
Log "  QC Performance scheme: $(if ($hasQcPerf) { 'Present' } else { 'Not found (will use standard)' })"

Log ""
Log "Summary: $($script:kbDevices.Count) keyboard(s), $($script:tpDevices.Count) touchpad/mice, $($script:hidCycleTargets.Count) HID cycle targets"

# ============================================================================
# Stress Functions
# ============================================================================

function Stress-PPTE {
    param([int]$DelayMs)
    $current = Get-ActiveScheme
    $target = if ($current -eq $balanced) { $qcPerf } else { $balanced }
    $name   = if ($target -eq $balanced) { "Balanced" } else { "QCPerf" }
    $available = powercfg /list 2>$null
    if ($target -eq $qcPerf -and $available -notmatch $qcPerf) {
        $target = $performance; $name = "HighPerf"
        if ($available -notmatch $performance) {
            powercfg /duplicatescheme $balanced $performance 2>$null | Out-Null
        }
    }
    powercfg /setactive $target 2>$null
    $verify = Get-ActiveScheme
    LogCsv "PPTE_FLIP" "to=$name" $(if ($verify -eq $target) { "OK" } else { "FAIL" })
    Start-Sleep -Milliseconds $DelayMs
}

function Stress-USB {
    param([int]$DelayMs)
    $subgroup = "2a737441-1930-4402-8d77-b2bebba308a3"
    $setting  = "48e6b7a6-50f5-4782-a5d4-53bb8f07e226"
    $q = powercfg /query SCHEME_CURRENT $subgroup $setting 2>$null
    $enabled = $q -match 'Setting Index:\s*0x0+1'
    $newVal = if ($enabled) { 0 } else { 1 }
    $action = if ($enabled) { "DISABLE" } else { "ENABLE" }
    powercfg /setacvalueindex SCHEME_CURRENT $subgroup $setting $newVal 2>$null
    powercfg /setdcvalueindex SCHEME_CURRENT $subgroup $setting $newVal 2>$null
    powercfg /setactive SCHEME_CURRENT 2>$null
    LogCsv "USB_SUSPEND" $action "OK"
    Start-Sleep -Milliseconds $DelayMs
}

function Stress-HID {
    param([int]$DelayMs)
    $devs = $script:hidCycleTargets | Where-Object {
        -not $script:hidSkipList.ContainsKey($_.InstanceId) -and
        (Get-PnpDevice -InstanceId $_.InstanceId -ErrorAction SilentlyContinue).Status -eq 'OK'
    }
    if (-not $devs) { return }

    foreach ($d in $devs) {
        $id = $d.InstanceId
        $short = $id.Substring(0, [Math]::Min($id.Length, 60))
        $name = $d.FriendlyName
        try {
            Disable-PnpDevice -InstanceId $id -Confirm:$false -ErrorAction Stop
            LogCsv "HID_CYCLE" "DISABLE:$short" "OK"
            Start-Sleep -Milliseconds ([Math]::Max(200, $DelayMs / 4))
            Enable-PnpDevice -InstanceId $id -Confirm:$false -ErrorAction Stop
            LogCsv "HID_CYCLE" "ENABLE:$short" "OK"

            Start-Sleep -Milliseconds 1000
            $chk = Get-PnpDevice -InstanceId $id -ErrorAction SilentlyContinue
            if ($chk -and $chk.Status -eq 'OK') {
                $script:hidRecoveries++
                Log "HID '$name' cycled and self-recovered" "OK"
                LogCsv "HID_CYCLE" "VERIFY:$short" "SELF_RECOVERED"
            } else {
                Start-Sleep -Milliseconds 2000
                $chk2 = Get-PnpDevice -InstanceId $id -ErrorAction SilentlyContinue
                if ($chk2 -and $chk2.Status -eq 'OK') {
                    $script:hidRecoveries++
                    Log "HID '$name' slow self-recovery (3s)" "OK"
                    LogCsv "HID_CYCLE" "VERIFY:$short" "SLOW_RECOVERED"
                } else {
                    $script:hidFailures++
                    $st = if ($chk2) { $chk2.Status } else { "Gone" }
                    Log "HID '$name' FAILED TO RECOVER! Status=$st" "ERROR"
                    LogCsv "HID_CYCLE" "VERIFY:$short" "FAIL:$st"
                    Enable-PnpDevice -InstanceId $id -Confirm:$false -ErrorAction SilentlyContinue
                }
            }
        } catch {
            $errMsg = $_.Exception.Message
            if ($errMsg -match 'Not supported|not support|Generic failure') {
                $script:hidSkipList[$id] = $true
                Log "HID '$name' doesn't support disable/enable - skipping" "WARN"
                LogCsv "HID_CYCLE" "SKIP:$short" "NOT_SUPPORTED"
            } else {
                Log "HID cycle error '$name': $errMsg" "ERROR"
                LogCsv "HID_CYCLE" "$short" "EXCEPTION"
            }
            Enable-PnpDevice -InstanceId $id -Confirm:$false -ErrorAction SilentlyContinue
        }
    }
    Start-Sleep -Milliseconds $DelayMs
}

function Stress-SleepWake {
    param([int]$SleepSec, [int]$HoldSec, [int]$CycleNum)
    Log "SLEEP/WAKE cycle $CycleNum - sleeping ${SleepSec}s..."
    LogCsv "SLEEP_WAKE" "CYCLE:$CycleNum SLEEP:${SleepSec}s" "ENTERING"

    # Schedule a wake timer, then enter sleep
    # Use powercfg to set a wake timer
    $wakeTime = (Get-Date).AddSeconds($SleepSec + 2)
    $wakeTimeStr = $wakeTime.ToString("HH:mm:ss")

    # Create a scheduled task to wake the machine
    $taskName = "QCStress_WakeTimer_$CycleNum"
    $triggerTime = $wakeTime.ToString("yyyy-MM-ddTHH:mm:ss")
    schtasks /create /tn $taskName /tr "cmd /c echo wake" /sc once /st $wakeTimeStr /f /rl highest 2>$null | Out-Null
    # Set the task to wake the computer
    $xml = schtasks /query /tn $taskName /xml 2>$null
    if ($xml) {
        $xmlDoc = [xml]($xml -join "`n")
        $settingsNode = $xmlDoc.Task.Settings
        if ($settingsNode) {
            $wakeNode = $xmlDoc.CreateElement("WakeToRun", $xmlDoc.Task.NamespaceURI)
            $wakeNode.InnerText = "true"
            $settingsNode.AppendChild($wakeNode) | Out-Null
            $tempXml = Join-Path $env:TEMP "QCStress_wake_$CycleNum.xml"
            $xmlDoc.Save($tempXml)
            schtasks /create /tn $taskName /xml $tempXml /f 2>$null | Out-Null
            Remove-Item $tempXml -Force -ErrorAction SilentlyContinue
        }
    }

    # Enter sleep via powercfg or rundll32
    Start-Sleep -Milliseconds 500
    rundll32.exe powrprof.dll,SetSuspendState 0,1,0 2>$null

    # We'll resume here after wake
    $wakeActualTime = Get-Date
    Log "SLEEP/WAKE cycle $CycleNum - woke up at $($wakeActualTime.ToString('HH:mm:ss'))" "OK"
    LogCsv "SLEEP_WAKE" "CYCLE:$CycleNum" "WOKE"

    # Cleanup task
    schtasks /delete /tn $taskName /f 2>$null | Out-Null

    # Verify input devices are OK after wake
    Start-Sleep -Milliseconds 2000
    $kbOk = (Get-PnpDevice -Class Keyboard -Status OK -ErrorAction SilentlyContinue).Count -gt 0
    $tpOk = (Get-PnpDevice -Class Mouse -Status OK -ErrorAction SilentlyContinue).Count -gt 0

    if ($kbOk -and $tpOk) {
        Log "SLEEP/WAKE cycle $CycleNum - KB:OK TP:OK after wake" "OK"
        LogCsv "SLEEP_WAKE" "CYCLE:$CycleNum" "VERIFY_OK"
    } else {
        $kbTag = if ($kbOk) { "OK" } else { "DEAD" }
        $tpTag = if ($tpOk) { "OK" } else { "DEAD" }
        Log "SLEEP/WAKE cycle $CycleNum - KB:$kbTag TP:$tpTag AFTER WAKE!" "ERROR"
        LogCsv "SLEEP_WAKE" "CYCLE:$CycleNum KB=$kbTag TP=$tpTag" "FAIL"
    }

    Log "Holding awake for ${HoldSec}s before next cycle..."
    Start-Sleep -Seconds $HoldSec
}

# ============================================================================
# New Stress Functions (reverse-engineered from active-use KB/TP loss incident)
# ============================================================================

function Stress-USBReset {
    # Restarts ELAN USB composite parent devices, forcing full HidUsb/WudfRd
    # re-enumeration. This stresses the exact code path that takes 5-10s in the
    # DriverWatchdog logs (USB\VID_04F3&PID_0C9E&MI_01 HidUsb device start).
    param([int]$DelayMs)
    $targets = $script:elanUsbParents
    if (-not $targets -or $targets.Count -eq 0) {
        Log "USB RESET: No ELAN USB parent devices found - skipping" "WARN"
        LogCsv "USB_RESET" "NO_TARGETS" "SKIP"
        return
    }
    foreach ($d in $targets) {
        $id = $d.InstanceId
        $short = $id.Substring(0, [Math]::Min($id.Length, 60))
        Log "USB RESET: Restarting $($d.FriendlyName) ($short)" "WARN"

        # Try pnputil /restart-device (available Win10 1903+)
        $result = & pnputil /restart-device "$id" 2>&1
        if ($LASTEXITCODE -eq 0) {
            LogCsv "USB_RESET" "RESTART:$short" "OK"
        } else {
            # Fallback: disable then re-enable the composite parent
            Disable-PnpDevice -InstanceId $id -Confirm:$false -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 500
            Enable-PnpDevice -InstanceId $id -Confirm:$false -ErrorAction SilentlyContinue
            LogCsv "USB_RESET" "CYCLE:$short" "FALLBACK"
        }
    }

    # Wait for re-enumeration (mirrors the 5-10s DriverWatchdog times)
    Start-Sleep -Milliseconds ([Math]::Max(3000, $DelayMs))

    # Verify
    $kbOk = (Get-PnpDevice -Class Keyboard -Status OK -ErrorAction SilentlyContinue).Count -gt 0
    $tpOk = (Get-PnpDevice -Class Mouse -Status OK -ErrorAction SilentlyContinue).Count -gt 0
    $kbTag = if ($kbOk) { "OK" } else { "DEAD" }
    $tpTag = if ($tpOk) { "OK" } else { "DEAD" }
    if ($kbOk -and $tpOk) {
        LogCsv "USB_RESET" "VERIFY" "KB:OK TP:OK"
    } else {
        Log "USB RESET: POST-RESET FAILURE! KB:$kbTag TP:$tpTag" "ERROR"
        LogCsv "USB_RESET" "VERIFY" "KB:$kbTag TP:$tpTag"
    }
}

function Stress-Cascade {
    # Simulates the exact failure pattern from the incident:
    # 1. Touchpad/HID dies first (CM_PROB_DISABLED)
    # 2. 2-5 seconds later, keyboard dies
    # 3. Both re-enumerate and recover (or fail to recover)
    # This mimics the ELAN USB HID stack instability where TP cursor
    # disappears first, then keyboard follows seconds later.
    param([int]$DelayMs, [int]$CycleNum = 0)

    Log "CASCADE cycle $CycleNum - TP-first-then-KB pattern" "WARN"
    LogCsv "CASCADE" "CYCLE:$CycleNum" "STARTING"

    # Phase 1: Disrupt touchpad path
    $tpTargets = $script:elanTpHid
    if (-not $tpTargets -or $tpTargets.Count -eq 0) {
        # Fallback: use ELAN USB TP parent
        $tpTargets = $script:elanTpDevices
    }
    if (-not $tpTargets -or $tpTargets.Count -eq 0) {
        Log "CASCADE: No ELAN TP targets found - trying generic Mouse class" "WARN"
        $tpTargets = Get-PnpDevice -Class Mouse -Status OK -ErrorAction SilentlyContinue |
            Where-Object { $_.InstanceId -match 'HID' } | Select-Object -First 2
    }

    $tpDisabled = @()
    foreach ($d in $tpTargets) {
        try {
            Disable-PnpDevice -InstanceId $d.InstanceId -Confirm:$false -ErrorAction Stop
            $tpDisabled += $d
            Log "CASCADE: TP disabled - $($d.FriendlyName)" "WARN"
            LogCsv "CASCADE" "TP_DISABLE:$($d.InstanceId.Substring(0, [Math]::Min($d.InstanceId.Length,50)))" "OK"
        } catch {
            Log "CASCADE: TP disable failed - $($d.FriendlyName): $($_.Exception.Message)" "ERROR"
        }
    }

    # Stagger delay: 2-5 seconds (mimics the real gap between TP and KB loss)
    $stagger = Get-Random -Minimum 2000 -Maximum 5000
    Log "CASCADE: Staggering ${stagger}ms before KB disable..." "INFO"
    Start-Sleep -Milliseconds $stagger

    # Phase 2: Disrupt keyboard path
    $kbTargets = $script:elanKbHid
    if (-not $kbTargets -or $kbTargets.Count -eq 0) {
        $kbTargets = Get-PnpDevice -Class Keyboard -Status OK -ErrorAction SilentlyContinue |
            Where-Object { $_.InstanceId -match 'HID' } | Select-Object -First 2
    }

    $kbDisabled = @()
    foreach ($d in $kbTargets) {
        try {
            Disable-PnpDevice -InstanceId $d.InstanceId -Confirm:$false -ErrorAction Stop
            $kbDisabled += $d
            Log "CASCADE: KB disabled - $($d.FriendlyName)" "WARN"
            LogCsv "CASCADE" "KB_DISABLE:$($d.InstanceId.Substring(0, [Math]::Min($d.InstanceId.Length,50)))" "OK"
        } catch {
            Log "CASCADE: KB disable failed - $($d.FriendlyName): $($_.Exception.Message)" "ERROR"
        }
    }

    # Hold both down for 3-8 seconds (mimics the 3-13s disruption window)
    $holdDown = Get-Random -Minimum 3000 -Maximum 8000
    Log "CASCADE: Both TP+KB disabled. Holding ${holdDown}ms..." "ERROR"
    Start-Sleep -Milliseconds $holdDown

    # Phase 3: Re-enable everything
    foreach ($d in $tpDisabled) {
        Enable-PnpDevice -InstanceId $d.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
    }
    foreach ($d in $kbDisabled) {
        Enable-PnpDevice -InstanceId $d.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
    }
    LogCsv "CASCADE" "CYCLE:$CycleNum" "RE_ENABLED"

    # Phase 4: Verify recovery (check repeatedly over 15s)
    $recoveryStart = Get-Date
    $recovered = $false
    for ($w = 0; $w -lt 15; $w++) {
        Start-Sleep -Milliseconds 1000
        $kbOk = (Get-PnpDevice -Class Keyboard -Status OK -ErrorAction SilentlyContinue).Count -gt 0
        $tpOk = (Get-PnpDevice -Class Mouse -Status OK -ErrorAction SilentlyContinue).Count -gt 0
        if ($kbOk -and $tpOk) {
            $elapsed = [Math]::Round(((Get-Date) - $recoveryStart).TotalMilliseconds)
            Log "CASCADE cycle $CycleNum - RECOVERED in ${elapsed}ms" "OK"
            LogCsv "CASCADE" "CYCLE:$CycleNum RECOVERED:${elapsed}ms" "SELF_RECOVERED"
            $script:hidRecoveries++
            $recovered = $true
            break
        }
    }
    if (-not $recovered) {
        $kbTag = if ((Get-PnpDevice -Class Keyboard -Status OK -ErrorAction SilentlyContinue).Count -gt 0) { "OK" } else { "DEAD" }
        $tpTag = if ((Get-PnpDevice -Class Mouse -Status OK -ErrorAction SilentlyContinue).Count -gt 0) { "OK" } else { "DEAD" }
        Log "CASCADE cycle $CycleNum - FAILED TO RECOVER! KB:$kbTag TP:$tpTag" "ERROR"
        LogCsv "CASCADE" "CYCLE:$CycleNum KB=$kbTag TP=$tpTag" "PERSISTENT_FAILURE"
        $script:hidFailures++
        # Force re-enable again
        foreach ($d in ($tpDisabled + $kbDisabled)) {
            Enable-PnpDevice -InstanceId $d.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
        }
    }

    Start-Sleep -Milliseconds ([Math]::Max(2000, $DelayMs))
}

function Stress-WUDF {
    # Restarts the UMDF (WudfRd) driver stack for ELAN devices.
    # The incident logs show elanwbfusbdriver.dll crashing in WudfHost
    # with access violation (c0000005). This forces the same teardown/restart
    # path that happens during a real UMDF crash, stressing WudfRd recovery.
    param([int]$DelayMs)

    # Find ELAN devices serviced by WUDFRd
    $wudfDevices = @()
    $allDev = Get-PnpDevice -ErrorAction SilentlyContinue |
        Where-Object { $_.InstanceId -match 'VID_04F3' -and $_.Status -eq 'OK' }
    foreach ($d in $allDev) {
        # Check if device uses WUDFRd driver
        $drvInfo = Get-PnpDeviceProperty -InstanceId $d.InstanceId -KeyName 'DEVPKEY_Device_Service' -ErrorAction SilentlyContinue
        if ($drvInfo -and $drvInfo.Data -match 'WUDFRd') {
            $wudfDevices += $d
        }
    }

    if ($wudfDevices.Count -eq 0) {
        # Fallback: try the known ELAN USB composite parents
        $wudfDevices = $script:elanUsbParents
    }

    if ($wudfDevices.Count -eq 0) {
        Log "WUDF: No ELAN WUDFRd devices found - skipping" "WARN"
        LogCsv "WUDF_RESTART" "NO_TARGETS" "SKIP"
        return
    }

    foreach ($d in $wudfDevices) {
        $id = $d.InstanceId
        $short = $id.Substring(0, [Math]::Min($id.Length, 60))
        Log "WUDF: Restarting driver stack for $($d.FriendlyName) ($short)" "WARN"

        # Use pnputil to restart the device (triggers WudfRd teardown+restart)
        $result = & pnputil /restart-device "$id" 2>&1
        if ($LASTEXITCODE -eq 0) {
            LogCsv "WUDF_RESTART" "RESTART:$short" "OK"
        } else {
            # Fallback: disable/enable cycle
            Disable-PnpDevice -InstanceId $id -Confirm:$false -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 1000
            Enable-PnpDevice -InstanceId $id -Confirm:$false -ErrorAction SilentlyContinue
            LogCsv "WUDF_RESTART" "CYCLE:$short" "FALLBACK"
        }
    }

    # Wait for WudfHost process restart and device re-initialization
    Start-Sleep -Milliseconds ([Math]::Max(5000, $DelayMs))

    # Verify
    $kbOk = (Get-PnpDevice -Class Keyboard -Status OK -ErrorAction SilentlyContinue).Count -gt 0
    $tpOk = (Get-PnpDevice -Class Mouse -Status OK -ErrorAction SilentlyContinue).Count -gt 0
    $kbTag = if ($kbOk) { "OK" } else { "DEAD" }
    $tpTag = if ($tpOk) { "OK" } else { "DEAD" }
    if ($kbOk -and $tpOk) {
        Log "WUDF: Devices recovered after restart" "OK"
        LogCsv "WUDF_RESTART" "VERIFY" "KB:OK TP:OK"
    } else {
        Log "WUDF: POST-RESTART FAILURE! KB:$kbTag TP:$tpTag" "ERROR"
        LogCsv "WUDF_RESTART" "VERIFY" "KB:$kbTag TP:$tpTag"
    }
}

# ============================================================================
# Main
# ============================================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  QCStress - Starting Stress Test" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$activeStressors = @()
if ($ppteOn) { $activeStressors += "PPTE" }
if ($usbOn)  { $activeStressors += "USB" }
if ($hidOn)  { $activeStressors += "HID" }
if ($sleepOn) { $activeStressors += "Sleep($SleepCycles cycles)" }
if ($usbResetOn) { $activeStressors += "USB-Reset" }
if ($cascadeOn)  { $activeStressors += "Cascade(TP->KB)" }
if ($wudfOn)     { $activeStressors += "WUDF-Restart" }

Write-Host "  Active: $($activeStressors -join ' + ')" -ForegroundColor White
Write-Host "  Intensity=$Intensity  Duration=${DurationMinutes}min" -ForegroundColor White
if ($Mode -eq "scenario") { Write-Host "  Scenario: $Scenario" -ForegroundColor White }
Write-Host "  Log: $logFile" -ForegroundColor DarkGray
Write-Host ""

Log "Active stressors: $($activeStressors -join ', ')"
if ($Mode -eq "scenario") { Log "Scenario: $Scenario" }
Log "Starting stress... Ctrl+C to stop."
Log "================================================================"

$startTime = Get-Date
$endTime = $startTime.AddMinutes($DurationMinutes)
$iter = 0; $pFlips = 0; $uToggles = 0; $hCycles = 0; $sCycles = 0
$urCycles = 0; $cCycles = 0; $wCycles = 0
$origScheme = Get-ActiveScheme

# ---- Scenario mode: run specific counts ----
if ($Mode -eq "scenario" -and $Scenario) {
    try {
        # Run each stressor for its specified count
        if ($scenarioCounts.ppte -gt 0) {
            Log "Running $($scenarioCounts.ppte) PPTE flips..."
            for ($i = 0; $i -lt $scenarioCounts.ppte; $i++) {
                Stress-PPTE -DelayMs $settings.PpteDelayMs
                $pFlips++
                if ($i % 50 -eq 0) { Write-Host "`r  PPTE: $($i+1)/$($scenarioCounts.ppte)  " -NoNewline -ForegroundColor DarkGray }
            }
            Write-Host ""
        }
        if ($scenarioCounts.usb -gt 0) {
            Log "Running $($scenarioCounts.usb) USB suspend toggles..."
            for ($i = 0; $i -lt $scenarioCounts.usb; $i++) {
                Stress-USB -DelayMs $settings.UsbDelayMs
                $uToggles++
                if ($i % 10 -eq 0) { Write-Host "`r  USB: $($i+1)/$($scenarioCounts.usb)  " -NoNewline -ForegroundColor DarkGray }
            }
            Write-Host ""
        }
        if ($scenarioCounts.hid -gt 0) {
            Log "Running $($scenarioCounts.hid) HID device cycles..."
            for ($i = 0; $i -lt $scenarioCounts.hid; $i++) {
                Stress-HID -DelayMs $settings.HidDelayMs
                $hCycles++
                Write-Host "`r  HID: $($i+1)/$($scenarioCounts.hid)  " -NoNewline -ForegroundColor DarkGray
            }
            Write-Host ""
        }
        if ($scenarioCounts.sleep -gt 0) {
            Log "Running $($scenarioCounts.sleep) sleep/wake cycles (${SleepDurationSec}s sleep, ${WakeHoldSec}s wake)..."
            for ($i = 0; $i -lt $scenarioCounts.sleep; $i++) {
                Stress-SleepWake -SleepSec $SleepDurationSec -HoldSec $WakeHoldSec -CycleNum ($i + 1)
                $sCycles++
            }
        }
        if ($scenarioCounts.usbreset -gt 0) {
            Log "Running $($scenarioCounts.usbreset) USB composite reset cycles..."
            for ($i = 0; $i -lt $scenarioCounts.usbreset; $i++) {
                Stress-USBReset -DelayMs $settings.HidDelayMs
                $urCycles++
                Write-Host "`r  USB-Reset: $($i+1)/$($scenarioCounts.usbreset)  " -NoNewline -ForegroundColor DarkGray
            }
            Write-Host ""
        }
        if ($scenarioCounts.cascade -gt 0) {
            Log "Running $($scenarioCounts.cascade) cascade (TP->KB) cycles..."
            for ($i = 0; $i -lt $scenarioCounts.cascade; $i++) {
                Stress-Cascade -DelayMs $settings.HidDelayMs -CycleNum ($i + 1)
                $cCycles++
                Write-Host "`r  Cascade: $($i+1)/$($scenarioCounts.cascade)  " -NoNewline -ForegroundColor DarkGray
            }
            Write-Host ""
        }
        if ($scenarioCounts.wudf -gt 0) {
            Log "Running $($scenarioCounts.wudf) WUDF driver restart cycles..."
            for ($i = 0; $i -lt $scenarioCounts.wudf; $i++) {
                Stress-WUDF -DelayMs $settings.HidDelayMs
                $wCycles++
                Write-Host "`r  WUDF: $($i+1)/$($scenarioCounts.wudf)  " -NoNewline -ForegroundColor DarkGray
            }
            Write-Host ""
        }
    } finally {
        # Cleanup handled below in shared finally block
    }
} else {
    # ---- Duration-based mode ----
    try {
        # Run sleep cycles first if requested (before entering the main loop)
        if ($sleepOn -and $SleepCycles -gt 0 -and $Mode -ne "all") {
            Log "Running $SleepCycles sleep/wake cycles..."
            for ($i = 0; $i -lt $SleepCycles; $i++) {
                if ((Get-Date) -ge $endTime) { break }
                Stress-SleepWake -SleepSec $SleepDurationSec -HoldSec $WakeHoldSec -CycleNum ($i + 1)
                $sCycles++
            }
        }

        while ((Get-Date) -lt $endTime) {
            $iter++
            $e = [Math]::Round(((Get-Date) - $startTime).TotalMinutes, 1)
            Write-Host "`r  [${e}m/${DurationMinutes}m] iter=$iter ppte=$pFlips usb=$uToggles hid=$hCycles sleep=$sCycles ur=$urCycles casc=$cCycles wudf=$wCycles  " -NoNewline -ForegroundColor DarkGray

            if ($ppteOn) { Stress-PPTE -DelayMs $settings.PpteDelayMs; $pFlips++ }
            if ($usbOn -and ($iter % 5 -eq 0)) { Stress-USB -DelayMs $settings.UsbDelayMs; $uToggles++ }
            if ($hidOn -and ($iter % 20 -eq 0)) { Stress-HID -DelayMs $settings.HidDelayMs; $hCycles++ }
            if ($usbResetOn -and ($iter % 15 -eq 0)) { Stress-USBReset -DelayMs $settings.HidDelayMs; $urCycles++ }
            if ($cascadeOn -and ($iter % 25 -eq 0)) { Stress-Cascade -DelayMs $settings.HidDelayMs -CycleNum $cCycles; $cCycles++ }
            if ($wudfOn -and ($iter % 30 -eq 0)) { Stress-WUDF -DelayMs $settings.HidDelayMs; $wCycles++ }

            # Interleave sleep cycles in "all" mode
            if ($sleepOn -and $Mode -eq "all" -and $SleepCycles -gt 0 -and $sCycles -lt $SleepCycles -and ($iter % 100 -eq 0)) {
                $sCycles++
                Stress-SleepWake -SleepSec $SleepDurationSec -HoldSec $WakeHoldSec -CycleNum $sCycles
            }
        }
    } finally {
        # Cleanup handled below
    }
}

# ============================================================================
# Cleanup
# ============================================================================
Write-Host ""
Log "================================================================"
Log "Done. ppte=$pFlips usb=$uToggles hid=$hCycles sleep=$sCycles usbreset=$urCycles cascade=$cCycles wudf=$wCycles iters=$iter"
Log "  HID self-recoveries: $($script:hidRecoveries)" "OK"
if ($script:hidFailures -gt 0) {
    Log "  HID PERSISTENT FAILURES: $($script:hidFailures)" "ERROR"
} else {
    Log "  HID persistent failures: 0" "OK"
}
if ($script:hidSkipList.Count -gt 0) {
    Log "  HID devices skipped (not supported): $($script:hidSkipList.Count)" "WARN"
}

# Restore original power scheme
if ($origScheme) { powercfg /setactive $origScheme 2>$null; Log "Restored scheme $origScheme" "OK" }

# Restore USB selective suspend
powercfg /setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 1 2>$null
powercfg /setdcvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 1 2>$null
powercfg /setactive SCHEME_CURRENT 2>$null
Log "Restored USB selective suspend" "OK"

# Re-enable any downed input devices
$downDevs = @()
$downDevs += Get-PnpDevice -Class Keyboard -ErrorAction SilentlyContinue | Where-Object { $_.Status -ne 'OK' -and $_.Status -ne 'Unknown' }
$downDevs += Get-PnpDevice -Class Mouse -ErrorAction SilentlyContinue | Where-Object { $_.Status -ne 'OK' -and $_.Status -ne 'Unknown' }
$downDevs += Get-PnpDevice -Class HIDClass -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Error' -and $_.InstanceId -match 'VID_04F3|VID_045E' }
foreach ($d in $downDevs) {
    Log "Re-enabling $($d.FriendlyName)..." "WARN"
    Enable-PnpDevice -InstanceId $d.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
}

# Clean up any leftover wake tasks
schtasks /query 2>$null | Select-String "QCStress_WakeTimer" | ForEach-Object {
    $tn = ($_ -split '\s+')[0]
    schtasks /delete /tn $tn /f 2>$null | Out-Null
}

Log "Log: $logFile"
Log "CSV: $csvFile"
