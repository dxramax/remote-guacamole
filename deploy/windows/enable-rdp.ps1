<#
.SYNOPSIS
Enables Windows Remote Desktop (RDP) and opens firewall rules.

.NOTES
Run in an elevated PowerShell session (Administrator).
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host 'Enabling RDP (fDenyTSConnections=0)...'
New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -PropertyType DWord -Value 0 -Force | Out-Null

Write-Host 'Enabling Remote Desktop firewall rules...'
Get-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue | Enable-NetFirewallRule | Out-Null

# Optional: ensure NLA stays default; uncomment to disable NLA if needed
# New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name 'UserAuthentication' -PropertyType DWord -Value 1 -Force | Out-Null

Write-Host 'RDP enabled. You may need to sign out/in for group policy to reflect.'

