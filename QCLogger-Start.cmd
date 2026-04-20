@echo off
setlocal enabledelayedexpansion
:: ============================================================================
:: QCLogger - Qualcomm Selfhost Persistent Trace Logger
:: Start Script - Configures autologger + live session for continuous logging
:: Survives sleep, hibernate, and reboot
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

:: ---- Settings ----
set MaxFileSizeInMB=256
set BufferSizeInKB=512
set MinimumBuffers=8
set FileMaxVal=20
set FlushTimer=1

echo ============================================================
echo   QCLogger - Qualcomm Persistent Trace Logger
echo ============================================================
echo.

:: ---- Create output directory ----
if not exist %LogDir% mkdir %LogDir%

:: ---- Clean up any existing sessions ----
echo [1/5] Cleaning up existing sessions...
logman stop -n %LiveSession% >nul 2>&1
logman delete -n %LiveSession% >nul 2>&1
logman stop %SessionName% -ets >nul 2>&1
reg delete "%WmiKey%\%SessionName%" /f >nul 2>&1

:: ---- Record start time ----
echo %date% %time% > "%LogDir%\StartTime.txt"

:: ---- Pre-capture PNP state ----
echo [2/5] Capturing pre-capture device state...
pnputil.exe /export-pnpstate "%LogDir%\PreCapture.pnp" >nul 2>&1

:: ---- Configure Autologger (persists through reboot/sleep/hibernate) ----
echo [3/5] Configuring autologger for reboot persistence...
reg add "%WmiKey%\%SessionName%" /v Start /t REG_DWORD /d 1 /f >nul
reg add "%WmiKey%\%SessionName%" /v Guid /t REG_SZ /d "{E8D56743-E2E1-4A57-9C0A-3BE24680EBEB}" /f >nul
reg add "%WmiKey%\%SessionName%" /v FileName /t REG_SZ /d "%LogDir%\Trace.etl" /f >nul
reg add "%WmiKey%\%SessionName%" /v FileMax /t REG_DWORD /d %FileMaxVal% /f >nul
reg add "%WmiKey%\%SessionName%" /v MaxFileSize /t REG_DWORD /d %MaxFileSizeInMB% /f >nul
reg add "%WmiKey%\%SessionName%" /v BufferSize /t REG_DWORD /d %BufferSizeInKB% /f >nul
reg add "%WmiKey%\%SessionName%" /v MinimumBuffers /t REG_DWORD /d %MinimumBuffers% /f >nul
reg add "%WmiKey%\%SessionName%" /v FlushTimer /t REG_DWORD /d %FlushTimer% /f >nul

:: ---- Add all trace providers ----
echo [4/5] Adding trace providers (QC + USB + HID + Input + Bus)...

:: ---- QC USB4 Providers ----
call :AddProvider "{1B502FCB-68CD-4407-A59E-1EAF8AB9EA26}" 5 0xFFFFFFFFFFFFFFFF
call :AddProvider "{505A6797-992E-43E6-B84E-235E41E3FD82}" 5 0xFFFFFFFFFFFFFFFF
call :AddProvider "{914D56C3-C726-494D-A824-3E6C2D0B9F2D}" 5 0xFFFFFFFFFFFFFFFF
call :AddProvider "{38AE9E05-004E-4963-9B66-F9AA7DE33388}" 5 0xFFFFFFFFFFFFFFFF

:: ---- QC USB3/xHCI Providers ----
call :AddProvider "{11ED5F0A-0200-42AF-B5DF-B8BEC02C9624}" 5 0xFFFFFFFFFFFFFFFF
call :AddProvider "{6FD2F1A8-C3D9-4A72-B122-30C6AD3E0A5F}" 5 0xFFFFFFFFFFFFFFFF
call :AddProvider "{3168776E-0E5B-4B63-8F92-9D6C1B395166}" 5 0xFFFFFFFFFFFFFFFF

:: ---- QC PCIe / Display / PMIC ----
call :AddProvider "{11BB6DA3-32F8-443D-886F-2811CD201BB7}" 5 0xFFFFFFFFFFFFFFFF
call :AddProvider "{47711976-08C7-44EF-8FA2-082DA6A30A30}" 5 0xFFFFFFFFFFFFFFFF
call :AddProvider "{E55D560E-55FA-47C3-A3EC-2AA0C319C2EF}" 5 0xFFFFFFFFFFFFFFFF
call :AddProvider "{3804DC7C-C7BC-457D-8386-DB0BCB690358}" 5 0xFFFFFFFFFFFFFFFF

