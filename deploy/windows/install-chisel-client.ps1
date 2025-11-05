param(
  [Parameter()] [string] $ServerUrl = 'wss://remote.alfaclouds.com/chisel',
  [Parameter()] [string] $Auth = 'guac:change_me_chisel',
  [Parameter()] [int] $RemotePort = 13389,
  [Parameter()] [switch] $InstallOnly,
  [Parameter()] [switch] $RunAsScheduledTask
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$dir = 'C:\\ProgramData\\chisel'
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
$exe = Join-Path $dir 'chisel.exe'
$gz = Join-Path $dir 'chisel.gz'

if (-not (Test-Path $exe)) {
  Write-Host 'Downloading chisel client...'
  Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/jpillora/chisel/releases/download/v1.9.1/chisel_1.9.1_windows_amd64.gz' -OutFile $gz
  certutil -f -decode $gz $exe | Out-Null
}

$cmdArgs = @('client','--keepalive','30s','--auth',$Auth,$ServerUrl,"R:$RemotePort:127.0.0.1:3389")

if ($RunAsScheduledTask) {
  $task = 'Chisel-Reverse-RDP'
  $action = New-ScheduledTaskAction -Execute $exe -Argument ($cmdArgs -join ' ')
  $trigger1 = New-ScheduledTaskTrigger -AtLogOn
  $trigger2 = New-ScheduledTaskTrigger -AtStartup
  $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -RunLevel Highest -LogonType Interactive
  $settings = New-ScheduledTaskSettingsSet -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew
  if (Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue) { Unregister-ScheduledTask -TaskName $task -Confirm:$false | Out-Null }
  Register-ScheduledTask -TaskName $task -Action $action -Trigger @($trigger1,$trigger2) -Principal $principal -Settings $settings | Out-Null
  Start-ScheduledTask -TaskName $task | Out-Null
  Write-Host "Scheduled task '$task' created and started."
}

if (-not $InstallOnly) {
  Write-Host 'Starting chisel client now...'
  & $exe @($cmdArgs)
}

