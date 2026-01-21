param(
  [Parameter(Mandatory=$true)] [string] $ContaboHost,
  [Parameter(Mandatory=$true)] [string] $ContaboUser,
  [Parameter()] [int] $RemotePort = 13389,
  [Parameter(Mandatory=$true)] [string] $KeyPath,
  [Parameter()] [string] $KnownHostsPath = "C:\\ProgramData\\ssh\\known_hosts",
  [Parameter()] [switch] $RunAsCurrentUser
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path $KeyPath)) { throw "Key not found: $KeyPath" }
$key = Resolve-Path -LiteralPath $KeyPath
if (-not (Test-Path $KnownHostsPath)) { New-Item -ItemType File -Path $KnownHostsPath -Force | Out-Null }

$taskName = 'Maintain-SSH-Reverse-RDP-Direct'
$ssh = 'C:\\Windows\\System32\\OpenSSH\\ssh.exe'
$args = @('
  -NT',
  '-o','ExitOnForwardFailure=yes',
  '-o','ServerAliveInterval=30',
  '-o','ServerAliveCountMax=3',
  '-o','StrictHostKeyChecking=accept-new',
  '-o',"UserKnownHostsFile=$KnownHostsPath",
  '-i',"$key",
  '-R',"127.0.0.1:$RemotePort:localhost:3389",
  "$ContaboUser@$ContaboHost"
) -join ' '

$action = New-ScheduledTaskAction -Execute $ssh -Argument $args
$trigger1 = New-ScheduledTaskTrigger -AtLogOn
$trigger2 = New-ScheduledTaskTrigger -AtStartup
$principal = if ($RunAsCurrentUser) {
  New-ScheduledTaskPrincipal -UserId $env:USERNAME -RunLevel Highest -LogonType Interactive
} else {
  New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest
}
$settings = New-ScheduledTaskSettingsSet -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew

if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
  Unregister-ScheduledTask -TaskName $taskName -Confirm:$false | Out-Null
}

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger @($trigger1,$trigger2) -Principal $principal -Settings $settings | Out-Null
Start-ScheduledTask -TaskName $taskName | Out-Null
Write-Host "Scheduled task '$taskName' created and started."

