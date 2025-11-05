param(
  [Parameter()] [int] $RemotePort = 13389,
  [Parameter()] [switch] $RelaxRdp
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host '[setup-local] Enabling RDP and firewall'
powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'windows/enable-rdp.ps1')

if ($RelaxRdp) {
  Write-Host '[setup-local] Relaxing RDP (disable NLA)'
  powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'windows/relax-rdp.ps1')
}

Write-Host '[setup-local] Installing persistent reverse SSH tunnel (Scheduled Task)'
powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'windows/run-ssh-reverse.ps1') -RemotePort $RemotePort -Persist

Write-Host '[setup-local] Done. The tunnel will run in the background at logon/startup.'

