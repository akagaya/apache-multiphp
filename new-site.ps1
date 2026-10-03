#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
  指定した PHP バージョンで動くサイトを、専用ポートの VirtualHost として払い出します。

.DESCRIPTION
  apache\conf\extra\enable-<識別子>\<サイト名>.conf を作成し、構成テストに通れば該当サービスを再起動します。
  構成テストに失敗した場合は作成した conf を取り消します。

.PARAMETER name
  サイト名（英数字・ハイフン・アンダースコア）。conf とログのファイル名に使います。

.PARAMETER php
  PHP バージョン（例: 8.4 / php84）。PHP を使わない場合は static。

.PARAMETER port
  待ち受けポート。省略時は -portRangeStart 以降で、設定済みでも使用中でもないポートを選びます。

.PARAMETER documentRoot
  ドキュメントルート。省略時は <インストール先>\sites\<サイト名> を作成します。

.PARAMETER installPath
  インストール先。既定値は .\server

.PARAMETER portRangeStart
  ポート自動選択の開始番号。既定値は 30000

.PARAMETER noRestart
  サービスを再起動しません。

.EXAMPLE
  .\new-site.ps1 -name project-a -php 7.4
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_-]*$')][string]$name,
  [Parameter(Mandatory)][string]$php,
  [ValidateRange(1, 65535)][int]$port,
  [string]$documentRoot,
  [string]$installPath = '.\server',
  [ValidateRange(1024, 65535)][int]$portRangeStart = 30000,
  [switch]$noRestart
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib\MultiPhp.psm1') -Force -DisableNameChecking

$installPath = (Resolve-Path -LiteralPath $installPath).ProviderPath.TrimEnd('\')
$id = Resolve-PhpId $php
$siteDir = Join-Path $installPath "apache\conf\extra\enable-$id"
if (-not (Test-Path -LiteralPath $siteDir)) {
  throw "$id はインストールされていません（$siteDir がありません）。"
}

$configured = @(Get-SiteConfiguration -InstallPath $installPath)
$duplicate = @($configured | Where-Object { $_.Site -eq $name })
if ($duplicate.Count -gt 0) {
  throw "サイト '$name' は既に存在します: $($duplicate[0].File)"
}

$usedPorts = @($configured | ForEach-Object { $_.Port }) + @(Get-ListeningPort | ForEach-Object { $_.Port })
if ($port) {
  if ($usedPorts -contains $port) { throw "ポート $port は設定済みか使用中です。" }
}
else {
  $port = Find-FreePort -Start $portRangeStart -Used $usedPorts
}

$createdRoot = $false
if (-not $documentRoot) {
  $documentRoot = Join-Path $installPath "sites\$name"
}
$documentRoot = Get-FullPath $documentRoot
if (-not (Test-Path -LiteralPath $documentRoot)) {
  New-Item -ItemType Directory -Path $documentRoot -Force | Out-Null
  $createdRoot = $true
  if ($id -eq 'static') {
    Write-TextFile -Path (Join-Path $documentRoot 'index.html') -Lines @("<!doctype html><title>$name</title><p>$name</p>")
  }
  else {
    Write-TextFile -Path (Join-Path $documentRoot 'index.php') -Lines @('<?php', "echo '${name}: PHP ' . PHP_VERSION;")
  }
}

$confPath = Join-Path $siteDir "$name.conf"
Write-TextFile -Path $confPath -Lines (New-SiteConfig -Name $name -Id $id -Port $port -DocumentRoot $documentRoot)

$test = Test-HttpdConfig -InstallPath $installPath -Id $id
if (-not $test.Success) {
  Remove-Item -LiteralPath $confPath -Force
  throw "構成テストに失敗したため、サイトの作成を取り消しました。`n$($test.Output -join "`n")"
}

$serviceName = Get-ServiceNameForId $id
if (-not $noRestart) {
  $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
  if (-not $service) {
    Write-Warning "サービス $serviceName が登録されていません。install.ps1 を実行してください。"
  }
  elseif ($service.Status -eq 'Running') {
    Restart-Service -Name $serviceName -Force
  }
  else {
    Start-Service -Name $serviceName
  }
}

Write-Host ''
Write-Host "サイト '$name' を作成しました。" -ForegroundColor Green
[pscustomobject]@{
  Site         = $name
  Service      = $serviceName
  Url          = "http://$([Environment]::MachineName):$port/"
  DocumentRoot = $documentRoot
  Config       = $confPath
  NewRoot      = $createdRoot
}
