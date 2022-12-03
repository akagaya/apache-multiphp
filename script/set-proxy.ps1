[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$proxyserver = [System.Net.WebProxy]::GetDefaultProxy().Address.Authority
if( -not($proxyserver) ){
  Write-Output "プロキシ設定は検出されませんでした。"
  return
}
$env:http_proxy = $proxyserver
$env:https_proxy = $proxyserver
$proxy = [System.Net.WebProxy]::GetDefaultProxy()

Write-Output '
プロキシが検出されました。
表示されるダイアログに認証情報を入力してください。
認証が不要な場合は「キャンセル」をクリックします。
'
try {
  $proxycred = Get-Credential  
  $proxy.Credentials = $proxycred
}
catch {
  continue
}
[System.Net.WebRequest]::DefaultWebProxy = $proxy

try {
  Invoke-WebRequest "https://www.google.com/" > $null
}
catch {
  Write-Output "ネットワーク接続に失敗しました。"
  throw "Network error."
}