@echo off
setlocal
chcp 65001 >nul
set "ROOT=%LOCALAPPDATA%\ZHSDesktop"
set "PY=%ROOT%\.venv\Scripts\python.exe"
set "ZHS=%ROOT%\.venv\Scripts\zhs.exe"
set "HELPER=%ROOT%\zhidao_only.py"
if not exist "%ROOT%\privacy-accepted-v5.2.7.flag" (
  echo [CONSENT] Please open the GUI and accept the privacy notice first.
  exit /b 2
)
if not exist "%PY%" (
  echo [ENV] The app-local Python runtime is missing. Reinstall the app.
  exit /b 5
)
if not exist "%HELPER%" (
  echo [ENV] The course reader is missing. Reinstall the app.
  exit /b 5
)
cd /d "%USERPROFILE%"
if errorlevel 1 exit /b 5
if /I "%~1"=="doctor" goto doctor
if /I "%~1"=="login" goto login
if /I "%~1"=="courses" goto courses
if /I "%~1"=="progress" goto progress
if /I "%~1"=="play-ai" goto playai
echo [INVALID] Unsupported task. Use doctor, login, courses or progress.
exit /b 2

:doctor
"%PY%" "%HELPER%" doctor-server
exit /b %ERRORLEVEL%

:login
if not exist "%ZHS%" (
  echo [ENV] ZHS entrypoint is missing. Reinstall the app.
  exit /b 5
)
"%ZHS%" login
exit /b %ERRORLEVEL%

:courses
"%PY%" "%HELPER%" courses
exit /b %ERRORLEVEL%

:progress
"%PY%" "%HELPER%" progress
exit /b %ERRORLEVEL%

:playai
if not exist "%ZHS%" (
  echo [ENV] ZHS executable is missing. Reinstall the app.
  exit /b 5
)
if "%~2"=="" goto badplayargs
if "%~3"=="" goto badplayargs
REM Optional console observer preserves original interactive output and reports
REM only numeric progress. Missing observer falls back to the exact ZHS CLI.
REM No retry is attempted after observer invocation.
if "%~4"=="" goto originalplay
if not exist "%ROOT%\ZHS-ConsoleMonitor.py" goto originalplay
"%PY%" "%ROOT%\ZHS-ConsoleMonitor.py" "%~4" "%~2" "%~3"
exit /b %ERRORLEVEL%

:originalplay
REM Legacy upstream ZHS 0.1.5 CLI. Request generation and sending remain untouched.
"%ZHS%" play -c "%~2:%~3" --type ai
exit /b %ERRORLEVEL%

:badplayargs
echo [INVALID] Missing courseId or classId. No task was started.
exit /b 2
