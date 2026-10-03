#Requires -Version 5.1
<#
.SYNOPSIS
  サイトの一覧を、設定上のポートと実際の待ち受け状況を突き合わせて表示します。

.DESCRIPTION
  apache\conf\extra\enable-*\*.conf の Listen と DocumentRoot（define.conf の変数を展開）を読み、
  サービスの状態と、そのポートを httpd が実際に待ち受けているかを併せて返します。
  結果はオブジェクトとして出力されるため、Export-Csv や ConvertTo-Json にそのまま渡せます。

.PARAMETER installPath
  インストール先。既定値は .\server

.EXAMPLE
  .\get-sites.ps1 | Format-Table

.EXAMPLE
  .\get-sites.ps1 | Export-Csv sites.csv -NoTypeInformation -Encoding UTF8
#>
[CmdletBinding()]
param(
  [string]$installPath = '.\server'
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib\MultiPhp.psm1') -Force -DisableNameChecking

$installPath = (Resolve-Path -LiteralPath $installPath).ProviderPath.TrimEnd('\')

$services = @{}
foreach ($service in @(Get-Service -Name 'multiphp-*' -ErrorAction SilentlyContinue)) {
  $services[$service.Name] = [string]$service.Status
}

$httpdPids = @(Get-Process -Name 'httpd' -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })
$listening = @{}
foreach ($entry in @(Get-ListeningPort)) {
  $owner = 'other'
  if ($httpdPids -contains $entry.ProcessId) { $owner = 'httpd' }
  if (-not $listening.ContainsKey($entry.Port) -or $owner -eq 'httpd') { $listening[$entry.Port] = $owner }
}

foreach ($site in @(Get-SiteConfiguration -InstallPath $installPath | Sort-Object Port)) {
  $serviceName = Get-ServiceNameForId $site.Id
  $status = 'NotInstalled'
  if ($services.ContainsKey($serviceName)) { $status = $services[$serviceName] }
  $listen = 'No'
  if ($listening.ContainsKey($site.Port)) {
    if ($listening[$site.Port] -eq 'httpd') { $listen = 'Yes' } else { $listen = 'OtherProcess' }
  }
  [pscustomobject]@{
    Port         = $site.Port
    Php          = $site.Id
    Site         = $site.Site
    Service      = $serviceName
    Status       = $status
    Listening    = $listen
    DocumentRoot = $site.DocumentRoot
  }
}
