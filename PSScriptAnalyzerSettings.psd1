# PSScriptAnalyzer 設定: Windows PowerShell 5.1（Windows 10 / Server 2019 相当）との互換性を検査する
@{
  ExcludeRules = @(
    # 対話的なインストーラのため、色付きの画面出力に Write-Host を使う
    'PSAvoidUsingWriteHost'
    # 内部関数の New- / Set- に ShouldProcess は持たせない
    'PSUseShouldProcessForStateChangingFunctions'
    # 既存利用者との互換のため、install.ps1 の引数名（-installPath など）を維持する
    'PSUseSingularNouns'
  )
  Rules        = @{
    PSUseCompatibleSyntax   = @{
      Enable         = $true
      TargetVersions = @('5.1')
    }
    PSUseCompatibleCommands = @{
      Enable         = $true
      TargetProfiles = @('win-48_x64_10.0.17763.0_5.1.17763.316_x64_4.0.30319.42000_framework')
    }
    PSUseCompatibleTypes    = @{
      Enable         = $true
      TargetProfiles = @('win-48_x64_10.0.17763.0_5.1.17763.316_x64_4.0.30319.42000_framework')
    }
  }
}
