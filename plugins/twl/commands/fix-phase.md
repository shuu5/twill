---
type: composite
tools: [Bash, Skill, Read]
effort: medium
maxTurns: 30
---
# 自動修正ループ（chain-driven）

CRITICAL finding の自動修正と再検証を管理する。
chain ステップの実行順序は deps.yaml で宣言されている。
本コマンドには chain で表現できないドメインルールのみを記載する。

## chain ライフサイクル

| Step | コンポーネント | 型 |
|------|--------------|------|
| 4 | fix-phase（本コンポーネント） | composite |

## ドメインルール

### checkpoint 読み込み（MUST）

phase-review と ac-verify の両 checkpoint から CRITICAL findings を読み込む。
specialist raw output は参照しない。

```bash
# phase-review checkpoint から CRITICAL findings を取得
PHASE_REVIEW_FINDINGS=$(python3 -m twl.autopilot.checkpoint read --step phase-review --critical-findings 2>/dev/null || echo "")
phase_review_critical=$(python3 -m twl.autopilot.checkpoint read --step phase-review --field critical_count 2>/dev/null || echo "0")

# ac-verify checkpoint から CRITICAL findings を取得
AC_VERIFY_FINDINGS=$(python3 -m twl.autopilot.checkpoint read --step ac-verify --critical-findings 2>/dev/null || echo "")
ac_verify_critical=$(python3 -m twl.autopilot.checkpoint read --step ac-verify --field critical_count 2>/dev/null || echo "0")

# 両方を結合して修正指示として使用
CRITICAL_FINDINGS="${PHASE_REVIEW_FINDINGS}
${AC_VERIFY_FINDINGS}"
CRITICAL_COUNT=$(( ${phase_review_critical:-0} + ${ac_verify_critical:-0} ))
```

### 発動条件

```
IF phase_review_critical + ac_verify_critical == 0
THEN SKIP（修正不要）
ELSE fix-phase を実行（phase-review CRITICAL / ac-verify CRITICAL のいずれかが 1 以上）
```

**重要**: ac-verify CRITICAL は「テスト RED のまま PR を出した（GREEN 未完了）」等の TDD 違反を示す。
phase-review CRITICAL が 0 であっても ac-verify CRITICAL が 1 以上なら fix-phase を発動する。

**confidence 設計**: `critical_count` は confidence フィルタを持たない（checkpoint.py の設計意図）。
confidence フィルタは書き込み側の責務であり、ac-verify 書き込み経路が >= 80 を保証する:
- `ac-impl-coverage-check.sh`: CRITICAL は confidence=90 固定
- LLM delegate パス（ac-verify.md）: CRITICAL は confidence=80 固定

### 修正ループ

1. CRITICAL findings を修正指示として渡す
2. コード修正を実施
3. 修正後にテスト再実行（pr-test）
4. テスト PASS → post-fix-verify へ
5. テスト FAIL → 修正を見直し再試行（最大 1 ループ）

### エスカレーション条件

```
IF 修正ループが 1 回を超える（自動修正で解決不可）
THEN fix-phase を中断し FAIL を返す
```

### 制約

- fix-phase 内での修正はスコープ内ファイルのみ
- 修正が他のテストを破壊する場合は即座に revert
- AI が判断に迷う場合は修正を試みず FAIL を返す

## チェックポイント（MUST）

`/twl:post-fix-verify` を Skill tool で自動実行。