:: ---- MS USB Host Providers ----
call :AddProvider "{6E6CC2C5-8110-490E-9905-9F2ED700E455}" 5 0xFFFFFFFFFFFFFFFF
call :AddProvider "{9F7711DD-29AD-C1EE-1B1B-B52A0118A54C}" 5 0xFFFFFFFFFFFFFFFF
call :AddProvider "{6FB6E467-9ED4-4B73-8C22-70B97E22C7D9}" 5 0xFFFFFFFFFFFFFFFF
call :AddProvider "{30E1D284-5D88-459C-83FD-6345B39B19EC}" 5 0xFFFFFFFFFFFFFFFF
call :AddProvider "{3BBABCCA-A210-4570-B501-0E34D88A88FB}" 4 0xFFFFFFFFFFFFFFFF
call :AddProvider "{D75AEDBE-CFCD-42B9-94AB-F47B224245DD}" 5 0xFFFFFFFFFFFFFFFF
call :AddProvider "{BC6C9364-FC67-42C5-ACF7-ABED3B12ECC6}" 5 0xFFFFFFFFFFFFFFFF
call :AddProvider "{EF201D1B-4E45-4199-9E9E-74591F447955}" 5 0xFFFFFFFFFFFFFFFF

:: ---- MS USB-C / UCSI / URS / UFN Providers ----
call :AddProvider "{C5964C90-1824-4835-857A-5E95F8AA33B2}" 5 0xFFFFFFFFFFFFFFFF
call :AddProvider "{EAD1EE75-4BFE-4E28-8AFA-E94B0A1BAF37}" 5 0xFFFFFFFFFFFFFFFF
call :AddProvider "{C500C63A-6EFE-433B-84A7-C0740D5DC97F}" 5 0xFFFFFFFFFFFFFFFF
call :AddProvider "{EDEF8E04-4E22-4A95-9D04-539EBD112A5E}" 5 0xFFFFFFFFFFFFFFFF
call :AddProvider "{8DEAEA72-4C63-49A4-9B8B-25DA24DAE056}" 5 0xFFFFFFFFFFFFFFFF
call :AddProvider "{4921461B-27DE-4937-AC2D-96390848DDF4}" 5 0xFFFFFFFFFFFFFFFF
call :AddProvider "{0F1ECE0C-1647-4051-B1BA-D3A0694E6B12}" 5 0xFFFFFFFFFFFFFFFF
call :AddProvider "{468D9E9D-07F5-4537-B650-98389559206E}" 5 0xFFFFFFFFFFFFFFFF
call :AddProvider "{8650230D-68B0-476E-93ED-634490DCE145}" 5 0xFFFFFFFFFFFFFFFF
call :AddProvider "{04B3644B-27CA-4CAC-9243-29BED5C91CF9}" 5 0xFFFFFFFFFFFFFFFF
call :AddProvider "{9C06E0CA-F00E-4AC3-A049-65663B654393}" 5 0xFFFFFFFFFFFFFFFF
call :AddProvider "{C1330B70-D01E-4AA6-B30D-B2BDAF228EC3}" 5 0xFFFFFFFFFFFFFFFF
call :AddProvider "{8FBF685A-DCE5-44C2-B126-5E90176993A7}" 5 0xFFFFFFFFFFFFFFFF

:: ---- HID / Input Providers ----
call :AddProvider "{47C779CD-4EFD-49D7-9B10-9F16E5C25D06}" 5 0xFFFFFFFFFFFFFFFF
call :AddProvider "{6465DA78-E7A0-4F39-B084-8F53C7C30DC6}" 5 0xFFFFFFFFFFFFFFFF
call :AddProvider "{896F2806-9D0E-4D5F-AA25-7ACDBF4EAF2C}" 5 0xFFFFFFFFFFFFFFFF
call :AddProvider "{E742C27D-29B1-4E4B-94EE-074D3AD72836}" 5 0xFFFFFFFFFFFFFFFF
call :AddProvider "{07699FF6-D2C0-4323-B927-2C53442ED29B}" 5 0xFFFFFFFFFFFFFFFF
call :AddProvider "{0107CF95-313A-473E-9078-E73CD932F2FE}" 5 0xFFFFFFFFFFFFFFFF
call :AddProvider "{0A6B3BB2-3504-49C1-81D0-6A4B88B96427}" 5 0xFFFFFFFFFFFFFFFF
call :AddProvider "{5ED8BB73-C76F-49D9-BF05-4982903C6CA5}" 5 0xFFFFFFFFFFFFFFFF
call :AddProvider "{7FFB8EB8-2C86-45D6-A7C5-C023D9C070C1}" 5 0xFFFFFFFFFFFFFFFF
call :AddProvider "{78396E52-9753-4D63-8CF5-A936B4989FF2}" 5 0xFFFFFFFFFFFFFFFF
call :AddProvider "{51B2172F-205D-40C1-9A30-ED090FF72E6C}" 5 0xFFFFFFFFFFFFFFFF
call :AddProvider "{5E11AB47-4E39-4D45-8BD5-C9C42AB9D1E6}" 5 0xFFFFFFFFFFFFFFFF

