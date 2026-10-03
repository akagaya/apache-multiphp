<#
.SYNOPSIS
  lib\MultiPhp.psm1 の純粋関数（配布ページ解析・設定生成など）を検証します。
  Windows 以外の PowerShell 7 でも実行できます。ネットワークとサービスには触れません。

.EXAMPLE
  pwsh -NoProfile -File tests/run-tests.ps1
#>
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\lib\MultiPhp.psm1') -Force -DisableNameChecking

$script:failures = 0
$script:passes = 0
function Assert-Equal {
  param($Expected, $Actual, [string]$Name)
  $e = ($Expected | ForEach-Object { "$_" }) -join "`n"
  $a = ($Actual | ForEach-Object { "$_" }) -join "`n"
  if ($e -ceq $a) { $script:passes++ }
  else {
    $script:failures++
    Write-Host "FAIL: $Name" -ForegroundColor Red
    Write-Host "  expected: $e"
    Write-Host "  actual  : $a"
  }
}
function Assert-True {
  param([bool]$Condition, [string]$Name)
  Assert-Equal $true $Condition $Name
}
function Assert-Throws {
  param([scriptblock]$Script, [string]$Name)
  $thrown = $false
  try { & $Script } catch { $thrown = $true }
  Assert-Equal $true $thrown $Name
}

# --- 識別子とポート -----------------------------------------------------------
Assert-Equal 'php84' (ConvertTo-PhpId ([version]'8.4.12')) 'ConvertTo-PhpId'
Assert-Equal 'php84' (Resolve-PhpId '8.4') 'Resolve-PhpId 8.4'
Assert-Equal 'php55' (Resolve-PhpId 'PHP55') 'Resolve-PhpId PHP55'
Assert-Equal 'static' (Resolve-PhpId 'static') 'Resolve-PhpId static'
Assert-Throws { Resolve-PhpId '8' } 'Resolve-PhpId 不正値'
Assert-Equal 20084 (Get-DefaultPort 'php84') 'Get-DefaultPort php84'
Assert-Equal 20055 (Get-DefaultPort 'php55') 'Get-DefaultPort php55'
Assert-Equal 20090 (Get-DefaultPort 'php90') 'Get-DefaultPort php90（将来版）'
Assert-Equal 80 (Get-DefaultPort 'static') 'Get-DefaultPort static'
Assert-Equal 'multiphp-php84' (Get-ServiceNameForId 'php84') 'Get-ServiceNameForId'

# --- href 抽出 -----------------------------------------------------------------
$html = @'
<a href="/downloads/releases/php-8.4.12-Win32-vs17-x64.zip">x</a>
<A HREF='php-8.4.12-nts-Win32-vs17-x64.zip'>x</A>
<a href=https://example.com/other.zip>x</a>
<a href="/downloads/releases/php-debug-pack-8.4.12-Win32-vs17-x64.zip">x</a>
'@
$links = @(Get-HrefList -Html $html -BaseUrl 'https://windows.php.net/downloads/releases/')
Assert-Equal @(
  'https://windows.php.net/downloads/releases/php-8.4.12-Win32-vs17-x64.zip'
  'https://windows.php.net/downloads/releases/php-8.4.12-nts-Win32-vs17-x64.zip'
  'https://example.com/other.zip'
  'https://windows.php.net/downloads/releases/php-debug-pack-8.4.12-Win32-vs17-x64.zip'
) $links 'Get-HrefList 相対・絶対・引用符なし'

