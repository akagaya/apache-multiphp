Param(
    [string]$installPath = ".\server"
)

# パスの解決
$fullPath = Resolve-Path $installPath -ErrorAction SilentlyContinue
if (-not $fullPath) {
    Write-Error "指定されたインストールパスが見つかりません: $installPath"
    return
}

$basePath = $fullPath.ProviderPath
$extraDir = Join-Path $basePath "apache\conf\extra"
if (-not (Test-Path $extraDir)) {
    Write-Error "Apacheの設定ディレクトリが見つかりません: $extraDir"
    return
}

Write-Host "Scanning: $extraDir" -ForegroundColor Cyan

$results = @()
# enable-* フォルダ内のすべての .conf ファイルを対象にする
$confFiles = Get-ChildItem -Path $extraDir -Filter "*.conf" -Recurse | Where-Object { $_.DirectoryName -match "enable-" }

foreach ($file in $confFiles) {
    $parentDir = $file.Directory.Name
    $content = Get-Content $file.FullName
    
    $currentPort = $null
    $currentDocRoot = $null
    $currentServerName = $null

    foreach ($line in $content) {
        $trimmed = $line.Trim()
        if ($trimmed.StartsWith("#")) { continue }

        # Listen ポートの抽出
        if ($trimmed -match "Listen\s+(\d+)") {
            $currentPort = $Matches[1]
        }
        # DocumentRoot の抽出
        if ($trimmed -match 'DocumentRoot\s+"?([^"\s]+)"?') {
            $currentDocRoot = $Matches[1]
        }
        # ServerName の抽出
        if ($trimmed -match 'ServerName\s+([^\s]+)') {
            $currentServerName = $Matches[1]
        }

        # 1つの Listen 設定が見つかるごとに記録
        if ($currentPort) {
            $results += [PSCustomObject]@{
                PHP_Version  = $parentDir -replace "enable-", ""
                Port         = $currentPort
                ServerName   = if ($currentServerName) { $currentServerName } else { "N/A" }
                DocumentRoot = if ($currentDocRoot) { $currentDocRoot } else { "N/A" }
                ConfigFile   = $file.Name
            }
            # 次の検索のためにリセット
            $currentPort = $null
        }
    }
}

if ($results.Count -eq 0) {
    Write-Host "有効なポート設定は見つかりませんでした。" -ForegroundColor Yellow
} else {
    $results | Sort-Object Port | Format-Table -AutoSize
    
    # 実行ディレクトリに出力
    $results | ConvertTo-Json | Set-Content "installed_ports.json" -Encoding utf8
    $results | Export-Csv -Path "installed_ports.csv" -NoTypeInformation -Encoding utf8
    Write-Host "Done." -ForegroundColor Green
}
