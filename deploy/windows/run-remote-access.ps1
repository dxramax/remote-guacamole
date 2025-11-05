param(
  [Parameter()] [string] $ServerUrl = 'wss://remote.alfaclouds.com/chisel',
  [Parameter()] [string] $Auth = 'guac:REDACTED',
  [Parameter()] [int] $RemotePort = 13389,
  [Parameter()] [switch] $Persist
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Info($m) { Write-Host ("[+] " + $m) }
function Write-Warn($m) { Write-Warning $m }
function Ensure-Admin {
  $current = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($current)
  if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host 'Elevating to Administrator...'
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -ServerUrl `"$ServerUrl`" -Auth `"$Auth`" -RemotePort $RemotePort " + ($(if ($Persist) { '-Persist' } else { '' }))
    $psi.Verb = 'runas'
    try {
      [System.Diagnostics.Process]::Start($psi) | Out-Null
      exit 0
    } catch {
      throw 'User cancelled elevation or elevation failed.'
    }
  }
}

Ensure-Admin

# 1) Enable RDP and firewall
Write-Info 'Enabling RDP and firewall rules'
New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -PropertyType DWord -Value 0 -Force | Out-Null
Get-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue | Enable-NetFirewallRule | Out-Null
Try { Start-Service -Name TermService -ErrorAction SilentlyContinue } Catch {}

# Verify RDP locally
$rdpTest = Test-NetConnection -ComputerName localhost -Port 3389
if (-not $rdpTest.TcpTestSucceeded) { Write-Warn 'Local RDP port 3389 not reachable. Ensure RDP service is running and no 3rd-party firewall blocks it.' }

# 2) Install chisel client
$base = 'C:\\ProgramData\\chisel'
New-Item -ItemType Directory -Force -Path $base | Out-Null
$exe = Join-Path $base 'chisel.exe'
if (-not (Test-Path $exe)) {
  Write-Info 'Downloading chisel client (HTTPS 443)'
  $gz = Join-Path $base 'chisel.gz'
  try {
    Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/jpillora/chisel/releases/download/v1.9.1/chisel_1.9.1_windows_amd64.gz' -OutFile $gz
    # Decompress GZip to EXE
    $in = [IO.File]::OpenRead($gz)
    try {
      $gzip = New-Object IO.Compression.GzipStream($in, [IO.Compression.CompressionMode]::Decompress)
      $out = [IO.File]::Create($exe)
      try { $gzip.CopyTo($out) } finally { $out.Dispose() }
    } finally { $in.Dispose() }
    Remove-Item $gz -Force -ErrorAction SilentlyContinue
  } catch {
    Write-Warn "Download failed: $($_.Exception.Message)"
    Write-Warn 'Manually download chisel from: https://github.com/jpillora/chisel/releases and place chisel.exe at C:\ProgramData\chisel\chisel.exe'
    throw
  }
}

# 3) Start chisel reverse client now
$args = @('client','--keepalive','30s','--auth',$Auth,$ServerUrl,"R:$RemotePort:127.0.0.1:3389")
Write-Info ("Starting chisel: {0} {1}" -f $exe, ($args -join ' '))
$proc = Start-Process -FilePath $exe -ArgumentList ($args -join ' ') -PassThru -WindowStyle Hidden
Start-Sleep -Seconds 3
if ($proc.HasExited) { Write-Warn "Chisel exited with code $($proc.ExitCode). Continue to persistence step or re-run with a visible window to see logs." }

# 4) Optional: make persistent for the current user
if ($Persist) {
  Write-Info 'Creating Scheduled Task (current user, run at logon and startup)'
  $taskName = 'Chisel-Reverse-RDP'
  $action = New-ScheduledTaskAction -Execute $exe -Argument ($args -join ' ')
  $trigger1 = New-ScheduledTaskTrigger -AtLogOn
  $trigger2 = New-ScheduledTaskTrigger -AtStartup
  $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -RunLevel Highest -LogonType Interactive
  $settings = New-ScheduledTaskSettingsSet -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew
  if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false | Out-Null }
  Register-ScheduledTask -TaskName $taskName -Action $action -Trigger @($trigger1,$trigger2) -Principal $principal -Settings $settings | Out-Null
  Start-ScheduledTask -TaskName $taskName | Out-Null
}

# 5) Connectivity hints
Write-Info 'If connection still fails:'
Write-Host '  - Confirm HTTPS to chisel endpoint:'
try {
  $testUrl = $ServerUrl -replace '^wss','https'
  $dummy = Invoke-WebRequest -UseBasicParsing -Method Head -Uri $testUrl -TimeoutSec 10
  Write-Host ("    HTTPS OK -> {0}" -f $testUrl)
} catch { Write-Warn ("    HTTPS check failed: {0}" -f $_.Exception.Message) }

Write-Host '  - Then open https://remote.alfaclouds.com/guacamole/ and click "Windows-Workstation"'
Write-Host '  - Keep this script running for a minute and retry if needed'

Write-Info 'Done.'

