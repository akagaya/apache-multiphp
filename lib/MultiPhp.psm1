# Apache-multiPHP 共通モジュール
# Windows PowerShell 5.1 で動作すること（PowerShell 7 固有の構文は使わない）

Set-StrictMode -Version 2.0

$script:MinPhpVersion = [version]'5.5'
$script:PhpDefaultPortBase = 20000
$script:StaticId = 'static'
$script:ServicePrefix = 'multiphp-'
$script:FirewallRuleName = 'multiphp-httpd'
$script:GeneratedHeader = '# このファイルは apache-multiphp の install.ps1 が生成します。再インストール時に上書きされるため、直接編集しないでください。'
# Apache Lounge は User-Agent でアクセスを制限している。
# -apacheZip を指定しない場合に限り、ブラウザの User-Agent を名乗って取得する。
$script:LoungeUserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:128.0) Gecko/20100101 Firefox/128.0'
# 存在する場合に LoadFile で明示的に読み込む依存 DLL（PATH 経由でも解決されるが、従来動作を維持する）
$script:PhpDependencyDlls = @('libpq.dll', 'libssh2.dll', 'libsasl.dll', 'libsqlite3.dll', 'libeay32.dll', 'ssleay32.dll')
$script:ProxyPrompted = $false

#region 共通ユーティリティ

function Get-FullPath {
  param([Parameter(Mandatory)][string]$Path)
  $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
}

# BOM なし UTF-8 / CRLF で書き込む（Apache と PHP は BOM 付きファイルを正しく読めない）
function Write-TextFile {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Lines
  )
  $full = Get-FullPath $Path
  $dir = Split-Path -Parent $full
  if ($dir -and -not (Test-Path -LiteralPath $dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
  }
  $text = ($Lines -join "`r`n") + "`r`n"
  [IO.File]::WriteAllText($full, $text, (New-Object System.Text.UTF8Encoding($false)))
}

function ConvertTo-ApachePath {
  param([Parameter(Mandatory)][string]$Path)
  $Path -replace '\\', '/'
}

# ネイティブコマンドを実行し、標準エラー出力も含めて結果を返す。
# $ErrorActionPreference = 'Stop' のまま stderr を拾うと終了エラーになるため、一時的に緩める。
function Invoke-NativeCommand {
  param(
    [Parameter(Mandatory)][string]$FilePath,
    [string[]]$ArgumentList = @()
  )
  $previous = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $output = & $FilePath @ArgumentList 2>&1 | ForEach-Object { "$_" }
    $code = $LASTEXITCODE
  }
  finally {
    $ErrorActionPreference = $previous
  }
  [pscustomobject]@{ ExitCode = $code; Output = @($output) }
}

function Write-Step {
  param([Parameter(Mandatory)][string]$Message)
  Write-Host ''
  Write-Host ('=' * 60) -ForegroundColor Cyan
  Write-Host $Message -ForegroundColor Cyan
  Write-Host ('=' * 60) -ForegroundColor Cyan
}

#endregion

#region PHP バージョンと識別子

function ConvertTo-PhpId {
  param([Parameter(Mandatory)][version]$Version)
  'php{0}{1}' -f $Version.Major, $Version.Minor
}

# "8.4" / "php84" / "static" を識別子に正規化する
function Resolve-PhpId {
  param([Parameter(Mandatory)][string]$Value)
  $v = $Value.Trim().ToLowerInvariant()
  if ($v -eq $script:StaticId) { return $script:StaticId }
  if ($v -match '^\d+\.\d+$') { return (ConvertTo-PhpId ([version]$v)) }
  if ($v -match '^php\d{2,}$') { return $v }
  throw "PHP バージョンの指定が不正です: '$Value'（例: 8.4 / php84 / static）"
}

# 既定ポート: static は 80、PHP は 20000 + 識別子の数字部（php84 -> 20084）
function Get-DefaultPort {
  param([Parameter(Mandatory)][string]$Id)
  if ($Id -eq $script:StaticId) { return 80 }
  if ($Id -notmatch '^php(\d+)$') { throw "不正な識別子です: $Id" }
  $script:PhpDefaultPortBase + [int]$Matches[1]
}

function Get-ServiceNameForId {
  param([Parameter(Mandatory)][string]$Id)
  $script:ServicePrefix + $Id
}

#endregion

#region 配布ページの解析（純粋関数）

function Get-HrefList {
  param(
    [Parameter(Mandatory)][AllowEmptyString()][string]$Html,
    [Parameter(Mandatory)][string]$BaseUrl,
    [string]$Extension = 'zip'
  )
  $pattern = '(?i)href\s*=\s*["'']?([^"''\s>]+\.' + [regex]::Escape($Extension) + ')["'']?'
  $base = New-Object System.Uri($BaseUrl)
  foreach ($m in [regex]::Matches($Html, $pattern)) {
    (New-Object System.Uri($base, $m.Groups[1].Value)).AbsoluteUri
  }
}

