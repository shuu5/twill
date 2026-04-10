# types.yaml 再設計案 — observer → supervisor 置換

## 変更内容

### Before（現行）

```yaml
observer:
  section: skills
  can_spawn: [workflow, atomic, composite, specialist, reference, script]
  can_supervise: [controller]
  spawnable_by: [user, launcher]
  token_target:
    warning: 2000
    critical: 3000
```

### After（提案）

```yaml
supervisor:
  section: skills
  can_spawn: [workflow, atomic, composite, specialist, reference, script]
  can_supervise: [controller]
  spawnable_by: [user]
  token_target:
    warning: 2000
    critical: 3000
```

## 変更点

| 項目 | Before | After | 理由 |
|------|--------|-------|------|
| 型名 | `observer` | `supervisor` | ユーザーの命名指示。controller の上位であることを明示 |
| prefix | `co-` | `su-` | controller の `co-` と区別 |
| spawnable_by | `[user, launcher]` | `[user]` | launcher からの自動起動は Phase 2 以降で検討 |

## 影響範囲

### types.yaml 内の参照更新

observer を参照している箇所:

```yaml
atomic:
  spawnable_by: [workflow, controller, observer]  # → supervisor
  
specialist:
  spawnable_by: [workflow, composite, controller, observer]  # → supervisor

reference:
  spawnable_by: [..., observer, ...]  # → supervisor
```

### 外部ファイルの参照更新

- `plugins/twl/skills/co-observer/SKILL.md` → `plugins/twl/skills/su-observer/SKILL.md`
  - `type: observer` → `type: supervisor`
- `plugins/twl/deps.yaml` 内の co-observer エントリ → su-observer
- `plugins/twl/architecture/domain/model.md` の Observer クラス → Supervisor
- `plugins/twl/architecture/domain/context-map.md` の Observer Context → Supervision Context
- `plugins/twl/architecture/vision.md` の Meta-cognitive カテゴリ → Supervisor カテゴリ
- `plugins/twl/architecture/domain/contexts/observation.md` の OBS-* 制約 → supervision.md の SU-* 制約
- `plugins/twl/CLAUDE.md` の controller 一覧

### CLI コード影響

- `cli/twl/src/twl/core/` — type_rules のパース（observer → supervisor）
- テスト内の observer 参照
