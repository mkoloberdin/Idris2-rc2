# idris2-browser

*[English](README.md)*

ある環境にインストールされている Idris 2 のパッケージを、端末で閲覧するツールです。次のものを見られます。

- パッケージの一覧と統計
- 各パッケージのモジュール
- 各モジュールの定義（種類、型、ドキュメントコメント）
- 全定義名の検索

```
┌──────────────────┐┌─────────────────────┐┌──────────────────────────┐
│Packages          ││Modules              ││Definitions (exported)    │
│  base 0.8.0      ││  Data.List          ││> fn   sortBy             │
│> contrib 0.8.0   ││> Data.List.Extra    ││  fn   nub                │
└──────────────────┘└─────────────────────┘└──────────────────────────┘
 Doc │ Type │ Stats │ Package
┌─────────────────────────────────────────────────────────────────────┐
│ ドキュメントコメント、型、統計、パッケージの情報                    │
└─────────────────────────────────────────────────────────────────────┘
F1 Doc F2 Type F3 Stats F4 Package F5 Filter F6 Search F10 Quit
```

二つのプログラムでできています。

- `idris2-browser-index` は、インストール済みの TTC ファイルを `idris2api` で読み、JSON ファイルの索引を書きます。
  - 既定の（Chez）バックエンドでビルドします。
  - TTC を書いたコンパイラと、同じバージョンの Idris 2 でビルドする必要があります。
- `idris2-browser` は画面の側で、rc2 と `termui` でビルドします。
  - 起動時にインデクサを実行して、索引を最新にします。
  - その後は索引だけを読みます。

索引は公開された形式です（[`doc/index-format.md`](doc/index-format.md)）。そのため、エディタのプラグインなど、ほかのフロントエンドからも読めます。設計、パッケージの探し方の規則、測定結果は [`doc/design.md`](doc/design.md) にあります。いずれも英語です。

## 何を調べるか

`PATH` 上の `idris2` から見える範囲を調べます。

- `idris2 --prefix` が表示する prefix です。この値は `IDRIS2_PREFIX` に従います。
- その前に、`IDRIS2_PACKAGE_PATH` のディレクトリも探します。
- TTC のバージョンが違うパッケージは、「読めない」と表示します。

## ビルド

```sh
source ../../env.sh
idris2 --build index.ipkg                                       # build/index/exec/idris2-browser-index
../../rc2/build/exec/idris2-rc2 --cg rc2 --build browser.ipkg   # build/browser/exec/idris2-browser
```

## 使い方

```sh
build/browser/exec/idris2-browser --indexer build/index/exec/idris2-browser-index
```

| オプション | 効果 |
|---|---|
| `--index-dir DIR` | 索引のディレクトリ（既定は `$XDG_CACHE_HOME/idris2-browser`、無ければ `~/.cache/idris2-browser`） |
| `--indexer PATH` | 実行するインデクサ（既定は `PATH` 上の `idris2-browser-index`） |
| `--no-update` | 索引を更新せずに、そのまま表示する |
| `--dump W H [ACTION...]` | 画面をテキストに描く（テスト用） |

環境全体の最初の索引作りには時間がかかります（925 モジュールで 26 秒）。それ以降は、変わったモジュールだけを読み直します（変更が無ければ 0.7 秒）。

キー操作は次のとおりです。

| キー | 動作 |
|---|---|
| F1〜F4 | タブを選ぶ |
| F5 または `f` | フィルタを切り替える（公開分、全部、ドキュメントの無い公開分） |
| F6 または `/` | 検索する |
| Enter | 検索結果へ移動する |
| Tab | 欄の間を移る |
| F10、`q`、Esc | 終了する |

インデクサだけを使う場合は、次のとおりです。

```sh
idris2-browser-index --update [--json] [--pretty] [--index-dir DIR] [--prefix DIR]
idris2-browser-index --print-index-dir
```

## テスト

```sh
tests/verify.sh            # 確認する
tests/verify.sh --accept   # 今回の実行結果で tests/expected/ を書き直す
```

`rc2/build/exec/idris2-rc2` が必要です。書き込むのは `tests/build/` の下だけです。
