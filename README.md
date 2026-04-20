# QC Stress Logger (QCLogger)

A Windows-first diagnostic toolkit for reproducing and investigating intermittent keyboard/touchpad failures, especially on Qualcomm Snapdragon self-host devices.

This toolchain combines persistent ETW logging, stress orchestration, anomaly monitoring, and post-capture analytics to produce a shareable incident package and an actionable HTML report.

## Why This Exists

Intermittent input issues are hard to root-cause because they often occur:
- after sleep/modern standby/hibernate
- during long idle windows
- under aggressive power-state transitions
- with timing-sensitive USB/HID/I2C behavior

QCLogger is designed to make those failures observable and repeatable.

## Key Capabilities

- Persistent logging that survives reboot/sleep/hibernate
- Automated collection of ETL + EVTX + PnP snapshots + system metadata
- One-click stress + monitor workflow with auto-stop on detected failure
- Deep analysis report generation with issue heuristics and timeline correlation
- Qualcomm-aware provider coverage (PPTE/USB/UCSI/PCIe/PMIC) plus Microsoft input stack

## Repository Contents

| File | Purpose |
|---|---|
| Analyze-QCLogs.ps1 | Primary analysis engine that parses collected artifacts and generates the HTML report |
| QCLogger-Start.cmd | Starts persistent autologger/live sessions and pre-capture metadata collection |
| QCLogger-Stop.cmd | Stops sessions, exports events/artifacts, triggers analysis, opens report |
| QCMonitor.ps1 | Real-time keyboard/touchpad health monitor and anomaly detector |
| QCStress.ps1 | Stress harness for PPTE, USB suspend, HID cycle, and sleep/wake scenarios |
| QCTest.cmd | One-click orchestrator: start logger + monitor + stress and auto-handle incident capture |
| USAGE_GUIDE.md | Extended usage reference and examples |
| README.txt | Legacy plain-text quick guide |

## Requirements

- Windows 10/11
- Administrator permissions (UAC elevation required)
- PowerShell 5.1 or newer
- No external dependencies required for core scripts

## Quick Start

### 1) Start Persistent Logging

Run as Administrator:

- QCLogger-Start.cmd

Then reboot once to ensure autologger persistence is active.

### 2) Reproduce the Issue

Use the machine normally or run stress workflows until keyboard/touchpad disruption is observed.
Record approximate incident time.

### 3) Stop + Collect + Analyze

Run as Administrator:

- QCLogger-Stop.cmd

This will:
- stop all trace sessions
- export event logs
- capture post-state PnP snapshot
- package build/system metadata
- run Analyze-QCLogs.ps1
- generate/open HTML report

### 4) Review Output

All outputs are written under:

- C:\QCLogger\

Key artifact:

- C:\QCLogger\QCLogger-Report.html

## One-Click End-to-End Workflow

Use:

- QCTest.cmd

This orchestrates:
- logger startup
- monitor startup
- stress startup
- anomaly watch loop
- automatic stop/collection/reporting on detected failure or end condition

Example invocations:

```bat
QCTest.cmd
QCTest.cmd -Mode ppte -Intensity extreme -Duration 60
QCTest.cmd -Mode all -Intensity high -Duration 30 -Poll 1
QCTest.cmd -SleepCycles 10 -SleepSec 30 -WakeHoldSec 15
QCTest.cmd -Mode scenario -Scenario "ppte:300,sleep:5"
```

## Stress Tool (QCStress.ps1)

Use when you need controlled pressure on input-related paths.

List scenarios/options:

```powershell
powershell -ExecutionPolicy Bypass -File QCStress.ps1 -ListScenarios
```

Common modes:
- all
- ppte
- usb
- hid
- sleep
- scenario

Examples:

```powershell
powershell -ExecutionPolicy Bypass -File QCStress.ps1
powershell -ExecutionPolicy Bypass -File QCStress.ps1 -Mode ppte -Intensity extreme
powershell -ExecutionPolicy Bypass -File QCStress.ps1 -Mode sleep -SleepCycles 10
powershell -ExecutionPolicy Bypass -File QCStress.ps1 -Mode scenario -Scenario "ppte:200,usb:50,hid:10,sleep:5"
```

Safety behaviors:
- auto-discovers target devices from Device Manager
- attempts restoration of changed power/device states on exit
- supports Ctrl+C with cleanup path

## Monitor Tool (QCMonitor.ps1)

Use when you need real-time signal on keyboard/touchpad health changes.

Example:

```powershell
powershell -ExecutionPolicy Bypass -File QCMonitor.ps1 -Beep
powershell -ExecutionPolicy Bypass -File QCMonitor.ps1 -PollIntervalSec 1 -Beep
```

Detects:
- device disappearance
- status transitions (OK -> degraded/failed)
- recovery events
- new device arrival
- prolonged input idle windows

## Analysis Scope (Analyze-QCLogs.ps1)

The report is designed to identify and correlate:
- sleep/wake-related input loss
- intermittent device disconnect/reconnect patterns
- USB controller and hub failures
- I2C/SPI/ACPI related input path instability
- driver watchdog and UMDF/WudfRd symptoms
- PnP problem-code evidence before/after incident
- timing overlap between power transitions and user-visible failures

## Output Inventory

Typical artifacts under C:\QCLogger\ include:
- Trace*.etl / LiveTrace.etl
- *_System.evtx / *_Application.evtx / *_DriverWatchdog.evtx
- PreCapture.pnp / PostCapture.pnp
- BuildInfo.txt / SystemInfo.txt / StartTime.txt / StopTime.txt
- QCLogger-Report.html

## Recommended Triage Workflow

1. Run QCTest.cmd with a targeted stress profile
2. Allow monitor to detect failure condition
3. Stop/collect and review QCLogger-Report.html
4. Validate timeline against observed user symptoms
5. Share full C:\QCLogger\ package for escalation

## Sharing With Engineering

When filing an issue or sharing with an investigation team, include:
- zipped C:\QCLogger\ folder
- rough incident timestamp
- symptom narrative (for example: keyboard dead after overnight standby)
- whether external USB keyboard/mouse behavior differed from built-in devices

## GitHub Repository Setup (Using gh)

After installing Git and GitHub CLI, publish this folder with:

```powershell
git init
git add .
git commit -m "Initial commit: QC Stress Logger"
gh auth login --hostname github.com --git-protocol https --web
gh repo create QCStresserLogger --source . --private --remote origin --push --description "QC stress logger for reproducing and diagnosing keyboard/touchpad failures on Windows"
```

If you prefer public visibility, replace --private with --public.

## Notes and Limitations

- Must run elevated for driver/power/logging operations
- Some HID devices may not support disable/enable cycling
- Sleep/wake behavior differs across platform firmware and policy
- Event availability can vary by OS build and OEM image

## License

No license file is currently present in this repository.
If you plan to share broadly, add a license file (for example MIT) before public release.

## Acknowledgments

Built for practical, field-focused diagnostics where intermittent input failures require both high-fidelity data capture and reproducible stress conditions.
