@echo off
setlocal enabledelayedexpansion
:: ============================================================================
:: QCLogger - Qualcomm Selfhost Persistent Trace Logger
:: Stop Script - Stops logging, collects all artifacts, runs analysis
:: ============================================================================

:: ---- Auto-elevate to Admin ----
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator privileges...
    powershell -Command "Start-Process -Verb RunAs -FilePath '%~f0'"
    exit /b
)

set SessionName=QCLogger
set LiveSession=QCLogger_Live
set LogDir=C:\QCLogger
set WmiKey=HKLM\System\CurrentControlSet\Control\WMI\Autologger
set ScriptDir=%~dp0

echo ============================================================
echo   QCLogger - Stopping and Collecting Logs
echo ============================================================
echo.

:: ---- Record stop time ----
echo %date% %time% > "%LogDir%\StopTime.txt"

:: ---- Stop live session ----
echo [1/7] Stopping live trace session...
logman stop -n %LiveSession% >nul 2>&1
logman delete -n %LiveSession% >nul 2>&1

:: ---- Stop autologger session (running after reboot) ----
echo [2/7] Stopping autologger trace session...
logman stop %SessionName% -ets >nul 2>&1

:: ---- Remove autologger config (prevent restart on next boot) ----
echo [3/7] Removing autologger configuration...
reg delete "%WmiKey%\%SessionName%" /f >nul 2>&1

:: ---- Export post-capture PNP state ----
echo [4/7] Capturing post-capture device state...
pnputil.exe /export-pnpstate "%LogDir%\PostCapture.pnp" >nul 2>&1

:: ---- Export event logs ----
echo [5/7] Exporting event logs...
wevtutil.exe epl System "%LogDir%\%COMPUTERNAME%_System.evtx" /ow:true >nul 2>&1
wevtutil.exe epl Application "%LogDir%\%COMPUTERNAME%_Application.evtx" /ow:true >nul 2>&1
wevtutil.exe epl "Microsoft-Windows-Kernel-PnP/Driver Watchdog" "%LogDir%\%COMPUTERNAME%_DriverWatchdog.evtx" /ow:true >nul 2>&1
wevtutil.exe epl "Microsoft-Windows-Kernel-ShimEngine/Operational" "%LogDir%\%COMPUTERNAME%_KernelShimEngine.evtx" /ow:true >nul 2>&1
wevtutil.exe epl "Microsoft-Windows-USB-UCMUCSICX/Operational" "%LogDir%\%COMPUTERNAME%_UcmUcsiCx.evtx" /ow:true >nul 2>&1

:: ---- Collect system info ----
echo [6/7] Collecting system information...
reg query "HKLM\Software\Microsoft\Windows NT\CurrentVersion" /v BuildLabEX > "%LogDir%\BuildInfo.txt" 2>nul
reg query "HKLM\Software\Microsoft\Windows NT\CurrentVersion" /v CurrentBuildNumber >> "%LogDir%\BuildInfo.txt" 2>nul
reg query "HKLM\Software\Microsoft\Windows NT\CurrentVersion" /v DisplayVersion >> "%LogDir%\BuildInfo.txt" 2>nul
reg query "HKLM\Software\Microsoft\Windows NT\CurrentVersion" /v UBR >> "%LogDir%\BuildInfo.txt" 2>nul
systeminfo > "%LogDir%\SystemInfo.txt" 2>nul

:: ---- Check for USB live kernel reports ----
if exist %SystemRoot%\LiveKernelReports\USB* (
    echo   Found USB LiveKernelReports - copying...
    if not exist "%LogDir%\LiveKernelReports" mkdir "%LogDir%\LiveKernelReports"
    xcopy /Y /S "%SystemRoot%\LiveKernelReports\USB*" "%LogDir%\LiveKernelReports\" >nul 2>&1
)

:: ---- List collected files ----
echo.
echo   Collected files in %LogDir%:
echo   -------------------------------------------
dir /B "%LogDir%\*.etl" 2>nul
dir /B "%LogDir%\*.evtx" 2>nul
dir /B "%LogDir%\*.pnp" 2>nul
dir /B "%LogDir%\*.txt" 2>nul
echo   -------------------------------------------
echo.

:: ---- Run analysis ----
echo [7/7] Running analysis and generating HTML report...
echo.

if exist "%ScriptDir%Analyze-QCLogs.ps1" (
    powershell.exe -ExecutionPolicy Bypass -File "%ScriptDir%Analyze-QCLogs.ps1" -LogDir "%LogDir%"
) else (
    echo WARNING: Analyze-QCLogs.ps1 not found in %ScriptDir%
    echo Please run it manually: powershell -File Analyze-QCLogs.ps1 -LogDir "%LogDir%"
)

echo.
echo ============================================================
echo   LOGGING STOPPED - Collection Complete
echo ============================================================
echo.
echo   All artifacts saved to: %LogDir%
echo   HTML report: %LogDir%\QCLogger-Report.html
echo.
echo   You can re-run analysis anytime:
echo     powershell -File "%ScriptDir%Analyze-QCLogs.ps1" -LogDir "%LogDir%"
echo ============================================================
echo.
pause
