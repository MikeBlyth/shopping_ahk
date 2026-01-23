@echo off
echo Stopping Ruby Server on port 54567...

:: Kill process listening on port 54567
for /f "tokens=5" %%a in ('netstat -aon ^| find ":54567"') do (
  echo Found process %%a on port 54567, killing...
  taskkill /F /PID %%a
)

echo Done.
