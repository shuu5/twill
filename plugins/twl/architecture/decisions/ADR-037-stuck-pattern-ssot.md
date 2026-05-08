# ADR-037: Stuck Pattern SSoT 化 + AUTOPILOT_AUTO_UNSTUCK default=1 切替

- **Status**: Accepted
- **Date**: 2026-05-08
- **Issue**: #1582
- **Predecessors**: ADR-034（Autonomous Chain Reliability）, #1580（queued_message_residual追加）

## 背景

### コンテキスト

autopilot ループでの "stuck" 検知パターンは、実装開始時点で以下 4 箇所に分散・重複して定義されていた:

1. `autopilot-orchestrator.sh` の `detect_input_waiting()` — 3 つの配列にハードコード
2. `plugins/session/scripts/lib/observer-auto-inject.sh` — 独自 regex
3. `plugins/session/scripts/cld-observe-any` — パターン参照
4. `plugins/twl/skills/su-observer/scripts/step0-monitor-bootstrap.sh` — コメント参照

この分散により:
- 新規 pattern 追加時に複数ファイルを手動同期する必要があった
- 同一 pattern の regex 表記が consumer 間で微妙に乖離するリスクがあった
- `queued_message_residual` のように廃止予定フラグを付けた pattern の管理が困難だった

また、`AUTOPILOT_AUTO_UNSTUCK` は #1580 で初実装時に **opt-in（default=0）** とされたが、
実運用で observer が毎回手動で `AUTOPILOT_AUTO_UNSTUCK=1` を export する必要があり、
運用負荷が高いという問題があった（pitfalls-catalog §2.6 相当の観察）。

## 決定

### 決定 1: `stuck-patterns.yaml` を SSoT として新設

`plugins/twl/refs/stuck-patterns.yaml` を全 stuck pattern knowledge の唯一の情報源として新設する。

スキーマ:
```yaml
patterns:
  - id: <pattern_id>          # 識別子（英数字・アンダースコア）
    regex: "<ERE regex>"      # grep -E 互換の正規表現
    recovery_action: "<説明>"  # 検知時のアクション（人間可読）
    owner_layer: "<layer>"    # orchestrator / observer / orchestrator+observer
    confidence: high|medium|low
    notes: "<optional>"       # 廃止予定等の補足
```

### 決定 2: `stuck-patterns-lib.sh` を新設し consumer に統合

`plugins/twl/scripts/lib/stuck-patterns-lib.sh` を新設し、`_load_stuck_patterns()` 関数を提供する。
各 consumer はこの lib を `source` することで YAML からパターン配列を取得する。

### 決定 3: AUTOPILOT_AUTO_UNSTUCK default を 0 → 1 に変更

`${AUTOPILOT_AUTO_UNSTUCK:-0}` → `${AUTOPILOT_AUTO_UNSTUCK:-1}` に変更し、
auto-unstuck を **opt-out 型（default=1）** に切り替える。

無効化が必要なケースのために `AUTOPILOT_AUTO_UNSTUCK_DISABLE=1` opt-out パスを追加する。

## 影響

### ポジティブ

- pattern 追加・変更は `stuck-patterns.yaml` の 1 箇所のみで完結
- `twl audit stuck-patterns` で drift lint が可能（CI に組み込み可能）
- auto-unstuck の default=1 により、observer が手動設定せずとも deadlock から自動回復

### ネガティブ・リスク

- `AUTOPILOT_AUTO_UNSTUCK:-1` への変更は **既存の挙動変更**。
  従来（default=0）は auto-unstuck が無効だったため、deadlock 後も orchestrator は
  手動介入なしに進まなかった。new default では 600s 後に自動 bypass される。
- `stuck-patterns-lib.sh` の YAML parse は Python に依存。Python 未インストール環境では
  パターンロードが fallback（空配列）になる可能性があるが、既存配列はそのまま保持されるため
  機能的な退化は発生しない。

### マイグレーション

- 既存の `detect_input_waiting()` のハードコード配列はそのまま残す（後方互換）。
  lib 経由ロードとの二重定義は将来 Issue で統合予定（TODO）。
- `AUTOPILOT_AUTO_UNSTUCK_DISABLE=1` で旧 opt-in 挙動に戻すことができる。

## 廃止予定（Deprecation）

- `queued_message_residual` pattern: Issue #1034 mailbox Phase 3 完遂後、
  tmux message queue が構造的に消滅するため deprecate 候補。
  `stuck-patterns.yaml` の `notes` フィールドで追跡する。

## 関連

- [stuck-patterns.yaml](../../refs/stuck-patterns.yaml)
- [stuck-patterns-lib.sh](../../scripts/lib/stuck-patterns-lib.sh)
- [pitfalls-catalog.md §2.1](../../skills/su-observer/refs/pitfalls-catalog.md)
- Issue #1580（queued_message_residual 追加）
- Issue #1582（本 ADR の実装）
