## Context

co-issue の Step 1.5 は `architecture/domain/glossary.md` の MUST 用語と explore-summary.md の用語を照合し、未登録用語を INFO 通知するだけの仕組みになっている。登録すべきかの判断基準が暗黙知であり、ユーザーが毎回ゼロから判断しなければならない。

判断基準を `refs/ref-glossary-criteria.md` として明文化し、Step 1.5 フロー内で LLM が各未登録用語を自動分類したうえで登録推奨候補だけをユーザーに提案する仕組みを導入する。

## Goals / Non-Goals

**Goals:**

- `refs/ref-glossary-criteria.md` を新規作成し、3軸基準（Context 横断性・ドメイン固有性・定着度）と判定ロジック（2/3軸以上で推奨）を明文化する
- `skills/co-issue/SKILL.md` の Step 1.5 を拡張し、INFO 通知後に ref-glossary-criteria を DCI で Read して各用語を3軸判断するフローを追加する
- `deps.yaml` に `ref-glossary-criteria` エントリと co-issue.calls 参照を追加する

**Non-Goals:**

- `glossary.md` への自動書き込み（ユーザー確認必須の原則を維持）
- 用語の fuzzy-match・正規化（#182 のスコープ）
- merge-gate の glossary drift 検出変更（worker-architecture の責務）
- glossary.md 自体のフォーマット変更
- SHOULD 用語「glossary 照合」の定義更新

## Decisions

### D1: 3軸基準の構造

| 軸 | 登録すべき | 登録不要 |
|---|---|---|
| Context 横断性 | 複数 Bounded Context で使用 | 1つの Context 内で完結 |
| ドメイン固有性 | このプラグインのドメイン固有概念 | プラットフォーム/インフラ/汎用 DDD 用語 |
| 定着度 | 複数ファイルで使用 or 複数 Issue/PR で言及 | 提案段階の新概念（単一箇所のみ） |

**判定ロジック**: 3軸のうち2軸以上で「登録すべき」に該当 → 登録推奨。1軸のみ → 登録不要。

**MUST/SHOULD 振り分け**: Context 横断性あり → MUST。なし → SHOULD。

### D2: DCI Read パターン

ref-glossary-criteria は ARCH_CONTEXT（architecture/ ディレクトリ）に含まれない個別 ref のため、Step 1.5 フロー内で個別に Read する（DCI パターン準拠）。

### D3: context-map.md 不在時のフォールバック

context-map.md が ARCH_CONTEXT に含まれない場合、Context 横断性を「不明」として1軸分マイナス（つまり残り2軸のうち2軸以上で推奨必要）扱いとする。

### D4: 非ブロッキング原則の維持

AskUserQuestion による確認待ちは Step 1.5 内で完結し、ユーザーが全拒否しても Phase 2 に継続する。

## Risks / Trade-offs

- **コードベース調査コスト**: 定着度判断でコードベースを grep するため LLM のターン消費が増える。バジェット制御は既存の depth_instruction パターンに準じて将来対応
- **context-map.md 不在時の精度低下**: 横断性が「不明」扱いになると判断精度が落ちるが、フォールバック明示により一貫性を維持できる
- **INFO → 提案への昇格**: 提案が増えすぎると UX が悪化するリスクがあるが、2軸以上の閾値で絞り込むことで緩和する
