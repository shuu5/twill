## Context

Worker LLM は workflow-setup → workflow-test-ready → workflow-pr-cycle の 3 chain を 1 autopilot セッションで実行する。chain 内のステップ遷移は既に明示化済みだが、chain 間遷移（workflow → workflow）は各 SKILL.md の最終ステップに依存している。

現状の問題:
- `workflow-setup` Step 4: IS_AUTOPILOT 判定なしで `/twl:workflow-test-ready` の呼び出し指示が不明確
- `workflow-test-ready` Step 4: opsx-apply 内部の Step 3 に IS_AUTOPILOT 判定 + pr-cycle 呼び出しが隠れており、SKILL.md 側で把握しにくい
- `check.md`: CRITICAL FAIL 時でも無条件で `/twl:opsx-apply` を呼び出す指示があり、opsx-apply のスキップ制御と競合する

## Goals / Non-Goals

**Goals:**
- 各 workflow SKILL.md の最終ステップに autopilot 判定 bash スニペットを明示的に埋め込む
- 遷移責務を SKILL.md 側に一元化し、opsx-apply は実装のみに集中させる
- check.md の無条件 opsx-apply 呼び出しを CRITICAL FAIL 時スキップ条件付きに修正する
- 「即座に Skill tool を実行せよ。プロンプトで停止するな」の一文を各遷移指示に追加する

**Non-Goals:**
- orchestrator の nudge ロジック改善
- chain 内ステップの追加明示化（2026-03-30 修正済み）
- compaction recovery ロジックの変更（#129 対応済み）

## Decisions

### D1: autopilot 判定スニペットの配置

各 SKILL.md の最終ステップに以下の bash スニペットを埋め込む（opsx-apply.md L の既存コードと同一）:

```bash
ISSUE_NUM=$(git branch --show-current | grep -oP '^\w+/\K\d+(?=-)' 2>/dev/null || echo "")
IS_AUTOPILOT=false
if [ -n "$ISSUE_NUM" ]; then
  AUTOPILOT_STATUS=$(bash scripts/state-read.sh --type issue --issue "$ISSUE_NUM" --field status 2>/dev/null || echo "")
  IS_AUTOPILOT=$([[ "$AUTOPILOT_STATUS" == "running" ]] && echo true || echo false)
fi
```

**理由**: スニペットを各 SKILL.md に置くことで、LLM が一連のフローを 1 つの指示として認識できる。opsx-apply への依存を切ることで暗黙の dependency chain が解消される。

### D2: opsx-apply Step 3 のスリム化

opsx-apply.md の Step 3 から IS_AUTOPILOT 判定 + pr-cycle 呼び出しロジックを削除し、シンプルなチェックポイント出力のみにする。

**理由**: 遷移責務は呼び出し元の SKILL.md 側が持つべき。opsx-apply は `/twl:apply` のラッパーであり、実装完了通知のみを担う。

### D3: check.md の条件付き opsx-apply

check.md 末尾の「チェックポイント（MUST）」に CRITICAL FAIL 条件を追加:
- CRITICAL FAIL なし → `/twl:opsx-apply` を Skill tool で自動実行
- CRITICAL FAIL あり → opsx-apply をスキップし、FAIL 内容を報告して停止

**理由**: CRITICAL FAIL 時に opsx-apply を呼び出すと、実装が壊れた状態で進行する。workflow-test-ready Step 3 の結果判定ロジックと整合させる。

### D4: 遷移指示の明示化

各 SKILL.md の遷移指示に「即座に Skill tool を実行せよ。プロンプトで停止するな」を追加。

## Risks / Trade-offs

- **二重呼び出しリスク**: opsx-apply から pr-cycle 呼び出しを削除するため、SKILL.md 側に pr-cycle 呼び出しが移る。opsx-apply を直接呼び出した場合（autopilot 外）は pr-cycle が自動実行されなくなる。→ 許容: 直接呼び出しは非 autopilot セッションであり、手動で pr-cycle を実行するフロー。
- **スニペット重複**: 同一 bash スニペットが複数 SKILL.md に存在する。→ 許容: DRY より明示性を優先（各 SKILL.md が自己完結していることが chain の安定性を高める）。
