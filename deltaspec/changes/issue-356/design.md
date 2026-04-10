## Context

ADR-014 は observer 型を supervisor 型に完全置換することを決定した。
`co-observer/SKILL.md` は ADR-013 ベースで実装されており、ADR-014 の Decision 1〜2 に基づいて
`su-observer/SKILL.md` への移行が必要。

既存の co-observer は以下の属性を持つ:
- `type: observer`、`spawnable_by: [user, controller]`
- `deps.yaml`: `supervises: [co-autopilot, co-issue, co-architect, co-project, co-utility]`
- Step 0〜3 のモード判定・pair 起動・supervise・delegate-test フロー

`#348` で `types.yaml` に `supervisor` 型が定義済みであることを前提とする。

## Goals / Non-Goals

**Goals:**
- `plugins/twl/skills/co-observer/` を削除し `su-observer/` として再作成する
- `su-observer/SKILL.md` を `type: supervisor`、`spawnable_by: [user]` で作成する
- ADR-014 Decision 2 のプロジェクト常駐ライフサイクルに基づく Step 0〜7 の基本構造を定義する
- 既存 co-observer の Step 0〜3 フローを移行・再設計する
- `deps.yaml` の `co-observer` 参照を `su-observer` に更新する
- `twl validate` が PASS する状態にする

**Non-Goals:**
- Step 4〜7 の詳細実装（後続 Issue #365, #368 等で対応）
- compaction 実装（PostCompact/PreCompact hook）（後続 Issue で対応）
- 三層記憶モデルの完全実装
- Wave 自動管理機能

## Decisions

### D1: ディレクトリリネーム方式
`co-observer/` を削除して `su-observer/` を新規作成する。git rename ではなく削除+追加。
理由: SKILL.md の内容が大幅に変わるため、rename 履歴の保持よりも明確な新規作成が適切。

### D2: frontmatter 属性
```yaml
name: twl:su-observer
type: supervisor
spawnable_by: [user]
```
- `spawnable_by: [controller]` を削除: ADR-014 Decision 2 では su-observer はユーザーが直接起動する
- `supervises` 属性: supervisor 型スキーマに従って定義

### D3: Step 0〜7 基本構造
| Step | 概要 | 詳細化 |
|------|------|--------|
| Step 0 | モード判定（supervise / delegate-test / retrospect） | このIssue |
| Step 1 | セッション起動・監視開始 | このIssue（基本構造のみ） |
| Step 2 | controller spawn と観察 | このIssue（基本構造のみ） |
| Step 3 | 問題検出・3層介入 | このIssue（介入catalog継承） |
| Step 4 | Wave 管理 | 後続 Issue |
| Step 5 | Long-term Memory 保存 | 後続 Issue |
| Step 6 | Compaction 外部化 | 後続 Issue |
| Step 7 | セッション終了 | このIssue（基本構造のみ） |

### D4: deps.yaml 更新範囲
- `co-observer` キーを `su-observer` にリネーム
- `path: skills/co-observer/SKILL.md` → `path: skills/su-observer/SKILL.md`
- `supervises` 配列を `supervisor` 型スキーマに合わせて更新
- `co-observer` を参照している箇所（controller 定義など）も更新

## Risks / Trade-offs

- **後続 Issue との境界**: Step 4〜7 の基本構造はプレースホルダーとして定義。詳細実装は後続 Issue に委ねる
- **deps.yaml 参照の漏れ**: co-observer を参照しているエントリが複数あるため、更新漏れに注意が必要
- **`twl validate` の依存**: `#348` で supervisor 型が types.yaml に追加されていない場合、validate が失敗する
