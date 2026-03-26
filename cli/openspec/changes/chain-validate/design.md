## Context

`loom-engine.py` には既に `validate_v3_schema()` が存在し、v3.0 固有の構文検証（calls キー、step 型、step_in 構造、chain 参照、chains 構造）を行っている。しかしこれは「各フィールドが正しい型・参照先を持つか」の片方向チェックであり、「双方向で整合しているか」は検証していない。

既存パターン: `deep_validate()` は `(criticals, warnings, infos)` タプルを返す。`chain_validate` も同じシグネチャに従う。

## Goals / Non-Goals

**Goals:**

- `chains.steps` に listed されたコンポーネントが `chain` フィールドで逆参照していること、およびその逆を検証
- `parent.calls[].step` で指定された子が `step_in.parent` で親を逆参照していること、およびその逆を検証
- Chain 種別（A/B）ごとの参加者型制約を検証
- calls 内 step 番号の昇順を検証
- プロンプト body 内の `/{plugin}:{name}` パターンと `Step {N} から呼び出される` パターンを deps.yaml と照合
- `loom check`（`--check` フラグ）実行時に v3.0 検出で自動統合

**Non-Goals:**

- deps.yaml スキーマ定義自体の変更（#11 スコープ）
- chain テンプレート生成
- `loom rename` 時の chain 自動更新（#5 スコープ）
- body 内の一般的な参照検証（chain/step 以外、#7 スコープ）

## Decisions

1. **関数シグネチャ**: `chain_validate(deps: dict, plugin_root: Path) -> Tuple[List[str], List[str], List[str]]` — `deep_validate` と同じ `(criticals, warnings, infos)` パターンを採用。chain 整合性の不一致は CRITICAL（壊れた参照）、型制約違反は WARNING、step 昇順違反は WARNING、prompt 不整合は WARNING とする。

2. **統合ポイント**: `--check` フラグのハンドラ内に v3.0 判定を追加し、`chain_validate` を呼び出す。`--validate` や `--deep-validate` にも統合する。

3. **Chain 種別判定**: `chains` セクション内に `type: A` / `type: B` フィールドがない場合、chain 名の慣習（例: naming convention）ではなく `types.yaml` の `can_spawn` ルールから参加可能な型を導出する。ただし Issue の AC では明確に Chain A = `workflow|atomic`、Chain B = `atomic|composite` と定義されているため、chain_data に `type` キーがあればそれを使い、なければ参加者の型から推論する。

4. **prompt-consistency の正規表現**: body テキストから `/{plugin_name}:{component_name}` と `{parent_name} Step {N} から呼び出される` / `{parent_name} の Step {N} から呼び出される` パターンを検出。日本語パターンも対応。

5. **エラータグ命名**: 既存の `[v3-*]` パターンに合わせ、`[chain-bidir]`, `[step-bidir]`, `[chain-type]`, `[step-order]`, `[prompt-chain]` を使用。

## Risks / Trade-offs

- **prompt-consistency の偽陽性**: body テキスト内の参照パターンは自由記述のため、正規表現で完全にカバーするのは難しい。偽陽性は WARNING レベルにとどめ、CRITICAL にしない。
- **Chain 種別のスキーマ依存**: `chains` セクションに `type` フィールドがない v3.0 deps.yaml では型制約チェックが限定的になる。初期実装では `type` フィールド必須としない（存在する場合のみチェック）。
- **パフォーマンス**: body 読み込みは `deep_validate` で既に行っているパターンがあり、同等のコスト。chain 数が多いプラグインでも数十程度の想定で問題なし。
