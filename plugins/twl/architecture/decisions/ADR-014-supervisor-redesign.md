# ADR-014: Observer → Supervisor 再定義 — プロジェクト常駐メタ認知レイヤー

## Status
Accepted

## Supersedes
ADR-013 (Observer の First-Class 昇格)

## Context

### 背景

ADR-013 は observer 型を定義し、co-observer を controller の上位メタ認知レイヤーとして位置づけた。しかし 47 件の Issue を含む複数 Wave の実セッション運用を経て、以下の根本的な設計ミスが判明した。

### ADR-013 の問題点

1. **命名の矛盾**: `co-observer` は controller と同格の `co-` prefix を持つが、実際には controller の上位に位置する
2. **起動モデルの逆転**: co-autopilot の `--with-observer` フラグでペア起動される — 監視者が被監視者に従属する設計
3. **ライフサイクルの断絶**: autopilot セッション終了で observer のコンテキストが全て失われる。プロジェクト横断の連続的知識が維持できない
4. **制約 OB-3 と実態の矛盾**: 「observed session に inject 禁止」としたが、実際のユーザー Observer 行動では inject/send-keys による直接介入が常態化
5. **ユーザー role の暗黙的実行**: Wave 管理、障害対応、セッション間調整など、ユーザーが手動で担っていた supervisor 責務が co-observer の設計スコープ外

### 実セッションからの定量データ（47 件 Issue、10 Wave）

| ユーザーの Observer 行動 | 回数 | co-observer で対応可能か |
|--------------------------|------|------------------------|
| non_terminal_chain_end 回復 | 47/47 | Layer 0 Auto で部分的に可 |
| PR 手動作成・マージ管理 | ~30 | 不可（controller spawn が必要） |
| Wave 計画立案・再計画 | 10 | 不可（プロジェクト全体の判断が必要） |
| Worker crash/timeout 回復 | ~5 | Layer 0 Auto で可 |
| 並行セッション調整 | 複数 | 不可（複数 controller のコンテキストが必要） |
| rebase conflict 解決 | ~3 | Layer 2 Escalate |
| compaction 前の知識外部化 | 複数 | 不可（ライフサイクルが短すぎる） |
| 構造的問題の発見→Issue 起票 | 複数 | 不可（非技術的判断） |

### 問題の本質

co-observer は「controller を監視する observer」として設計されたが、ユーザーが実際に行っていたのは「プロジェクト全体を管理する supervisor」であった。この差は命名・ライフサイクル・権限スコープすべてに影響する。

## Decision

### Decision 1: `supervisor` 型への完全置換

`types.yaml` の `observer` 型を `supervisor` 型に **完全置換** する。

```yaml
supervisor:
  section: skills
  can_supervise: [controller]
  can_spawn: [workflow, atomic, composite, specialist, reference, script]
  spawnable_by: [user]
  token_target:
    warning: 2000
    critical: 3000
```

**命名規則**: supervisor 型のコンポーネントは `su-` prefix を使用する。controller の `co-` prefix と明確に区別する。

**型階層の変更**:
```
ADR-013: user → observer (co-observer) → controller (co-*)
ADR-014: user → supervisor (su-observer) → controller (co-*)
```

co-self-improve は controller 型のまま維持（ADR-011 Decision 1 を尊重）。su-observer が co-self-improve のテスト実行を委譲する関係は継続する。

### Decision 2: プロジェクト常駐ライフサイクル

su-observer は **プロジェクトごとに 1 つの連続したセッション** として定義する。

- **起動場所**: bare repo の main ディレクトリ（`~/projects/local-projects/<project>/main/`）
- **起動タイミング**: ユーザーがプロジェクト作業を開始する時に 1 回
- **ライフサイクル**: プロジェクト作業の終了まで常駐。controller の開始・終了とは独立
- **session 形態**: main window の cld セッションそのものが su-observer として機能。ユーザーは su-observer に対して指示を出し、su-observer が各 controller を spawn して observe する

**起動フロー**:
```
ユーザー → main で cld 起動 → /twl:su-observer で supervisor モード開始
su-observer は常駐し、ユーザーの指示を受けて:
  → co-autopilot を session:spawn → observe
  → co-issue を session:spawn → observe
  → co-architect を session:spawn → observe
  → Wave 管理、障害対応、知識外部化
```

### Decision 3: 三層記憶モデル

su-observer の知識管理は **固定性（sharpness）** と **持続性（persistence）** の 2 軸で分類される 3 層で構成する。

| 層 | 固定性 | 持続性 | 対応する認知 | 実装 |
|----|--------|--------|------------|------|
| **Long-term Memory** | sharp/fixed | 永続 | 検索して引き出せる知識 | Memory MCP (pluggable) + auto-memory |
| **Working Memory Externalization** | sharp/fixed | 一時的 | 今やっている作業の一時退避 | PreCompact → .supervisor/working-memory.md → PostCompact |
| **Compressed Memory** | **dynamic/fuzzy** | セッション内 | プロジェクト全体のぼんやりした全体像 | compaction 後の圧縮コンテキスト |

**重要な特性**: Long-term Memory と Working Memory Externalization はどちらも **sharp（明確で固定された記憶）** だが持続性が全く異なる。Compressed Memory だけが **dynamic** であり、compaction のたびに変容する。過去の記憶がうっすら残る場合もあれば消える場合もあるが、Long-term Memory が存在するかもしれないという **手がかり** になりうる。

**Memory MCP の Pluggable 設計**: 現在は doobidoo MCP を使用するが、su-observer は MCP 名をハードコードせず reference ファイル（`refs/memory-mcp-config.md`）経由で参照する。将来の MCP 入れ替え時は reference のみ更新。

