## Context

`issue-spec-review.md` は specialist 並列 spawn 前に `/tmp` へ manifest ファイルを書き込む。現状は `date +%s%N | tail -c8` でファイル名を生成しているため、予測可能（CWE-377）かつ並列起動時に衝突する可能性がある。

`check-specialist-completeness.sh` フックは `/tmp/.specialist-manifest-*.txt` の glob でアクティブな manifest を検索しており、ファイル名のプレフィックス `.specialist-manifest-` からコンテキストを抽出している。CONTEXT 文字列は `[a-zA-Z0-9_-]+` で検証される。

## Goals / Non-Goals

**Goals:**

- `issue-spec-review.md` の manifest ファイル生成を `mktemp` ベースに変更する（CWE-377 対策 + 衝突回避）
- 生成ファイルのパーミッションを 600 に設定する
- クリーンアップロジック（`:131-140`）を新命名規則に追従させる
- hook（`check-specialist-completeness.sh`）の glob パターンと整合性を保つ
- AC-3: 影響箇所を全列挙し、参照箇所を新命名規則に更新する
- 並列起動テスト（AC-4）を追加する

**Non-Goals:**

- `post-fix-verify.md`、`merge-gate.md`、`phase-review.md` の CONTEXT_ID 生成変更（本 Issue のスコープ外）
- `/tmp` 以外のディレクトリへの変更

## Decisions

### manifest ファイル命名

`mktemp /tmp/.specialist-manifest-XXXXXXXX.txt` を使用する。

理由:
- ドット付きプレフィックス（`.specialist-manifest-`）を維持することで、hook の glob パターン `/tmp/.specialist-manifest-*.txt` との互換性を保つ
- mktemp の 8 文字ランダムサフィックスで衝突を事実上排除
- CONTEXT 導出は `$(basename "$MANIFEST_FILE" .txt | sed 's/^\.specialist-manifest-//')` とし、8 文字ランダム文字列が CONTEXT_ID となる

### クリーンアップ

現行コード:
```bash
if [[ -n "${CONTEXT_ID:-}" ]]; then
  rm -f /tmp/.specialist-manifest-${CONTEXT_ID}.txt \
        /tmp/.specialist-spawned-${CONTEXT_ID}.txt
else
  rm -f /tmp/.specialist-manifest-spec-review-*.txt \
        /tmp/.specialist-spawned-spec-review-*.txt
fi
```

変更後:
- `MANIFEST_FILE` 変数を cleanup 時に直接使用してピンポイント削除する
- spawned ファイルは `CONTEXT_ID` から導出したパスを使う
- glob フォールバックは削除可能（MANIFEST_FILE が常に設定されるため）

### hook の CONTEXT 検証互換性

mktemp のランダムサフィックスは英数字（`[a-zA-Z0-9]`）のみで構成される。hook の `[a-zA-Z0-9_-]+` 検証をパスする。

## Risks / Trade-offs

- **hook の glob 変更不要**: `.specialist-manifest-` プレフィックスを維持するため hook は変更不要
- **tests の整合**: `spec-review-gate.test.sh`・`check-specialist-completeness.test.sh` では `ctx` を手動設定しているため、新命名規則に合わせたファイルパスを使うよう更新が必要
- **CONTEXT_ID の長さ変化**: 従来 `spec-review-XXXXXXXX`（17+ 文字）→ 新 `XXXXXXXX`（8 文字）。CONTEXT_ID をファイル名以外で使用している箇所がないことを確認済み（AC-3 調査で確認）
