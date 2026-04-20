@echo off
setlocal enabledelayedexpansion
:: ============================================================================
:: QCTest - One-Click Stress + Monitor + Logging
:: Launches QCLogger, QCStress, and QCMonitor together.
:: When QCMonitor detects KB/TP failure, automatically stops everything,
:: collects logs, generates the report, and shows a notification.
:: ============================================================================

:: ---- Auto-elevate to Admin ----
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator privileges...
    powershell -Command "Start-Process -Verb RunAs -FilePath '%~f0' -ArgumentList '%*'"
    exit /b
)

set ScriptDir=%~dp0
set LogDir=C:\QCLogger
set MonitorLog=%LogDir%\monitor
set StressLog=%LogDir%\stress
set FlagFile=%LogDir%\_anomaly_detected.flag
set TestStartTime=%date% %time%

:: ---- Parse arguments ----
set StressMode=all
set StressIntensity=high
set StressDuration=60
set PollInterval=2
set SleepCycles=0
set SleepDurationSec=15
set WakeHoldSec=10
set Scenario=

:ParseArgs
if "%~1"=="" goto :DoneArgs
if /I "%~1"=="-Mode"          ( set StressMode=%~2& shift & shift & goto :ParseArgs )
if /I "%~1"=="-Intensity"     ( set StressIntensity=%~2& shift & shift & goto :ParseArgs )
if /I "%~1"=="-Duration"      ( set StressDuration=%~2& shift & shift & goto :ParseArgs )
if /I "%~1"=="-Poll"          ( set PollInterval=%~2& shift & shift & goto :ParseArgs )
if /I "%~1"=="-SleepCycles"   ( set SleepCycles=%~2& shift & shift & goto :ParseArgs )
if /I "%~1"=="-SleepSec"      ( set SleepDurationSec=%~2& shift & shift & goto :ParseArgs )
if /I "%~1"=="-WakeHoldSec"   ( set WakeHoldSec=%~2& shift & shift & goto :ParseArgs )
if /I "%~1"=="-Scenario"      ( set Scenario=%~2& shift & shift & goto :ParseArgs )
shift
goto :ParseArgs
:DoneArgs

echo.
echo ============================================================
echo   QCTest - Automated Stress + Monitor + Logging
echo ============================================================
echo.
echo   Stress Mode      : %StressMode%
echo   Stress Intensity : %StressIntensity%
echo   Max Duration     : %StressDuration% minutes
echo   Sleep Cycles     : %SleepCycles% (sleep %SleepDurationSec%s / wake %WakeHoldSec%s)
echo   Poll Interval    : %PollInterval% seconds
if not "%Scenario%"=="" echo   Scenario         : %Scenario%
echo   Log Directory    : %LogDir%
echo.

:: ---- Cleanup any previous flag ----
if exist "%FlagFile%" del /f "%FlagFile%" >nul 2>&1

:: ---- Step 1: Start QCLogger (tracing) ----
echo [1/4] Starting QCLogger trace session...
if not exist %LogDir% mkdir %LogDir%

:: Record start time
echo %date% %time% > "%LogDir%\StartTime.txt"

:: Capture pre-test PNP state
pnputil.exe /export-pnpstate "%LogDir%\PreCapture.pnp" >nul 2>&1

:: Configure autologger (inline from QCLogger-Start logic)
set SessionName=QCLogger
set LiveSession=QCLogger_Live
set WmiKey=HKLM\System\CurrentControlSet\Control\WMI\Autologger

:: Clean existing
logman stop -n %LiveSession% >nul 2>&1
logman delete -n %LiveSession% >nul 2>&1
logman stop %SessionName% -ets >nul 2>&1
reg delete "%WmiKey%\%SessionName%" /f >nul 2>&1

