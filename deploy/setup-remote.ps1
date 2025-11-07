param(
  [Parameter()] [string] $RemoteAlias = 'contabo_de'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "[setup-remote] Copying manifests and scripts to ${RemoteAlias}:/tmp/remote-setup"
scp -r deploy ${RemoteAlias}:/tmp/remote-setup | Out-Null

Write-Host "[setup-remote] Running remote bootstrap"
ssh $RemoteAlias "bash -lc 'chmod +x /tmp/remote-setup/deploy/server/bootstrap.sh && /tmp/remote-setup/deploy/server/bootstrap.sh'"

Write-Host '[setup-remote] Done.'