:: ---- Keyboard / Mouse Class Drivers ----
call :AddProvider "{B41B0A56-4483-48EF-A772-0B007CBEA8C6}" 5 0xFFFFFFFFFFFFFFFF
call :AddProvider "{09281F1F-F66E-485A-99A2-91638F782C49}" 5 0xFFFFFFFFFFFFFFFF
call :AddProvider "{BBBC2565-8272-486E-B5E5-2BC4630374BA}" 5 0xFFFFFFFFFFFFFFFF
call :AddProvider "{FC8DF8FD-D105-40A9-AF75-2EEC294ADF8C}" 5 0xFFFFFFFFFFFFFFFF

:: ---- I2C / SPI / SerCx / SpbCx (bus for internal touchpad/keyboard) ----
call :AddProvider "{0AE46F43-B144-4056-9195-470054009D6C}" 5 0xFFFFFFFFFFFFFFFF
call :AddProvider "{E6086B4D-AEFF-472B-BDA7-EEC662AFBF11}" 5 0xFFFFFFFFFFFFFFFF
call :AddProvider "{13CF0A0A-50F6-4F4B-80EA-1B3121F5658C}" 5 0xFFFFFFFFFFFFFFFF

:: ---- Win32k Input / GPIO ----
call :AddProvider "{5A81715A-84C0-4DEF-AE38-EDDE40DF5B3A}" 5 0xFFFFFFFFFFFFFFFF
call :AddProvider "{7E6B69B9-2AEC-4FB3-9426-69A0F2B61A86}" 5 0xFFFFFFFFFFFFFFFF
call :AddProvider "{487D6E37-1B9D-46D3-A8FD-54CE8BDF8A53}" 5 0xFFFFFFFFFFFFFFFF

:: ---- QC Battery/PMIC (power-related, helps correlate power issues) ----
call :AddProvider "{4A651CBB-7073-495F-9984-A2AE76C9EB58}" 5 0xFFFFFFFFFFFFFFFF
call :AddProvider "{97413F1D-5298-4884-94EB-6FEFBC0AC4A7}" 5 0xFFFFFFFFFFFFFFFF

:: ---- Start Live Session (immediate capture, no reboot needed) ----
echo [5/5] Starting live trace session...
logman create trace -n %LiveSession% -o "%LogDir%\LiveTrace.etl" -f bincirc -max %MaxFileSizeInMB% -bs %BufferSizeInKB% -nb %MinimumBuffers% 640 -ct perf >nul 2>&1