function Get-UrlFileName {
  param([Parameter(Mandatory)][string]$Url)
  [IO.Path]::GetFileName(([uri]$Url).AbsolutePath)
}

# 各マイナーバージョンの最新スレッドセーフ版を選ぶ
function Select-PhpRelease {
  param(
    [AllowEmptyCollection()][string[]]$Url = @(),
    [Parameter(Mandatory)][ValidateSet('x86', 'x64')][string]$Arch,
    [version]$MinVersion = $script:MinPhpVersion,
    [string[]]$Only
  )
  $latest = @{}
  foreach ($u in $Url) {
    $file = Get-UrlFileName $u
    # NTS 版は "-nts-" を含むため、この正規表現に一致しない
    if ($file -notmatch '^php-(\d+)\.(\d+)\.(\d+)-Win32-(v[cs]\d+)-(x86|x64)\.zip$') { continue }
    if ($Matches[5] -ne $Arch) { continue }
    $build = $Matches[4]
    $version = [version]('{0}.{1}.{2}' -f $Matches[1], $Matches[2], $Matches[3])
    $minor = [version]('{0}.{1}' -f $version.Major, $version.Minor)
    if ($minor -lt $MinVersion) { continue }
    $key = $minor.ToString()
    if ($Only -and ($Only -notcontains $key)) { continue }
    if (-not $latest.ContainsKey($key) -or $latest[$key].Version -lt $version) {
      $latest[$key] = [pscustomobject]@{
        Minor    = $key
        Version  = $version
        Id       = (ConvertTo-PhpId $version)
        Build    = $build
        Url      = $u
        FileName = $file
      }
    }
  }
  $latest.Values | Sort-Object Version -Descending
}

function Select-ApacheBuild {
  param(
    [AllowEmptyCollection()][string[]]$Url = @(),
    [Parameter(Mandatory)][ValidateSet('x86', 'x64')][string]$Arch
  )
  $platform = if ($Arch -eq 'x86') { 'win32' } else { 'win64' }
  $candidates = foreach ($u in $Url) {
    $file = Get-UrlFileName $u
    if ($file -notmatch '^httpd-(\d+\.\d+\.\d+)(?:-(\d{6}))?-(win32|win64)-(vs\d+)\.zip$') { continue }
    if ($Matches[3] -ne $platform) { continue }
    $date = 0
    if ($Matches[2]) { $date = [int]$Matches[2] }
    [pscustomobject]@{
      Version  = [version]$Matches[1]
      Date     = $date
      Toolset  = [int]($Matches[4].Substring(2))
      Url      = $u
      FileName = $file
    }
  }
  $candidates | Sort-Object Version, Date, Toolset -Descending | Select-Object -First 1
}

# PHP マイナーバージョンごとに、最新の正式リリース版 Xdebug（TS）を選ぶ
function Select-XdebugBuild {
  param(
    [AllowEmptyCollection()][string[]]$Url = @(),
    [Parameter(Mandatory)][ValidateSet('x86', 'x64')][string]$Arch
  )
  $latest = @{}
  foreach ($u in $Url) {
    $file = Get-UrlFileName $u
    # パッチ番号の直後が "-" であることを要求し、alpha / beta / RC を除外する
    if ($file -notmatch '^php_xdebug-(\d+\.\d+\.\d+)-(\d+\.\d+)(?:-(.+))?\.dll$') { continue }
    $version = [version]$Matches[1]
    $phpMinor = $Matches[2]
    $tags = ''
    if ($Matches[3]) { $tags = $Matches[3] }
    $is64 = $tags -match 'x86_64'
    if (($Arch -eq 'x64') -ne $is64) { continue }
    if ($tags -match '(^|-)nts(-|$)') { continue }
    if (-not $latest.ContainsKey($phpMinor) -or $latest[$phpMinor].Version -lt $version) {
      $latest[$phpMinor] = [pscustomobject]@{ PhpMinor = $phpMinor; Version = $version; Url = $u; FileName = $file }
    }
  }
  $latest
}

function ConvertFrom-Sha256Sum {
  param([AllowEmptyString()][string]$Text = '')
  $map = @{}
  foreach ($line in ($Text -split "`r?`n")) {
    if ($line -match '^\s*([0-9a-fA-F]{64})\s+\*?(\S+)\s*$') {
      $map[$Matches[2]] = $Matches[1].ToLowerInvariant()
    }
  }
  $map
}

#endregion

#region 設定ファイル生成（純粋関数）