# --- PHP リリース選択 -----------------------------------------------------------
$phpUrls = @(
  'https://windows.php.net/downloads/releases/php-8.4.12-Win32-vs17-x64.zip'
  'https://windows.php.net/downloads/releases/php-8.4.12-nts-Win32-vs17-x64.zip'
  'https://windows.php.net/downloads/releases/php-8.4.9-Win32-vs17-x64.zip'
  'https://windows.php.net/downloads/releases/archives/php-8.4.10-Win32-vs17-x64.zip'
  'https://windows.php.net/downloads/releases/php-8.4.12-Win32-vs17-x86.zip'
  'https://windows.php.net/downloads/releases/php-8.5.0RC1-Win32-vs17-x64.zip'
  'https://windows.php.net/downloads/releases/archives/php-5.5.38-Win32-VC11-x64.zip'
  'https://windows.php.net/downloads/releases/archives/php-5.4.45-Win32-VC9-x86.zip'
  'https://windows.php.net/downloads/releases/archives/php-5.3.29-Win32-VC9-x86.zip'
  'https://windows.php.net/downloads/releases/php-debug-pack-8.4.12-Win32-vs17-x64.zip'
)
$x64 = @(Select-PhpRelease -Url $phpUrls -Arch x64)
Assert-Equal @('8.4', '5.5') @($x64 | ForEach-Object { $_.Minor }) 'Select-PhpRelease x64 のマイナー一覧（NTS・RC・debug-pack を除外）'
Assert-Equal '8.4.12' $x64[0].Version 'Select-PhpRelease 最新パッチを選ぶ'
Assert-Equal 'php-8.4.12-Win32-vs17-x64.zip' $x64[0].FileName 'Select-PhpRelease ファイル名'
Assert-Equal 'php84' $x64[0].Id 'Select-PhpRelease 識別子'
$x86 = @(Select-PhpRelease -Url $phpUrls -Arch x86)
Assert-Equal @('8.4') @($x86 | ForEach-Object { $_.Minor }) 'Select-PhpRelease x86 は 5.5 未満を除外'
$only = @(Select-PhpRelease -Url $phpUrls -Arch x64 -Only @('5.5'))
Assert-Equal @('5.5') @($only | ForEach-Object { $_.Minor }) 'Select-PhpRelease -Only'
Assert-Equal 0 @(Select-PhpRelease -Url @() -Arch x64).Count 'Select-PhpRelease 空入力'

# --- Apache Lounge ---------------------------------------------------------------
$apacheUrls = @(
  'https://www.apachelounge.com/download/VS17/binaries/httpd-2.4.65-250724-Win64-VS17.zip'
  'https://www.apachelounge.com/download/VS17/binaries/httpd-2.4.65-250701-Win64-VS17.zip'
  'https://www.apachelounge.com/download/VS17/binaries/httpd-2.4.64-250710-Win64-VS17.zip'
  'https://www.apachelounge.com/download/VS17/binaries/httpd-2.4.65-250724-win32-VS17.zip'
  'https://www.apachelounge.com/download/VS17/modules/mod_fcgid-2.3.10-win64-VS17.zip'
)
$apache = Select-ApacheBuild -Url $apacheUrls -Arch x64
Assert-Equal 'httpd-2.4.65-250724-Win64-VS17.zip' $apache.FileName 'Select-ApacheBuild x64 最新'
$apache86 = Select-ApacheBuild -Url $apacheUrls -Arch x86
Assert-Equal 'httpd-2.4.65-250724-win32-VS17.zip' $apache86.FileName 'Select-ApacheBuild x86'
Assert-Equal 'httpd-2.4.58-win64-VS17.zip' (Select-ApacheBuild -Url @('https://a/httpd-2.4.58-win64-VS17.zip') -Arch x64).FileName 'Select-ApacheBuild 日付なし旧形式'
Assert-True ($null -eq (Select-ApacheBuild -Url @() -Arch x64)) 'Select-ApacheBuild 該当なし'

# --- Xdebug ----------------------------------------------------------------------
$xdebugUrls = @(
  'https://xdebug.org/files/php_xdebug-3.4.5-8.4-ts-vs17-x86_64.dll'
  'https://xdebug.org/files/php_xdebug-3.4.5-8.4-nts-vs17-x86_64.dll'
  'https://xdebug.org/files/php_xdebug-3.4.4-8.4-ts-vs17-x86_64.dll'
  'https://xdebug.org/files/php_xdebug-3.5.0alpha1-8.5-ts-vs17-x86_64.dll'
  'https://xdebug.org/files/php_xdebug-3.4.5-8.4-ts-vs17.dll'
  'https://xdebug.org/files/php_xdebug-2.5.5-5.5-vc11-x86_64.dll'
  'https://xdebug.org/files/php_xdebug-2.5.5-5.5-vc11-nts-x86_64.dll'
  'https://xdebug.org/files/php_xdebug-2.5.5-5.5-vc11.dll'
)
$xd = Select-XdebugBuild -Url $xdebugUrls -Arch x64
Assert-Equal @('5.5', '8.4') @($xd.Keys | Sort-Object) 'Select-XdebugBuild x64 対象（alpha を除外）'
Assert-Equal 'php_xdebug-3.4.5-8.4-ts-vs17-x86_64.dll' $xd['8.4'].FileName 'Select-XdebugBuild 8.4 最新 TS'
Assert-Equal 'php_xdebug-2.5.5-5.5-vc11-x86_64.dll' $xd['5.5'].FileName 'Select-XdebugBuild 5.5 TS'
$xd86 = Select-XdebugBuild -Url $xdebugUrls -Arch x86
Assert-Equal 'php_xdebug-3.4.5-8.4-ts-vs17.dll' $xd86['8.4'].FileName 'Select-XdebugBuild x86'