:: Autologger config
reg add "%WmiKey%\%SessionName%" /v Start /t REG_DWORD /d 1 /f >nul
reg add "%WmiKey%\%SessionName%" /v Guid /t REG_SZ /d "{E8D56743-E2E1-4A57-9C0A-3BE24680EBEB}" /f >nul
reg add "%WmiKey%\%SessionName%" /v FileName /t REG_SZ /d "%LogDir%\Trace.etl" /f >nul
reg add "%WmiKey%\%SessionName%" /v FileMax /t REG_DWORD /d 20 /f >nul
reg add "%WmiKey%\%SessionName%" /v MaxFileSize /t REG_DWORD /d 256 /f >nul
reg add "%WmiKey%\%SessionName%" /v BufferSize /t REG_DWORD /d 512 /f >nul
reg add "%WmiKey%\%SessionName%" /v MinimumBuffers /t REG_DWORD /d 8 /f >nul
reg add "%WmiKey%\%SessionName%" /v FlushTimer /t REG_DWORD /d 1 /f >nul

:: Add key providers (subset for perf — the most relevant ones)
for %%G in (
    "{1B502FCB-68CD-4407-A59E-1EAF8AB9EA26}"
    "{505A6797-992E-43E6-B84E-235E41E3FD82}"
    "{914D56C3-C726-494D-A824-3E6C2D0B9F2D}"
    "{38AE9E05-004E-4963-9B66-F9AA7DE33388}"
    "{11ED5F0A-0200-42AF-B5DF-B8BEC02C9624}"
    "{6E6CC2C5-8110-490E-9905-9F2ED700E455}"
    "{9F7711DD-29AD-C1EE-1B1B-B52A0118A54C}"
    "{6FB6E467-9ED4-4B73-8C22-70B97E22C7D9}"
    "{C5964C90-1824-4835-857A-5E95F8AA33B2}"
    "{EAD1EE75-4BFE-4E28-8AFA-E94B0A1BAF37}"
    "{C500C63A-6EFE-433B-84A7-C0740D5DC97F}"
    "{47C779CD-4EFD-49D7-9B10-9F16E5C25D06}"
    "{6465DA78-E7A0-4F39-B084-8F53C7C30DC6}"
    "{896F2806-9D0E-4D5F-AA25-7ACDBF4EAF2C}"
    "{E742C27D-29B1-4E4B-94EE-074D3AD72836}"
    "{B41B0A56-4483-48EF-A772-0B007CBEA8C6}"
    "{09281F1F-F66E-485A-99A2-91638F782C49}"
    "{BBBC2565-8272-486E-B5E5-2BC4630374BA}"
    "{FC8DF8FD-D105-40A9-AF75-2EEC294ADF8C}"
    "{0AE46F43-B144-4056-9195-470054009D6C}"
    "{E6086B4D-AEFF-472B-BDA7-EEC662AFBF11}"
    "{3804DC7C-C7BC-457D-8386-DB0BCB690358}"
) do (
    reg add "%WmiKey%\%SessionName%\%%~G" /v Enabled /t REG_DWORD /d 1 /f >nul
    reg add "%WmiKey%\%SessionName%\%%~G" /v EnableLevel /t REG_DWORD /d 5 /f >nul
    reg add "%WmiKey%\%SessionName%\%%~G" /v MatchAnyKeyword /t REG_QWORD /d 0xFFFFFFFFFFFFFFFF /f >nul
)

:: Start live session
logman create trace -n %LiveSession% -o "%LogDir%\LiveTrace.etl" -f bincirc -max 256 -bs 512 -nb 8 640 -ct perf >nul 2>&1
for %%G in (
    "{6E6CC2C5-8110-490E-9905-9F2ED700E455}"
    "{9F7711DD-29AD-C1EE-1B1B-B52A0118A54C}"
    "{6FB6E467-9ED4-4B73-8C22-70B97E22C7D9}"
    "{47C779CD-4EFD-49D7-9B10-9F16E5C25D06}"
    "{6465DA78-E7A0-4F39-B084-8F53C7C30DC6}"
    "{C5964C90-1824-4835-857A-5E95F8AA33B2}"
    "{EAD1EE75-4BFE-4E28-8AFA-E94B0A1BAF37}"
    "{3804DC7C-C7BC-457D-8386-DB0BCB690358}"
) do (
    logman update trace -n %LiveSession% -p %%~G 0xFFFFFFFFFFFFFFFF 5 >nul 2>&1
)
logman start -n %LiveSession% >nul 2>&1
echo   Tracing started.

