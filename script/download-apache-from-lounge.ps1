Param(
  $arch = "x64",
  [string]$outdir = [string](Get-Location)
)

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# アーキテクチャ書き換え
$arch = switch ($arch) {
  x86 { 
    "win32"
  }
  x64 {
    "win64"
  }
  Default {
    "win64"
  }
}

Write-Host '
############################################################
現在取得可能なビルド済みApache httpdをダウンロードします。
https://www.apachelounge.com/download/
############################################################
'

# Apache LoungeはUAを見てアクセス制限をしている模様（Bot除け？）
# 適当に現行ブラウザのUAを借りてきてそれを名乗ることで回避する
$ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:109.0) Gecko/20100101 Firefox/119.0"

$response = Invoke-WebRequest "https://www.apachelounge.com/download/" -UserAgent $ua
$targetregex = "httpd-(\d*.\d*.\d*)-(\d*)-" + $arch + "-(v[sc]\d*)"

$links = @()

$response.ParsedHtml.getElementsByTagName("a") | ForEach-Object {
  if($_.innerHTML -match $targetregex){
    $links += [PSCustomObject]@{
      "version" = $Matches[0]
      "url"     = "https://www.apachelounge.com/" + $_.pathname
    }
  }
}

$links | Format-Table -AutoSize

Write-Host "ダウンロードを開始します。"
$dlurl = $links[0].url
Invoke-WebRequest $dlurl -OutFile ($outdir + "\apache.zip") -UserAgent $ua
Write-Host "ダウンロードが完了しました。"