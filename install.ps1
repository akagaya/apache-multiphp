﻿Param(
  $installPath = ".\server\",
  [ValidateSet("x86", "x64")]$arch = "x64",
  [bool]$threadsafe = $true,
  [bool]$xdebug = $true
)
# パス準備
$startpath = Get-Location
try {
  $dldir = $installPath + "\downloads\" 
  if(-not(Test-Path $dldir)){
    New-Item $dldir -ItemType Directory -ErrorAction stop
  }
  $installPath = Convert-Path $installPath -ErrorAction stop
  $dldir = Convert-Path $dldir -ErrorAction Stop
}
catch {
  Write-Host $_
  Write-Host '
ファイル操作に失敗しました。
インストール先フォルダのアクセス権設定を確認してください。
インストール処理を終了します。
' -ForegroundColor Red
  Set-Location $startpath  
  return
}

Start-Transcript -Path ($installPath + "\multiphp-installlog-" + [String](Get-Date -Format 'yyyyMMdd_HHmmss') + ".log")

Write-Host '
############################################################
Apache-multiPHP インストーラ
############################################################
インストール済みサービスを停止します。
'
Get-Service -Name "multiPHP-*" | ForEach-Object {
  Stop-Service $_
}


# ダウンロード処理
Set-Location $PSScriptRoot
try {
  # プロキシ設定
  . .\script\set-proxy.ps1

  # Visual C++ランタイムパッケージ
  Write-Host "最新のVisual C++ランタイムパッケージをダウンロードします。"
  Invoke-WebRequest ("https://aka.ms/vs/17/release/vc_redist." + $arch + ".exe") -OutFile ($dldir + "\vc_redist." + $arch + ".exe")
  Write-Host "最新のVisual C++ランタイムパッケージをインストールします。"
  Start-Process ($dldir + "\vc_redist." + $arch + ".exe") -ArgumentList "/install /passive /norestart" -Wait
  Write-Host "以前のVisual C++ランタイムパッケージ（VC11）をダウンロードします。"
  Invoke-WebRequest ("https://download.microsoft.com/download/1/6/B/16B06F60-3B20-4FF2-B699-5E9B7962F9AE/VSU_4/vcredist_" + $arch + ".exe") -OutFile ($dldir + "\vc_redist-vc11." + $arch + ".exe")
  Write-Host "以前のVisual C++ランタイムパッケージ（VC11）インストールします。"
  Start-Process ($dldir + "\vc_redist-vc11." + $arch + ".exe") -ArgumentList "/install /passive /norestart" -Wait
  Write-Host "PHP 5.4以前の実行にはさらにランタイムパッケージが必要な場合があります。公式サイトより取得してインストールしてください。"
  Write-Host "https://learn.microsoft.com/ja-JP/cpp/windows/latest-supported-vc-redist"

  # Apache HTTPDダウンロード
  .\script\download-apache-from-lounge.ps1 -arch $arch -outdir $dldir

  # PHPダウンロード
  .\script\download-php.ps1 -arch $arch -threadsafe $threadsafe -outdir ($dldir + "\php")

  # XDebugモジュールダウンロード
  if($xdebug){
    .\script\download-php-xdebug.ps1 -arch $arch -outdir ($dldir + "\php\xdebug")
  }
}
catch {
  Write-Host $_
  Write-Host "ファイルのダウンロードに失敗しました。処理を終了します。"
  Remove-Item $dldir -Force -Recurse
  Set-Location $startpath  
  return
}


Write-Host '
############################################################
Apache-multiPHP インストール
############################################################
'
# ファイル展開
Write-Host "ファイルの展開を開始します。"
Set-Location $installPath
# Apache
############################################################
Write-Host "Apache展開中..." -NoNewline
Expand-Archive -Path ($dldir + "apache.zip") -DestinationPath "apache_ext" -Force
Move-Item -Path ".\apache_ext\Apache24\*" -Destination ".\apache_ext" -Force
Remove-Item ".\apache_ext\Apache24" -Force -Recurse
# conf処理
Move-Item -Path ".\apache_ext\conf" -Destination ".\apache_ext\conf_org"
if (Test-Path ".\apache\conf_org") {
  Remove-Item ".\apache\conf_org" -Force -Recurse
}
if(-not(Test-Path ".\apache")){
  New-Item ".\apache" -ItemType Directory
}
Copy-Item -Path ".\apache_ext\*" -Destination ".\apache" -Force -Recurse
Remove-Item ".\apache_ext" -Force -Recurse

