# 移行計画: co-observer → su-observer

## 移行方針

ADR-013 の observer 設計を ADR-014 の supervisor 設計に段階的に移行する。
既存ファイルのリネーム・書き換えが中心。新機能（compaction 外部化）は後半 Phase で追加。

## Phase 構成

### Phase 1: 型システム + ADR（基盤）

**目的**: types.yaml と ADR を更新し、supervisor 型の基盤を確立する。

| 変更対象 | 変更内容 |
|----------|----------|
| `cli/twl/types.yaml` | `observer` → `supervisor` rename + spawnable_by 内の observer → supervisor 全置換 |
| `plugins/twl/architecture/decisions/ADR-014-supervisor-redesign.md` | Status: Proposed → Accepted |
| `plugins/twl/architecture/decisions/ADR-013-observer-first-class.md` | Status: Accepted → Superseded by ADR-014 |
| CLI テスト | observer → supervisor のテスト修正 |

**依存**: なし（最初に実装必須）

### Phase 2: ドメインモデル + Context 更新

**目的**: architecture 仕様を supervisor 設計に合わせて更新する。

| 変更対象 | 変更内容 |
|----------|----------|
| `plugins/twl/architecture/domain/model.md` | Observer クラス → Supervisor クラス、InterventionRecord の observer → supervisor |
| `plugins/twl/architecture/domain/context-map.md` | Observer Context → Supervision Context、関係図更新 |
| `plugins/twl/architecture/vision.md` | Meta-cognitive カテゴリ → Supervisor カテゴリ |
| `plugins/twl/architecture/domain/contexts/observation.md` | OBS-* 制約の su-observer 関連を supervision.md に移動。co-self-improve 関連は残す |
| `plugins/twl/architecture/domain/contexts/supervision.md` | 新規（Phase 1 で作成済み → 最終化） |

**依存**: Phase 1

### Phase 3: su-observer SKILL.md + deps.yaml

**目的**: co-observer → su-observer のスキル実装を入れ替える。

| 変更対象 | 変更内容 |
|----------|----------|
| `plugins/twl/skills/co-observer/` → `plugins/twl/skills/su-observer/` | ディレクトリリネーム |
| `plugins/twl/skills/su-observer/SKILL.md` | ADR-014 設計に基づく完全書き直し |
| `plugins/twl/deps.yaml` | co-observer → su-observer エントリ書き換え + type: supervisor |
| `plugins/twl/CLAUDE.md` | controller 一覧の co-observer → su-observer 更新 |
| `plugins/twl/refs/intervention-catalog.md` | spawnable_by に supervisor を追加（observer を置換） |

**依存**: Phase 1, 2

### Phase 4: compaction 知的外部化

**目的**: 3 hook（PreCompact/PostCompact/SessionStart(compact)）と su-compact スキルを実装する。

| 変更対象 | 変更内容 |
|----------|----------|
| `plugins/twl/scripts/su-precompact.sh` | PreCompact hook: Working Memory 退避 + 圧縮ヒント |
| `plugins/twl/scripts/su-postcompact.sh` | PostCompact hook: Working Memory の sharp 復帰 |
| `plugins/twl/scripts/su-session-compact.sh` | SessionStart(compact) hook: ambient hints 注入 |
| `.claude/settings.json` | PreCompact/PostCompact/SessionStart(compact) hook 設定追加 |
| `plugins/twl/refs/memory-mcp-config.md` | Memory MCP の pluggable 設定（現在: doobidoo） |
| `plugins/twl/skills/su-observer/SKILL.md` | su-compact モードの詳細追加 |
| `plugins/twl/commands/su-compact.md` | su-compact コマンド（atomic or workflow） |
| `plugins/twl/refs/externalization-schema.md` | 外部化ファイルのスキーマ定義 |
| `plugins/twl/deps.yaml` | su-compact + scripts + refs の追加 |

**依存**: Phase 3

### Phase 5: Wave 管理自動化

**目的**: su-observer の Wave 管理ループを実装する。

| 変更対象 | 変更内容 |
|----------|----------|
| `plugins/twl/commands/wave-collect.md` | Wave 完了時の結果収集 atomic |
| `plugins/twl/commands/externalize-state.md` | 状態外部化 atomic |
| `plugins/twl/skills/su-observer/SKILL.md` | Wave 管理 Step の最終化 |
| `plugins/twl/deps.yaml` | 新コマンドの追加 |

**依存**: Phase 4

### Phase 6: co-autopilot ペア起動の移行

**目的**: co-autopilot の `--with-observer` フラグを廃止し、su-observer → co-autopilot の spawn 方向に統一する。

| 変更対象 | 変更内容 |
|----------|----------|
| `plugins/twl/skills/co-autopilot/SKILL.md` | `--with-observer` フラグ削除、su-observer からの spawn 受け入れ |
| `plugins/twl/skills/co-self-improve/SKILL.md` | co-observer 参照 → su-observer 参照に更新 |
| `plugins/twl/commands/intervene-*.md` | observer → supervisor 参照更新 |

**依存**: Phase 3

## 依存グラフ

```
Phase 1 (型+ADR)
  ├── Phase 2 (ドメイン更新)
  │     └── Phase 3 (SKILL.md + deps)
  │           ├── Phase 4 (compaction)
  │           │     └── Phase 5 (Wave管理)
  │           └── Phase 6 (ペア起動移行)
  └── Phase 6 にも依存
```

## 削除対象

Phase 3 完了後に以下を削除:
- `plugins/twl/skills/co-observer/` ディレクトリ全体（su-observer に置換済み）
- `plugins/twl/architecture/domain/contexts/observation.md` の OBS-* 制約部分（supervision.md の SU-* に移動済み）

Phase 6 完了後に以下を削除:
- co-autopilot の `--with-observer` 関連コード

## リスクと緩和策

| リスク | 緩和策 |
|--------|--------|
| Phase 1 の型変更が CLI テストを大量に壊す | observer → supervisor の sed 置換 + テスト全件実行で確認 |
| deps.yaml の型不整合 | `twl check` + `twl validate` で Phase ごとに検証 |
| co-autopilot の --with-observer が使用中 | Phase 6 を最後に配置し、Phase 3 完了時点で両方動作する状態を維持 |
| PostCompact hook の動作が不安定 | Phase 4 は単独テスト可能。su-observer 本体への影響なし |