:: Add the same providers to the live session
call :AddLiveProvider "{1B502FCB-68CD-4407-A59E-1EAF8AB9EA26}" 5 0xFFFFFFFFFFFFFFFF
call :AddLiveProvider "{505A6797-992E-43E6-B84E-235E41E3FD82}" 5 0xFFFFFFFFFFFFFFFF
call :AddLiveProvider "{914D56C3-C726-494D-A824-3E6C2D0B9F2D}" 5 0xFFFFFFFFFFFFFFFF
call :AddLiveProvider "{38AE9E05-004E-4963-9B66-F9AA7DE33388}" 5 0xFFFFFFFFFFFFFFFF
call :AddLiveProvider "{11ED5F0A-0200-42AF-B5DF-B8BEC02C9624}" 5 0xFFFFFFFFFFFFFFFF
call :AddLiveProvider "{6FD2F1A8-C3D9-4A72-B122-30C6AD3E0A5F}" 5 0xFFFFFFFFFFFFFFFF
call :AddLiveProvider "{3168776E-0E5B-4B63-8F92-9D6C1B395166}" 5 0xFFFFFFFFFFFFFFFF
call :AddLiveProvider "{11BB6DA3-32F8-443D-886F-2811CD201BB7}" 5 0xFFFFFFFFFFFFFFFF
call :AddLiveProvider "{47711976-08C7-44EF-8FA2-082DA6A30A30}" 5 0xFFFFFFFFFFFFFFFF
call :AddLiveProvider "{E55D560E-55FA-47C3-A3EC-2AA0C319C2EF}" 5 0xFFFFFFFFFFFFFFFF
call :AddLiveProvider "{3804DC7C-C7BC-457D-8386-DB0BCB690358}" 5 0xFFFFFFFFFFFFFFFF
call :AddLiveProvider "{6E6CC2C5-8110-490E-9905-9F2ED700E455}" 5 0xFFFFFFFFFFFFFFFF
call :AddLiveProvider "{9F7711DD-29AD-C1EE-1B1B-B52A0118A54C}" 5 0xFFFFFFFFFFFFFFFF
call :AddLiveProvider "{6FB6E467-9ED4-4B73-8C22-70B97E22C7D9}" 5 0xFFFFFFFFFFFFFFFF
call :AddLiveProvider "{30E1D284-5D88-459C-83FD-6345B39B19EC}" 5 0xFFFFFFFFFFFFFFFF
call :AddLiveProvider "{3BBABCCA-A210-4570-B501-0E34D88A88FB}" 4 0xFFFFFFFFFFFFFFFF
call :AddLiveProvider "{D75AEDBE-CFCD-42B9-94AB-F47B224245DD}" 5 0xFFFFFFFFFFFFFFFF
call :AddLiveProvider "{BC6C9364-FC67-42C5-ACF7-ABED3B12ECC6}" 5 0xFFFFFFFFFFFFFFFF
call :AddLiveProvider "{EF201D1B-4E45-4199-9E9E-74591F447955}" 5 0xFFFFFFFFFFFFFFFF
call :AddLiveProvider "{C5964C90-1824-4835-857A-5E95F8AA33B2}" 5 0xFFFFFFFFFFFFFFFF
call :AddLiveProvider "{EAD1EE75-4BFE-4E28-8AFA-E94B0A1BAF37}" 5 0xFFFFFFFFFFFFFFFF
call :AddLiveProvider "{C500C63A-6EFE-433B-84A7-C0740D5DC97F}" 5 0xFFFFFFFFFFFFFFFF
call :AddLiveProvider "{EDEF8E04-4E22-4A95-9D04-539EBD112A5E}" 5 0xFFFFFFFFFFFFFFFF
call :AddLiveProvider "{8DEAEA72-4C63-49A4-9B8B-25DA24DAE056}" 5 0xFFFFFFFFFFFFFFFF
call :AddLiveProvider "{4921461B-27DE-4937-AC2D-96390848DDF4}" 5 0xFFFFFFFFFFFFFFFF
call :AddLiveProvider "{0F1ECE0C-1647-4051-B1BA-D3A0694E6B12}" 5 0xFFFFFFFFFFFFFFFF
call :AddLiveProvider "{468D9E9D-07F5-4537-B650-98389559206E}" 5 0xFFFFFFFFFFFFFFFF
call :AddLiveProvider "{8650230D-68B0-476E-93ED-634490DCE145}" 5 0xFFFFFFFFFFFFFFFF
call :AddLiveProvider "{04B3644B-27CA-4CAC-9243-29BED5C91CF9}" 5 0xFFFFFFFFFFFFFFFF
call :AddLiveProvider "{9C06E0CA-F00E-4AC3-A049-65663B654393}" 5 0xFFFFFFFFFFFFFFFF
call :AddLiveProvider "{C1330B70-D01E-4AA6-B30D-B2BDAF228EC3}" 5 0xFFFFFFFFFFFFFFFF
call :AddLiveProvider "{8FBF685A-DCE5-44C2-B126-5E90176993A7}" 5 0xFFFFFFFFFFFFFFFF
call :AddLiveProvider "{47C779CD-4EFD-49D7-9B10-9F16E5C25D06}" 5 0xFFFFFFFFFFFFFFFF
call :AddLiveProvider "{6465DA78-E7A0-4F39-B084-8F53C7C30DC6}" 5 0xFFFFFFFFFFFFFFFF
call :AddLiveProvider "{896F2806-9D0E-4D5F-AA25-7ACDBF4EAF2C}" 5 0xFFFFFFFFFFFFFFFF
call :AddLiveProvider "{E742C27D-29B1-4E4B-94EE-074D3AD72836}" 5 0xFFFFFFFFFFFFFFFF
call :AddLiveProvider "{07699FF6-D2C0-4323-B927-2C53442ED29B}" 5 0xFFFFFFFFFFFFFFFF
call :AddLiveProvider "{0107CF95-313A-473E-9078-E73CD932F2FE}" 5 0xFFFFFFFFFFFFFFFF
call :AddLiveProvider "{0A6B3BB2-3504-49C1-81D0-6A4B88B96427}" 5 0xFFFFFFFFFFFFFFFF
call :AddLiveProvider "{5ED8BB73-C76F-49D9-BF05-4982903C6CA5}" 5 0xFFFFFFFFFFFFFFFF
call :AddLiveProvider "{7FFB8EB8-2C86-45D6-A7C5-C023D9C070C1}" 5 0xFFFFFFFFFFFFFFFF
call :AddLiveProvider "{78396E52-9753-4D63-8CF5-A936B4989FF2}" 5 0xFFFFFFFFFFFFFFFF
call :AddLiveProvider "{51B2172F-205D-40C1-9A30-ED090FF72E6C}" 5 0xFFFFFFFFFFFFFFFF
call :AddLiveProvider "{5E11AB47-4E39-4D45-8BD5-C9C42AB9D1E6}" 5 0xFFFFFFFFFFFFFFFF
call :AddLiveProvider "{B41B0A56-4483-48EF-A772-0B007CBEA8C6}" 5 0xFFFFFFFFFFFFFFFF
call :AddLiveProvider "{09281F1F-F66E-485A-99A2-91638F782C49}" 5 0xFFFFFFFFFFFFFFFF
call :AddLiveProvider "{BBBC2565-8272-486E-B5E5-2BC4630374BA}" 5 0xFFFFFFFFFFFFFFFF
call :AddLiveProvider "{FC8DF8FD-D105-40A9-AF75-2EEC294ADF8C}" 5 0xFFFFFFFFFFFFFFFF
call :AddLiveProvider "{0AE46F43-B144-4056-9195-470054009D6C}" 5 0xFFFFFFFFFFFFFFFF
call :AddLiveProvider "{E6086B4D-AEFF-472B-BDA7-EEC662AFBF11}" 5 0xFFFFFFFFFFFFFFFF
call :AddLiveProvider "{13CF0A0A-50F6-4F4B-80EA-1B3121F5658C}" 5 0xFFFFFFFFFFFFFFFF
call :AddLiveProvider "{5A81715A-84C0-4DEF-AE38-EDDE40DF5B3A}" 5 0xFFFFFFFFFFFFFFFF
call :AddLiveProvider "{7E6B69B9-2AEC-4FB3-9426-69A0F2B61A86}" 5 0xFFFFFFFFFFFFFFFF
call :AddLiveProvider "{487D6E37-1B9D-46D3-A8FD-54CE8BDF8A53}" 5 0xFFFFFFFFFFFFFFFF
call :AddLiveProvider "{4A651CBB-7073-495F-9984-A2AE76C9EB58}" 5 0xFFFFFFFFFFFFFFFF
call :AddLiveProvider "{97413F1D-5298-4884-94EB-6FEFBC0AC4A7}" 5 0xFFFFFFFFFFFFFFFF

