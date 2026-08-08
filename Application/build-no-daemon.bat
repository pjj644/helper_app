@echo off
setlocal
set JAVA_HOME=D:\deveco\DevEco Studio\jbr
set DEVECO_SDK_HOME=D:\deveco\DevEco Studio\sdk
set PATH=%JAVA_HOME%\bin;%PATH%
cd /d "%~dp0"
"D:\deveco\DevEco Studio\tools\hvigor\bin\hvigorw.bat" --no-daemon assembleHap %*
endlocal
