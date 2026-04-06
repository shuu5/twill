## Context

co-issue の Phase 3b では issue-critic と issue-feasibility が並列 spawn される。各 specialist は maxTurns: 15 の制限下で動作し、scope_files リストのファイルを個別に調査する。scope_files が 4 件以上になると、ファイルごとの依存追跡・呼び出し元検索で turn を消費し、出力生成フェーズに到達できない。

現在の Step 3c は specialist の返却値をパースするが、出力が空または構造化されていない場合は `ref-specialist-output-schema.md` のパース失敗フォールバック（出力全文を WARNING finding として扱う）が適用される。ただし出力が完全に空の場合は findings: [] として扱われサイレントに通過する。

## Goals / Non-Goals

**Goals:**
- scope_files が多い場合でも specialist が構造化 findings 出力を確実に生成できるようにする
- Step 3c で出力なし完了を検知してユーザーに警告する
- 多層防御構成（Agent 側 + 呼び出し側）で信頼性を高める

**Non-Goals:**
- maxTurns 値自体の変更
- worker-codex-reviewer や PR Cycle 系 reviewer への変更
- 完全な出力保証（LLM 指示遵守依存のため）
- deps.yaml の構造変更

## Decisions

### 1. Agent 側: プロンプトによる調査バジェット制御

`agents/issue-critic.md` と `agents/issue-feasibility.md` に以下のルールを追加:

```
## 調査バジェット制御

scope_files が 3 ファイル以上の場合:
- 各ファイルの調査を最大 2-3 tool calls に制限する
- 調査は「ファイル存在確認 + 直接の呼び出し元 1 段」に留める
- 再帰的な依存追跡は行わない
- 残り turns が 3 以下になったら、調査を打ち切り出力生成を優先する
```

**理由**: Agent 定義にバジェット意識を持たせることで、呼び出し側プロンプト変更との多層防御を実現する。

### 2. 呼び出し側: scope_files 依存の調査深度指示注入

`skills/co-issue/SKILL.md` Phase 3b の specialist spawn 時のプロンプトに以下の擬似コードを追加:

```
file_count = len(structured_issue.scope_files)
IF file_count <= 2:
  depth_instruction = "各ファイルの呼び出し元まで追跡可"
ELSE:
  depth_instruction = "各ファイルは存在確認と直接参照のみ。再帰追跡禁止。残りturns=3になったら出力生成を優先"
```

**理由**: 呼び出し側でも制御することで Agent 定義変更が反映されない場合のフォールバックになる。

### 3. Step 3c: 出力なし完了の検知とロール分担の明記

Step 3c に以下を追加:

1. **出力なし検知**: specialist 返却値に `status:` または `findings:` キーワードが含まれない場合は「出力なし完了」と判定
2. **WARNING 表示**: findings テーブルに `WARNING: <specialist-name>: 構造化出力なしで完了（調査が maxTurns に到達した可能性）` を追加
3. **Phase 4 非ブロック**: WARNING は表示するが Phase 4 を停止しない
4. **役割分担の明記**: 出力なし検知（上位ガード）→ パース失敗フォールバック（下位ガード）の順を文書化

**理由**: サイレントな findings: [] による偽陰性をユーザーが認識できるようにする。

## Risks / Trade-offs

- **LLM 指示遵守**: プロンプト指示は LLM の確率的判断に依存するため完全な保証はない。出力検知が最終フォールバックとして機能する
- **調査品質の低下**: scope_files >= 3 では調査深度を意図的に制限するため、深い依存関係の問題を見逃す可能性がある。ただし現状は出力ゼロなのでトレードオフとして許容
- **WARNING ノイズ**: 出力なし完了の検知が過敏に発火する可能性があるが、Phase 4 非ブロックのため運用上の問題は小さい