logman start -n %LiveSession% >nul 2>&1

echo.
echo ============================================================
echo   LOGGING ACTIVE
echo ============================================================
echo.
echo   Log directory : %LogDir%
echo   Started       : %date% %time%
echo.
echo   Logging persists through:
echo     [x] Sleep / Modern Standby
echo     [x] Hibernate
echo     [x] Reboot (autologger activates on boot)
echo.
echo   Live session captures immediately.
echo   After reboot, autologger takes over automatically.
echo.
echo   To stop logging and generate report:
echo     Run QCLogger-Stop.cmd as Administrator
echo ============================================================
echo.
pause
goto :eof

:: ============================================================================
:: Subroutines
:: ============================================================================

:AddProvider
:: %1 = GUID, %2 = Level, %3 = Keywords
reg add "%WmiKey%\%SessionName%\%~1" /v Enabled /t REG_DWORD /d 1 /f >nul
reg add "%WmiKey%\%SessionName%\%~1" /v EnableLevel /t REG_DWORD /d %~2 /f >nul
reg add "%WmiKey%\%SessionName%\%~1" /v MatchAnyKeyword /t REG_QWORD /d %~3 /f >nul
goto :eof

:AddLiveProvider
:: %1 = GUID, %2 = Level, %3 = Keywords
logman update trace -n %LiveSession% -p %~1 %~3 %~2 >nul 2>&1
goto :eof
