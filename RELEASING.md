# リリース手順

## 通常リリース

1. PR を main にマージ
2. GitHub 上で手動リリースを作成
   - タグ: `v2.x.x`（例: `v2.1.0`）
   - **"Generate release notes"** ボタンでリリースノートを自動生成
3. Actions タブから **Update Floating Tag** を手動実行
   - `target`: 作成したタグ（例: `v2.1.0`）
   - `major_version`: `v2`

これで `jksy/setup-imagemagick@v2` を使っているユーザーに最新版が届く。

`v1.x.x` を出すとき（v1 系の修正）は `major_version: v1` を選ぶ。

## PR のラベル

リリースノートは PR のラベルで分類される（`.github/release.yml`、上から最初に一致した分類に入る）。
変更の種類はファイルからは判別できないので、**PR を作るときに種別ラベルを 1 つ手で付ける**。

| 分類 | ラベル | 付け方 |
|---|---|---|
| Breaking Changes | `breaking change` | 手で付ける（major） |
| New Features | `enhancement` | 手で付ける（minor） |
| Bug Fixes | `bug` | 手で付ける（patch） |
| Security | `security` | 手で付ける |
| Documentation | `documentation` | labeler（`**/*.md`） |
| Dependencies | `dependencies` | Renovate（action の実行に関わる依存） |
| CI | `github_actions` | labeler（`.github/**`、`renovate.json`）、Renovate（`.github/` 配下の依存） |

ドキュメントだけ・CI だけの PR は labeler が付けるラベルで足りる。

## ロールバック

問題が発生した場合は **Update Floating Tag** を再実行し、一つ前のタグを指定する。

- `target`: 戻したいタグ（例: `v2.0.0`）
- `major_version`: `v2`

## バージョニングルール

[Conventional Commits](https://www.conventionalcommits.org/) に従ってコミットメッセージを書き、それに基づいてバージョンを決定する。

| コミット | バージョン |
|---|---|
| `fix:` | patch（例: 1.1.2 → 1.1.3）|
| `feat:` | minor（例: 1.1.2 → 1.2.0）|
| `BREAKING CHANGE:` | major（例: 1.1.2 → 2.0.0）|

メジャーバージョンを上げたときは、`update-floating-tag.yml` の `major_version` の選択肢に新しいメジャー（例: `v3`）を足す。
