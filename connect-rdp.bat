@echo off
echo Starting RDP tunnel to workstation...
echo.
echo After connected, open Remote Desktop and connect to: localhost:3389
echo.
start "" mstsc /v:localhost:3389
ssh -L 3389:127.0.0.1:13389 -i "%USERPROFILE%\.ssh\contabo_de" dxfoso@5.189.146.175
pause
