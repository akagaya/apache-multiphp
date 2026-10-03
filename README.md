# apache-multiphp

## これは何？

Windows に「Apache HTTPD」と複数バージョンの「PHP」「Xdebug」を一括でインストールし、PHP のバージョンごとに Windows サービスとして同時に動かすためのスクリプト群です。

もともとは、DNS のない小規模なイントラネットの共有試験サーバーで、プロジェクトごとに指定した PHP バージョンのサイトを「ポート単位の VirtualHost」として払い出すために作りました。同じ環境を開発メンバーの手元にも再現できるよう、インストーラーとして整備しています。

* PHP のバージョンごとに `multiphp-phpXX` という Windows サービスを登録します（各サービスで PHP はモジュールとして動作します）。
* サイトは「PHP バージョン × ポート」で払い出します。名前解決（DNS や hosts）は不要です。
* 共有サーバーでも個人の端末でも、**イントラネットに公開する前提**の設定です（全インターフェースで待ち受けます）。

**本番環境での利用は想定していません。** サポートの終了した PHP も動かすため、信頼できるネットワーク内でのみ利用してください。

### 取得元

* Apache HTTPD: https://www.apachelounge.com/download/
* PHP: https://windows.php.net/downloads/releases/ と https://windows.php.net/downloads/releases/archives/
* Xdebug: https://xdebug.org/download/historical

PHP は windows.php.net が公開している SHA256 で検証します（公開されていないファイルは警告を出して検証を省略します）。

### 対応する PHP バージョン

取得できる **PHP 5.5 以降のスレッドセーフ版すべて** が対象です。バージョンごとの設定ファイルはインストール時に生成するため、新しい PHP が公開されたときもスクリプトの修正なしで導入できます。

## 動作環境

* Windows 10 / Windows Server 2016 以降
* Windows PowerShell 5.1 以降
* 管理者権限

## 使い方

### インストール・更新

管理者として起動した PowerShell で `install.ps1` を実行します。既定ではカレントフォルダの `server` フォルダにインストールします。

```powershell
.\install.ps1
# 例: インストール先と PHP バージョンを指定し、ファイアウォール規則も作成する
.\install.ps1 -installPath D:\multiphp -phpVersions 7.4,8.3,8.4 -firewall
```

| 引数 | 既定値 | 説明 |
| --- | --- | --- |
| `-installPath` | `.\server` | インストール先 |
| `-arch` | `x64` | `x64` または `x86` |
| `-xdebug` | `$true` | Xdebug を導入するか |
| `-phpVersions` | （すべて） | 導入する PHP のマイナーバージョン（例: `7.4,8.4`） |
| `-apacheZip` | （自動取得） | 手元の Apache httpd の zip を使う場合に指定 |
| `-firewall` | なし | `httpd.exe` の受信を許可するファイアウォール規則を作成 |
| `-firewallProfile` | `Domain,Private` | ファイアウォール規則のプロファイル |
| `-proxyCredential` | （自動） | 認証付きプロキシの資格情報。省略時は Windows の資格情報を試し、拒否されたら入力を求めます |
| `-skipVcRedist` | なし | Visual C++ 再頒布可能パッケージの導入を省略 |

`-threadsafe $false` は指定できなくなりました。ノンスレッドセーフ版 PHP には Apache 用モジュールが含まれないためです。

Apache Lounge はブラウザ以外からのアクセスを制限しています。自動取得ではブラウザの User-Agent を名乗って取得しますが、失敗する場合や避けたい場合は、ブラウザで zip を取得して `-apacheZip` で指定してください。

インストール先には次のフォルダを作成します。

```
インストール先
├─apache      Apache HTTPD
├─php         PHP（php55, php56, ... php84 のようにバージョンごと）
├─htdocs      既定のドキュメントルート
├─sites       new-site.ps1 で払い出したサイトの既定のドキュメントルート
├─logs        ログ
└─downloads   ダウンロードのキャッシュ
```

### サイトの払い出し

```powershell
# PHP 7.4 で動くサイトを作成（ポートは 30000 以降の空きを自動選択）
.\new-site.ps1 -name project-a -php 7.4

# ポートとドキュメントルートを指定
.\new-site.ps1 -name project-b -php 8.4 -port 30100 -documentRoot D:\www\project-b

# PHP を使わない静的サイト
.\new-site.ps1 -name docs -php static
```

`apache\conf\extra\enable-<識別子>\<サイト名>.conf` を作成し、構成テストに通れば該当サービスを再起動します。構成テストに失敗した場合は作成を取り消します。ドキュメントルートを省略した場合は `sites\<サイト名>` を作成します。

払い出したサイトを止めるには `remove-site.ps1` を使います。conf を改名して読み込み対象から外すだけで、ドキュメントルートとログは残します。

```powershell
.\remove-site.ps1 -name project-a
```

