$tgtsvc = Get-Service multiphp-*
$tgtsvc | ForEach-Object {
  $_ | Stop-Service
  $_ | Set-Service -StartupType Manual
}