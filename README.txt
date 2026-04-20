============================================================
 QCLogger - Qualcomm Selfhost Persistent Trace Logger
============================================================

A simplified diagnostic tool for continuously collecting
Qualcomm USB/HID/Input trace logs on selfhost machines.
Designed for diagnosing keyboard and touchpad loss/interruption.

REQUIREMENTS
  - Windows with admin access
  - PowerShell 5.1+ (built into Windows)
  - No additional tools needed

DISTRIBUTION
  Copy the entire QCLogger folder to the target machine.
  No installation required.

QUICK START
============================================================

  Step 1: START LOGGING
    - Right-click QCLogger-Start.cmd → Run as administrator
    - Reboot the machine (autologger activates on boot)
    - Logging now runs continuously, surviving:
        • Sleep / Modern Standby
        • Hibernate
        • Reboot

  Step 2: REPRODUCE THE ISSUE
    - Use the machine normally until keyboard/touchpad issue occurs
    - Note the approximate timestamp when the issue happens

  Step 3: STOP AND ANALYZE
    - Right-click QCLogger-Stop.cmd → Run as administrator
    - The tool will:
        1. Stop all trace sessions
        2. Export PNP device state
        3. Export system/application event logs
        4. Collect all ETL trace files
        5. Analyze logs for keyboard/touchpad issues
        6. Generate and open an HTML diagnostic report

  All output is saved to: C:\QCLogger\

FILES IN THIS TOOL
============================================================

  QCLogger-Start.cmd    - Start persistent logging (auto-elevates)
  QCLogger-Stop.cmd     - Stop logging and generate report (auto-elevates)
  QCTest.cmd            - ONE-CLICK: stress + monitor + logging (auto-elevates)
  Analyze-QCLogs.ps1    - Analysis engine (called by Stop script)
  QCStress.ps1          - Stress tool: PPTE / USB / HID cycling
  QCMonitor.ps1         - Anomaly detector: watches KB/TP health
  USAGE_GUIDE.md        - Full usage guide with examples
  README.txt            - This file

OUTPUT FILES (in C:\QCLogger\)
============================================================

  Trace*.etl            - Raw ETW trace files (QC/USB/HID/Input providers)
  LiveTrace.etl         - Live session trace (pre-reboot capture)
  *_System.evtx         - Windows System event log
  *_Application.evtx    - Windows Application event log
  *_DriverWatchdog.evtx - Driver Watchdog events
  PreCapture.pnp        - Device state before logging started
  PostCapture.pnp       - Device state when logging stopped
  BuildInfo.txt         - OS build information
  StartTime.txt         - Logging start timestamp
  StopTime.txt          - Logging stop timestamp
  QCLogger-Report.html  - Diagnostic analysis report

WHAT THE REPORT ANALYZES
============================================================

  The HTML report automatically diagnoses:
  - Post-sleep/hibernate input device failures
  - Intermittent keyboard/touchpad disconnection patterns
  - USB controller errors affecting input devices
  - I2C/SPI bus failures (internal keyboard/touchpad)
  - Driver watchdog timeouts for input drivers
  - PnP device problem codes on HID/input devices
  - Correlation between power transitions and input loss

  The report includes:
  - Executive summary with issue count
  - Detected issues with severity and description
  - Sleep/wake session table with austerity detection
  - Incident deep dive with visual timeline
  - PPTE power scheme thrashing analysis
  - WudfRd / UMDF failure tracking
  - Error summary and provider breakdown
  - ETL trace file summary
  - Actionable recommendations

