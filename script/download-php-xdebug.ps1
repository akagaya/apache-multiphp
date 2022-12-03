# x86(32bit) or x64(64bit)
Param(
  [ValidateSet("x86", "x64")]$arch = "x64",
  [bool]$threadsafe = $true,
  [string]$outdir = "php"
)

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Write-Host '
############################################################
現在取得可能なビルド済みXdebugをダウンロードします。
https://xdebug.org/download/historical
############################################################
'

$baseUrl = "https://xdebug.org"
$targetregex = "php_xdebug-(\d*\.\d*\.\d*(?:RC\d*)?)-(\d*\.\d*)-v[cs]\d*" +
  (& { if (-not $threadsafe) { Write-Output "-nts" } }) +
  (& { if ($arch -eq "x64") { Write-Output "-x86_64" } }) +
".dll"

# 配布ページスクレイピング
$response = Invoke-WebRequest ($baseUrl + "/download/historical")
$html = $response.ParsedHtml.getElementsByTagName("a")
$xdbglist = @{}
foreach ( $dom in $html ) {
  if ( ($dom.pathname -match $targetregex) ) {
    $mver = $Matches[2]

    # 各最新版リンクを取得
    if (($xdbglist[$mver] -eq $null) -or ($xdbglist[$mver]["latest"] -lt $Matches[1]) ) {
      $pkginfo = @{
        "latest" = $Matches[2]
        "link"   = $baseUrl + "/" + $dom.pathname
      }
      $xdbglist[$mver] = $pkginfo
    }
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