Param(
  [ValidateSet("x86", "x64")]$arch = "x64",
  [string]$outdir = [string](Get-Location)
)

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

Write-Host '
############################################################
現在取得可能なビルド済みApache httpdをダウンロードします。
https://www.apachehaus.com/cgi-bin/download.plx
############################################################
'

$response = Invoke-WebRequest "https://www.apachehaus.com/cgi-bin/download.plx" -UseBasicParsing
$targetregex = "httpd-(\d*.\d*.\d*)-([a-z0-9]*)-" + $arch + "-(v[sc]\d*)"

$links = @()

# HTMLからリンク(href)を抽出する正規表現
$rawLinks = [regex]::Matches($response.Content, '(?i)href=["'']?([^"''>]+\.zip)["'']?') | ForEach-Object { $_.Groups[1].Value }

foreach ($link in $rawLinks) {
  # ファイル名部分のみを抽出してマッチング
  $filename = $link -split "/" | Select-Object -Last 1
  if($filename -match $targetregex){
    $links += [PSCustomObject]@{
      "version" = $Matches[1]
      "sslver" = $Matches[2]
      "arch" = $arch
      "build" = $Matches[3]
    }
  }
}

$links | Format-Table -AutoSize

Write-Host '開いたウィンドウの中から取得するバージョンを選択し、「OK」を押してください。
特に理由がない限り、「sslver」が「oから始まり数値の大きいもの」を選択します。
'
$selectver = $links | Out-GridView -PassThru
if($null -eq $selectver){
  throw "Download Error."
}
Write-Host $selectver

Write-Host "ダウンロードを開始します。"
$dlurl = "https://www.apachehaus.com/downloads/httpd-" + 
  "$($selectver.version)-$($selectver.sslver)-$($selectver.arch)-$($selectver.build).zip"
Invoke-WebRequest $dlurl -OutFile ($outdir + "\apache.zip")
Write-Host "ダウンロードが完了しました。"