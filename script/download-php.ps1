# x86(32bit) or x64(64bit)
Param(
  [ValidateSet("x86", "x64")]$arch = "x64",
  [bool]$threadsafe = $true,
  [string]$outdir = "php"
)

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Write-Host '
############################################################
現在取得可能なビルド済みPHPをダウンロードします。
https://windows.php.net/downloads/releases/
https://windows.php.net/downloads/releases/archives/
############################################################
'

$baseUrl = "https://windows.php.net/"
$targetUrl = @(
  "downloads/releases/",          # サポート中のバージョン
  "downloads/releases/archives/"  # サポート終了（EOL）のバージョン
)

$phplist = @{}
# HTMLスクレイピング用
$targetregex = "php-(\d*\.\d*)\.(\d*)" + (&{if(-not $threadsafe){Write-Output "-nts"}}) + "-Win32-(v[cs]\d*)-" + $arch + "\.zip"

Write-Host "一覧の取得中..."
foreach($url in $targetUrl){
  $response = Invoke-WebRequest ($baseUrl + $url)
  # aタグ一覧を取得。Powershell7.xから`ParsedHtml`プロパティは削除されたため、5.1を使うか代替案検討
  # https://docs.microsoft.com/ja-jp/powershell/scripting/whats-new/differences-from-windows-powershell?view=powershell-7.2#changes-to-web-cmdlets
  $html = $response.ParsedHtml.getElementsByTagName("a")

  foreach ( $dom in $html ) {
    if ( ($dom.innerHTML -match $targetregex) ) {
      $mver = $Matches[1]

      # 各最新版リンクを取得
      if (($phplist[$mver] -eq $null) -or ([int32]$phplist[$mver]["latest"] -lt [int32]$Matches[2]) ) {
        $pkginfo = @{
          "latest" = $Matches[2]
          "link"   = $baseUrl + $dom.pathname
        }
        $phplist[$mver] = $pkginfo
      }
    }
  }  
}

Write-Host "以下のバージョンが利用可能です。"
$phplist | Format-Table -AutoSize

# ダウンロード処理
Write-Host "ダウンロードを開始します。"
$currentpath = Get-Location
if(-not (Test-Path $outdir)){
  New-Item $outdir -ItemType Directory > $null
}
Set-Location $outdir

$ziplist = [PSCustomObject]@()
# 進捗表示用
$dlcnt = 1

# 処理開始
$phplist.keys | ForEach-Object{
  # 進捗表示
  Write-Progress -Activity "進捗状況 - PHP" -PercentComplete ($dlcnt / $phplist.Count * 100) -Status ([string]$dlcnt + "/" + [string]$phplist.Count)
  $dlcnt++

  $dlzip = ($phplist[$_].link -split "/")[-1]
  Write-Host "ダウンロード中：" $dlzip -NoNewline
  $ziplist += [PSCustomObject]@{
    "Version" = $_
    "MinorVersion" = $phplist[$_].latest
    "File" = [string](Get-Location) + "\$dlzip"
  }
  if(Test-Path $dlzip){
    Write-Host " -> ファイルは既に存在するため、スキップします。"
    return
  }
  Invoke-WebRequest $phplist[$_].link -OutFile $dlzip -UseBasicParsing
  Write-Host " -> 完了"
}
Write-Progress -Activity "進捗状況 - PHP" -Completed
$ziplist | Sort-Object -Property Version -Descending | Export-Csv -Path "downloaded-php.csv" -NoTypeInformation -Encoding UTF8 -Force
Write-Host "ダウンロードが完了しました。"
Set-Location $currentpath

