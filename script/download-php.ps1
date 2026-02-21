# x86(32bit) or x64(64bit)
Param(
  [ValidateSet("x86", "x64")]$arch = "x64",
  [bool]$threadsafe = $true,
  [string]$outdir = "php"
)

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

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
  $fullUrl = $baseUrl + $url
  $response = Invoke-WebRequest $fullUrl -UseBasicParsing
  
  # HTMLからリンク(href)を抽出する正規表現（大文字小文字を区別せず、引用符の有無にも対応）
  $links = [regex]::Matches($response.Content, '(?i)href=["'']?([^"''>]+\.zip)["'']?') | ForEach-Object { $_.Groups[1].Value }

  foreach ($link in $links) {
    # ファイル名部分のみを抽出してマッチング
    $filename = $link -split "/" | Select-Object -Last 1
    if ($filename -match $targetregex) {
      $mver = $Matches[1]
      $pver = $Matches[2]

      # パスを絶対URLに変換
      $absLink = if ($link.StartsWith("http")) { $link } 
                 elseif ($link.StartsWith("/")) { "https://windows.php.net" + $link }
                 else { $baseUrl + $url + $link }

      # 各最新版リンクを取得
      if (($phplist[$mver] -eq $null) -or ([int32]$phplist[$mver]["latest"] -lt [int32]$pver) ) {
        $pkginfo = @{
          "latest" = $pver
          "link"   = $absLink
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

