@echo off
rem Run DevEco code linter (code-linter.json5 rules) via official DevEco CLI
cd /d "D:\harmony\helper_app\Application"
set DEVECO_CLI_STUDIO_PATH=D:\deveco\DevEco Studio
devecocli check lint
exit /b %errorlevel%