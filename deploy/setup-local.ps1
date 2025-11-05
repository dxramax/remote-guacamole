param(
  [Parameter()] [int] $RemotePort = 13389,
  [Parameter()] [string] $RemoteAlias = 'contabo_de',
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

Write-Host '[setup-local] Verifying server listener comes up...'
$maxTries = 10
for ($i=1; $i -le $maxTries; $i++) {
  try {
    $out = ssh $RemoteAlias "ss -ltn | grep ':$RemotePort' || netstat -ltn 2>/dev/null | grep ':$RemotePort' || echo not_listening"
  } catch { $out = 'not_listening' }
  if ($out -and ($out -notmatch 'not_listening')) { Write-Host "[setup-local] Tunnel UP on server 127.0.0.1:$RemotePort"; break }
  Start-Sleep -Seconds 3
  if ($i -eq $maxTries) { Write-Warning "[setup-local] Tunnel not detected yet on server. It may take a few more seconds or check Scheduled Task status." }
}

Write-Host '[setup-local] Done. The tunnel will run in the background at logon/startup.'
