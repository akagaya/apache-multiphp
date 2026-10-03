#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
  Apache-multiPHP のサービスを停止し、起動種別を手動にします。

.PARAMETER php
  対象を絞る場合に指定します（例: 8.4 / php84 / static）。省略時はすべて。
#>
[CmdletBinding()]
param(
  [string[]]$php
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib\MultiPhp.psm1') -Force -DisableNameChecking

$names = if ($php) { @($php | ForEach-Object { Get-ServiceNameForId (Resolve-PhpId $_) }) } else { @('multiphp-*') }
foreach ($service in @(Get-Service -Name $names -ErrorAction SilentlyContinue)) {
  Write-Host "停止: $($service.Name)"
  Stop-Service -Name $service.Name -Force
  Set-Service -Name $service.Name -StartupType Manual
}
