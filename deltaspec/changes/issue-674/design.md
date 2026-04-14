## Context

CRG symlink 自己参照バグが3回再発している。既存の防御は:
1. orchestrator の realpath ガード（#605 で強化）: worktree 作成時の自己参照を防ぐ
2. crg-auto-build.md: symlink 検出時はスキップ（ビルド不要と判定）

しかし LLM ステップ（crg-auto-build）が明示的な `ln` 禁止ルールを持たないため、LLM が「壊れた symlink を修復しようとして新しい symlink を作成する」行動を取ると self-reference が発生しうる。また observer のヘルスチェックがないため再発の早期検出が困難。

## Goals / Non-Goals

**Goals:**
- LLM が `ln` コマンドで `.code-review-graph` symlink を作成することを明文ルールで禁止する
- orchestrator の CRG セクションに自己参照残存を検出・修復する追加ガードを追加する
- su-observer が Wave 開始時に CRG symlink の健全性を自動チェックする

**Non-Goals:**
- symlink 方式の全廃（repo_root env var 方式への移行）は scope 外（将来 Issue で対応）
- CRG MCP server のソースコード変更
- クロスリポジトリ環境での CRG 対応

## Decisions

### Decision 1: crg-auto-build.md に MUST NOT ルール追加

**対象**: `plugins/twl/commands/crg-auto-build.md` の `禁止事項（MUST NOT）` セクション

追加内容:
- `ln` コマンドを実行してはならない（symlink 作成禁止）
- `.code-review-graph` ディレクトリ/ファイルを手動で作成/削除してはならない

**理由**: LLM ステップは MUST NOT ルールが最も効果的な行動制御手段。明示的禁止がないと LLM が「壊れた symlink を修復しようとする」リスクがある。

### Decision 2: orchestrator に残存 symlink 追加チェック追加

**対象**: `plugins/twl/scripts/autopilot-orchestrator.sh` の CRG セクション（L325-348）

既存の壊れた symlink 自己回復コード（L335-338）を強化:
- 壊れた symlink（`-L` だが `-d` でない）を削除する既存コードはそのまま維持
- `worktree_dir == main` の場合にのみ: `main/.code-review-graph` が symlink になっていた場合は削除してログを出す追加チェックを、CRG セクションの冒頭（outer if の前）に追加する

**理由**: orchestrator が main で動作しているときに、main の `.code-review-graph` が誤って symlink になっていた場合の自動修復。

### Decision 3: su-observer Wave 開始フックに CRG ヘルスチェック追加

**対象**: `plugins/twl/skills/su-observer/SKILL.md`

Wave 開始時のチェックリストに追加:
```bash
_crg_path="${TWILL_REPO_ROOT}/main/.code-review-graph"
if [[ -L "$_crg_path" ]]; then
  echo "⚠️ [CRG health] main/.code-review-graph がシンボリックリンクです。自己参照の可能性があります。"
fi
```

**理由**: 壊れた状態に早期気づくことで修復コストを最小化する。

## Risks / Trade-offs

- orchestrator への変更は最小限（新しいチェックコードの追加のみ）。既存の realpath ガードは変更しない。
- su-observer SKILL.md への追加はドキュメント変更のみ。実際の観察ロジックが存在する場合はそこに追加する。
- crg-auto-build.md の MUST NOT 追加は LLM への指示変更であり、過去の動作を制限する。副作用は最小。
