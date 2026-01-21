param(
  [Parameter()] [string] $ContaboHost = '5.189.146.175',
  [Parameter()] [string] $ContaboUser = 'dxfoso',
  [Parameter()] [int] $RemotePort = 13389,
  [Parameter()] [string] $KeyPath = "$env:USERPROFILE\.ssh\contabo_de",
  [Parameter()] [switch] $Persist
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Ensure-Admin {
  $current = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($current)
  if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host 'Elevating to Administrator...'
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -ContaboHost `"$ContaboHost`" -ContaboUser `"$ContaboUser`" -RemotePort $RemotePort -KeyPath `"$KeyPath`" " + ($(if ($Persist) { '-Persist' } else { '' }))
    $psi.Verb = 'runas'
    try { [System.Diagnostics.Process]::Start($psi) | Out-Null; exit 0 } catch { throw 'Elevation failed or cancelled.' }
  }
}

Ensure-Admin

Write-Host '[+] Enabling RDP and firewall'
New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -PropertyType DWord -Value 0 -Force | Out-Null
Get-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue | Enable-NetFirewallRule | Out-Null
Try { Start-Service -Name TermService -ErrorAction SilentlyContinue } Catch {}

if (-not (Test-Path $KeyPath)) { throw "Key not found: $KeyPath" }

$ssh = 'C:\\Windows\\System32\\OpenSSH\\ssh.exe'
if (-not (Test-Path $ssh)) { throw 'OpenSSH client not found. Install with: Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0' }

function New-SshArgs($bindLocalLoopback) {
  $r = if ($bindLocalLoopback) { "127.0.0.1:$RemotePort:localhost:3389" } else { "$RemotePort:localhost:3389" }
  @(
    '-NT',
    '-o','ExitOnForwardFailure=yes',
    '-o','ServerAliveInterval=30',
    '-o','ServerAliveCountMax=3',
    '-o','StrictHostKeyChecking=accept-new',
    '-i',"$KeyPath",
    '-R', $r,
    "$ContaboUser@$ContaboHost"
  )
}

$argsPrimary = New-SshArgs $true     # -R 127.0.0.1:PORT:localhost:3389 (preferred)
$argsFallback = New-SshArgs $false    # -R PORT:localhost:3389 (compatibility)

if ($Persist) {
  Write-Host '[+] Creating Scheduled Task under current user (run at logon & startup)'
  $task = 'SSH-Reverse-RDP'
  # Prefer config-based invocation to avoid quoting issues
  $cfgDir = Join-Path $env:USERPROFILE '.ssh'
  if (-not (Test-Path $cfgDir)) { New-Item -ItemType Directory -Path $cfgDir -Force | Out-Null }
  $cfg = Join-Path $cfgDir 'config'
  $hostAlias = 'contabo_rev'
  $block = @(
    "Host $hostAlias",
    "  HostName $ContaboHost",
    "  User $ContaboUser",
    "  IdentityFile $KeyPath",
    "  ExitOnForwardFailure yes",
    "  ServerAliveInterval 30",
    "  ServerAliveCountMax 3",
    "  RemoteForward $RemotePort localhost:3389",
    "  StrictHostKeyChecking accept-new"
  ) -join "`r`n"
  Add-Content -Path $cfg -Value ("`r`n" + $block + "`r`n")
  $action = New-ScheduledTaskAction -Execute $ssh -Argument "-NT $hostAlias"
  $trigger1 = New-ScheduledTaskTrigger -AtLogOn
  $trigger2 = New-ScheduledTaskTrigger -AtStartup
  $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -RunLevel Highest -LogonType Interactive
  $settings = New-ScheduledTaskSettingsSet -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew
  if (Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue) { Unregister-ScheduledTask -TaskName $task -Confirm:$false | Out-Null }
  Register-ScheduledTask -TaskName $task -Action $action -Trigger @($trigger1,$trigger2) -Principal $principal -Settings $settings | Out-Null
  Start-ScheduledTask -TaskName $task | Out-Null
  Write-Host '[+] Task created. It may take a few seconds to establish the tunnel.'
  Write-Host '    To view running ssh processes: Get-CimInstance Win32_Process -Filter "Name=''ssh.exe''" | Select ProcessId,CommandLine'
} else {
  Write-Host '[+] Starting reverse SSH tunnel in foreground (leave this window open)'
  $cfgDir = Join-Path $env:USERPROFILE '.ssh'
  if (-not (Test-Path $cfgDir)) { New-Item -ItemType Directory -Path $cfgDir -Force | Out-Null }
  $cfg = Join-Path $cfgDir 'config'
  $hostAlias = 'contabo_rev'
  $block = @(
    "Host $hostAlias",
    "  HostName $ContaboHost",
    "  User $ContaboUser",
    "  IdentityFile $KeyPath",
    "  ExitOnForwardFailure yes",
    "  ServerAliveInterval 30",
    "  ServerAliveCountMax 3",
    "  RemoteForward $RemotePort localhost:3389",
    "  StrictHostKeyChecking accept-new"
  ) -join "`r`n"
  Add-Content -Path $cfg -Value ("`r`n" + $block + "`r`n")
  & $ssh -NT $hostAlias
  if ($LASTEXITCODE -ne 0) {
    Write-Warning 'Alias form failed, retrying with direct -R syntax'
    & $ssh @argsPrimary
    if ($LASTEXITCODE -ne 0) {
      Write-Warning "Primary -R failed, retrying fallback -R $RemotePort:localhost:3389"
      & $ssh @argsFallback
    }
  }
}

Write-Host '[i] If Guacamole still says unreachable, verify on server:'
Write-Host '    ssh contabo_de "ss -ltn | grep 13389 || echo not listening"'