# confが存在しない場合のみconfをコピー
if ((Test-Path ".\apache\conf")) {
  Write-Host "confフォルダが存在するため、設定を変更せずそのまま利用します。"
} else {
  New-Item ".\apache\conf" -ItemType Directory > $null
  Copy-Item -Path ($PSScriptRoot + "\config\apache\*") -Destination ".\apache\conf" -Force -Recurse
  # 関連パスをセット
  Add-Content -Path ".\apache\conf\define.conf" -Value ('
Define SRVROOT "' + $installPath + '\apache"
Define DEFAULT_DOCROOT "' + $installPath + '\htdocs"
Define DEFAULT_LOGDIR "' + $installPath + '\logs"
Define PHPROOT "' + $installPath + '\php"
')
}
Write-Host "完了"


# PHP
############################################################
Write-Host "PHP展開中..." -NoNewline
$phplist = Import-Csv -Path ($dldir + "\php\downloaded-php.csv")
if (-not(Test-Path "php")) {
  New-Item -Path "php" -ItemType Directory > $null
}

$cnt = 1
$phplist | ForEach-Object {
  # 進捗表示
  Write-Progress -Activity "展開中 - PHP" -PercentComplete ($cnt / $phplist.Count * 100) -Status "$($_.Version) - $([string]$cnt) / $([string]$phplist.Count)"
  $cnt++

  $exp = "php" + ($_.Version -replace "\.", "")
  Expand-Archive -Path $_.File -DestinationPath $exp -Force
  if(-not(Test-Path "php\$exp")){
    New-Item "php\$exp" -ItemType Directory > $null
  }
  # 既存ファイルがあっても強制上書き
  Copy-Item -Path "$exp\*" -Destination ("php\" + $exp) -Force -Recurse
  Remove-Item $exp -Recurse -Force
}
Write-Progress -Activity "展開中 - PHP" -Completed

# `php.ini`の設置とXDebugの反映
$xdbgconf = Get-Content ($PSScriptRoot + "\config\php\xdebug.ini")
$phplist = Get-ChildItem ".\php"
$phplist | ForEach-Object {
  # `php.ini`が存在しない場合だけコピー
  if(-not(Test-Path ($_.FullName + "\php.ini"))){
    Copy-Item -Path ($PSScriptRoot + "\config\php\" + $_.Name + "\*") -Destination $_.FullName -Recurse
    # extを絶対パスで追記
    Add-Content -Path ($_.FullName + "\php.ini") -Value ('extension_dir = "' + $_.FullName + '\ext"')
    
    # 新規コピー時のみXDebug設定を追記
    if($xdebug){
      Copy-Item -Path ($dldir + "\php\xdebug\" + $_.Name + "\*") -Destination $_.FullName -Recurse -Force
      Add-Content -Path ($_.FullName + "\php.ini") -Value $xdbgconf
    }
  }
}
Write-Host "完了"

# 既定のDocumentRootとlogsフォルダ設置
Write-Host "既定フォルダの展開中..."
if(-not(Test-Path ($installPath + "\logs")) ){
  New-Item -Path ($installPath + "\logs") -ItemType Directory > $null
}
if (-not(Test-Path ($installPath + "\htdocs")) ) {
  Copy-Item -Path ($PSScriptRoot + "\htdocs") -Destination $installPath -Recurse
}
Write-Host "既定フォルダの展開完了"


################################################################
# サービス登録
################################################################
Write-Host "サービス登録を開始します。"
# 一旦全削除
Write-Host "既存サービス削除中..."
Get-Service -Name "multiPHP-*" | ForEach-Object{
  sc.exe delete $_.Name
}
# 追加
Write-Host "サービス登録中..."
Invoke-Expression ($installPath + '\apache\bin\httpd.exe -k install -n "multiphp-static"')
$phplist | ForEach-Object {
  $expression = $installPath + '\apache\bin\httpd.exe -k install -n "multiphp-' + $_.Name + '" -D' + $_.Name
  $expression
  Invoke-Expression ($expression)
}

Get-Service -Name "multiPHP-*" | ForEach-Object {
  start-service $_
}

Write-Host '
############################################################
インストールが完了しました！
'

Set-Location $startpath
Stop-Transcript