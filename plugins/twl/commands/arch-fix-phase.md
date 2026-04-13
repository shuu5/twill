---
type: atomic
tools: [Bash, Read, Edit]
effort: medium
maxTurns: 20
---
# アーキテクチャ docs 修正ループ（arch-fix-phase）

arch-phase-review の findings に基づき、architecture docs を自動修正する。
fix-phase の architecture docs 版。最大 1 ラウンド。

## 発動条件

```
IF arch-phase-review の checkpoint に CRITICAL findings (confidence >= 80) または
   WARNING findings が存在
THEN arch-fix-phase を実行
ELSE スキップ（PASS）
```

```bash
CRITICAL_FINDINGS=$(python3 -m twl.autopilot.checkpoint read --step arch-phase-review --critical-findings 2>/dev/null || echo "[]")
CRITICAL_COUNT=$(python3 -m twl.autopilot.checkpoint read --step arch-phase-review --field critical_count 2>/dev/null || echo "0")
```

## 修正ループ（最大 1 ラウンド）

### Round 1: CRITICAL/WARNING を修正

1. arch-phase-review checkpoint の CRITICAL/WARNING findings を読み込む
2. findings に従い architecture docs ファイルを修正する
3. 修正後に `git add -p` してスコープ外ファイルが含まれていないか確認する
4. commit は行わない（ループ完了後に workflow が commit）

### 修正ルール

- スコープ: architecture docs ファイル（`architecture/` 配下の `.md` ファイル、および変更対象の docs ファイル）のみ
- コードファイル（`.py`, `.sh`, `.ts` 等）への修正は行わない
- 修正後にコンテンツが要件を満たしているか自己検証する

## エスカレーション（REJECT）

修正後も CRITICAL findings が残存する場合:

```bash
python3 -m twl.autopilot.checkpoint write --step arch-fix-phase --status "REJECT" \
  --findings "$REMAINING_FINDINGS"
```

REJECT の場合、merge-gate は BLOCK となりユーザーに手動修正を要求する。

## checkpoint 書き出し（MUST）

```bash
# 修正実施後
python3 -m twl.autopilot.checkpoint write --step arch-fix-phase --status "PASS" --findings "[]"
# または修正後も CRITICAL 残存時
python3 -m twl.autopilot.checkpoint write --step arch-fix-phase --status "REJECT" \
  --findings "$REMAINING_CRITICAL"
```

## 禁止事項（MUST NOT）

- 1 ラウンドを超える修正ループを実行してはならない
- スコープ外ファイル（コード、設定ファイル等）を修正してはならない
- 修正が不明確な場合は REJECT を返してユーザーに委ねること
