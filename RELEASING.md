# リリース手順

## 通常リリース

1. PR を main にマージ
2. GitHub 上で手動リリースを作成
   - タグ: `v1.x.x`（例: `v1.2.0`）
   - リリースノートを記載
3. Actions タブから **Update Floating Tag** を手動実行
   - `target`: 作成したタグ（例: `v1.2.0`）
   - `major_version`: `v1`

これで `jksy/setup-imagemagick@v1` を使っているユーザーに最新版が届く。

## ロールバック

問題が発生した場合は **Update Floating Tag** を再実行し、一つ前のタグを指定する。

- `target`: 戻したいタグ（例: `v1.1.9`）
- `major_version`: `v1`

## バージョニングルール

[Conventional Commits](https://www.conventionalcommits.org/) に従ってコミットメッセージを書き、それに基づいてバージョンを決定する。

| コミット | バージョン |
|---|---|
| `fix:` | patch（例: 1.1.2 → 1.1.3）|
| `feat:` | minor（例: 1.1.2 → 1.2.0）|
| `BREAKING CHANGE:` | major（例: 1.1.2 → 2.0.0）|
