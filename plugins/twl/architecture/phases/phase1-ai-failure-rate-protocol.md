# Phase 1 β AI 失敗率測定プロトコル

Issue #1019 AC8 の測定設計と実施手順。MCP 経路が CLI 経路の失敗率の半分以下であることを binomial proportion test で検定する。

## 前提条件（MUST — 実測前に確認）

1. **#1018 PR merge 後の MCP server 動作確認**: `mcp__twl__twl_state_read` および `mcp__twl__twl_state_write` が正常に応答すること。動作確認コマンド: `python3 -m twl.autopilot.state read --type session` が exit 0 を返すこと。
2. **cold-start セッション**: 各試行は新規 Claude Code セッション（`cld` コマンドで新規起動）で実施すること。セッション間の状態汚染を防ぐ。
3. **worktree 環境**: main worktree で実施すること（`~/projects/local-projects/twill/main/`）。

## 測定設計（N=240）

### 試行数の根拠

```
N = 20 trials/操作/経路 × 6 操作 × 2 経路 = 240 試行
```

- **20 trials/操作/経路**: power analysis（下記参照）に基づく
- **6 操作**: twl autopilot の主要操作を網羅
- **2 経路**: CLI 経路と MCP 経路の比較

### Power Analysis

- 帰無仮説: H0: p_mcp ≥ 0.5 × p_cli
- 対立仮説: H1: p_mcp < 0.5 × p_cli
- 有意水準: α = 0.05（Bonferroni 補正後: α/6 = 0.0083 per 操作）
- 検出力: β = 0.80（20% false negative rate）
- 想定効果量: p_cli = 0.15, p_mcp = 0.05（MCP が 1/3 の失敗率）
- 必要サンプルサイズ: 各グループ n ≥ 15、安全マージン込みで n = 20

### 測定対象操作（6 操作）

| 操作名 | 説明 | 測定内容 |
|--------|------|----------|
| `issue_init` | Issue 状態初期化 | 新規 issue JSON の作成成功率 |
| `read_field` | フィールド読み込み | 既存 issue の特定フィールド取得成功率 |
| `status_transition` | ステータス遷移 | running → merge-ready 遷移成功率 |
| `rbac_violation` | RBAC 違反操作 | Worker が Pilot 専用フィールドを書き込めないことの確認（violation 検出率） |
| `failed_done_force` | 失敗→完了強制 | `--force-done` での状態強制遷移成功率 |
| `sets_nested_key` | ネストキー設定 | `--set a.b.c=value` 形式のネスト書き込み成功率 |

### 測定経路（2 経路）

#### CLI 経路

```bash
python3 -m twl.autopilot.state read  --type issue --issue <N> [--field <F>]
python3 -m twl.autopilot.state write --type issue --issue <N> --role worker --set <k>=<v>
```

#### MCP 経路

```
mcp__twl__twl_state_read  (ツール引数: type="issue", issue_num=N, field=F)
mcp__twl__twl_state_write (ツール引数: type="issue", issue_num=N, role="worker", set_fields={k: v})
```

## Goldfile（成功判定基準）

Goldfile は各操作 × 経路の「成功とみなす出力パターン」を定義する。

- 配置場所: `cli/twl/tests/scripts/ac8_goldfiles/<operation>_<route>.txt`
- 形式: 成功判定の正規表現パターンまたは期待出力の一部
- 一致判定: 実際の出力に goldfile の内容（または正規表現）が含まれる場合に「成功」

## 失敗パターン分類（MECE 4 + 1）

各試行が失敗した場合、以下のパターンに分類する。分子（失敗率計算の対象）はパターン 1-4 のみ。

| パターン | 識別子 | 識別方法 |
|----------|--------|----------|
| 1 | `pythonpath_not_set` | stderr に `ModuleNotFoundError` を含む |
| 2 | `subcommand_name_error` | exit_code ≠ 0 かつ stderr に `unknown` または `invalid choice` を含む |
| 3 | `enum_notation_error` | exit_code = 2 かつ stderr に `invalid` と `expected` を両方含む |
| 4 | `missing_required_option` | exit_code = 2 かつ stderr に `required` または `missing` を含む |
| 5 | `out_of_scope` | 上記 1-4 に該当しない失敗（StateError など）— **分子から除外** |

### MECE 保証

- パターン 1 → 4 の順で優先評価
- どれにも該当しない場合はパターン 5（out_of_scope）
- 分子定義: patterns 1-4 のみ（pattern 5 は除外）

## データ収集形式（CSV）

実測データは以下のカラムで CSV に記録する。

```
operation,route,trial_index,success,failure_pattern,session_id,timestamp
issue_init,cli,1,true,,sess-abc123,2026-04-01T10:00:00Z
issue_init,cli,2,false,pythonpath_not_set,sess-def456,2026-04-01T10:05:00Z
...
```

| カラム | 型 | 説明 |
|--------|----|------|
| operation | str | 6 操作のいずれか |
| route | str | `cli` または `mcp` |
| trial_index | int | 1-20（各 operation × route 内の通し番号） |
| success | bool | `true` / `false` |
| failure_pattern | str | 失敗時のみ: パターン識別子（空文字可） |
| session_id | str | cold-start セッション識別子 |
| timestamp | str | ISO 8601 形式 |

保存先: `cli/twl/tests/scripts/ac8_data/<YYYYMMDD_HHMMSS>.csv`

## Prompt 標準化（測定環境ガードレール）

各試行は以下の標準化された prompt テンプレートを使用する。prompt の自由度が結果に影響しないよう、操作ごとに prompt を固定する。

- **CLI 経路**: シェルコマンドを直接実行（prompt なし、コマンド文字列を固定）
- **MCP 経路**: `mcp__twl__twl_state_read` / `mcp__twl__twl_state_write` を直接ツール呼び出し（prompt なし）

プロンプトエンジニアリングの影響を排除するため、Claude に自然言語で操作を依頼するのではなく、ツールを直接呼び出す形式とする。

## 統計判定（binomial proportion test）

`cli/twl/tests/scripts/ac8_significance_test.py` を参照。

- **アプローチ A**: 線形結合の z-test（H0: p_mcp - 0.5 × p_cli ≥ 0）
- **アプローチ B**: bootstrap 比率比検定（B ≥ 10000 resamplings、1-sided 95% CI）
- **Bonferroni 補正**: α/6 = 0.0083（6 操作の多重検定補正）
- **全体判定**: 全操作達成 → "全達成"、一部達成 → "部分達成"、全未達成 → "未達成"

## doobidoo Memory 記録

検定完了後、以下を `mcp__doobidoo__memory_store` で記録する。

1. **raw data hash**: CSV ファイルの SHA256 hash
2. **達成判定結果**: overall_judgment, p_values, failure_rates
3. 必須タグ: `["phase1", "ac8", "ai-failure-rate"]`
