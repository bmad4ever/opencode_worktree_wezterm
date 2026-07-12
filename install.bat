@echo off
set cfg=%USERPROFILE%\.config\opencode

mkdir "%cfg%\commands" 2>nul
mkdir "%cfg%\scripts" 2>nul
mkdir "%cfg%\plugins" 2>nul

copy /Y ".opencode\commands\*.md" "%cfg%\commands\" >nul 2>&1
copy /Y ".opencode\scripts\*.ps1" "%cfg%\scripts\" >nul 2>&1
copy /Y ".opencode\plugins\*.js" "%cfg%\plugins\" >nul 2>&1

echo Script executed successfully.