## Why

ADR-001 (Autopilot-first) で `--auto`/`--auto-merge` フラグの廃止を決定したが、Worker 層の workflow スキル・コマンドにフラグが残存している。`issue-{N}.json` ベースの autopilot 判定（設計が定めた代替メカニズム）が未実装のため、設計と実装が乖離している。

## What Changes

- Worker 層の全コンポーネントから `--auto`/`--auto-merge` フラグ参照を除去
- `state-read.sh` による `issue-{N}.json` ベースの autopilot 判定を実装
- chain 自動継続を `workflow-test-ready`/`workflow-pr-cycle` と同じ設計に統一
- openspec 内の矛盾する記述（c-2d session-management）を修正

## Capabilities

### New Capabilities

- **issue-{N}.json ベース autopilot 判定**: Worker が `state-read.sh --type issue --issue $ISSUE_NUM --field status` で autopilot 配下かを判定。`status=running` なら autopilot 配下、空なら standalone 実行
- **統一 chain 継続パターン**: autopilot 配下→自動継続、standalone→案内表示で停止

### Modified Capabilities

- **workflow-setup**: `--auto`/`--auto-merge` 引数解析を除去。state-read.sh で判定
- **opsx-apply**: `--auto` 分岐を除去。state-read.sh で判定
- **pr-cycle-analysis**: `--auto` を除去。state-read.sh で自動起票判定
- **self-improve-propose**: `--auto` を除去。state-read.sh で自動承認判定
- **autopilot-launch**: プロンプトから `--auto --auto-merge` を除去。Issue 番号のみ渡す
- **co-autopilot**: `--auto-merge` 言及を除去（`--auto` は Pilot 層フラグとして存続）

## Impact

**変更対象ファイル:**

| ファイル | 変更内容 |
|---------|---------|
| `commands/autopilot-launch.md` | PROMPT から `--auto --auto-merge` 除去 |
| `skills/workflow-setup/SKILL.md` | 引数解析除去 + state-read.sh 判定追加 |
| `commands/opsx-apply.md` | `--auto` 分岐除去 + state-read.sh 判定追加 |
| `commands/pr-cycle-analysis.md` | `--auto` 除去 + state-read.sh 判定追加 |
| `commands/self-improve-propose.md` | `--auto` 除去 + state-read.sh 判定追加 |
| `skills/co-autopilot/SKILL.md` | `--auto-merge` 言及除去のみ |
| `openspec/changes/c-2d-.../specs/session-management/spec.md` | `--auto --auto-merge` 除去 |

**依存関係:** なし（他の open Issue と独立して実施可能）
**API/インターフェース変更:** Worker 起動プロンプトのインターフェースが変更（`--auto --auto-merge` → Issue 番号のみ）
