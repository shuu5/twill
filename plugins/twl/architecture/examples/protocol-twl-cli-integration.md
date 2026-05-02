# Example: twl CLI Integration Protocol

> このファイルは `protocols/<name>.md` フォーマットの実例です（AC9）。
> `architecture/protocols/` 配下に配置して使用します。

---

## Participants

- Provider: `twill` リポジトリ（`cli/twl/` ディレクトリ）
- Consumer: `plugins/twl` リポジトリ

## Pinned Reference

<!-- MUST: 40-char commit SHA のみ使用（tag/branch 禁止） -->
repo: twill
sha: a3f8c2d1e4b5f6a7b8c9d0e1f2a3b4c5d6e7f8a9

> **注**: 上記 SHA は例示用の架空の値です。実際の運用では `git log --oneline -1` で取得した実 SHA を記録してください。

## Interface Contract

### twl CLI コマンドインターフェース

Consumer（plugins/twl）は以下の twl CLI サブコマンドを使用する：

| コマンド | 用途 | 引数 |
|---------|------|------|
| `twl check` | deps.yaml 整合性検証 | `--deps-integrity` |
| `twl chain export` | chain-steps.sh 同期確認 | なし |
| `twl config get` | 設定値取得 | `<key>` |

### 環境変数

| 変数 | 意味 |
|------|------|
| `CLAUDE_PLUGIN_ROOT` | plugins/twl のルートパス |
| `AUTOPILOT_DIR` | autopilot 作業ディレクトリ（デフォルト: `.autopilot`） |

## Drift Detection

SHA ピンのドリフトを検出するための手順：

**cron（推奨）:**
```bash
# weekly check script
PINNED_SHA="a3f8c2d1e4b5f6a7b8c9d0e1f2a3b4c5d6e7f8a9"
PROVIDER_LATEST=$(git -C /path/to/twill rev-parse origin/main)
if [[ "$PINNED_SHA" != "$PROVIDER_LATEST" ]]; then
  echo "DRIFT: pinned SHA is behind. Update Pinned Reference section."
fi
```

**GitHub Actions:**
```yaml
- name: Validate protocol SHA pins
  run: |
    find architecture/protocols -name "*.md" | while read f; do
      sha=$(grep 'sha:' "$f" | awk '{print $2}')
      if ! echo "$sha" | grep -qE '^[a-f0-9]{40}$'; then
        echo "ERROR: invalid SHA in $f: $sha"
        exit 1
      fi
    done
```

**手動レビュー:** 四半期ごとに `git -C /path/to/twill log --oneline <sha>` で参照先 commit が存在することを確認する。

## Migration Path

Pinned Reference を更新する手順：

1. Provider（twill）リポジトリで対象変更を commit する
2. `git -C /path/to/twill rev-parse HEAD` で新しい SHA を取得する
3. このファイルの `Pinned Reference` セクションの `sha:` を新しい値に更新する
4. Consumer（plugins/twl）側の依存コードを新しいインターフェースに対応させる
5. `Interface Contract` セクションを最新状態に更新する
