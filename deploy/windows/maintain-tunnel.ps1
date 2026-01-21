param(
  [Parameter(Mandatory=$true)] [string] $ContaboHost,
  [Parameter(Mandatory=$true)] [string] $ContaboUser,
  [Parameter(Mandatory=$false)] [int] $RemotePort = 13389,
  [Parameter(Mandatory=$false)] [string] $KeyPath,
  [Parameter(Mandatory=$false)] [string] $KnownHostsPath = "C:\\ProgramData\\ssh\\known_hosts"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try { New-Item -ItemType Directory -Path 'C:\\ProgramData\\ssh' -Force | Out-Null } catch {}
$LogPath = 'C:\\ProgramData\\ssh\\tunnel.log'
function Write-Log { param([string]$m) Add-Content -Path $LogPath -Value ("{0} {1}" -f (Get-Date -Format o), $m) }

function Test-Command($Name) {
  $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

if (-not (Test-Command 'ssh')) {
  Write-Error 'OpenSSH client not found. Install with: Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0'
}

$khDir = Split-Path -Parent $KnownHostsPath
if (-not (Test-Path $khDir)) { New-Item -ItemType Directory -Path $khDir -Force | Out-Null }
if (-not (Test-Path $KnownHostsPath)) { New-Item -ItemType File -Path $KnownHostsPath -Force | Out-Null }

$keyArg = ''
if ($KeyPath -and (Test-Path $KeyPath)) { $keyArg = "-i `"$KeyPath`"" }

Write-Host "Maintaining reverse tunnel to $ContaboUser@$ContaboHost (remote 127.0.0.1:$RemotePort -> local 3389)"
Write-Log "Starting tunnel to $ContaboUser@$ContaboHost:$RemotePort with key '$KeyPath'"

$sshExe = (Get-Command ssh -ErrorAction SilentlyContinue).Source
if (-not $sshExe) { $sshExe = 'C:\\Windows\\System32\\OpenSSH\\ssh.exe' }
Write-Log "Using ssh exe: $sshExe"

while ($true) {
  $cmd = @(
    $sshExe,'-NT',
    '-o','ExitOnForwardFailure=yes',
    '-o','ServerAliveInterval=30',
    '-o','ServerAliveCountMax=3',
    '-o','StrictHostKeyChecking=accept-new',
    '-o',"UserKnownHostsFile=$KnownHostsPath",
    '-R',"127.0.0.1:$RemotePort:localhost:3389",
    "$ContaboUser@$ContaboHost"
  )
  if ($keyArg) { $cmd += @('-i', $KeyPath) }
  Write-Log ("Exec: {0} {1}" -f $cmd[0], ($cmd[1..($cmd.Count-1)] -join ' '))
  try {
    & $cmd[0] @($cmd[1..($cmd.Count-1)])
    $code = $LASTEXITCODE
    Write-Log ("ssh exited code {0}" -f $code)
  } catch {
    Write-Log ("ssh error: {0}" -f $_.Exception.Message)
  }
  Start-Sleep -Seconds 5
}