# --- SHA256 一覧 -------------------------------------------------------------------
$hash = 'A' * 64
$sums = ConvertFrom-Sha256Sum ("$hash *php-8.4.12-Win32-vs17-x64.zip`r`n" + ('b' * 64) + '  php-8.3.1-Win32-vs16-x64.zip' + "`nbroken line")
Assert-Equal ('a' * 64) $sums['php-8.4.12-Win32-vs17-x64.zip'] 'ConvertFrom-Sha256Sum バイナリ表記・小文字化'
Assert-Equal ('b' * 64) $sums['php-8.3.1-Win32-vs16-x64.zip'] 'ConvertFrom-Sha256Sum テキスト表記'
Assert-Equal 2 $sums.Count 'ConvertFrom-Sha256Sum 不正行を無視'

# --- 設定生成 ----------------------------------------------------------------------
$define = New-DefineConfig -InstallPath 'C:\multi php\server'
Assert-True ($define -contains 'Define SRVROOT "C:/multi php/server/apache"') 'New-DefineConfig 区切り文字と空白'

$php = [pscustomobject]@{
  Id = 'php84'; ModuleName = 'php_module'; ModuleFile = 'php8apache2_4.dll'; CoreDll = 'php8ts.dll'
  Dependencies = @('libpq.dll', 'libsqlite3.dll')
}
$loader = New-PhpLoaderConfig -Php $php
Assert-True ($loader -contains '<IfDefine php84>') 'New-PhpLoaderConfig IfDefine'
Assert-True ($loader -contains '  LoadFile "${PHPROOT}/php84/php8ts.dll"') 'New-PhpLoaderConfig コア DLL'
Assert-True ($loader -contains '  LoadFile "${PHPROOT}/php84/libpq.dll"') 'New-PhpLoaderConfig 依存 DLL'
Assert-True ($loader -contains '  LoadModule php_module "${PHPROOT}/php84/php8apache2_4.dll"') 'New-PhpLoaderConfig LoadModule'
Assert-True ($loader -contains '  IncludeOptional "${SRVROOT}/conf/extra/enable-php84/*.conf"') 'New-PhpLoaderConfig サイト読み込み'
Assert-True ((New-PhpLoaderMainConfig) -contains '  IncludeOptional "${SRVROOT}/conf/extra/enable-static/*.conf"') 'New-PhpLoaderMainConfig'

$default = New-DefaultSiteConfig -Id 'php84' -Port 20084
Assert-True ($default -contains 'Listen 20084') 'New-DefaultSiteConfig Listen'
Assert-True (-not ($default -contains '  DirectoryIndex index.html')) 'New-DefaultSiteConfig PHP は DirectoryIndex を持たない'
Assert-True ((New-DefaultSiteConfig -Id 'static' -Port 80) -contains '  DirectoryIndex index.html') 'New-DefaultSiteConfig static'

$site = New-SiteConfig -Name 'proj-a' -Id 'php74' -Port 30001 -DocumentRoot 'D:\www\proj-a' -CreatedAt ([datetime]'2026-10-03 12:00')
Assert-True ($site -contains 'Listen 30001') 'New-SiteConfig Listen'
Assert-True ($site -contains '<VirtualHost *:30001>') 'New-SiteConfig VirtualHost'
Assert-True ($site -contains '  DocumentRoot "D:/www/proj-a"') 'New-SiteConfig DocumentRoot'