STRESS TESTING (QCStress.ps1)
============================================================

  Auto-discovers keyboard, touchpad, and HID devices from
  Device Manager at startup. Stress-tests them via PPTE
  flipping, USB suspend cycling, HID cycling, and sleep/wake.
  Auto-elevates to admin. Restores everything on exit.

  List all scenarios and options:
    powershell -ExecutionPolicy Bypass -File QCStress.ps1 -ListScenarios

  Modes:
    -Mode ppte      PPTE power scheme flipping only
    -Mode usb       USB selective suspend toggling only
    -Mode hid       HID device disable/enable cycling only
    -Mode sleep     Sleep/wake (modern standby) cycling only
    -Mode all       All of the above (default)
    -Mode scenario  Custom scenario string

  Sleep/Wake:
    -SleepCycles 5         Number of sleep/wake cycles
    -SleepDurationSec 15   How long to stay asleep
    -WakeHoldSec 10        How long awake between cycles

  Custom Scenario:
    -Mode scenario -Scenario "ppte:200,usb:50,hid:10,sleep:5"
    Runs each stressor for the specified number of cycles.

  Intensity:
    -Intensity low       2s between PPTE flips
    -Intensity medium    500ms (default)
    -Intensity high      100ms
    -Intensity extreme   20ms

  Examples:
    powershell -ExecutionPolicy Bypass -File QCStress.ps1
    powershell -ExecutionPolicy Bypass -File QCStress.ps1 -Mode ppte -Intensity extreme
    powershell -ExecutionPolicy Bypass -File QCStress.ps1 -Mode sleep -SleepCycles 10
    powershell -ExecutionPolicy Bypass -File QCStress.ps1 -Mode scenario -Scenario "ppte:300,sleep:5"

  Output: C:\QCLogger\stress\

ANOMALY MONITORING (QCMonitor.ps1)
============================================================

  Platform-agnostic watchdog that detects when keyboard and
  touchpad stop working. Works on Intel, AMD, and Qualcomm.

  Usage:
    powershell -ExecutionPolicy Bypass -File QCMonitor.ps1 -Beep

  Parameters:
    -PollIntervalSec 1   Check every 1 second (default: 2)
    -Beep                Audible alert on device failure

  What it detects:
    - Device disappearance (removed from PnP)
    - Device status change (OK -> Error/Degraded)
    - Device recovery (Error -> OK)
    - New device arrival
    - System-wide input idle >2 minutes

  Live status line:
    [14:30:05] KB:OK TP:OK Devs:5/5 Idle:3s Anomalies:0

  Output: C:\QCLogger\monitor\

RECOMMENDED WORKFLOW
============================================================

  EASIEST: One-click automated test
    Double-click QCTest.cmd
    It launches logging + stress + monitor automatically.
    When KB/TP fails, it pops a notification, stops everything,
    collects logs, and generates the report.

  Options for QCTest.cmd:
    QCTest.cmd
    QCTest.cmd -Mode ppte -Intensity extreme -Duration 60
    QCTest.cmd -Mode all -Intensity high -Duration 30 -Poll 1
    QCTest.cmd -SleepCycles 10 -SleepSec 30 -WakeHoldSec 15
    QCTest.cmd -Mode scenario -Scenario "ppte:300,sleep:5"

  MANUAL: Run tools separately
    1. Terminal 1: Start the monitor
       powershell -ExecutionPolicy Bypass -File QCMonitor.ps1 -Beep

    2. Terminal 2: Start the stress tool
       powershell -ExecutionPolicy Bypass -File QCStress.ps1 -Mode all -Intensity high

    3. When QCMonitor beeps / shows KB:DEAD or TP:DEAD,
       you have reproduced the failure.

    4. Run QCLogger-Stop.cmd to collect traces + report.
  - Executive summary with issue count
  - Detected issues with severity and description
  - Power transition timeline
  - Input device status from PNP state
  - Full event timeline with search/filter
  - ETL trace file summary

RE-RUNNING ANALYSIS
============================================================

  To re-analyze previously collected logs:
    powershell -ExecutionPolicy Bypass -File Analyze-QCLogs.ps1 -LogDir "C:\QCLogger"

TRACE PROVIDERS INCLUDED
============================================================

  Qualcomm:  USB4, USB3, xHCI, PCIe, Display, PMIC, Battery
  Microsoft: USB Hub, xHCI, UCX, UCSI, URS, UFN, PCI
  HID/Input: HidClass, HidUsb, HidI2C, HidSPI, HidBth,
             KbdHid, KbdClass, MouHid, MouClass, VHF
  Bus:       SpbCx (SPI), SerCx2 (I2C), I3C, GPIO
  Win32k:    Input processing, tracelogging
