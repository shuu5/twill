## Context

`plugins/twl/commands/change-propose.md` の Step 0 auto_init フローでは、`twl spec new "issue-<N>"` の呼出後に echo 2 行で `.deltaspec.yaml` を手動補完している。しかし `twl spec new` 自体が `name:`, `status:`, `issue:` を自動書き込みするため、この補完は二重書き込みとなる。

Issue #448 のスコープは `change-propose.md` の該当 echo 行の削除とコメント追加のみ。CLI 側（`cli/twl/src/twl/spec/new.py`）は変更しない。

## Goals / Non-Goals

**Goals:**
- `change-propose.md` Step 0 の echo 2 行（name/status 補完）を削除する
- `twl spec new` 呼出箇所に自動補完の説明コメントを追加する
- `.deltaspec.yaml` への重複エントリを防止する

**Non-Goals:**
- `cli/twl/` のコードを変更しない
- `twl spec new` の動作を変更しない
- 他のステップ（Step 1〜6）を変更しない

## Decisions

**削除対象（change-propose.md:40-46 付近）:**
```bash
5. .deltaspec.yaml に必須フィールドを補完:
   echo "name: issue-<N>" >> deltaspec/changes/issue-<N>/.deltaspec.yaml
   echo "status: pending" >> deltaspec/changes/issue-<N>/.deltaspec.yaml
```
→ この箇条書き項目 5（echo 2 行）を完全に削除する。

**追加コメント（`twl spec new` 呼出直後）:**
```bash
# twl spec new が自動補完する（issue 番号・name・status）
```

## Risks / Trade-offs

- リスクなし（機能的変更なし）
- ドキュメントの削除は後方互換性に影響しない
