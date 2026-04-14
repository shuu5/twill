## Context

`twl --validate` は deps.yaml のコンポーネント宣言が `types.yaml` の型ルールに適合しているか検証する。現在 13 件の違反があり、3 つのルートコーズに集約される:

1. **types.yaml ルール不足（違反 1-7）**: controller 型と atomic 型の `spawnable_by`/`can_spawn` 定義が実装の実態（ADR-014 の su-observer spawn、su-compact → externalize-state spawn）を反映していない
2. **validate.py の plugin キー未対応（違反 8-11）**: v3-calls-key バリデーターが `plugin` キーを不明キーとして報告するが、これはクロスプラグイン参照用の正規メタ情報
3. **chain-steps.sh の名前不一致（違反 12-13）**: `board-status-update` エントリが `project-board-status-update`（deps.yaml 側の正式名）と不一致

## Goals / Non-Goals

**Goals:**
- `twl --validate` の Violations を 0 にする
- 最小限のファイル変更（3 ファイルのみ）で全 13 違反を解消する
- deps.yaml 側のコンポーネント宣言は変更しない

**Non-Goals:**
- types.yaml の大規模リファクタリング
- hook の追加（Issue A/B/C/D）
- validate.py のアーキテクチャ変更

## Decisions

### 1. types.yaml: controller 型への supervisor 追加（違反 1-3）

ADR-014 で su-observer（supervisor 型）が controller を spawn できる設計が確定している。types.yaml の controller 型ルールを実態に合わせる:
- `spawnable_by: [user, launcher]` → `[user, launcher, supervisor]`
- `can_spawn: [workflow, atomic, composite, specialist, reference, script]` → `[..., controller]`（su-observer 経由の controller spawn 許可）

deps.yaml 側は既に宣言済みのため変更不要。

### 2. types.yaml: atomic 型への user/atomic 追加（違反 4-7）

su-compact（atomic）が user から直接呼ばれ、externalize-state（atomic）を spawn する設計。type を composite に変更すると `spawnable_by: [workflow, controller]` となり現行の `user` との互換性が崩れるため、atomic 型のルール自体を拡張する:
- `spawnable_by: [workflow, controller, supervisor]` → `[..., user]`
- `can_spawn: [reference, script]` → `[..., atomic]`

### 3. validate.py: plugin キーを除外キーリストに追加（違反 8-11）

`plugin` キーはクロスプラグイン参照のメタ情報として正規に利用される（例: `plugin: twl`）。validate.py の v3-calls-key チェックで `step` と同様に除外する。deps.yaml の calls 形式は変更しない。

### 4. chain-steps.sh: board-status-update → project-board-status-update（違反 12-13）

deps.yaml の chain 定義では `project-board-status-update` が正式名称。chain-steps.sh 内の全連想配列（CHAIN_STEP_DISPATCH, CHAIN_STEP_WORKFLOW, CHAIN_STEP_COMMAND）を統一する。

## Risks / Trade-offs

- **types.yaml 拡張の副作用**: spawnable_by/can_spawn を広げることで、validate 時のチェックが緩くなる側面はあるが、変更は実態のユースケースに追従するのみであり意図的
- **chain-steps.sh リネームの影響**: board-status-update 名でハードコードしているスクリプトがあれば動作変更となるが、chain-runner.sh はステップ名を chain-steps.sh から動的に参照するため影響なし
