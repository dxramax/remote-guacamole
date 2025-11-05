param(
  [Parameter(Mandatory=$true)] [string] $Username,
  [Parameter(Mandatory=$true)] [SecureString] $Password,
  [Parameter()] [switch] $AddToAdministrators
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (Get-LocalUser -Name $Username -ErrorAction SilentlyContinue) {
  Write-Host "[i] User '$Username' already exists"
} else {
  Write-Host "[+] Creating local user '$Username'"
  New-LocalUser -Name $Username -Password $Password -PasswordNeverExpires -AccountNeverExpires | Out-Null
}

Write-Host "[+] Adding '$Username' to 'Remote Desktop Users'"
Add-LocalGroupMember -Group 'Remote Desktop Users' -Member $Username -ErrorAction SilentlyContinue

if ($AddToAdministrators) {
  Write-Host "[+] Adding '$Username' to 'Administrators'"
  Add-LocalGroupMember -Group 'Administrators' -Member $Username -ErrorAction SilentlyContinue
}

Write-Host '[i] Use .\'"$Username"' as the username in Guacamole.'

