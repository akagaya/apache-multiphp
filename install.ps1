#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
  Apache HTTPD と複数バージョンの PHP をインストール（更新）し、PHP バージョンごとに Windows サービスを登録します。

.DESCRIPTION
  新規インストールと更新は同じ操作です。更新時の扱いは次のとおりです。
  - バイナリ（Apache / PHP / Xdebug）は最新版で上書きします。
  - ツール管理の設定（conf\extra\php-loader.conf、conf\extra\php\*.conf）は毎回再生成します。
  - 利用者の設定（httpd.conf などの conf、define.conf、conf\extra\enable-*\、php.ini）は存在しない場合のみ作成します。
  - 登録済みのサービスは作り直さず、起動種別を維持します。更新前に稼働していたサービスと新規サービスを起動します。

.PARAMETER installPath
  インストール先。既定値は .\server

.PARAMETER arch
  x64（既定）または x86

.PARAMETER xdebug
  Xdebug を導入するか。既定値は $true

.PARAMETER phpVersions
  導入する PHP のマイナーバージョン（例: 7.4,8.3,8.4）。省略時は取得可能な 5.5 以降のすべて。

.PARAMETER apacheZip
  手元にある Apache httpd の zip を使う場合に指定します。省略時は Apache Lounge から取得します。

.PARAMETER firewall
  httpd.exe の受信を許可する Windows ファイアウォール規則を作成します。

.PARAMETER firewallProfile
  ファイアウォール規則を適用するプロファイル。既定値は Domain, Private

.PARAMETER proxyCredential
  認証付きプロキシの資格情報。省略時は Windows の資格情報を試し、拒否された場合に入力を求めます。

.PARAMETER skipVcRedist
  Visual C++ 再頒布可能パッケージの導入を省略します。

.PARAMETER threadsafe
  互換性のために残している引数です。Apache モジュール版 PHP はスレッドセーフ版のみのため、$false は指定できません。

.EXAMPLE
  .\install.ps1

.EXAMPLE
  .\install.ps1 -installPath D:\multiphp -phpVersions 7.4,8.3,8.4 -firewall