### サイトの一覧

```powershell
.\get-sites.ps1 | Format-Table
.\get-sites.ps1 | Export-Csv sites.csv -NoTypeInformation -Encoding UTF8
```

設定上のポートと、`httpd` が実際にそのポートで待ち受けているか（`Listening`）を突き合わせて表示します。`Listening` が `OtherProcess` の場合は、ほかのプログラムがそのポートを使っています。

### サービスの停止・削除

```powershell
.\stop-service.ps1              # すべて停止し、起動種別を手動にする
.\stop-service.ps1 -php 7.4     # 特定のバージョンだけ
.\remove-service.ps1            # サービスとファイアウォール規則を削除（ファイルは残す）
```

## 既定の構成

### サービスとポート

| サービス名 | 既定のポート | 内容 |
| --- | --- | --- |
| `multiphp-static` | 80 | PHP を読み込まない Apache HTTPD |
| `multiphp-phpXX` | `200XX`（20000 + 識別子の数字部。PHP 8.4 なら 20084） | 対応するバージョンの PHP を読み込む Apache HTTPD |

各サービスの既定のサイトは `インストール先\htdocs` をドキュメントルートとします。

### Xdebug

すべてのリクエストで IDE（ポート `9003`）への接続を試みます（`xdebug.start_with_request = yes`）。PHP 7.1 以前は Xdebug 2、7.2 以降は Xdebug 3 の設定を書き込みます。

## 設定を変更する

設定方法は各ソフトウェアのドキュメントを参照してください。

* Apache HTTPD: https://httpd.apache.org/docs/2.4/
* PHP: https://www.php.net/manual/ja/configuration.file.php
* Xdebug: https://xdebug.org/docs/all_settings

### 更新時に維持されるファイル・上書きされるファイル

| 種類 | ファイル | 更新時 |
| --- | --- | --- |
| 利用者の設定 | `apache\conf` 内のファイル（`httpd.conf` など）、`define.conf`、`apache\conf\extra\enable-*\`、各 PHP の `php.ini` | 存在しない場合のみ作成。既存のものは変更しない |
| ツールの管理 | `apache\conf\extra\php-loader.conf`、`apache\conf\extra\php\*.conf` | 毎回再生成（直接編集しないでください） |
| バイナリ | Apache HTTPD、PHP、Xdebug | 最新版で上書き |

`htdocs`、`sites`、`logs` には触れません。登録済みのサービスは作り直さず、起動種別を維持します。更新前に動いていたサービスと、新しく登録したサービスを起動します。

### 共通のドキュメントルートやログフォルダを変更する

`インストール先\apache\conf\define.conf` の次の行を書き換えてください。

```apacheconf
Define DEFAULT_DOCROOT "ここを書き換え"
Define DEFAULT_LOGDIR "ここを書き換え"
```

### サイトの設定を変更する

`インストール先\apache\conf\extra\enable-<識別子>\` 内の `*.conf` を編集・追加してください。フォルダ内の `*.conf` はすべて、対応するサービスの起動時に読み込まれます。

```
インストール先\apache\conf\extra
├─enable-static   multiphp-static が読み込むサイト設定
├─enable-php55    multiphp-php55 が読み込むサイト設定
├─enable-phpXX
├─php             PHP の読み込み設定（ツール管理）
└─php-loader.conf PHP の切り替え（ツール管理）
```

### PHP 拡張の依存 DLL について

`libpq.dll` などの依存 DLL を解決するため、各サービスの環境変数 `PATH` の先頭に、そのサービスの PHP フォルダを設定しています（レジストリ `HKLM\SYSTEM\CurrentControlSet\Services\<サービス名>\Environment`）。システムの `PATH` を変更した場合は、`install.ps1` を再実行すると反映されます。

## 開発

```powershell
# 単体テスト（Windows 以外の PowerShell 7 でも実行可能）
pwsh -NoProfile -File tests/run-tests.ps1

# 静的解析（PowerShell 5.1 との互換性を含む）
Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
```

`.ps1` / `.psm1` は Windows PowerShell 5.1 で日本語を正しく読めるよう、BOM 付き UTF-8 で保存してください。

## FAQ

### コンテナ技術を使えばよいのでは？

本番環境（多くは Linux）との一致が重要な場合は、コンテナを使ってください。本ツールは「Windows 上で、複数の PHP バージョンを手軽に同時に動かしたい」場合のためのものです。Windows 版 PHP と Linux 版 PHP の差（ファイル名の大文字小文字、パス区切り、利用できる拡張など）は検出できません。

### サービスが起動しない

`install.ps1` の最後に表示される一覧と、`インストール先\logs` のエラーログを確認してください。構成テストに失敗したサービスは起動しません。手動で確認する場合は次のように実行します。

```powershell
インストール先\apache\bin\httpd.exe -t -D php84
```
