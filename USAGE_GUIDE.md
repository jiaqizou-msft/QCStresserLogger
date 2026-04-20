# QCLogger — Qualcomm Keyboard/Touchpad Diagnostic Logger

## Overview

QCLogger is a one-click diagnostic tool for capturing and analyzing keyboard/touchpad loss, interruption, and wake failures on Qualcomm Snapdragon Windows devices (Surface and other ARM64 platforms).

It captures USB, HID, Input, I2C/SPI bus, power management, and Qualcomm-specific (PPTE, PEP, PCIe, PMIC) traces continuously — surviving sleep, hibernate, and reboot — then generates a detailed HTML diagnostic report.

---

## What's in the Folder

| File | Description |
|------|-------------|
| `QCLogger-Start.cmd` | Starts persistent logging (auto-elevates to admin) |
| `QCLogger-Stop.cmd` | Stops logging, collects artifacts, generates report (auto-elevates to admin) |
| **`QCTest.cmd`** | **One-click: launches stress + monitor + logging, auto-stops on failure** |
| `Analyze-QCLogs.ps1` | Analysis engine that produces the HTML report |
| `QCStress.ps1` | Stress tool — flips PPTE, cycles USB suspend, toggles HID devices |
| `QCMonitor.ps1` | Anomaly detector — watches keyboard/touchpad health in real-time |
| `USAGE_GUIDE.md` | This guide |
| `README.txt` | Quick reference |

---

## Step-by-Step Instructions

### Step 1 — Start Logging

1. Copy the **QCLogger** folder to the target machine (anywhere is fine).
2. Double-click **`QCLogger-Start.cmd`**.
3. A UAC prompt will appear — click **Yes**.
4. The script will configure tracing and display a confirmation.
5. **Reboot the machine** — the autologger activates on boot and continues through sleep/hibernate.

> **Logging is now active.** You do not need to keep any window open.  
> The logger persists through sleep, modern standby, hibernate, and reboot.

### Step 2 — Reproduce the Issue

Use the machine normally until the keyboard/touchpad issue occurs:
- Keyboard stops responding after sleep
- Touchpad stops working after hibernate
- Single keypress doesn't wake the device
- Input devices intermittently disconnect

**Note the approximate time** when the issue happens (helpful for analysis).

### Step 3 — Stop Logging and Generate Report

1. Double-click **`QCLogger-Stop.cmd`**.
2. A UAC prompt will appear — click **Yes**.
3. The script will:
   - Stop all trace sessions
   - Remove the autologger (prevents restart on next boot)
   - Export PnP device state
   - Export System, Application, Driver Watchdog, and UcmUcsiCx event logs
   - Collect system info and OS build numbers
   - Copy USB LiveKernelReports (if any exist)
   - Run the analysis engine
   - Open the HTML report in your browser

### Step 4 — Review the Report

The report opens automatically at:
```
C:\QCLogger\QCLogger-Report.html
```

---

## What the Report Contains

| Section | What it shows |
|---------|---------------|
| **Key Metrics** | Total events, boot cycles, issues found, PPTE flips, UMDF crashes |
| **Detected Issues** | Auto-diagnosed problems with severity ratings |
| **Sleep/Wake Timeline** | Every modern standby session with duration, wake source, and austerity status |
| **Incident Deep Dive** | Visual timeline of the worst detected failure |
| **PPTE Power Cycling** | Qualcomm power scheme thrashing analysis with peak burst rates |
| **PnP & Driver Failures** | WudfRd load failures, UMDF crashes, device problem codes |
| **System Errors** | All error/critical events grouped by provider |
| **Event Source Breakdown** | Top 20 event providers ranked by volume with relevance tags |
| **ETL Trace Summary** | ETL file inventory with decoded event counts and provider GUIDs |
| **Recommendations** | Actionable next steps for investigation |

---

## Issue Patterns Automatically Detected

| Pattern | Description |
|---------|-------------|
| **Austerity Wake Loss** | After long standby, battery drain budget triggers austerity mode, powering down USB/I2C buses — keyboard/touchpad can't signal wake |
| **Overnight Sleep Failure** | Sleep >4 hours where wake source is accelerometer/lid instead of keyboard/touchpad |
| **PPTE Thrashing** | Qualcomm PPTE rapidly toggling Balanced↔Performance power schemes (can overwhelm USB selective suspend) |
| **WudfRd Input Device Failure** | UMDF driver fails to load for ELAN touchpad or keyboard at boot |
| **UMDF Host Crash** | UMDF host process crashes affecting co-hosted input devices |
| **USB Controller Errors** | USB errors that can affect all USB-connected input |
| **ACPI Timer Failures** | Wake timer device failures that prevent periodic device refresh in standby |

