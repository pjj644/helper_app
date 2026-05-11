@echo off
set "JAVA_HOME=D:\deveco\DevEco Studio\jbr"
set "DEVECO_SDK_HOME=D:\deveco\DevEco Studio\sdk"
set "OHOS_SDK_HOME=D:\deveco\DevEco Studio\sdk\default\openharmony"
set "PATH=D:\deveco\DevEco Studio\tools\hvigor\bin;D:\deveco\DevEco Studio\jbr\bin;%PATH%"
cd /d "D:\harmony\helper_app\Application"
call hvigorw.bat assembleHap
