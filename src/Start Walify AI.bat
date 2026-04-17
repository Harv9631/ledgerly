@echo off
title Walify AI
echo Closing old Walify AI...
taskkill /f /im electron.exe 2>nul
taskkill /f /im node.exe 2>nul
timeout /t 2 /nobreak >nul
cd /d C:\Users\harve\src
echo Starting Walify AI...
npx electron .