---

## Re-Running Analysis on Existing Logs

To re-analyze previously collected logs (or logs from another machine):

```powershell
powershell -ExecutionPolicy Bypass -File Analyze-QCLogs.ps1 -LogDir "C:\QCLogger"
```

Or point it at any folder containing `.evtx`, `.etl`, and `.pnp` files:
```powershell
powershell -ExecutionPolicy Bypass -File Analyze-QCLogs.ps1 -LogDir "C:\path\to\logs"
```

---

## Output Files

All artifacts are saved to **`C:\QCLogger\`**:

| File | Content |
|------|---------|
| `Trace*.etl` | Raw ETW trace data (QC + USB + HID + Input + Bus providers) |
| `LiveTrace.etl` | Live session trace captured before first reboot |
| `*_System.evtx` | Windows System event log |
| `*_Application.evtx` | Application event log |
| `*_DriverWatchdog.evtx` | Driver Watchdog events |
| `*_KernelShimEngine.evtx` | Kernel ShimEngine events |
| `*_UcmUcsiCx.evtx` | USB-C UCSI events |
| `PreCapture.pnp` | Device state snapshot before logging started |
| `PostCapture.pnp` | Device state snapshot when logging stopped |
| `BuildInfo.txt` | OS build number and version |
| `SystemInfo.txt` | Full system information |
| `StartTime.txt` | Timestamp when logging started |
| `StopTime.txt` | Timestamp when logging stopped |
| `QCLogger-Report.html` | **The diagnostic report** |

---

## Sharing Logs for Investigation

To share logs with the engineering team:

1. Zip the entire `C:\QCLogger\` folder
2. Include the approximate timestamp of the issue
3. Describe what happened (e.g., "keyboard stopped working after overnight sleep")

---

## Trace Providers Included

<details>
<summary>Click to expand full provider list (55+ providers)</summary>

**Qualcomm-specific:**
- USB4 Filter, USB4 Bus
- xHCI Filter, UsbFnSS Filter
- UCSI (qcusbcucsi8380)
- PCIe (QcPPX)
- Display (QcDxkm)
- PMIC Glink, Battery Manager, Battery Miniclass

**Microsoft USB Stack:**
- USB Hub 3, USB Hub 2, USB Port
- xHCI (driver + common ETW + companion)
- UCX (ETW + WPP)
- USBCCGP, WinUSB, USB Serial
- UCM CX, UCSI, UCSI CX, UCSI ACPI
- URS CX, URS Synopsys
- UFX, UFX Synopsys
- USB Task, USB PM API, USB C API

**HID / Input:**
- HID Class (ETW + WPP), HID USB, HID I2C, HID SPI, HID SPI CX
- HID Interrupt, HID VHF, VHF Kernel, VHF User
- Keyboard HID, Keyboard Class
- Mouse HID, Mouse Class
- i8042 Port, GPIO (MsGpioWin32)
- Win32k Input (TraceLogging + WPP)

**Low-Power Bus:**
- SerCx2 (I2C), SpbCx (SPI), I3C Host

</details>

---

## Stress Testing (QCStress.ps1)

Auto-discovers keyboard, touchpad, and HID devices from Device Manager at startup. Stress-tests them via PPTE flipping, USB suspend cycling, HID device cycling, and sleep/wake transitions. Auto-elevates to admin and restores all settings on exit.

### Device Discovery

When QCStress starts, it enumerates Device Manager and logs:
- All **Keyboard** class devices (status and instance ID)
- All **Mouse/Touchpad** class devices
- All input-related **HID** devices, marking which ones are cycle targets
- **USB controllers** (hubs, xHCI)
- **Sleep model** (Modern Standby vs S3) and available power schemes

### List All Options

```powershell
powershell -ExecutionPolicy Bypass -File QCStress.ps1 -ListScenarios
```

### Basic Usage

```powershell
# Default: all stressors, medium intensity, 30 minutes
powershell -ExecutionPolicy Bypass -File QCStress.ps1

# PPTE flipping only, extreme speed, 1 hour
powershell -ExecutionPolicy Bypass -File QCStress.ps1 -Mode ppte -Intensity extreme -DurationMinutes 60

# Sleep/wake cycling: 10 cycles, 30s sleep, 15s awake
powershell -ExecutionPolicy Bypass -File QCStress.ps1 -Mode sleep -SleepCycles 10 -SleepDurationSec 30 -WakeHoldSec 15