#>
[CmdletBinding()]
param(
  [string]$installPath = '.\server',
  [ValidateSet('x86', 'x64')][string]$arch = 'x64',
  [bool]$xdebug = $true,
  [string[]]$phpVersions,
  [string]$apacheZip,
  [switch]$firewall,
  [ValidateSet('Domain', 'Private', 'Public', 'Any')][string[]]$firewallProfile = @('Domain', 'Private'),
  [pscredential]$proxyCredential,
  [switch]$skipVcRedist,
  [bool]$threadsafe = $true
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib\MultiPhp.psm1') -Force -DisableNameChecking

if (-not $threadsafe) {
  throw 'ノンスレッドセーフ版 PHP には Apache 用モジュールが含まれないため利用できません。-threadsafe は指定しないでください。'
}
if ($phpVersions) {
  foreach ($v in $phpVersions) {
    if ($v -notmatch '^\d+\.\d+$') { throw "-phpVersions は 8.4 のようなマイナーバージョンで指定してください: $v" }
  }
}

New-Item -ItemType Directory -Path $installPath -Force | Out-Null
$installPath = (Resolve-Path -LiteralPath $installPath).ProviderPath.TrimEnd('\')
$downloadDir = Join-Path $installPath 'downloads'
$tempDir = Join-Path $installPath '.tmp'
New-Item -ItemType Directory -Path $downloadDir, $tempDir -Force | Out-Null
if ($apacheZip) { $apacheZip = (Resolve-Path -LiteralPath $apacheZip).ProviderPath }

$logFile = Join-Path $installPath ('multiphp-installlog-{0:yyyyMMdd_HHmmss}.log' -f (Get-Date))
Start-Transcript -LiteralPath $logFile | Out-Null
try {
  ############################################################
  Write-Step 'ダウンロード'
  ############################################################
  Initialize-Network -ProxyCredential $proxyCredential

  if (-not $skipVcRedist) {
    Install-VcRedist -Arch $arch -DownloadDir $downloadDir
    Write-Host 'PHP 5.4 以前を動かす場合は、さらに古いランタイムが必要になることがあります。'
  }

  if ($apacheZip) {
    Write-Host "Apache httpd: 指定された zip を使用します（$apacheZip）"
    $apacheZipPath = $apacheZip
  }
  else {
    Write-Host 'Apache httpd を Apache Lounge から取得します。'
    $apacheZipPath = Save-ApacheFromLounge -Arch $arch -DownloadDir $downloadDir
  }

  Write-Host 'PHP の一覧を取得しています...'
  $releases = @(Get-PhpReleaseList -Arch $arch -Only $phpVersions)
  if ($releases.Count -eq 0) { throw '導入できる PHP が見つかりませんでした。' }
  if ($phpVersions) {
    $missing = @($phpVersions | Where-Object { @($releases.Minor) -notcontains $_ })
    if ($missing.Count -gt 0) { Write-Warning "次のバージョンは見つかりませんでした: $($missing -join ', ')" }
  }
  $releases | Format-Table Minor, Version, Build, FileName -AutoSize | Out-Host
  foreach ($release in $releases) {
    if (-not $release.Sha256) { Write-Warning "$($release.FileName) はハッシュが公開されていないため検証できません。" }
    $path = Save-Download -Uri $release.Url -Path (Join-Path $downloadDir "php\$($release.FileName)") -Sha256 $release.Sha256
    $release | Add-Member -NotePropertyName ZipPath -NotePropertyValue $path
  }

  $xdebugFiles = @{}
  if ($xdebug) {
    Write-Host 'Xdebug の一覧を取得しています...'
    try {
      $builds = Get-XdebugBuildList -Arch $arch
      foreach ($release in $releases) {
        if (-not $builds.ContainsKey($release.Minor)) {
          Write-Warning "PHP $($release.Minor) に対応する Xdebug が見つかりませんでした。"
          continue
        }
        $build = $builds[$release.Minor]
        $xdebugFiles[$release.Id] = Save-Download -Uri $build.Url -Path (Join-Path $downloadDir "xdebug\$($build.FileName)")
      }
    }
    catch {
      Write-Warning "Xdebug を取得できなかったため、今回は導入を省略します: $($_.Exception.Message)"
    }
  }

  ############################################################
  Write-Step 'サービスの停止'
  ############################################################
  $wasRunning = @{}
  foreach ($service in @(Get-Service -Name 'multiphp-*' -ErrorAction SilentlyContinue)) {
    $wasRunning[$service.Name] = ($service.Status -eq 'Running')
    if ($service.Status -ne 'Stopped') {
      Write-Host "停止: $($service.Name)"
      Stop-Service -Name $service.Name -Force
    }
  }

  ############################################################
  Write-Step 'Apache httpd の配置'
  ############################################################
  Install-ApachePackage -ZipPath $apacheZipPath -ApacheDir (Join-Path $installPath 'apache') -TempRoot $tempDir
  Install-ApacheConfig -InstallPath $installPath -TemplateDir (Join-Path $PSScriptRoot 'templates\apache')

  ############################################################
  Write-Step 'PHP の配置'
  ############################################################
  foreach ($release in $releases) {
    Write-Host "PHP $($release.Version)"
    $destination = Join-Path $installPath "php\$($release.Id)"
    Install-PhpPackage -ZipPath $release.ZipPath -Destination $destination -Version $release.Version -Arch $arch -TempRoot $tempDir
    if ($xdebugFiles.ContainsKey($release.Id)) {
      Copy-Item -LiteralPath $xdebugFiles[$release.Id] -Destination (Join-Path $destination 'ext\php_xdebug.dll') -Force
    }
  }

  ############################################################
  Write-Step '設定ファイルの生成'
  ############################################################
  $iniTemplate = Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot 'templates\php\php.ini.psd1')
  $installed = @(Get-InstalledPhp -InstallPath $installPath)
  $phpConfDir = Join-Path $installPath 'apache\conf\extra\php'
  foreach ($php in $installed) {
    if (Initialize-PhpIni -Php $php -Template $iniTemplate -Xdebug $xdebug) { Write-Host "作成: $($php.Id)\php.ini" }
    Write-TextFile -Path (Join-Path $phpConfDir "$($php.Id).conf") -Lines (New-PhpLoaderConfig -Php $php)
    if (Initialize-DefaultSite -InstallPath $installPath -Id $php.Id) { Write-Host "作成: enable-$($php.Id)\default.conf（ポート $($php.Port)）" }
  }
  if (Initialize-DefaultSite -InstallPath $installPath -Id 'static') { Write-Host '作成: enable-static\default.conf（ポート 80）' }
  Write-TextFile -Path (Join-Path $installPath 'apache\conf\extra\php-loader.conf') -Lines (New-PhpLoaderMainConfig)

  New-Item -ItemType Directory -Path (Join-Path $installPath 'logs') -Force | Out-Null
  if (-not (Test-Path -LiteralPath (Join-Path $installPath 'htdocs'))) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'htdocs') -Destination $installPath -Recurse
  }

  ############################################################
  Write-Step 'サービスの登録と起動'
  ############################################################
  $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
  $targets = @([pscustomobject]@{ Id = 'static'; Path = $null; Port = 80 }) +
    @($installed | ForEach-Object { [pscustomobject]@{ Id = $_.Id; Path = $_.Path; Port = $_.Port } })
  $summary = foreach ($target in $targets) {
    $name = Get-ServiceNameForId $target.Id
    try {
      $state = Register-MultiPhpService -InstallPath $installPath -Id $target.Id
    }
    catch {
      Write-Warning $_.Exception.Message
      [pscustomobject]@{ Service = $name; Port = $target.Port; Registration = 'Error'; Status = '未登録' }
      continue
    }
    if ($target.Path) {
      # 拡張モジュールの依存 DLL（libpq.dll など）を解決するため、サービスごとに PHP フォルダを PATH の先頭に置く
      Set-ServiceEnvironment -ServiceName $name -Variable @(New-ServicePathVariable -PhpPath $target.Path -MachinePath $machinePath)
    }
    $test = Test-HttpdConfig -InstallPath $installPath -Id $target.Id
    $status = '停止'
    if (-not $test.Success) {
      $status = '構成エラーのため未起動'
      Write-Warning "$name の構成テストに失敗しました。`n$($test.Output -join "`n")"
    }
    elseif ($state -eq 'Created' -or $wasRunning[$name]) {
      try {
        Start-Service -Name $name
        $status = '起動'
      }
      catch {
        $status = '起動失敗'
        Write-Warning "$name を起動できませんでした。ログ（$installPath\logs）を確認してください: $($_.Exception.Message)"
      }
    }
    [pscustomobject]@{ Service = $name; Port = $target.Port; Registration = $state; Status = $status }
  }

  if ($firewall) {
    Set-MultiPhpFirewallRule -InstallPath $installPath -FirewallProfile $firewallProfile
    Write-Host "ファイアウォール規則を作成しました（プロファイル: $($firewallProfile -join ', ')）"
  }

  Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue

  Write-Step 'インストールが完了しました'
  $summary | Format-Table -AutoSize | Out-Host
  Write-Host "ログ: $logFile"
}
catch {
  Write-Host ''
  Write-Host "インストールを中断しました: $($_.Exception.Message)" -ForegroundColor Red
  Write-Host "ログ: $logFile" -ForegroundColor Red
  throw
}
finally {
  Stop-Transcript | Out-Null
}
