## Why

auto-merge.md の IS_AUTOPILOT 判定・フォールバックガード・squash merge の全てが LLM の bash 解釈実行（MECHANICAL_LLM）に依存しており、不変条件 C（Worker マージ禁止）が破綻するリスクがある。Autopilot セッション 8ee2b490 で実際に複数回破綻した。設計哲学「LLM は判断のために使う。機械的にできることは機械に任せる」に従い、auto-merge ロジックを bash script 化する。

## What Changes

- `scripts/auto-merge.sh` を新設し、4 Layer ガード + squash merge + worktree 削除を機械的に実行
- `commands/auto-merge.md` を script 呼び出しのみに簡素化
- merge-gate-execute.sh と同等の CWD ガード・tmux window ガードを auto-merge.sh にも適用

## Capabilities

### New Capabilities

- `scripts/auto-merge.sh`: 4 Layer ガード付き auto-merge script
  - Layer 1: IS_AUTOPILOT 判定（state-read.sh + AUTOPILOT_DIR フォールバック）
  - Layer 2: CWD ガード（worktrees/ 配下実行拒否）
  - Layer 3: tmux window チェック（ap-#N パターン検出）
  - Layer 4: フォールバックガード（issue-{N}.json 直接存在確認）

### Modified Capabilities

- `commands/auto-merge.md`: LLM 解釈実行から `bash scripts/auto-merge.sh` 呼び出しに簡素化

## Impact

- `scripts/auto-merge.sh` — 新規ファイル
- `commands/auto-merge.md` — 大幅簡素化（script 呼び出しのみ）
- `scripts/state-read.sh`, `scripts/state-write.sh` — 既存利用（変更なし）
- `scripts/merge-gate-execute.sh` — 参照（ガードパターン流用、変更なし）
- #119 (chain-runner) — auto-merge を script 化対象に追加するコメント投稿
