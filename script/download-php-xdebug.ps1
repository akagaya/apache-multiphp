# x86(32bit) or x64(64bit)
Param(
  [ValidateSet("x86", "x64")]$arch = "x64",
  [bool]$threadsafe = $true,
  [string]$outdir = "php"
)

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

Write-Host '
############################################################
現在取得可能なビルド済みXdebugをダウンロードします。
https://xdebug.org/download/historical
############################################################
'

$baseUrl = "https://xdebug.org"
# バージョンとPHPバージョンを抽出するベース正規表現 (正式リリース版のみを対象にするため RC/alpha/beta は含めない)
$baseRegex = "php_xdebug-(\d+\.\d+\.\d+)-(\d+\.\d+)"

# 配布ページスクレイピング
$response = Invoke-WebRequest ($baseUrl + "/download/historical") -UseBasicParsing
$rawLinks = [regex]::Matches($response.Content, '(?i)href=["'']?([^"''>]+\.dll)["'']?') | ForEach-Object { $_.Groups[1].Value }

$xdbglist = @{}
foreach ( $link in $rawLinks ) {
  $filename = $link -split "/" | Select-Object -Last 1
  if ( ($filename -match $baseRegex) ) {
    $ver  = $Matches[1]
    $mver = $Matches[2]

    # すでにそのPHPバージョンの最新を見つけている場合はスキップ（上にあるものほど新しい）
    if ($xdbglist.ContainsKey($mver)) { continue }

    # 1. アーキテクチャのチェック
    if ($arch -eq "x64" -and $filename -notmatch "-x86_64") { continue }
    if ($arch -eq "x86" -and $filename -match "-x86_64") { continue }

    # 2. スレッドセーフのチェック
    if ($threadsafe) {
      # TS希望時：NTSタグがあるものは除外
      if ($filename -match "-nts[-.]") { continue }
    } else {
      # NTS希望時：NTSタグがあるもののみ
      if ($filename -notmatch "-nts[-.]") { continue }
    }

    # 最初に適合したものを最新として記録
    $pkginfo = @{
      "latest_ver" = $ver
      "link"       = if ($link.StartsWith("http")) { $link } 
                     elseif ($link.StartsWith("/")) { $baseUrl + $link }
                     else { $baseUrl + "/download/" + $link }
    }
    $xdbglist[$mver] = $pkginfo
  }
}

# ダウンロード
$currentpath = Get-Location

if (-not (Test-Path $outdir)) {
  New-Item $outdir -ItemType Directory > $null
}
Set-Location $outdir

$dlcnt = 1
$xdbglist.Keys | ForEach-Object {
  # 進捗表示
  Write-Progress -Activity "進捗状況 - XDebug" -PercentComplete ($dlcnt / $xdbglist.Count * 100) -Status ([string]$dlcnt + "/" + [string]$xdbglist.Count)
  $dlcnt++

  Write-Host "ダウンロード中：" $xdbglist[$_].link
  $path = New-Item ("php" + ($_ -replace "\.", "") + "\ext\") -ItemType Directory -Force
  Invoke-WebRequest $xdbglist[$_].link -OutFile ([String]$path + "\php_xdebug.dll") -UseBasicParsing
}
Write-Progress -Activity "進捗状況 - XDebug" -Completed

Set-Location $currentpath
Write-Host "ダウンロードが完了しました。"