# Custom scenario: 200 PPTE flips + 50 USB toggles + 5 sleep cycles
powershell -ExecutionPolicy Bypass -File QCStress.ps1 -Mode scenario -Scenario "ppte:200,usb:50,sleep:5"
```

### Modes

| Mode | Description |
|------|-------------|
| `all` | PPTE + USB + HID cycling combined (default) |
| `ppte` | PPTE power scheme flipping only |
| `usb` | USB selective suspend toggling only |
| `hid` | HID device disable/enable cycling only |
| `sleep` | Sleep/wake (modern standby) cycling only |
| `scenario` | Custom scenario string (see below) |

### Parameters

| Parameter | Values | Default | Description |
|-----------|--------|---------|-------------|
| `-Mode` | `ppte`, `usb`, `hid`, `sleep`, `all`, `scenario` | `all` | Which subsystems to stress |
| `-Intensity` | `low`, `medium`, `high`, `extreme` | `medium` | Speed of cycling |
| `-DurationMinutes` | Any integer | `30` | Max duration for time-based modes |
| `-SleepCycles` | Any integer | `0` | Number of sleep/wake cycles |
| `-SleepDurationSec` | Any integer | `15` | Seconds to stay asleep per cycle |
| `-WakeHoldSec` | Any integer | `10` | Seconds to stay awake between cycles |
| `-Scenario` | String | — | Custom scenario (e.g. `"ppte:200,sleep:5"`) |
| `-ListScenarios` | Switch | — | Show all scenarios and exit |
| `-LogDir` | Path | `C:\QCLogger\stress` | Where to save logs |

### Custom Scenarios

Use `-Mode scenario -Scenario "..."` to specify exactly how many cycles of each stressor:

```
Format: stressor:cycles,stressor:cycles,...
Stressors: ppte, usb, hid, sleep
```

**Example Scenarios:**

| Scenario | Command |
|----------|---------|
| Quick smoke test | `-Scenario "ppte:50,sleep:3"` |
| Heavy PPTE + USB | `-Scenario "ppte:500,usb:100"` |
| Full gauntlet | `-Scenario "ppte:300,usb:60,hid:15,sleep:5"` |
| Sleep soak | `-Mode sleep -SleepCycles 20 -SleepDurationSec 30` |
| Default (no params) | Just run `QCStress.ps1` |

### Intensity Levels

| Level | PPTE Flip Delay | USB Toggle Delay | HID Cycle Delay |
|-------|----------------|-------------------|------------------|
| `low` | 2000ms | 10000ms | 15000ms |
| `medium` | 500ms | 5000ms | 8000ms |
| `high` | 100ms | 2000ms | 4000ms |
| `extreme` | 20ms | 500ms | 2000ms |

### What It Stresses

- **PPTE** — Rapidly flips the active power scheme between Balanced and Performance (mimics Qualcomm qcppte8480.exe behavior)
- **USB** — Toggles USB selective suspend on/off, forcing USB hub power state changes
- **HID** — Disables and re-enables HID devices (touchpad, keyboard), testing PnP recovery. Automatically skips devices that don't support disable/enable.
- **Sleep/Wake** — Puts the system into Modern Standby for a configurable duration, then wakes via scheduled task. Verifies KB/TP health after each wake.

### Safety

- Discovers actual devices at startup (no hardcoded VID/PIDs)
- Skips HID devices that return "Not supported" on first attempt
- Restores original power scheme on exit
- Re-enables USB selective suspend on exit
- Re-enables any disabled input devices on exit
- Cleans up wake timer scheduled tasks
- Press `Ctrl+C` to stop early — cleanup still runs

### Output

Logs are saved to `C:\QCLogger\stress\`:
- `stress_*.log` — Human-readable event log with device discovery
- `stress_events_*.csv` — Machine-parseable CSV of every action and result

---

## Anomaly Monitoring (QCMonitor.ps1)

Platform-agnostic watchdog that continuously monitors keyboard and touchpad health. Works on **any Windows device** — Intel, AMD, or Qualcomm ARM64.

### Basic Usage

```powershell
# Start monitoring with audible alerts
powershell -ExecutionPolicy Bypass -File QCMonitor.ps1 -Beep

# Faster polling (every 1 second)
powershell -ExecutionPolicy Bypass -File QCMonitor.ps1 -PollIntervalSec 1 -Beep
```

### Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-PollIntervalSec` | `2` | How often to check device status (seconds) |
| `-Beep` | Off | Audible beep when a device fails |
| `-LogDir` | `C:\QCLogger\monitor` | Where to save logs |

### What It Detects