function New-DefineConfig {
  param([Parameter(Mandatory)][string]$InstallPath)
  $root = ConvertTo-ApachePath $InstallPath
  @(
    '# パス定義（install.ps1 が初回のみ生成します。以後は自由に編集できます）'
    ('Define SRVROOT "{0}/apache"' -f $root)
    ('Define DEFAULT_DOCROOT "{0}/htdocs"' -f $root)
    ('Define DEFAULT_LOGDIR "{0}/logs"' -f $root)
    ('Define PHPROOT "{0}/php"' -f $root)
  )
}

function New-PhpLoaderMainConfig {
  @(
    $script:GeneratedHeader
    '# 起動時の -D <識別子> に応じて PHP モジュールとサイト設定を読み込みます。'
    'IncludeOptional "${SRVROOT}/conf/extra/php/*.conf"'
    ''
    '<IfDefine EnablePHP>'
    '  DirectoryIndex index.php index.html'
    '  AddType application/x-httpd-php .php'
    '</IfDefine>'
    ''
    '<IfDefine !EnablePHP>'
    '  IncludeOptional "${SRVROOT}/conf/extra/enable-static/*.conf"'
    '</IfDefine>'
  )
}

function New-PhpLoaderConfig {
  param([Parameter(Mandatory)]$Php)
  $id = $Php.Id
  $phpDir = '${PHPROOT}/' + $id
  $lines = @(
    $script:GeneratedHeader
    "<IfDefine $id>"
    '  Define EnablePHP'
    ('  PidFile "${SRVROOT}/logs/httpd.' + $id + '.pid"')
    ''
    '  # 依存 DLL はサービスごとの環境変数 PATH（install.ps1 が設定）でも解決されます。'
    ('  LoadFile "' + $phpDir + '/' + $Php.CoreDll + '"')
  )
  foreach ($dll in $Php.Dependencies) {
    $lines += ('  LoadFile "' + $phpDir + '/' + $dll + '"')
  }
  $lines += @(
    ''
    ('  LoadModule ' + $Php.ModuleName + ' "' + $phpDir + '/' + $Php.ModuleFile + '"')
    ('  PHPIniDir "' + $phpDir + '"')
    ''
    ('  IncludeOptional "${SRVROOT}/conf/extra/enable-' + $id + '/*.conf"')
    '</IfDefine>'
  )
  $lines
}

function New-DefaultSiteConfig {
  param(
    [Parameter(Mandatory)][string]$Id,
    [Parameter(Mandatory)][int]$Port
  )
  $lines = @(
    '# サービス既定のサイト（install.ps1 が初回のみ生成します。以後は自由に編集できます）'
    "Listen $Port"
    "ServerName 127.0.0.1:$Port"
    ''
    'DocumentRoot "${DEFAULT_DOCROOT}"'
    '<Directory "${DEFAULT_DOCROOT}">'
    '  Options All'
    '  AllowOverride All'
    '  Require all granted'
  )
  if ($Id -eq $script:StaticId) { $lines += '  DirectoryIndex index.html' }
  $lines += @(
    '</Directory>'
    ''
    ('ErrorLog "${DEFAULT_LOGDIR}/error-httpd_' + $Id + '.log"')
    ('CustomLog "${DEFAULT_LOGDIR}/access-httpd_' + $Id + '.log" customcsv')
  )
  $lines
}

function New-SiteConfig {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$Id,
    [Parameter(Mandatory)][int]$Port,
    [Parameter(Mandatory)][string]$DocumentRoot,
    [datetime]$CreatedAt = (Get-Date)
  )
  $root = ConvertTo-ApachePath $DocumentRoot
  @(
    ('# new-site.ps1 により生成（サイト: {0} / {1} / {2:yyyy-MM-dd HH:mm}）' -f $Name, $Id, $CreatedAt)
    "Listen $Port"
    "<VirtualHost *:$Port>"
    ('  DocumentRoot "{0}"' -f $root)
    ('  <Directory "{0}">' -f $root)
    '    Options Indexes FollowSymLinks'
    '    AllowOverride All'
    '    Require all granted'
    '  </Directory>'
    ''
    ('  ErrorLog "${DEFAULT_LOGDIR}/error-site_' + $Name + '.log"')
    ('  CustomLog "${DEFAULT_LOGDIR}/access-site_' + $Name + '.log" customcsv')
    '</VirtualHost>'
  )
}

