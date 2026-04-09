@echo off
title Ledgerly
echo Closing old Ledgerly...
taskkill /f /im electron.exe 2>nul
taskkill /f /im node.exe 2>nul
timeout /t 2 /nobreak >nul
cd /d C:\Users\harve\src
echo Starting Ledgerly...
npx electron .
