param(
  [Parameter(Mandatory=$true)] [string] $ContaboHost,
  [Parameter(Mandatory=$true)] [string] $ContaboUser,
  [Parameter()] [int] $RemotePort = 13389,
  [Parameter()] [string] $KeyPath,
  [Parameter()] [string] $KnownHostsPath = "C:\\ProgramData\\ssh\\known_hosts",
  [Parameter()] [switch] $RunAsCurrentUser
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$taskName = 'Maintain-SSH-Reverse-RDP'
$preferred = Join-Path 'C:\\ProgramData\\ssh' 'maintain-tunnel.ps1'
if (Test-Path $preferred) {
  $scriptPath = $preferred
} else {
  $scriptPath = Join-Path $PSScriptRoot 'maintain-tunnel.ps1'
}

if (-not (Test-Path $scriptPath)) {
  Write-Error "Cannot find maintain-tunnel.ps1 at $scriptPath"
}

$argList = @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$scriptPath`"",'-ContaboHost',"`"$ContaboHost`"",'-ContaboUser',"`"$ContaboUser`"",'-RemotePort',"$RemotePort",'-KnownHostsPath',"`"$KnownHostsPath`"")
if ($KeyPath) { $argList += @('-KeyPath',"`"$KeyPath`"") }

$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ($argList -join ' ')
$trigger1 = New-ScheduledTaskTrigger -AtStartup
$trigger2 = New-ScheduledTaskTrigger -AtLogOn
$principal = if ($RunAsCurrentUser) {
  New-ScheduledTaskPrincipal -UserId $env:USERNAME -RunLevel Highest -LogonType Interactive
} else {
  New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest
}
$settings = New-ScheduledTaskSettingsSet -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew

try {
  if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false | Out-Null
  }
  Register-ScheduledTask -TaskName $taskName -Action $action -Trigger @($trigger1,$trigger2) -Principal $principal -Settings $settings | Out-Null
  Start-ScheduledTask -TaskName $taskName | Out-Null
  Write-Host "Scheduled task '$taskName' created and started."
} catch {
  Write-Error $_
}
