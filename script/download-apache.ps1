Param(
  [ValidateSet("x86", "x64")]$arch = "x64",
  [string]$outdir = [string](Get-Location)
)

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Write-Host '
############################################################
現在取得可能なビルド済みApache httpdをダウンロードします。
https://www.apachehaus.com/cgi-bin/download.plx
############################################################
'

$response = Invoke-WebRequest "https://www.apachehaus.com/cgi-bin/download.plx"
$targetregex = "httpd-(\d*.\d*.\d*)-([a-z0-9]*)-" + $arch + "-(v[sc]\d*)"

$links = @()

$response.ParsedHtml.getElementsByTagName("a") | ForEach-Object {
  if($_.innerHTML -match $targetregex){
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