# php.ini-development の末尾に追記する内容を生成する
function New-PhpIniAddition {
  param(
    [Parameter(Mandatory)][version]$Version,
    [Parameter(Mandatory)][string]$ExtensionDir,
    [AllowEmptyCollection()][string[]]$ExtensionFiles = @(),
    [Parameter(Mandatory)][hashtable]$Template,
    [bool]$Xdebug
  )
  $minor = [version]('{0}.{1}' -f $Version.Major, $Version.Minor)
  $lines = @(
    ''
    ';;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;'
    '; apache-multiphp による追記（初回インストール時のみ）'
    ';;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;'
    ('extension_dir = "{0}"' -f $ExtensionDir)
  )
  $lines += @($Template.Settings)
  foreach ($ext in $Template.Extensions) {
    if ($ext.ContainsKey('Min') -and $minor -lt [version]$ext.Min) { continue }
    if ($ext.ContainsKey('Max') -and $minor -gt [version]$ext.Max) { continue }
    $names = @($ext.Name)
    if ($ext.ContainsKey('Alternatives')) { $names += @($ext.Alternatives) }
    $found = $null
    foreach ($n in $names) {
      if ($ExtensionFiles -contains "php_$n.dll") { $found = $n; break }
    }
    if (-not $found) {
      # 新しい PHP で拡張が廃止・改名された場合に気付けるよう、黙って飛ばさない
      Write-Warning "PHP $minor には拡張 $($ext.Name) がないため、有効化しませんでした。"
      $lines += "; apache-multiphp: 拡張 $($ext.Name) は ext フォルダにないため有効化していません"
      continue
    }
    if ($minor -ge [version]'7.2') { $lines += "extension=$found" } else { $lines += "extension=php_$found.dll" }
  }
  if ($Xdebug) {
    $lines += ''
    $lines += 'zend_extension = php_xdebug.dll'
    # Xdebug 3 は PHP 7.2 以降。旧設定名を残すと Xdebug 3 が警告を出すため、バージョンで切り替える。
    if ($minor -ge [version]'7.2') { $lines += @($Template.Xdebug3) } else { $lines += @($Template.Xdebug2) }
  }
  $lines
}

function New-ServicePathVariable {
  param(
    [Parameter(Mandatory)][string]$PhpPath,
    [AllowEmptyString()][string]$MachinePath = ''
  )
  $parts = @($PhpPath) + @($MachinePath -split ';' | Where-Object { $_ -and ($_ -ne $PhpPath) })
  'PATH=' + ($parts -join ';')
}

#endregion

#region Apache 設定の読み取り

function Get-ApacheDefine {
  param([Parameter(Mandatory)][string]$InstallPath)
  $map = @{}
  $file = Join-Path $InstallPath 'apache\conf\define.conf'
  if (Test-Path -LiteralPath $file) {
    foreach ($line in Get-Content -LiteralPath $file) {
      if ($line -match '^\s*Define\s+(\S+)\s+"?([^"]*?)"?\s*$') { $map[$Matches[1]] = $Matches[2] }
    }
  }
  $map
}

