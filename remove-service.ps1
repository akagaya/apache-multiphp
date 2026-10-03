#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
  Apache-multiPHP のサービスとファイアウォール規則を削除します。インストール先のファイルは削除しません。
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib\MultiPhp.psm1') -Force -DisableNameChecking

foreach ($service in @(Get-Service -Name 'multiphp-*' -ErrorAction SilentlyContinue)) {
  if ($service.Status -ne 'Stopped') { Stop-Service -Name $service.Name -Force }
  $result = Invoke-NativeCommand -FilePath 'sc.exe' -ArgumentList @('delete', $service.Name)
  if ($result.ExitCode -ne 0) {
    Write-Warning "$($service.Name) を削除できませんでした。`n$($result.Output -join "`n")"
  }
  else {
    Write-Host "削除: $($service.Name)"
  }
}
Remove-MultiPhpFirewallRule
