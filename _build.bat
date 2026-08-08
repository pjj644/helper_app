@echo off
rem Incremental debug build. Prefer official DevEco CLI, fallback to hvigorw.bat
cd /d "D:\harmony\helper_app\Application"

where devecocli >nul 2>nul
if %errorlevel%==0 goto :cli

set JAVA_HOME=D:\deveco\DevEco Studio\jbr
set DEVECO_SDK_HOME=D:\deveco\DevEco Studio\sdk
set PATH=%JAVA_HOME%\bin;%PATH%
"D:\deveco\DevEco Studio\tools\hvigor\bin\hvigorw.bat" --no-daemon assembleHap
exit /b %errorlevel%

:cli
set DEVECO_CLI_STUDIO_PATH=D:\deveco\DevEco Studio
devecocli build --modules entry@default --build-mode debug
exit /b %errorlevel%