function Expand-ApacheVariable {
  param(
    [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
    [Parameter(Mandatory)][hashtable]$Define
  )
  $result = $Text
  foreach ($key in $Define.Keys) {
    $result = $result.Replace('${' + $key + '}', $Define[$key])
  }
  $result
}

# 本ツールのレイアウト（enable-<識別子>/<サイト>.conf）を前提に、サイトごとの Listen と DocumentRoot を読む
function Read-SiteConfigFile {
  param(
    [Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Lines,
    [hashtable]$Define = @{}
  )
  $ports = @()
  $docRoot = $null
  foreach ($raw in $Lines) {
    $line = $raw.Trim()
    if ($line.StartsWith('#')) { continue }
    if ($line -match '^Listen\s+(?:(\S+):)?(\d+)(?:\s+\S+)?$') {
      $ports += [int]$Matches[2]
    }
    elseif (-not $docRoot -and $line -match '^DocumentRoot\s+"?([^"]+?)"?$') {
      $docRoot = Expand-ApacheVariable -Text $Matches[1] -Define $Define
    }
  }
  [pscustomobject]@{ Ports = $ports; DocumentRoot = $docRoot }
}

function Get-SiteConfiguration {
  param([Parameter(Mandatory)][string]$InstallPath)
  $extra = Join-Path $InstallPath 'apache\conf\extra'
  if (-not (Test-Path -LiteralPath $extra)) { return }
  $define = Get-ApacheDefine -InstallPath $InstallPath
  foreach ($dir in Get-ChildItem -LiteralPath $extra -Directory | Where-Object { $_.Name -like 'enable-*' }) {
    $id = $dir.Name.Substring('enable-'.Length)
    foreach ($file in Get-ChildItem -LiteralPath $dir.FullName -File | Where-Object { $_.Extension -eq '.conf' }) {
      $parsed = Read-SiteConfigFile -Lines @(Get-Content -LiteralPath $file.FullName) -Define $define
      foreach ($port in $parsed.Ports) {
        [pscustomobject]@{
          Id           = $id
          Site         = $file.BaseName
          Port         = $port
          DocumentRoot = $parsed.DocumentRoot
          File         = $file.FullName
        }
      }
    }
  }
}

function Find-FreePort {
  param(
    [Parameter(Mandatory)][int]$Start,
    [AllowEmptyCollection()][int[]]$Used = @(),
    [int]$Count = 10000
  )
  for ($p = $Start; $p -lt ($Start + $Count) -and $p -le 65535; $p++) {
    if ($Used -notcontains $p) { return $p }
  }
  throw "空きポートが見つかりません（$Start から $Count 件を確認）"
}

#endregion

#region インストール済み PHP の検出

function Get-InstalledPhp {
  param([Parameter(Mandatory)][string]$InstallPath)
  $root = Join-Path $InstallPath 'php'
  if (-not (Test-Path -LiteralPath $root)) { return }
  foreach ($dir in Get-ChildItem -LiteralPath $root -Directory | Sort-Object Name) {
    if ($dir.Name -notmatch '^php(\d{2,})$') { continue }
    $digits = $Matches[1]
    $module = Get-ChildItem -LiteralPath $dir.FullName -File |
      Where-Object { $_.Name -match '^php(\d+)apache2_4\.dll$' } | Select-Object -First 1
    if (-not $module) {
      Write-Warning "$($dir.FullName) に Apache 用モジュール（php*apache2_4.dll）がないため対象外にします。"
      continue
    }
    $null = $module.Name -match '^php(\d+)apache2_4\.dll$'
    $major = [int]$Matches[1]

    $version = $null
    $marker = Join-Path $dir.FullName 'multiphp.json'
    if (Test-Path -LiteralPath $marker) {
      try { $version = [version](Get-Content -LiteralPath $marker -Raw | ConvertFrom-Json).Version } catch { $version = $null }
    }
    if (-not $version) {
      $version = [version]('{0}.{1}' -f $digits.Substring(0, 1), $digits.Substring(1))
    }

    $moduleName = 'php_module'
    if ($major -le 7) { $moduleName = "php${major}_module" }
    $dependencies = @($script:PhpDependencyDlls | Where-Object { Test-Path -LiteralPath (Join-Path $dir.FullName $_) })

    [pscustomobject]@{
      Id           = $dir.Name
      Version      = $version
      Major        = $major
      Path         = $dir.FullName
      ModuleFile   = $module.Name
      ModuleName   = $moduleName
      CoreDll      = "php${major}ts.dll"
      Dependencies = $dependencies
      Port         = (Get-DefaultPort $dir.Name)
    }
  }
}

#endregion

#region ネットワーク

# Windows PowerShell 5.1 は既定で TLS 1.2 を使わないことがあるため追加する。
# TLS 1.3 は OS が未対応だと接続自体が失敗することがあるので、明示的には指定しない。
function Enable-ModernTls {
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
}

# システムのプロキシ設定を使い、まずは Windows の資格情報で認証を試みる。
# 407 が返った場合のみ資格情報の入力を求める（Invoke-HttpRequest）。
function Initialize-Network {
  param([pscredential]$ProxyCredential)
  Enable-ModernTls
  $proxy = [Net.WebRequest]::GetSystemWebProxy()
  if ($ProxyCredential) {
    $proxy.Credentials = $ProxyCredential.GetNetworkCredential()
    $script:ProxyPrompted = $true
  }
  else {
    $proxy.Credentials = [Net.CredentialCache]::DefaultNetworkCredentials
  }
  [Net.WebRequest]::DefaultWebProxy = $proxy
}

function Get-HttpStatusCode {
  param($ErrorRecord)
  try {
    $response = $ErrorRecord.Exception.Response
    if ($response) { return [int]$response.StatusCode }
  }
  catch { Write-Verbose 'HTTP ステータスを取得できませんでした。' }
  $null
}

function Invoke-HttpRequest {
  param(
    [Parameter(Mandatory)][string]$Uri,
    [string]$OutFile,
    [string]$UserAgent
  )
  $params = @{ Uri = $Uri; UseBasicParsing = $true }
  if ($OutFile) { $params.OutFile = $OutFile }
  if ($UserAgent) { $params.UserAgent = $UserAgent }
  # Windows PowerShell 5.1 は進捗表示があると大きなファイルの取得が極端に遅くなる
  $ProgressPreference = 'SilentlyContinue'
  try {
    Invoke-WebRequest @params
  }
  catch {
    if ((Get-HttpStatusCode $_) -ne 407 -or $script:ProxyPrompted) { throw }
    $script:ProxyPrompted = $true
    $credential = Get-Credential -Message 'プロキシの認証情報を入力してください'
    if (-not $credential) { throw }
    [Net.WebRequest]::DefaultWebProxy.Credentials = $credential.GetNetworkCredential()
    Invoke-WebRequest @params
  }
}

function Get-WebText {
  param(
    [Parameter(Mandatory)][string]$Uri,
    [string]$UserAgent
  )
  $content = (Invoke-HttpRequest -Uri $Uri -UserAgent $UserAgent).Content
  if ($content -is [byte[]]) { $content = [Text.Encoding]::UTF8.GetString($content) }
  [string]$content
}

function Get-FileSha256 {
  param([Parameter(Mandatory)][string]$Path)
  (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

# 一時ファイルに取得してから置き換えるため、途中で失敗しても壊れたキャッシュは残らない
function Save-Download {
  param(
    [Parameter(Mandatory)][string]$Uri,
    [Parameter(Mandatory)][string]$Path,
    [string]$Sha256,
    [string]$UserAgent,
    [switch]$Force
  )
  $Path = Get-FullPath $Path
  if (-not $Force -and (Test-Path -LiteralPath $Path)) {
    if (-not $Sha256 -or (Get-FileSha256 $Path) -eq $Sha256) {
      Write-Host "  キャッシュを使用: $(Split-Path -Leaf $Path)"
      return $Path
    }
    Write-Warning "キャッシュのハッシュが一致しないため再取得します: $Path"
  }
  $dir = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
  $partial = "$Path.part"
  Write-Host "  ダウンロード中: $Uri"
  Invoke-HttpRequest -Uri $Uri -OutFile $partial -UserAgent $UserAgent | Out-Null
  if ($Sha256) {
    $actual = Get-FileSha256 $partial
    if ($actual -ne $Sha256) {
      Remove-Item -LiteralPath $partial -Force
      throw "SHA256 が一致しません: $Uri（期待値 $Sha256 / 実際 $actual）"
    }
  }
  Move-Item -LiteralPath $partial -Destination $Path -Force
  $Path
}

function Get-PhpReleaseList {
  param(
    [Parameter(Mandatory)][ValidateSet('x86', 'x64')][string]$Arch,
    [string[]]$Only
  )
  $sources = @(
    'https://windows.php.net/downloads/releases/'
    'https://windows.php.net/downloads/releases/archives/'
  )
  $urls = @()
  $sha = @{}
  foreach ($source in $sources) {
    $urls += @(Get-HrefList -Html (Get-WebText $source) -BaseUrl $source)
    try {
      $map = ConvertFrom-Sha256Sum (Get-WebText ($source + 'sha256sum.txt'))
      foreach ($key in $map.Keys) {
        if (-not $sha.ContainsKey($key)) { $sha[$key] = $map[$key] }
      }
    }
    catch {
      Write-Warning "ハッシュ一覧を取得できませんでした。該当ファイルの検証は省略します: $source"
    }
  }
  foreach ($release in Select-PhpRelease -Url $urls -Arch $Arch -Only $Only) {
    $hash = $null
    if ($sha.ContainsKey($release.FileName)) { $hash = $sha[$release.FileName] }
    $release | Add-Member -NotePropertyName Sha256 -NotePropertyValue $hash -PassThru
  }
}

function Get-XdebugBuildList {
  param([Parameter(Mandatory)][ValidateSet('x86', 'x64')][string]$Arch)
  $page = 'https://xdebug.org/download/historical'
  $urls = @(Get-HrefList -Html (Get-WebText $page) -BaseUrl $page -Extension 'dll')
  Select-XdebugBuild -Url $urls -Arch $Arch
}

function Save-ApacheFromLounge {
  param(
    [Parameter(Mandatory)][ValidateSet('x86', 'x64')][string]$Arch,
    [Parameter(Mandatory)][string]$DownloadDir
  )
  $page = 'https://www.apachelounge.com/download/'
  $urls = @(Get-HrefList -Html (Get-WebText -Uri $page -UserAgent $script:LoungeUserAgent) -BaseUrl $page)
  $build = Select-ApacheBuild -Url $urls -Arch $Arch
  if (-not $build) {
    throw "Apache Lounge で $Arch 用の httpd が見つかりませんでした。手動でダウンロードし、-apacheZip で zip を指定してください。"
  }
  Write-Host "  Apache httpd $($build.Version)（$($build.FileName)）"
  Save-Download -Uri $build.Url -Path (Join-Path $DownloadDir $build.FileName) -UserAgent $script:LoungeUserAgent
}

function Install-VcRedist {
  param(
    [Parameter(Mandatory)][ValidateSet('x86', 'x64')][string]$Arch,
    [Parameter(Mandatory)][string]$DownloadDir
  )
  $packages = @(
    @{ Name = '最新の Visual C++ 再頒布可能パッケージ'; Url = "https://aka.ms/vs/17/release/vc_redist.$Arch.exe"; File = "vc_redist.$Arch.exe" }
    @{ Name = 'Visual C++ 2012 再頒布可能パッケージ（PHP 5.5 / 5.6 用）'; Url = "https://download.microsoft.com/download/1/6/B/16B06F60-3B20-4FF2-B699-5E9B7962F9AE/VSU_4/vcredist_$Arch.exe"; File = "vc_redist-vc11.$Arch.exe" }
  )
  foreach ($package in $packages) {
    Write-Host $package.Name
    $path = Save-Download -Uri $package.Url -Path (Join-Path $DownloadDir $package.File) -Force
    $process = Start-Process -FilePath $path -ArgumentList '/install', '/passive', '/norestart' -Wait -PassThru
    # 0: 成功 / 1638: より新しい版が導入済み / 3010, 1641: 再起動が必要
    if (@(0, 1638, 3010, 1641) -notcontains $process.ExitCode) {
      Write-Warning "$($package.Name) のインストールが終了コード $($process.ExitCode) で終了しました。"
    }
  }
}

#endregion

#region 展開と配置

function New-CleanDirectory {
  param([Parameter(Mandatory)][string]$Path)
  if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Recurse -Force }
  New-Item -ItemType Directory -Path $Path -Force | Out-Null
}

function Install-ApachePackage {
  param(
    [Parameter(Mandatory)][string]$ZipPath,
    [Parameter(Mandatory)][string]$ApacheDir,
    [Parameter(Mandatory)][string]$TempRoot
  )
  $temp = Join-Path $TempRoot 'apache'
  New-CleanDirectory $temp
  Expand-Archive -LiteralPath $ZipPath -DestinationPath $temp -Force
  $httpd = Get-ChildItem -LiteralPath $temp -Recurse -File -Filter 'httpd.exe' |
    Where-Object { $_.Directory.Name -eq 'bin' } | Select-Object -First 1
  if (-not $httpd) { throw "zip 内に bin\httpd.exe が見つかりません: $ZipPath" }
  $root = $httpd.Directory.Parent.FullName

  New-Item -ItemType Directory -Path $ApacheDir -Force | Out-Null
  # 配布版の conf は参照用として conf_org に置く。稼働中の conf には触れない。
  $original = Join-Path $ApacheDir 'conf_org'
  if (Test-Path -LiteralPath $original) { Remove-Item -LiteralPath $original -Recurse -Force }
  $distConf = Join-Path $root 'conf'
  if (Test-Path -LiteralPath $distConf) { Move-Item -LiteralPath $distConf -Destination $original }
  Copy-Item -Path (Join-Path $root '*') -Destination $ApacheDir -Recurse -Force
  Remove-Item -LiteralPath $temp -Recurse -Force
}

# テンプレートのうち、まだ存在しないファイルだけを配置する（利用者が編集したファイルは維持）
function Install-ApacheConfig {
  param(
    [Parameter(Mandatory)][string]$InstallPath,
    [Parameter(Mandatory)][string]$TemplateDir
  )
  $confDir = Join-Path $InstallPath 'apache\conf'
  $templateRoot = (Resolve-Path -LiteralPath $TemplateDir).ProviderPath.TrimEnd('\', '/')
  foreach ($source in Get-ChildItem -LiteralPath $templateRoot -Recurse -File) {
    $relative = $source.FullName.Substring($templateRoot.Length).TrimStart('\', '/')
    $destination = Join-Path $confDir $relative
    if (Test-Path -LiteralPath $destination) { continue }
    $parent = Split-Path -Parent $destination
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    Copy-Item -LiteralPath $source.FullName -Destination $destination
  }
  $define = Join-Path $confDir 'define.conf'
  if (-not (Test-Path -LiteralPath $define)) {
    Write-TextFile -Path $define -Lines (New-DefineConfig -InstallPath $InstallPath)
  }
}

function Install-PhpPackage {
  param(
    [Parameter(Mandatory)][string]$ZipPath,
    [Parameter(Mandatory)][string]$Destination,
    [Parameter(Mandatory)][version]$Version,
    [Parameter(Mandatory)][string]$Arch,
    [Parameter(Mandatory)][string]$TempRoot
  )
  $temp = Join-Path $TempRoot ([IO.Path]::GetFileNameWithoutExtension($ZipPath))
  New-CleanDirectory $temp
  Expand-Archive -LiteralPath $ZipPath -DestinationPath $temp -Force
  $module = Get-ChildItem -LiteralPath $temp -File | Where-Object { $_.Name -match '^php\d+apache2_4\.dll$' }
  if (-not $module) {
    Remove-Item -LiteralPath $temp -Recurse -Force
    throw "Apache 用モジュールが含まれていません（ノンスレッドセーフ版の可能性があります）: $ZipPath"
  }
  New-Item -ItemType Directory -Path $Destination -Force | Out-Null
  Copy-Item -Path (Join-Path $temp '*') -Destination $Destination -Recurse -Force
  Remove-Item -LiteralPath $temp -Recurse -Force
  $marker = [pscustomobject]@{ Version = $Version.ToString(); Arch = $Arch } | ConvertTo-Json -Compress
  Write-TextFile -Path (Join-Path $Destination 'multiphp.json') -Lines @($marker)
}

function Initialize-PhpIni {
  param(
    [Parameter(Mandatory)]$Php,
    [Parameter(Mandatory)][hashtable]$Template,
    [bool]$Xdebug
  )
  $ini = Join-Path $Php.Path 'php.ini'
  if (Test-Path -LiteralPath $ini) { return $false }
  $base = Join-Path $Php.Path 'php.ini-development'
  if (-not (Test-Path -LiteralPath $base)) { throw "php.ini-development が見つかりません: $base" }
  $extDir = Join-Path $Php.Path 'ext'
  $files = @()
  if (Test-Path -LiteralPath $extDir) { $files = @(Get-ChildItem -LiteralPath $extDir -File -Filter 'php_*.dll' | ForEach-Object { $_.Name }) }
  $useXdebug = $Xdebug -and ($files -contains 'php_xdebug.dll')
  $addition = New-PhpIniAddition -Version $Php.Version -ExtensionDir $extDir -ExtensionFiles $files -Template $Template -Xdebug $useXdebug
  Write-TextFile -Path $ini -Lines (@(Get-Content -LiteralPath $base) + $addition)
  $true
}

function Initialize-DefaultSite {
  param(
    [Parameter(Mandatory)][string]$InstallPath,
    [Parameter(Mandatory)][string]$Id
  )
  $dir = Join-Path $InstallPath "apache\conf\extra\enable-$Id"
  if (Test-Path -LiteralPath $dir) { return $false }
  Write-TextFile -Path (Join-Path $dir 'default.conf') -Lines (New-DefaultSiteConfig -Id $Id -Port (Get-DefaultPort $Id))
  $true
}

#endregion

#region サービスとファイアウォール

function Get-HttpdPath {
  param([Parameter(Mandatory)][string]$InstallPath)
  Join-Path $InstallPath 'apache\bin\httpd.exe'
}

function Get-HttpdDefineArgument {
  param([Parameter(Mandatory)][string]$Id)
  if ($Id -eq $script:StaticId) { return @() }
  @('-D', $Id)
}

function Test-HttpdConfig {
  param(
    [Parameter(Mandatory)][string]$InstallPath,
    [Parameter(Mandatory)][string]$Id
  )
  $arguments = @('-t') + @(Get-HttpdDefineArgument $Id)
  $result = Invoke-NativeCommand -FilePath (Get-HttpdPath $InstallPath) -ArgumentList $arguments
  [pscustomobject]@{ Success = ($result.ExitCode -eq 0); Output = $result.Output }
}

function Get-MultiPhpService {
  Get-CimInstance -ClassName Win32_Service -Filter "Name LIKE '$($script:ServicePrefix)%'"
}

# 未登録のサービスだけを登録する（登録済みのサービスは起動種別などを維持するため作り直さない）
function Register-MultiPhpService {
  param(
    [Parameter(Mandatory)][string]$InstallPath,
    [Parameter(Mandatory)][string]$Id
  )
  $name = Get-ServiceNameForId $Id
  $httpd = Get-HttpdPath $InstallPath
  $existing = Get-CimInstance -ClassName Win32_Service -Filter "Name='$name'"
  if ($existing) {
    if ($existing.PathName.IndexOf($httpd, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
      throw "サービス $name は別の場所の httpd を指しています（$($existing.PathName)）。remove-service.ps1 で削除してから再実行してください。"
    }
    return 'Existing'
  }
  $arguments = @('-k', 'install', '-n', $name) + @(Get-HttpdDefineArgument $Id)
  $result = Invoke-NativeCommand -FilePath $httpd -ArgumentList $arguments
  if (-not (Get-Service -Name $name -ErrorAction SilentlyContinue)) {
    throw "サービス $name を登録できませんでした。`n$($result.Output -join "`n")"
  }
  'Created'
}

function Set-ServiceEnvironment {
  param(
    [Parameter(Mandatory)][string]$ServiceName,
    [Parameter(Mandatory)][string[]]$Variable
  )
  $key = "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName"
  New-ItemProperty -LiteralPath $key -Name 'Environment' -PropertyType MultiString -Value $Variable -Force | Out-Null
}

function Set-MultiPhpFirewallRule {
  param(
    [Parameter(Mandatory)][string]$InstallPath,
    [Parameter(Mandatory)][string[]]$FirewallProfile
  )
  Remove-MultiPhpFirewallRule
  New-NetFirewallRule -Name $script:FirewallRuleName -DisplayName 'Apache-multiPHP (httpd.exe)' `
    -Direction Inbound -Action Allow -Protocol TCP -Program (Get-HttpdPath $InstallPath) `
    -Profile $FirewallProfile | Out-Null
}

function Remove-MultiPhpFirewallRule {
  Get-NetFirewallRule -Name $script:FirewallRuleName -ErrorAction SilentlyContinue | Remove-NetFirewallRule
}

function Get-ListeningPort {
  Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | ForEach-Object {
    [pscustomobject]@{ Port = [int]$_.LocalPort; ProcessId = [int]$_.OwningProcess }
  }
}

#endregion

Export-ModuleMember -Function *
