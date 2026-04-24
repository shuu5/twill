# ADR-026: spawn-controller.sh --with-chain 誤用防止（WARN で起動経路を明示）

- **Status**: Accepted
- **Date**: 2026-04-24
- **Issue**: #942
- **Related**: ADR-025 (#940), pitfalls-catalog.md §13.5

## Context

`spawn-controller.sh --with-chain --issue N` は `autopilot-launch.sh` に直接委譲する **skill bypass 経路**（経路 A'）である。Pilot が spawn されないため、`co-autopilot SKILL.md` Step 1-5（deps graph / Wave 計画 / retrospect / specialist-audit）が全 skip される。

### 14 PR skip incident (#923/#925-#937, Phase Z, 2026-04-24 verified)

Phase Z 本 session で su-observer が `working-memory.md` 前 session 踏襲のまま `--with-chain --issue N` を 14 回連続使用し、#923/#925-#937 の 14 PR 全てが specialist review を経由せずに merge された。

観察事実:
- su-observer は「co-autopilot と名前が付いているから skill を使っている」と判断（誤認）
- `--with-chain` 付与で skill bypass が発動し、Pilot 不在のまま Worker が直接起動
- phase-review / scope-judge / specialist-audit が一切走らなかった

### mental model の歪み

正規運用は「**1 Pilot = 複数 Issue を deps graph で Wave 計画**」であるにもかかわらず、「1 Issue = 1 Pilot」と錯覚して Issue 毎に `--with-chain --issue N` を叩いた（doobidoo `b42c7a71`）。`--with-chain` option の存在自体が single-issue mental model を誘発する構造的欠陥である。

## Decision

1. `spawn-controller.sh` の `WITH_CHAIN=true` block 冒頭に **WARN ブロックを追加**する。
   - stderr に `WARN:` 接頭辞付きメッセージを出力
   - メッセージに `skill bypass`、正規運用例、`pitfalls-catalog.md §13.5` 参照を含める
2. **exit code は 0 を維持**（後方互換）。autopilot-launch.sh への委譲ロジックは変更しない。
3. **rename / deprecate は本 Issue scope 外**。Phase AB 以降で Pilot-internal 呼出経路の分離が完了してから再検討する（下記 Consequences 参照）。

### 採用しなかった選択肢

| 案 | 却下理由 |
|----|---------|
| exit code を 2 に変更して即 deprecate | 既存 bats テスト（`spawn-controller-with-chain.bats`）が破壊される。Phase Z で merge 済み 14 PR の再現テストが走らなくなる。後方互換を破る変更は Phase AB 以降で慎重に行う |
| `--with-chain` option を完全削除 | Pilot-internal 呼出経路が `autopilot-launch.sh` 直接（spawn-controller.sh 非経由）であることを先に検証・分離する必要がある |
| escape hatch env var（`SPAWN_CONTROLLER_SUPPRESS_WARN=1`）追加 | 現時点で Pilot-internal 呼出経路は `spawn-controller.sh` を経由しないため不要。escape hatch は将来の設計変更時に再検討する |

## Consequences

### 即効（本 ADR 適用後）

- observer が `--with-chain --issue N` を呼ぶたびに stderr に WARN が出力され、skill bypass を認識できる
- 既存 bats テスト（`spawn-controller-with-chain.bats`、5 ケース）は回帰 PASS（exit 0 維持）
- 新規 bats テスト（`spawn-controller-with-chain-warn.bats`）が PASS

### 将来（Phase AB 以降で再評価）

- **rename（`--direct-worker-launch`）**: Pilot-internal 呼出経路の分離が完了し、`spawn-controller.sh --with-chain` が本当に observer 専用でなくなった段階で rename を検討
- **deprecate（exit 2 化）**: rename 後、旧 `--with-chain` が不要になった段階で段階的に deprecate
- **escape hatch 導入**: 将来 Pilot が `spawn-controller.sh --with-chain` を内部利用する設計変更が入った場合、WARN の誤発火防止のため `SPAWN_CONTROLLER_SUPPRESS_WARN=1` 等を導入する

### SKILL.md との役割分担

本 ADR（技術的 WARN 追加）と `su-observer/SKILL.md`（運用ルール明文化）は相互補完する。WARN は機械的な気づきを提供し、SKILL.md は observer が自律的に判断するためのルールを提供する。