# --- php.ini 追記 ----------------------------------------------------------------
$template = Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot '..\templates\php\php.ini.psd1')
$ext84 = @('php_bz2.dll', 'php_curl.dll', 'php_gd.dll', 'php_ldap.dll', 'php_mbstring.dll', 'php_exif.dll', 'php_zip.dll', 'php_xdebug.dll')
$ini84 = @(New-PhpIniAddition -Version ([version]'8.4.12') -ExtensionDir 'C:\s\php\php84\ext' -ExtensionFiles $ext84 -Template $template -Xdebug $true)
Assert-True ($ini84 -contains 'extension_dir = "C:\s\php\php84\ext"') 'php.ini extension_dir'
Assert-True ($ini84 -contains 'date.timezone = Asia/Tokyo') 'php.ini 設定'
Assert-True ($ini84 -contains 'extension=gd') 'php.ini 8.4 gd'
Assert-True (-not ($ini84 -contains 'extension=ldap')) 'php.ini 8.4 は ldap を有効化しない（Max 8.2）'
Assert-True ($ini84 -contains 'extension=zip') 'php.ini 8.4 zip'
Assert-True (-not ($ini84 -contains 'extension=fileinfo')) 'php.ini DLL がない拡張は有効化しない'
Assert-True ($ini84 -contains '; apache-multiphp: 拡張 fileinfo は ext フォルダにないため有効化していません') 'php.ini 有効化できなかった拡張を記録する'
Assert-True ($ini84 -contains 'xdebug.start_with_request = yes') 'php.ini Xdebug 3 設定'
Assert-True (-not ($ini84 -contains 'xdebug.remote_enable = 1')) 'php.ini Xdebug 3 で旧設定を書かない'
$mb = [array]::IndexOf($ini84, 'extension=mbstring'); $ex = [array]::IndexOf($ini84, 'extension=exif')
Assert-True ($mb -ge 0 -and $ex -gt $mb) 'php.ini exif は mbstring の後'

$ext55 = @('php_gd2.dll', 'php_ldap.dll', 'php_mbstring.dll', 'php_zip.dll')
$ini55 = @(New-PhpIniAddition -Version ([version]'5.5.38') -ExtensionDir 'ext' -ExtensionFiles $ext55 -Template $template -Xdebug $true)
Assert-True ($ini55 -contains 'extension=php_gd2.dll') 'php.ini 5.5 は旧名・DLL 形式'
Assert-True ($ini55 -contains 'extension=php_ldap.dll') 'php.ini 5.5 ldap'
Assert-True (-not ($ini55 -contains 'extension=php_zip.dll')) 'php.ini 5.5 zip は対象外（Min 8.2）'
Assert-True ($ini55 -contains 'xdebug.remote_enable = 1') 'php.ini Xdebug 2 設定'
$ini74 = @(New-PhpIniAddition -Version ([version]'7.4.33') -ExtensionDir 'ext' -ExtensionFiles @('php_gd2.dll') -Template $template -Xdebug $false)
Assert-True ($ini74 -contains 'extension=gd2') 'php.ini 7.4 は短縮形'
Assert-True (-not ($ini74 -contains 'zend_extension = php_xdebug.dll')) 'php.ini Xdebug 無効'

Assert-Equal 'PATH=C:\p\php84;C:\Windows;C:\Tools' (New-ServicePathVariable -PhpPath 'C:\p\php84' -MachinePath 'C:\Windows;;C:\Tools;C:\p\php84') 'New-ServicePathVariable'

# --- サイト設定の読み取り ------------------------------------------------------------
$parsed = Read-SiteConfigFile -Lines @(
  '# Listen 9999'
  'Listen 20084'
  'Listen 127.0.0.1:30002'
  'Listen [::]:30003 http'
  'DocumentRoot "${DEFAULT_DOCROOT}/sub"'
  'DocumentRoot "C:/second"'
) -Define @{ DEFAULT_DOCROOT = 'C:/s/htdocs' }
Assert-Equal @(20084, 30002, 30003) $parsed.Ports 'Read-SiteConfigFile Listen（コメント除外・アドレス付き）'
Assert-Equal 'C:/s/htdocs/sub' $parsed.DocumentRoot 'Read-SiteConfigFile DocumentRoot 変数展開'
$generated = Read-SiteConfigFile -Lines $site
Assert-Equal @(30001) $generated.Ports 'Read-SiteConfigFile 生成した conf を読める'
Assert-Equal 'D:/www/proj-a' $generated.DocumentRoot 'Read-SiteConfigFile 生成した conf の DocumentRoot'
Assert-Equal 'x/${UNKNOWN}' (Expand-ApacheVariable -Text '${A}/${UNKNOWN}' -Define @{ A = 'x' }) 'Expand-ApacheVariable 未定義は維持'

Assert-Equal 30002 (Find-FreePort -Start 30000 -Used @(30000, 30001, 30003)) 'Find-FreePort'
Assert-Throws { Find-FreePort -Start 65535 -Used @(65535) } 'Find-FreePort 枯渇'

