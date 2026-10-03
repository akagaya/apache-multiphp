#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
  new-site.ps1 で払い出したサイトを無効化します。

.DESCRIPTION
  サイトの conf を <サイト名>.removed-<日時> に改名して読み込み対象から外し、該当サービスを再起動します。
  ドキュメントルートとログは削除しません。元に戻す場合は、改名したファイルを <サイト名>.conf に戻してサービスを再起動してください。

.PARAMETER name
  サイト名

.PARAMETER installPath
  インストール先。既定値は .\server

.PARAMETER noRestart
  サービスを再起動しません。
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$name,
  [string]$installPath = '.\server',
  [switch]$noRestart
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib\MultiPhp.psm1') -Force -DisableNameChecking

$installPath = (Resolve-Path -LiteralPath $installPath).ProviderPath.TrimEnd('\')
$site = @(Get-SiteConfiguration -InstallPath $installPath | Where-Object { $_.Site -eq $name }) | Select-Object -First 1
if (-not $site) { throw "サイト '$name' が見つかりません。" }
if ($name -eq 'default') { throw 'default はサービス既定のサイトのため無効化できません。' }

$disabled = '{0}.removed-{1:yyyyMMddHHmmss}' -f $site.Site, (Get-Date)
Rename-Item -LiteralPath $site.File -NewName $disabled
Write-Host "無効化: $($site.File) -> $disabled"

$serviceName = Get-ServiceNameForId $site.Id
if (-not $noRestart) {
  $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
  if ($service -and $service.Status -eq 'Running') { Restart-Service -Name $serviceName -Force }
}
Write-Host "ドキュメントルートは残しています: $($site.DocumentRoot)"
