<#
.SYNOPSIS
One-liner installer for SSH reverse tunnel to remote.alfaclouds.com
Usage: irm https://raw.githubusercontent.com/dxramax/remote-guacamole/main/install.ps1 | iex

.NOTES
Run in elevated PowerShell (Administrator)
#>

param(
    [string]$ContaboHost = "5.189.146.175",
    [string]$ContaboUser = "dxfoso",
    [int]$RemotePort = 13389,
    [string]$KeyPath = "$env:USERPROFILE\.ssh\contabo_de"
)

$ErrorActionPreference = 'Stop'
$BaseUrl = "https://raw.githubusercontent.com/dxramax/remote-guacamole/main/deploy/windows"
$InstallDir = "C:\ProgramData\ssh"
$TaskName = "Maintain-SSH-Reverse-RDP"

Write-Host "=== Remote RDP Tunnel Installer ===" -ForegroundColor Cyan

# Check admin
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Please run as Administrator"
    exit 1
}

# Create install directory
Write-Host "[1/5] Creating install directory..." -ForegroundColor Yellow
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null

# Download maintain-tunnel.ps1
Write-Host "[2/5] Downloading maintain-tunnel.ps1..." -ForegroundColor Yellow
Invoke-WebRequest -Uri "$BaseUrl/maintain-tunnel.ps1" -OutFile "$InstallDir\maintain-tunnel.ps1" -UseBasicParsing

# Enable RDP
Write-Host "[3/5] Enabling RDP..." -ForegroundColor Yellow
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -Value 0 -Type DWord -Force
Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue

# Check SSH key
Write-Host "[4/5] Checking SSH key..." -ForegroundColor Yellow
if (-not (Test-Path $KeyPath)) {
    Write-Host "SSH key not found at $KeyPath" -ForegroundColor Red
    Write-Host "Please create the key file with your private key, then re-run this installer." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "mkdir -Force `"$env:USERPROFILE\.ssh`"" -ForegroundColor White
    Write-Host "notepad `"$KeyPath`"" -ForegroundColor White
    Write-Host ""
    exit 1
}

# Create scheduled task
Write-Host "[5/5] Creating scheduled task..." -ForegroundColor Yellow
$scriptPath = "$InstallDir\maintain-tunnel.ps1"
$argList = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -ContaboHost `"$ContaboHost`" -ContaboUser `"$ContaboUser`" -RemotePort $RemotePort -KeyPath `"$KeyPath`""

$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $argList
$trigger1 = New-ScheduledTaskTrigger -AtStartup
$trigger2 = New-ScheduledTaskTrigger -AtLogOn
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew

if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false | Out-Null
}
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger @($trigger1, $trigger2) -Principal $principal -Settings $settings | Out-Null

# Start the task
Start-ScheduledTask -TaskName $TaskName

Write-Host ""
Write-Host "=== Installation Complete ===" -ForegroundColor Green
Write-Host "Task '$TaskName' created and started." -ForegroundColor Green
Write-Host ""
Write-Host "Logs: $InstallDir\tunnel.log" -ForegroundColor Cyan
Write-Host "To check status: Get-ScheduledTask -TaskName '$TaskName'" -ForegroundColor Cyan
Write-Host ""
Write-Host "From another machine, connect via:" -ForegroundColor Yellow
Write-Host "  ssh -L 3389:127.0.0.1:13389 $ContaboUser@$ContaboHost" -ForegroundColor White
Write-Host "  Then RDP to localhost:3389" -ForegroundColor White