# --- ファイル系（一時フォルダ） --------------------------------------------------------
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('multiphp-test-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
  $file = Join-Path $tmp 'a\b.conf'
  Write-TextFile -Path $file -Lines @('日本語', 'x')
  $bytes = [IO.File]::ReadAllBytes($file)
  Assert-True (-not ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB)) 'Write-TextFile BOM なし'
  Assert-Equal "日本語`r`nx`r`n" ([Text.Encoding]::UTF8.GetString($bytes)) 'Write-TextFile CRLF'

  # インストール済み PHP の検出
  $install = Join-Path $tmp 'server'
  foreach ($d in @('php84', 'php55', 'php74', 'phpbroken', 'php83')) { New-Item -ItemType Directory -Path (Join-Path $install "php\$d") -Force | Out-Null }
  foreach ($f in @('php84\php8apache2_4.dll', 'php84\libpq.dll', 'php55\php5apache2_4.dll', 'php55\libeay32.dll', 'php74\php7apache2_4.dll')) {
    Set-Content -LiteralPath (Join-Path $install "php\$f") -Value ''
  }
  Write-TextFile -Path (Join-Path $install 'php\php84\multiphp.json') -Lines @('{"Version":"8.4.12","Arch":"x64"}')
  $found = @(Get-InstalledPhp -InstallPath $install -WarningAction SilentlyContinue)
  Assert-Equal @('php55', 'php74', 'php84') @($found | ForEach-Object { $_.Id }) 'Get-InstalledPhp モジュールのある php だけ'
  $p84 = $found | Where-Object { $_.Id -eq 'php84' }
  Assert-Equal '8.4.12' $p84.Version 'Get-InstalledPhp マーカーからバージョン'
  Assert-Equal 'php_module' $p84.ModuleName 'Get-InstalledPhp PHP 8 モジュール名'
  Assert-Equal @('libpq.dll') $p84.Dependencies 'Get-InstalledPhp 依存 DLL'
  $p55 = $found | Where-Object { $_.Id -eq 'php55' }
  Assert-Equal '5.5' $p55.Version 'Get-InstalledPhp マーカーなしは識別子から推定'
  Assert-Equal 'php5_module' $p55.ModuleName 'Get-InstalledPhp PHP 5 モジュール名'
  Assert-Equal 'php5ts.dll' $p55.CoreDll 'Get-InstalledPhp PHP 5 コア DLL'
  Assert-Equal 'php7_module' ($found | Where-Object { $_.Id -eq 'php74' }).ModuleName 'Get-InstalledPhp PHP 7 モジュール名'

  # サイト一覧
  Write-TextFile -Path (Join-Path $install 'apache\conf\define.conf') -Lines (New-DefineConfig -InstallPath $install)
  Write-TextFile -Path (Join-Path $install 'apache\conf\extra\enable-php84\default.conf') -Lines (New-DefaultSiteConfig -Id 'php84' -Port 20084)
  Write-TextFile -Path (Join-Path $install 'apache\conf\extra\enable-php84\proj.conf') -Lines $site
  Write-TextFile -Path (Join-Path $install 'apache\conf\extra\enable-php84\old.removed-20260101000000') -Lines @('Listen 39999')
  $sites = @(Get-SiteConfiguration -InstallPath $install | Sort-Object Port)
  Assert-Equal @(20084, 30001) @($sites | ForEach-Object { $_.Port }) 'Get-SiteConfiguration 無効化したサイトを除外'
  Assert-Equal ((ConvertTo-ApachePath $install) + '/htdocs') $sites[0].DocumentRoot 'Get-SiteConfiguration define.conf を展開'

  # テンプレート配置（既存ファイルは上書きしない）
  $conf = Join-Path $install 'apache\conf'
  Write-TextFile -Path (Join-Path $conf 'httpd.conf') -Lines @('# user edited')
  Install-ApacheConfig -InstallPath $install -TemplateDir (Join-Path $PSScriptRoot '..\templates\apache')
  Assert-Equal '# user edited' (Get-Content -LiteralPath (Join-Path $conf 'httpd.conf')) 'Install-ApacheConfig 既存 httpd.conf を維持'
  Assert-True (Test-Path -LiteralPath (Join-Path $conf 'extra/httpd-mpm.conf')) 'Install-ApacheConfig 不足ファイルを補う'
  Assert-True (Test-Path -LiteralPath (Join-Path $conf 'mime.types')) 'Install-ApacheConfig mime.types'

  Assert-True (Initialize-DefaultSite -InstallPath $install -Id 'static') 'Initialize-DefaultSite 新規作成'
  Assert-True (-not (Initialize-DefaultSite -InstallPath $install -Id 'php84')) 'Initialize-DefaultSite 既存フォルダは触らない'
}
finally {
  Remove-Item -LiteralPath $tmp -Recurse -Force
}

Write-Host ''
Write-Host "passed: $script:passes / failed: $script:failures"
if ($script:failures -gt 0) { exit 1 }