### Decision 4: Compaction の知的外部化 — 3 hook の使い分け

compaction は Claude Code の 3 つの hook（PreCompact / PostCompact / SessionStart(compact)）を使い分けて実現する。

#### Hook 発火順序と役割

```
① PreCompact → ② Compaction → ③ PostCompact → ④ SessionStart(compact)
```

| Hook | stdout の行き先 | 役割 |
|------|----------------|------|
| **PreCompact** | compaction **される** context（= 圧縮対象） | ファイルへの Working Memory 退避（side effect）+ 圧縮に残すべき情報のヒント |
| **PostCompact** | compaction **後の** 新 context | Working Memory の sharp な復帰（作業状態の即座の復元） |
| **SessionStart(compact)** | compaction **後の** 新 context | ambient hints の注入（Long-term Memory へのポインタ、プロジェクト全体像） |

PostCompact は「直前の作業の復帰」、SessionStart(compact) は「プロジェクト全体の再認識」と棲み分ける。

#### 自動外部化（安全弁）

context 消費量が **50% に到達** した時点で、su-observer は自動的に:
1. 現在の状態を判定（タスク途中 / Wave 完了後 / 設計議論中 / 障害対応中）
2. Long-term Memory に永続化すべき知識を Memory MCP に保存
3. Working Memory Externalization（一時退避）をファイルに書き出し
4. `/compact` を実行 → PreCompact/Compaction/PostCompact/SessionStart(compact) が順に発火

#### 明示的外部化（ユーザー指示）

`su-compact` スキルを提供し、ユーザーが任意のタイミングで:
- 外部化する知識の範囲を指定
- 外部化形式を選択（サマリ / 構造化 / ADR 的記録）
- compaction を実行

#### Wave 完了時の自動外部化

大量 Issue を Wave 分割で実装する場合:
1. Wave N の co-autopilot 完了を検知
2. 結果を収集（成功/失敗 Issue、介入記録、知見）
3. su-compact を実行:
   - Long-term Memory: Wave サマリ + 教訓を永続保存
   - Working Memory: 次 Wave の計画を一時退避
   - Compressed Memory: compaction 後にぼんやりと Wave 全体の記憶が残る
4. Wave N+1 の Issue を co-autopilot に渡して spawn
5. observe 再開

#### コンテキスト依存の外部化戦略

| 状況 | Long-term Memory に保存 | Working Memory に退避 |
|------|------------------------|----------------------|
| タスク途中 | なし（まだ教訓がない） | タスク状態、進捗、次のステップ |
| Wave 完了後 | 実装サマリ、教訓、パターン | 次 Wave の計画、引き継ぎ事項 |
| 設計議論後 | 決定事項、却下案、理由（ADR） | 未決定事項、次の議論ポイント |
| 障害対応後 | 障害パターン、回復手順 | 進行中の対応状況 |

### Decision 5: 介入プロトコルの継承と拡張

ADR-013 の 3 層介入プロトコル（Auto/Confirm/Escalate）は **そのまま継承** する。

**拡張点**:
- **OB-3 の廃止**: su-observer は observed session への inject/send-keys を **許可** する（ユーザーの実行動と一致）
- **OBS-3 の維持**: su-observer 自身が Issue の直接実装を行ってはならない（不変条件 K の supervisor 版）
- **OBS-4 の緩和**: supervised controller session の上限を 3 → **5** に拡張（Wave 管理では 4-5 並行が実測値）
- **intervention-catalog の継続使用**: 6 パターンの分類と InterventionRecord はそのまま活用

### Decision 6: Controller 操作カテゴリの更新

vision.md の Controller 操作カテゴリに Supervisor カテゴリを追加:

| カテゴリ | 定義 | 該当コンポーネント |
|----------|------|--------------------|
| Implementation | コード変更・PR 作成を伴う操作 | co-autopilot |
| Non-implementation | Issue 作成・設計・プロジェクト管理 | co-issue, co-project, co-architect |
| Utility | スタンドアロンユーティリティ操作 | co-utility |
| Observation | ライブセッション観察・問題検出・Issue 起票 | co-self-improve |
| **Supervisor** | プロジェクト常駐のメタ認知・Wave 管理・知識外部化 | su-observer |

## Consequences

### Positive

- ユーザーの実際の Observer 行動と設計が一致する
- プロジェクト常駐により、セッション横断的な知識の連続性が実現する
- 三層記憶モデルにより、compaction による知識喪失を構造的に防止できる
- `su-` prefix により controller との階層差が命名レベルで明確になる
- Wave 管理の自動化パスが開ける（su-observer が Wave 間の compaction を自律的に実行）

### Negative

- observer 型の完全置換により、ADR-013 で実装した全コンポーネントの移行が必要
- su-observer が main session そのものになるため、su-observer 非起動時の直接作業パスとの共存設計が必要
- compaction 知的外部化は Claude Code の 3 hook（PreCompact/PostCompact/SessionStart(compact)）に依存（hook 仕様変更リスク）
- Memory MCP の pluggable 設計により reference ファイル管理の追加コストが発生

### Mitigations

- 移行は段階的に行う（Phase 1: 型変更 + ADR、Phase 2: SKILL.md 再設計、Phase 3: compaction 実装）
- su-observer 非起動時は通常の cld セッションとして動作（supervisor スキルが load されないだけ）
- PreCompact/PostCompact hook の実装はプロジェクト settings.json に閉じ、グローバル設定には影響しない