:: ---- Step 2: Launch QCMonitor in background ----
echo [2/4] Launching anomaly monitor...
start "QCMonitor" powershell.exe -ExecutionPolicy Bypass -NoExit -File "%ScriptDir%QCMonitor.ps1" -PollIntervalSec %PollInterval% -Beep -LogDir "%MonitorLog%"
echo   Monitor running in separate window.

:: ---- Step 3: Launch QCStress in background ----
echo [3/4] Launching stress tool...
start "QCStress" powershell.exe -ExecutionPolicy Bypass -NoExit -File "%ScriptDir%QCStress.ps1" -Mode %StressMode% -Intensity %StressIntensity% -DurationMinutes %StressDuration% -LogDir "%StressLog%" -SleepCycles %SleepCycles% -SleepDurationSec %SleepDurationSec% -WakeHoldSec %WakeHoldSec%
echo   Stress running in separate window.

:: ---- Step 4: Watch for anomalies ----
echo.
echo [4/4] Monitoring for keyboard/touchpad failure...
echo.
echo   All three tools are running. This window watches for failures.
echo   When KB or TP dies, this script will:
echo     - Show a toast notification
echo     - Stop the stress tool
echo     - Stop tracing
echo     - Collect all logs
echo     - Generate the analysis report
echo.
echo   Press Ctrl+C to manually stop everything.
echo ============================================================
echo.

:: Poll the monitor anomalies CSV for DEVICE_LOST or DEVICE_FAILED on Keyboard/Mouse
:WatchLoop
timeout /t %PollInterval% /nobreak >nul 2>&1

:: Check if stress window is still running (if duration exceeded, it auto-closed)
tasklist /FI "WINDOWTITLE eq QCStress" 2>nul | find "powershell" >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo   Stress test completed its duration. Collecting logs...
    goto :CollectLogs
)

:: Check monitor CSV for keyboard/touchpad anomalies
if exist "%MonitorLog%" (
    for /f "delims=" %%F in ('dir /b /o-d "%MonitorLog%\anomalies_*.csv" 2^>nul') do (
        set LatestCSV=%MonitorLog%\%%F
        goto :CheckCSV
    )
)
goto :WatchLoop

:CheckCSV
if not exist "!LatestCSV!" goto :WatchLoop

:: Look for PERSISTENT FAILURE on Keyboard or Mouse (not self-recoveries)
findstr /I "PERSISTENT_FAILURE.*Keyboard PERSISTENT_FAILURE.*Mouse" "!LatestCSV!" >nul 2>&1
if %errorlevel% equ 0 (
    echo.
    echo   ************************************************************
    echo   *  ANOMALY DETECTED - Keyboard or Touchpad FAILURE!        *
    echo   *  Timestamp: %date% %time%                                *
    echo   ************************************************************
    echo.

    :: Record the anomaly time
    echo ANOMALY DETECTED: %date% %time% > "%FlagFile%"

    :: Toast notification
    powershell -Command "Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.MessageBox]::Show('Keyboard/Touchpad failure detected!`n`nTimestamp: %date% %time%`n`nLogs are being collected and analyzed automatically.','QCTest - FAILURE DETECTED','OK','Error')" >nul 2>&1

    goto :CollectLogs
)

goto :WatchLoop

:: ============================================================
:: Stop everything and collect logs
:: ============================================================
:CollectLogs
echo.
echo ============================================================
echo   Stopping all tools and collecting logs...
echo ============================================================
echo.

:: Record stop time
echo %date% %time% > "%LogDir%\StopTime.txt"

:: Kill stress window
echo [1/7] Stopping stress tool...
taskkill /FI "WINDOWTITLE eq QCStress" /F >nul 2>&1

:: Let monitor run a few more seconds to capture final state, then kill
timeout /t 3 /nobreak >nul 2>&1
echo [2/7] Stopping monitor...
taskkill /FI "WINDOWTITLE eq QCMonitor" /F >nul 2>&1