| Event | Description |
|-------|-------------|
| `DEVICE_DISRUPTED` | A device failed or disappeared (grace period starts) |
| `SELF_RECOVERED` | Device recovered within grace period — logged in **green** |
| `PERSISTENT_FAILURE` | Device did NOT recover after grace — logged in **red** |
| `DEVICE_ARRIVED` | A new input device appeared |
| `INPUT_IDLE` | No keyboard/mouse input for >2 minutes |

### Live Status Line

```
[14:30:05] KB:OK TP:OK Devs:23/43 Idle:3s Recovered:3 Failed:0
```

- **KB:OK / KB:DEAD** — Keyboard health (only Keyboard class devices)
- **TP:OK / TP:DEAD** — Touchpad/mouse health (only Mouse class devices)
- **Devs:23/43** — Healthy devices / total devices
- **Idle:3s** — Seconds since last input (yellow >30s, red >120s)
- **Recovered:3** — Self-recoveries from stress (green = healthy)
- **Failed:0** — Persistent failures (red = real problem)

### Output

Logs are saved to `C:\QCLogger\monitor\`:
- `monitor_*.log` — Human-readable event log
- `anomalies_*.csv` — CSV of every anomaly with timestamp, device, and status

---

## Recommended Workflow: Stress + Monitor

### Easiest: One-Click Automated Test (QCTest.cmd)

Double-click **`QCTest.cmd`** — it does everything automatically:

1. Starts ETW trace logging (autologger + live session)
2. Opens the anomaly monitor (QCMonitor) in a separate window
3. Opens the stress tool (QCStress) in a separate window
4. Watches for keyboard/touchpad failure in the background
5. **When a failure is detected:**
   - Shows a Windows notification popup
   - Stops the stress tool
   - Stops the monitor
   - Stops tracing
   - Exports PnP state, event logs, system info
   - Runs the analysis engine
   - Opens the HTML report

```
# Just double-click, or from command line:
QCTest.cmd

# With options:
QCTest.cmd -Mode ppte -Intensity extreme -Duration 60
QCTest.cmd -Mode all -Intensity high -Duration 30 -Poll 1
QCTest.cmd -SleepCycles 10 -SleepSec 30 -WakeHoldSec 15
QCTest.cmd -Mode scenario -Scenario "ppte:300,sleep:5"
```

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-Mode` | `all` | Stress mode: `ppte`, `usb`, `hid`, `sleep`, `all`, `scenario` |
| `-Intensity` | `high` | Stress speed: `low`, `medium`, `high`, `extreme` |
| `-Duration` | `60` | Max stress duration in minutes |
| `-Poll` | `2` | Monitor poll interval in seconds |
| `-SleepCycles` | `0` | Number of sleep/wake cycles |
| `-SleepSec` | `15` | Seconds to stay asleep per cycle |
| `-WakeHoldSec` | `10` | Seconds awake between sleep cycles |
| `-Scenario` | — | Custom scenario (e.g. `"ppte:200,sleep:5"`) |

If the stress duration completes without a failure, QCTest still collects all logs and generates the report.

### Manual: Run Tools Separately

Run both tools simultaneously to trigger and catch failures:

1. **Terminal 1** — Start the anomaly monitor:
   ```powershell
   powershell -ExecutionPolicy Bypass -File QCMonitor.ps1 -Beep
   ```

2. **Terminal 2** — Start stress testing:
   ```powershell
   powershell -ExecutionPolicy Bypass -File QCStress.ps1 -Mode all -Intensity high
   ```

3. **Wait** — When the monitor beeps and shows `KB:DEAD` or `TP:DEAD`, you've triggered a failure.

4. **Collect** — Run `QCLogger-Stop.cmd` to capture full traces and generate the diagnostic report.

5. **Analyze** — The HTML report will correlate the stress events with the failure.

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| UAC prompt doesn't appear | Right-click the `.cmd` file → **Run as administrator** |
| Script says "powershell not found" | Ensure PowerShell 5.1+ is available (built into Windows 10/11) |
| No ETL files generated | Make sure you rebooted after running Start, and waited before running Stop |
| Report shows 0 events | Ensure the `.evtx` files are in the log directory being analyzed |
| Want to re-run analysis only | `powershell -ExecutionPolicy Bypass -File Analyze-QCLogs.ps1 -LogDir "C:\QCLogger"` |

---

## Requirements

- Windows 10/11 (ARM64 or x64)
- PowerShell 5.1+ (built-in)
- No additional tools or installations needed
- ~72 KB tool size; logs typically 50–500 MB depending on duration
