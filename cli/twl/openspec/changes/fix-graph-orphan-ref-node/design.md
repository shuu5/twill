## Context

`twl-engine.py` の `build_graph()` / `classify_layers()` / `generate_graphviz()` に 3 つのバグがある。

1. `build_graph()` (L446-462): agent の `skills` フィールドが reverse dependency (`required_by`) に反映されない。agent が reference skill を skills として持つ場合、その skill の required_by が空のままになる
2. `classify_layers()` (L671-682): L1→L2 の 1 段のみ走査。L2 コマンドがさらに calls で呼ぶ L3 以降のコマンドが走査されず orphan 扱いになる
3. `generate_graphviz()` Legend: reference 型は legend_defs に定義済み（L1100）だが、`existing_types` 構築ロジックで reference が正しく含まれれば描画される。現状でも動作するが確認が必要

## Goals / Non-Goals

**Goals:**

- agent.skills で参照される skill が required_by に正しく追加される
- classify_layers() が任意深度の cmd→cmd チェーンを再帰的に走査する
- Legend に reference 型が常に正しく表示される
- 既存テストが全て PASS

**Non-Goals:**

- deps.yaml への calls 追加（shuu5/loom-plugin-dev#41 のスコープ）
- graph レイアウト最適化
- 新規テストファイルの追加（既存テストの修正のみ）

## Decisions

### D1: build_graph() に agent.skills の reverse dependency 追加

`build_graph()` の逆依存構築セクション（L446-462）に、agent の `skills` フィールドを走査するループを追加。deps.yaml の agents セクションから直接 `skills` フィールドを読み、`skill:{name}` ノードの required_by に agent を追加する。

graph ノードの `agent_skills` ではなく deps の `agents[name].skills` を使う。理由: build_graph() の逆依存構築は graph ノードの calls/uses_agents/external を走査する既存パターンに沿うが、agent.skills は calls とは別のフィールドなので deps から直接読む。

### D2: classify_layers() の再帰走査

L671-682 の L1→L2 走査を、未訪問コマンドがなくなるまでループする BFS/再帰に変更。`direct_commands` を seed とし、各ステップで新たに発見した commands を `sub_commands` に追加し、次のステップの seed にする。

### D3: Legend の reference 確認

`existing_types` は skill_data.get('type') で構築されるため、reference 型の skill が deps.yaml に存在すれば正しく追加される。build_graph() の修正で required_by が正しくなれば orphan 検出も正確になるため、Legend 自体の修正は不要の可能性が高い。ただし動作確認は行う。

## Risks / Trade-offs

- **再帰走査の循環**: cmd A → cmd B → cmd A のような循環呼び出しがあると無限ループになる。visited set で防止する
- **agent.skills の型制約**: agent.skills は reference 型 skill のみを想定しているが、コードでは型チェックを入れない（build_graph は型を問わず逆依存を構築する設計）
