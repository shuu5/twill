# ADR-001: Autopilot-first

## Status
Accepted

## Context

旧プラグイン (claude-plugin-dev) では `--auto` / `--auto-merge` フラグによる実行パスの分岐が存在し、以下の問題を引き起こしていた:

- フラグの組み合わせによる分岐の増加（手動/--auto/--auto-merge の3パス）
- 各パスで微妙に異なるステップ順序・エラーハンドリング
- テスト対象パスの倍増によるテストの不完全性
- 「手動でやった方が速い」判断によるバイパスの常態化

## Decision

全 Implementation 操作は co-autopilot 経由とする。単一 Issue の実装であっても `co-autopilot #N` で実行する。

### Controller 操作カテゴリ

| カテゴリ | 定義 | 該当 Controller | 経路 |
|----------|------|-----------------|------|
| Implementation | コード変更・PR 作成を伴う操作 | co-autopilot のみ | autopilot パイプライン経由 |
| Non-implementation | Issue 作成・設計・プロジェクト管理 | co-issue, co-project, co-architect | ユーザーが直接呼び出し |

### Emergency Bypass

以下の場合のみ、co-autopilot を経由せず手動で直接実装→PR→merge を許可する:

- co-autopilot 自体の障害（SKILL.md のバグ、セッション管理の故障等）
- co-autopilot の SKILL.md 自体の修正（bootstrap 問題: main/ で直接編集→commit→push）

Emergency bypass 使用時は、セッション後に retrospective で理由を記録する義務がある。

## Consequences

### Positive
- 単一実行パスによるテスト容易性の向上
- 状態管理の一元化（issue-{N}.json + session.json のみ）
- 再現性の保証（同じ入力 → 同じステップ順序）

### Negative
- ホットフィックス対応の遅延リスク（co-autopilot 経由のオーバーヘッド）
- co-autopilot 自体の障害時に bootstrap 問題が発生
- Emergency Bypass の判断基準が曖昧になるリスク

### Mitigations
- Emergency Bypass を明示的な例外条件として定義
- retrospective 記録義務による bypass 拡大解釈の抑止
