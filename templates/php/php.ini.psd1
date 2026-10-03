# php.ini の初回生成時に、PHP 同梱の php.ini-development の末尾へ追記する内容
# （既存の php.ini は上書きしません）
@{
  # そのまま追記する設定
  Settings   = @(
    'date.timezone = Asia/Tokyo'
  )

  # 有効化する拡張。ext フォルダに DLL が存在するものだけを有効化します。
  # Min / Max は PHP のマイナーバージョン（例: '8.2'）、Alternatives は旧名です。
  # 並び順は読み込み順です（exif は mbstring より後）。
  Extensions = @(
    @{ Name = 'bz2' }
    @{ Name = 'curl' }
    @{ Name = 'fileinfo' }
    @{ Name = 'gd'; Alternatives = @('gd2') }
    @{ Name = 'gettext' }
    @{ Name = 'ldap'; Max = '8.2' }
    @{ Name = 'mbstring' }
    @{ Name = 'exif' }
    @{ Name = 'openssl' }
    @{ Name = 'pdo_mysql' }
    @{ Name = 'pdo_pgsql' }
    @{ Name = 'pdo_sqlite' }
    @{ Name = 'zip'; Min = '8.2' }
  )

  # Xdebug 3（PHP 7.2 以降）
  Xdebug3    = @(
    'xdebug.mode = debug'
    'xdebug.start_with_request = yes'
    'xdebug.client_port = 9003'
    'xdebug.connect_timeout_ms = 200'
  )

  # Xdebug 2（PHP 7.1 以前）
  Xdebug2    = @(
    'xdebug.remote_enable = 1'
    'xdebug.remote_autostart = 1'
    'xdebug.remote_port = 9003'
    'xdebug.remote_timeout = 200'
  )
}
