## Context

loom-plugin-dev は B-1〜B-7 + C-1 + C-2a で基盤構造と独立系48コンポーネントを構築済み。setup chain（開発準備）と test-ready chain（テスト準備）に関連する11コンポーネントのうち、7個は既に移植済みだが、4個（services, ui-capture, e2e-plan, test-scaffold）が未移植で prompt ファイルが存在しない。また worktree-delete は script のみで command が未作成。

旧プラグイン（claude-plugin-dev）に全ソースが存在し、deps.yaml v3.0 構造への変換が必要。

## Goals / Non-Goals

**Goals:**

- 4個の未移植コンポーネントの COMMAND.md 新規作成と deps.yaml 登録
- worktree-delete の command 化（script は残存、command がラッパー）
- workflow-test-ready の calls 定義補完
- loom validate PASS

**Non-Goals:**

- 既存コンポーネント（init, worktree-create, crg-auto-build, worktree-list, opsx-apply）の内容変更
- chain 定義の変更（B-4 で確定済み）
- 新規 chain step の追加（既存 step 構成を維持）

## Decisions

### D1: 旧プラグインからの変換方式

旧 claude-plugin-dev の frontmatter 形式（`---` + description/type/allowed-tools）を loom-plugin-dev の COMMAND.md 形式（frontmatter なし、`# タイトル` から開始）に変換する。deps.yaml v3.0 がメタデータの SSOT であるため、prompt ファイルにはメタデータを含めない。

### D2: worktree-delete の command 化

現行 `scripts/worktree-delete.sh` はそのまま残し、新規 `commands/worktree-delete/COMMAND.md` を作成。COMMAND.md は script を呼び出すラッパーとして機能する。deps.yaml では command と script の両方を定義し、command が script を calls する関係を明示。

### D3: test-scaffold の composite 型

test-scaffold は旧プラグインで composite 型（spec-scaffold-tests + e2e-generate を統合管理）。loom-plugin-dev でも composite として登録し、将来の specialist spawn に対応可能な構造とする。

### D4: workflow-test-ready の calls 補完

現在 workflow-test-ready は deps.yaml に calls が未定義。test-scaffold と opsx-apply を calls に追加し、step 番号を割り当てる。

## Risks / Trade-offs

- **旧プラグインとの乖離**: 旧プラグインの prompt 内容をそのまま移植するのではなく、loom-plugin-dev の設計哲学（chain-driven, autopilot-first）に合わせて簡素化する。過度な簡素化は機能欠落のリスクがあるため、旧ソースの核心ロジックは維持する
- **worktree-delete 二重定義**: command と script の両方が存在することで混乱の可能性。deps.yaml の calls 関係で明示的にリンクすることで緩和
- **test-scaffold の specialist 依存**: composite 型だが現時点で specialist が未定義の場合、Agent tool での spawn に fallback する設計とする
