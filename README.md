# apache-multiphp

## これは何？

Windows環境に「Apache HTTPD」と現在ダウンロード可能な「PHP」の複数バージョン、「Xdebug」を一括でインストールするスクリプトです。
PHPのメジャーバージョンごとに`multiphp-phpXX`というWindowsサービスを登録します。
「環境面で制約があるものの、1環境で複数のPHPバージョンを共存させたい」といった特殊な場合に利用可能です。
その性質上、主に開発用の利用を想定しています。
**本番環境での利用は想定していません**

「Apache HTTPD」と「PHP」の各バージョン、「Xdebug」は下記ページより最新ビルドを取得・インストールします。

* Apache HTTPD
  * https://www.apachehaus.com/cgi-bin/download.plx
* PHP
  * https://windows.php.net/downloads/releases/
  * https://windows.php.net/downloads/releases/archives/
* Xdebug
  * https://xdebug.org/download/historical

### PHPバージョン対応

現在、以下バージョンのPHP用設定が含まれます。

* 5.5
* 5.6
* 7.0
* 7.1
* 7.2
* 7.3
* 7.4
* 8.0
* 8.1
* 8.2

## 使い方

管理者権限で実行したPowerShellにて`install.ps1`を実行してください。
既定ではスクリプトが置かれたパス配下に`server`というフォルダを作成し、その中にインストールします。

### 起動パラメータ

`install.ps1`の起動パラメータを以下に示します。

* `-installPath`
  * インストール先パスを文字列などで指定します。
    * 既定値：`.\server`
  * 指定されたパス配下に下記フォルダを作成し、ファイルを設置します。
    * `downloads`
    * `apache`
    * `php`
    * `htdocs`
    * `logs`
* `-arch`
  * 取得・インストールするバイナリのアーキテクチャを文字列で指定します。
    * 既定値：`x64`
  * 32bit版をインストールしたい場合は`x86`を指定します。
* `-threadsafe`
  * 取得・インストールするバイナリのスレッドセーフ要否を真偽値で指定します。
    * 既定値：`$true`（スレッドセーフ版をインストールする）
  * ノンスレッドセーフ版をインストールしたい場合は`$false`を指定します。
* `-xdebug`
  * PHPの拡張機能である「Xdebug」のインストール要否を真偽値で指定します。
    * 既定値：`$true`
  * 「Xdebug」が不要な場合は`$false`を指定します。

## 新規インストール後の既定値

新規インストール直後の挙動を以下に示します。

### Windowsサービスの分離

インストール時、Apache HTTPDをWindowsサービスとして登録します。
サービスはPHPのメジャーバージョンごとに登録され、それぞれのサービスでPHPはモジュールモードで動作します。
各サービス名は以下のとおりです。

* multiphp-static
  * PHPモジュールを読み込まずに動作するApache HTTPDです。
  * 既定では`port80`を使用します。
* multiphp-phpXX
  * サービス名と一致するバージョンのPHPモジュールを読み込んで動作するApache HTTPD群です。
  * 既定では`port200XX`（200＋PHPのメジャーバージョン番号）を使用します。

### ドキュメントルート

インストール後、すべてのサービスは`DocumentRoot`を`インストール先パス\htdocs`として起動します。

### Xdebugのポート

既定ではすべてのサービスで`9003`（Xdebug自身の既定値）を使用します。

## 設定を変更する

基本的にはApache HTTPDやPHP、Xdebugの設定変更方法ドキュメントなどを参照してください。

* Apache HTTPD
  * https://httpd.apache.org/docs/2.4/
* PHP
  * https://www.php.net/manual/ja/configuration.file.php
* Xdebug
  * https://xdebug.org/docs/all_settings
    * Xdebugのバージョンにより、設定値が異なる場合があります。バージョンは以下を参考にしてください。
      * `Xdebug 2.X.X` ～ PHP 7.1
      * `Xdebug 3.X.X` PHP 7.2 ～

本スクリプトでインストールした場合特有の設定を以下に示します。

### 共通のドキュメントルートやログフォルダを変更する

`インストール先パス\apache\conf\define.conf`の下記行を任意の値に書き換えてください。
```apacheconf
# ドキュメントルートの変更
Define DEFAULT_DOCROOT "ここを書き換え"

# ログフォルダの変更
Define DEFAULT_LOGDIR "ここを書き換え"
```

### サイト設定を変更する・サイトを増やす

既存のサイト設定の変更や`VirtualHost`などを用いた複数サイトを作成したい場合は、下記フォルダ内の`*.conf`を編集・追加してください。
フォルダ内に存在する`*.conf`ファイルはすべて、各サービス起動時に自動的に読み込まれます。
```
インストール先パス
├─apache
│  ├─conf
│  │  ├─extra
│  │  │  ├─enable-php55
│  │  │  ├─enable-php56
│  │  │  ├─enable-php70
│  │  │  ├─enable-php71
│  │  │  ├─enable-php72
│  │  │  ├─enable-php73
│  │  │  ├─enable-php74
│  │  │  ├─enable-php80
│  │  │  ├─enable-php81
│  │  │  ├─enable-php82
│  │  │  ├─httpd-static.conf → `multiphp-static`が読み込むconf
│  │  │  ├─php-loader.conf   → PHPのバージョン切り替え
```

## アップデート（実験的）

各種バイナリのアップデートにも同スクリプトが利用できます。
アップデートを行う場合は、新規インストールと同操作を実行します。
**動作は保証されないため、設定ファイルなどのバックアップを行ってください**

* 既存のApache HTTPDの`conf`フォルダは`conf_old_yyyyMMdd_HHmmss`とリネームされ、スクリプト同梱の`conf`が再配置されます。
* `php.ini`が存在する場合は既存ファイルを維持します。
* `htdocs`、`logs`フォルダが存在する場合、それらのフォルダは操作しません。
* 上記以外のファイルはすべて最新のファイルで上書きされます。

## FAQ

### コンテナ技術を使えばよいのでは？

仰るとおりです。
コンテナ技術を知識・環境の両面で利用できる場合はそちらをご利用ください。
（より安全かつ一般的な開発フローだと思います）
「環境面で制約があるものの、1環境で複数のPHPバージョンを共存させたい」といった特殊な場合にのみこちらのスクリプトが一助になるのではないかと思います。

### 最新のPHPが読み込まれない

設定ファイルが追従できていない可能性があります。
下記フォルダに対象バージョンのconfが存在するかご確認ください。
* `apache\conf\extra\php\`
* `apache\conf\extra\enable-phpXX`
