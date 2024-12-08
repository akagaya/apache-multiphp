$tgtsvc = Get-Service multiphp-*
$tgtsvc | ForEach-Object {
  $_ | Stop-Service
  Start-Process sc -ArgumentList "delete",$_.ServiceName
}