:: Stop live trace session
echo [3/7] Stopping trace sessions...
logman stop -n %LiveSession% >nul 2>&1
logman delete -n %LiveSession% >nul 2>&1
logman stop %SessionName% -ets >nul 2>&1
reg delete "%WmiKey%\%SessionName%" /f >nul 2>&1

:: Export PNP state
echo [4/7] Capturing post-test device state...
pnputil.exe /export-pnpstate "%LogDir%\PostCapture.pnp" >nul 2>&1

:: Export event logs
echo [5/7] Exporting event logs...
wevtutil.exe epl System "%LogDir%\%COMPUTERNAME%_System.evtx" /ow:true >nul 2>&1
wevtutil.exe epl Application "%LogDir%\%COMPUTERNAME%_Application.evtx" /ow:true >nul 2>&1
wevtutil.exe epl "Microsoft-Windows-Kernel-PnP/Driver Watchdog" "%LogDir%\%COMPUTERNAME%_DriverWatchdog.evtx" /ow:true >nul 2>&1
wevtutil.exe epl "Microsoft-Windows-Kernel-ShimEngine/Operational" "%LogDir%\%COMPUTERNAME%_KernelShimEngine.evtx" /ow:true >nul 2>&1
wevtutil.exe epl "Microsoft-Windows-USB-UCMUCSICX/Operational" "%LogDir%\%COMPUTERNAME%_UcmUcsiCx.evtx" /ow:true >nul 2>&1

:: Collect system info
echo [6/7] Collecting system information...
reg query "HKLM\Software\Microsoft\Windows NT\CurrentVersion" /v BuildLabEX > "%LogDir%\BuildInfo.txt" 2>nul
reg query "HKLM\Software\Microsoft\Windows NT\CurrentVersion" /v CurrentBuildNumber >> "%LogDir%\BuildInfo.txt" 2>nul
reg query "HKLM\Software\Microsoft\Windows NT\CurrentVersion" /v DisplayVersion >> "%LogDir%\BuildInfo.txt" 2>nul
reg query "HKLM\Software\Microsoft\Windows NT\CurrentVersion" /v UBR >> "%LogDir%\BuildInfo.txt" 2>nul
systeminfo > "%LogDir%\SystemInfo.txt" 2>nul

:: Copy USB LiveKernelReports if any
if exist %SystemRoot%\LiveKernelReports\USB* (
    if not exist "%LogDir%\LiveKernelReports" mkdir "%LogDir%\LiveKernelReports"
    xcopy /Y /S "%SystemRoot%\LiveKernelReports\USB*" "%LogDir%\LiveKernelReports\" >nul 2>&1
)

:: Copy stress and monitor logs into main log dir for the report
if exist "%StressLog%" (
    copy /Y "%StressLog%\*.log" "%LogDir%\" >nul 2>&1
    copy /Y "%StressLog%\*.csv" "%LogDir%\" >nul 2>&1
)
if exist "%MonitorLog%" (
    copy /Y "%MonitorLog%\*.log" "%LogDir%\" >nul 2>&1
    copy /Y "%MonitorLog%\*.csv" "%LogDir%\" >nul 2>&1
)

:: Run analysis
echo [7/7] Running analysis and generating HTML report...
echo.
if exist "%ScriptDir%Analyze-QCLogs.ps1" (
    powershell.exe -ExecutionPolicy Bypass -File "%ScriptDir%Analyze-QCLogs.ps1" -LogDir "%LogDir%"
) else (
    echo WARNING: Analyze-QCLogs.ps1 not found in %ScriptDir%
)

echo.
echo ============================================================
echo   TEST COMPLETE
echo ============================================================
echo.
echo   Test started  : %TestStartTime%
echo   Test stopped  : %date% %time%
echo.
if exist "%FlagFile%" (
    echo   Result        : FAILURE DETECTED
    type "%FlagFile%"
) else (
    echo   Result        : Stress duration completed (no failure)
)
echo.
echo   All artifacts : %LogDir%
echo   HTML report   : %LogDir%\QCLogger-Report.html
echo.
echo   Stress logs   : %StressLog%
echo   Monitor logs  : %MonitorLog%
echo ============================================================
echo.
pause
