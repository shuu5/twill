## Context

4ファイル5箇所に存在する `for VAR in $NUMS` パターン（unquoted word-split）を `mapfile` パターンへ統一する。`mapfile` は bash 4.0+ で利用可能で、対象の全スクリプトは `#!/usr/bin/env bash` を使用し Linux 環境専用のため互換性問題はない。

## Goals / Non-Goals

**Goals:**
- `shellcheck` word-split WARNING を全箇所解消する
- bash best practice に準拠した安全なイテレーションパターンへ統一する
- `autopilot-plan-board.sh` の数値バリデーションガードを維持する

**Non-Goals:**
- #137（プロジェクト探索ロジック共通化）との統合（本 Issue は独立修正）
- スクリプトのその他リファクタリング

## Decisions

### mapfile パターンへの統一

**変更前:**
```bash
PROJECT_NUMBERS=$(gh project list --owner "$OWNER" --format json | jq -r '.projects[].number')
for PROJECT_NUM in $PROJECT_NUMBERS; do
```

**変更後:**
```bash
mapfile -t PROJECT_NUMS < <(gh project list --owner "$OWNER" --format json | jq -r '.projects[].number')
for PROJECT_NUM in "${PROJECT_NUMS[@]}"; do
```

- ローカル変数名は `PROJECT_NUMBERS` → `PROJECT_NUMS`（配列であることを明示、命名衝突回避）
- `chain-runner.sh` は小文字 `project_numbers` → `project_nums` に合わせる

### autopilot-plan-board.sh の数値ガード維持

line 40-41 のバリデーションガードは `mapfile` 変換後も機能するためそのまま維持:
```bash
[[ ! "$pnum" =~ ^[0-9]+$ ]] && continue
```

## Risks / Trade-offs

- **リスク**: `mapfile` は bash 4.0+ 専用。macOS のデフォルト bash（3.2）では動作しない。ただし全スクリプトは Linux 環境のみ対象のため問題なし。
- **トレードオフ**: コード行数がわずかに増えるが、安全性と `shellcheck` 準拠を優先する。
