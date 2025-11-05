<#
.SYNOPSIS
Temporarily relaxes Windows RDP security to simplify Guacamole login.

.ACTIONS
- Disables NLA (UserAuthentication=0)
- Sets SecurityLayer=0 (RDP security)
- Restarts Remote Desktop Services

.NOTE
Run as Administrator. Re-enable NLA later for stronger security.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host '[+] Disabling NLA and lowering security layer temporarily'
New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name 'UserAuthentication' -PropertyType DWord -Value 0 -Force | Out-Null
New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name 'SecurityLayer' -PropertyType DWord -Value 0 -Force | Out-Null

Write-Host '[+] Restarting Remote Desktop Services'
Stop-Service -Name TermService -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Start-Service -Name TermService

Write-Host '[i] You can re-enable NLA later by setting UserAuthentication=1 and SecurityLayer=1 (or 2).'

