---
name: twl:ref-practices
description: 5原則+ライフサイクル+チェックポイント+パターン選択ガイド
type: reference
spawnable_by:
- controller
- atomic
---

<!-- Synced from twl docs/ — do not edit directly -->

# Loom — LLM ワークフロー構造化フレームワーク

**Loom** は、LLM のコンテキストウィンドウ制約を前提としたプロンプト分割・ワークフロー構造化フレームワークである。

## Loom の構成要素

| 要素 | 定義場所 | 概要 |
|------|---------|------|
| **6型システム** | `ref-types` | コンポーネントの型階層と spawn ルール (controller, workflow, composite, specialist, atomic, reference) |
| **5原則** | 本ドキュメント | 完結・明示・外部化・並列安全・コスト意識 |
| **7パターン** | 本ドキュメント | 並列レビュー、パイプライン、ファンアウト/ファンイン、Context Snapshot、Subagent Delegation、Session Isolation、Compaction Recovery |
| **Controller 設計原則** | 本ドキュメント | サイズ制限、インライン実装禁止、Phase 委譲、1 Controller = 1 Workflow |
| **アーキテクチャ評価** | `ref-architecture` | パターン適用状態の検証チェックリスト |
| **依存グラフ SSOT** | `ref-deps-format` + `twl` | deps.yaml による宣言的構造管理とツーリング |

### Loom のメタファー

```
経糸 (warp) = 型システム — コンポーネントの構造的骨格
緯糸 (weft) = コンテキスト — プロンプト、snapshot、外部記憶
布 (fabric) = 完成したワークフロー
織機 (twill) = forge — 布を織る道具そのもの
```

### Loom と ACE の関係

ACE (Adaptive Context Engineering) は「LLM のコンテキストウィンドウを適応的に管理する」広い概念。Loom はその具体的実装フレームワークであり、型・原則・パターン・ツーリングを通じて ACE を実現する。

---

## 5原則

### 1. 完結 (Self-Contained)
specialist のプロンプトは単体で目的・制約・報告方法が分かること。

**チェックリスト**:
- [ ] タスクの目的が1文で明記されている
- [ ] 成功条件が具体的に定義されている
- [ ] 使用可能なツールが列挙されている
- [ ] 出力フォーマットが定義されている
- [ ] エラー時の行動指針がある

### 2. 明示 (Explicit)
型・役割・ツール制約・報告ルールを冒頭で宣言。

**チェックリスト**:
- [ ] frontmatter で型・ツールが宣言されている
- [ ] プロンプト冒頭に「あなたは〜です」と役割を明示
- [ ] 禁止事項が明記されている
- [ ] 出力フォーマットが定義されている

### 3. 外部化 (Externalize)
フェーズ間コンテキスト共有は外部ストレージ経由。

**手段**:
- `github_issue`: GitHub Issue経由
- `github_pr`: GitHub PR経由
- `file`: ファイル経由（一時ファイル or 作業ファイル）
- `memory`: Memory MCP経由

**チェックリスト**:
- [ ] 外部コンテキスト手段が宣言されている
- [ ] フェーズ間で引き継ぐべきデータが明確
- [ ] 読み書きの責任が明確（誰が書き、誰が読むか）

### 4. 並列安全 (Parallel-Safe)
ファイル所有権分離、同一ファイル同時編集禁止。

**チェックリスト**:
- [ ] 各 specialist の作業対象ファイルが分離されている
- [ ] 同一ファイルへの同時書き込みがない
- [ ] 共有リソースへのアクセスが制御されている
- [ ] 結果統合ロジックが composite に定義されている

### 5. コスト意識 (Cost-Aware)
モデル・turn数を明示、コスト予測可能。

**チェックリスト**:
- [ ] 各 specialist の model が明示されている
- [ ] maxTurns が設定されている（暴走防止）
- [ ] effort が用途に応じて設定されている（下表参照）
- [ ] haiku で十分なタスクに opus を使っていない

**effort 判定基準**（specialist frontmatter）:

| カテゴリ | effort | 用途例 |
|----------|--------|--------|
| 構造チェック系（Read/Glob/Grep のみ、定型判定） | low | worker-structure, worker-principles, template-validator |
| コードレビュー系（コード文脈理解が必要） | medium | worker-code-reviewer, worker-security-reviewer 等 |
| 生成・修正系（コード生成・設計判断） | high | e2e-generate, e2e-heal, docs-researcher 等 |

**maxTurns 判定基準**（specialist frontmatter）:

| カテゴリ | maxTurns | 根拠 |
|----------|----------|------|
| 単純チェック系（Read/Grep のみ） | 15 | 通常 5-10 ターンで完了 |
| レビュー系（複数ファイル参照） | 20 | 通常 8-15 ターン |
| Playwright 操作系 | 30 | ブラウザ操作で多ターン消費 |
| ループ・生成系（Bash/Write あり） | 40 | 修正ループが発生し得る |

## Controller 設計原則

### controller vs workflow の使い分け

controller と workflow は異なる責務を持つ。ルーティングハブ controller（`co-entry` + 対応表）は非推奨。各ワークフローを `co-{purpose}` として独立定義する。

#### controller が必要なケース

| ケース | 例 | 理由 |
|--------|-----|------|
| 複数 workflow のセッション分離チェーン | setup → test-ready → apply → pr-cycle | workflow 間の状態引き継ぎ・セッション管理 |
| Adaptive context engineering | PR サイクルの動的フロー制御 | コンテキスト圧縮・復帰・動的判断 |
| セッション横断状態管理 | snapshot dir の初期化・復帰判定 | Session Isolation / Compaction Recovery |

#### workflow で十分なケース

| ケース | 例 | 理由 |
|--------|-----|------|
| 1セッション内の完結フロー | レビュー → テスト → 修復ループ | セッション管理不要、フロー制御のみ |
| 再利用可能なフロー | 複数 controller から共通呼び出し | DRY 原則、workflow として分離 |
| user-invocable なステップ集約 | `/twl:workflow-test-ready` | ユーザーが直接実行可能（`user-invocable: true`） |

#### controller が直接 atomic/composite を呼べるケース

2-3ステップの単純フローでは workflow 層は不要。controller がステップチェーンで直接 atomic/composite を呼び出すのが最もシンプル。

| ステップ数 | 推奨構成 |
|-----------|---------|
| 2-3 ステップ | controller → atomic/composite 直接 |
| 4 ステップ以上 | controller → workflow → atomic/composite |
| 再利用するフロー | workflow に分離（ステップ数不問） |

### スキルマッチングへの委任
Claude Code は frontmatter の `description` でユーザー意図を controller または user-invocable workflow にマッチングする。ルーティングロジックは不要。

- 各 `co-{purpose}` / `workflow-{purpose}` の description に発火トリガーフレーズを列挙
- 複数 controller・workflow を定義すれば、スキルマッチングが自動でルーティング処理
- controller 本文にはワークフロー実行ロジックのみ記載
- user-invocable workflow も同様にスキルマッチングの対象となる

### Phase への委譲（責務分離）

controller と composite の責務を分離する:

| 責務 | 記載場所 | 例 |
|------|---------|-----|
| ワークフロー全体の制御（ステップ順序、条件分岐） | **controller** | 「Step 3: レビューフェーズ」 |
| composite の前処理（入力データ収集） | **controller** | PR diff 取得 |
| composite の後処理（ワークフロー判断） | **controller** | Critical → 人間承認待ち |
| specialist 構成（どの specialist をどの条件で起動するか） | **composite** | 技術スタック判定テーブル |
| Task spawn テンプレート（prompt、model） | **composite** | Task() 呼び出し例 |
| 結果統合ロジック（フィルタ、ソート、集計） | **composite** | 信頼度80未満をフィルタ |

**理由（Loom: コンテキスト配分原則）**:
- controller SKILL.md はワークフロー開始時にコンテキストに読み込まれる
- composite の詳細が controller に含まれると、不要なステップでもコンテキストを占有する
- composite 内容変更時に controller も修正が必要になる（SSOT 違反）

**参照方式: 明示的 Read（推奨）**

controller は composite を**実行時に Read tool で読み込む**。これにより:
- composite 内容はそのステップ実行時のみコンテキストに存在する
- 他ステップ実行中は composite 詳細がコンテキストを占有しない
- composite が SSOT として機能する（controller に複製しない）

**controller の Step 記載例**:
```markdown
### Step 3: レビューフェーズ
1. PR diff を取得（`gh pr diff`）
2. `commands/phase-review.md` を Read し、その指示に従い実行:
   - 技術スタック判定 → specialists 並列 spawn → 結果統合
結果を `${SNAPSHOT_DIR}/03-review-result.md` に Write。
Critical/High 検出時は【人間承認待ち】。
```

### Controller 責務制約（MUST）

1. **サイズ制限**: controller の本文（frontmatter除外）は ~80行推奨。
   - 120行超 = Warning（分割検討）
   - 200行超 = Critical（即座に分割必須）

   **トークンベース閾値**（一次基準、行数基準は deprecated）:

   | 型 | Warning | Critical |
   |---|---|---|
   | controller | 1,500 tok | 2,500 tok |
   | workflow | 1,200 tok | 2,000 tok |
   | atomic / composite | 1,500 tok | 2,500 tok |
   | specialist | 1,800 tok | 2,500 tok |

   reference / script は対象外（意図的に長い / LLM ��ロンプトではない）。

2. **インライン実装禁止**: データ加工、バリデーション、フォーマット処理は
   atomic/composite/specialist に委譲。controller の Step は呼び出し指示のみ。
   - OK: 「`commands/execute-prepare.md` を Read し、その指示に従い実行」
   - NG: controller 内にバリデーションロジックを30行記載

3. **ドキュメント禁止**: アーキテクチャ概要、API バジェット表、フォーマット定義は
   reference に配置。controller には実行に必要な判定ロジックのみ。

4. **Reference 配置ルール**: reference の calls 宣言は、その reference を
   本文中で実際に参照するコンポーネントに置く。controller に「まとめ宣言」しない。

5. **allowed-tools 正確性**: frontmatter の allowed-tools/tools は本文で実際に使用する
   ツールと一致させる。宣言漏れ・過剰宣言の両方を禁止。

## プラグイン成果物の品質基準

### 必須成果物

| 成果物 | 要件 | 生成方法 |
|--------|------|----------|
| README.md | エントリーポイント表・構成・依存グラフ・インストール・検証 | generate Step 9 |
| docs/deps.svg | 全体依存グラフ | `twl update-readme` |
| docs/deps-{controller}.svg | コントローラー別分離図 | 同上（自動生成） |

### README.md 必須セクション
1. **エントリーポイント**: controller 一覧テーブル（コマンド・用途）
2. **アーキテクチャ**: コンポーネント構成（型別の数と一覧）
3. **依存関係**: `DEPS-GRAPH-START` / `DEPS-SUBGRAPHS-START` マーカー付き
4. **インストール**: `claude plugin add` コマンド
5. **検証**: `--check` / `--validate` / `--tree` コマンド

### マーカー構造
```markdown
<!-- DEPS-GRAPH-START -->
![Dependency Graph](./docs/deps.svg)
<!-- DEPS-GRAPH-END -->

<!-- DEPS-SUBGRAPHS-START -->
<!-- DEPS-SUBGRAPHS-END -->
```
`--update-readme` がマーカー内を自動更新する。README にマーカーがない場合は Warning。

## ライフサイクル

### persistent（小規模向け）
1セッションで全フェーズを通す。

**適用基準**:
- フェーズ数が少ない（2-3フェーズ）
- specialist 間のコンテキスト共有が多い
- specialist 数が小さい（3以下）

### per_phase（大規模・推奨）
フェーズごとに specialist を spawn → 結果統合。外部コンテキスト経由でフェーズ間を接続。

**適用基準**:
- フェーズ数が多い（4フェーズ以上）
- フェーズごとに異なる specialist 構成
- コスト効率を重視

**フロー例**:
```
Phase 1: Assessment
  controller
    └─ composite → specialists(validator, checker)
  → 外部コンテキスト書き込み

Phase 2: Generation
  controller（外部コンテキスト読み込み）
    └─ composite → specialists(generator, tester)
  → 外部コンテキスト更新
```

## チェックポイント設計

### 外付け reference 方式

| 要素 | 配置 |
|------|------|
| 有無の宣言 | deps.yaml の specialist に `checkpoint: true` |
| CP 参照先 | deps.yaml の specialist に `checkpoint_ref: {reference名}` |
| CP 内容 | reference 型スキルとして独立ファイル |
| 依存宣言 | deps.yaml の specialist → `skills: [{reference名}]` |

**利点**: 複数 specialist が同じ CP reference を共有可能。CP カスタマイズ時は reference だけ変更。

### CP reference テンプレート

```markdown
---
name: {plugin}:checkpoint-{purpose}
description: チェックポイント報告フォーマット
disable-model-invocation: true
---

# チェックポイント報告

## 報告タイミング
- タスク完了時
- 重要な判断ポイント

## 報告フォーマット

### 進捗報告
- status: completed | in_progress | blocked
- summary: 1行要約
- details: 詳細

### 成果物
- files_changed: [変更ファイルリスト]
- issues_found: [発見事項]
```

## Lead Session 中心モデル

コマンド（composite / atomic）は **lead session への指示書** であり、実行主体は常に lead session（= controller）。

### 統一的理解

| 型 | 役割 |
|------|------|
| controller | **lead session**（spawn 権限の主体） |
| workflow | フェーズ遷移制御 |
| **composite** | **spawn 指示書**（実行者の起動テンプレートを含む） |
| specialist | spawn される実行者 |
| atomic | 直接実行指示書（spawn を含まない） |
| reference | 知識提供 |

### 設計上の帰結

- **spawn 権限は lead session に帰属**: composite は「指示書」であり、spawn の実行主体ではない
- **composite vs atomic の区別**: specialist spawn 指示を含むか否か。含むなら composite、含まないなら atomic
- **deps.yaml のエッジ**: composite → specialist のエッジで spawn 関係を表現。controller → specialist の直接エッジは Subagent Delegation（composite を経由しない spawn）に使用
- **一貫原則**: SVG は設計時の構成関係を表す。コンポーネントの「所属」を正確に反映し、runtime の実行フロー（誰が Task() を呼ぶか）ではない

## パターン集

### パターン1: 並列レビュー（composite + specialist）
複数の観点で同時にレビュー。controller が composite の指示に従い specialist を並列 spawn → 結果統合。composite で parallel: true、specialist 構成は composite が定義。

### パターン2: パイプライン
フェーズを順次実行。前フェーズの結果を次フェーズに引き継ぎ。

### パターン3: ファンアウト/ファンイン（composite ベース）
1つのタスクを分割 → composite で specialist を並列 spawn → 結果統合。

### パターン4: Context Snapshot（ステップチェーン保護）
ステップ間の中間結果をファイルに構造化保存し、コンテキスト圧縮への耐性を提供。

**仕組み**:
- 各ステップは前ステップのスナップショットファイルを Read して開始
- 各ステップの結果をスナップショットとして Write
- 会話コンテキストに依存しないため、圧縮されても情報が失われない

**ディレクトリ構造例**:
```
/tmp/{plugin}-{workflow}/
├── 01-{step1}-results.md
├── 02-{step2}-results.md
├── 03-{step3}-results.md
└── ...
```

**ルール**:
1. controller 開始時にディレクトリ初期化
2. 各ステップは前ステップのスナップショットを Read して開始
3. 各ステップの結果をスナップショットとして Write
4. イテレーション時は該当ステップから上書き（後続はクリア）
5. セッション切断後も前回の状態から再開可能

**適用基準**: ステップ数が4以上のワークフロー

### パターン5: Subagent Delegation（コンテキスト節約）
Web取得・大量スキャン等を Task tool で specialist に委任し、メインコンテキストを保護。

**仕組み**:
- controller が Task tool で specialist agent を起動
- specialist は isolated context で実行
- メインコンテキストにはサマリーのみ戻す

**適用例**:
```
controller → Task(docs-researcher, "仕様を調査")
           ← サマリー（数行）のみ受け取り
           → スナップショットに保存
```

**deps.yaml の設定**（必須）:
- controller の `can_spawn` に `specialist` を追加（型制約）
- controller の `calls` に `- agent: {specialist名}` を追加（**SVG エッジ生成に必須**）
- specialist の `spawnable_by: [controller]` を設定

> **注意**: `can_spawn` だけでは SVG グラフにエッジが描画されない。`calls` に含めないと orphan 扱いになる。

**適用基準**: 結果だけ必要で、取得過程のコンテキストが不要なステップ

### パターン6: Session Isolation（セッション分離）
並行セッション安全性のためのセッション一意化パターン。

**仕組み**:
- ワークフロー開始時に 8文字の session_id を生成（`uuidgen | cut -c1-8`）
- snapshot_dir に session_id を付加
- session-info.json でセッションメタデータを永続化
- 再発見: `ls -td /tmp/{plugin}-{workflow}[-{target}]-*/session-info.json`

**パス規則**: `/tmp/{plugin}-{workflow}[-{target}]-{session_id}/`

**適用基準**: per_phase ライフサイクルで Context Snapshot を使用する全ワークフロー

### パターン7: Compaction Recovery（コンパクト復帰）
コンテキスト圧縮後のワークフロー状態復元パターン。Session Isolation と併用。

**仕組み**:
- snapshot ファイルでステップ進行状況を追跡
- specialists が snapshot ディレクトリに Write で結果出力
- controller 起動時に復帰判定を実行

**復帰プロトコル**:
controller 開始時に glob で既存セッションを検索 → snapshot ファイルの存在で分岐判定

**冪等性ルール**: 出力 snapshot ファイルが存在し内容がある場合、そのステップはスキップ

**適用基準**: per_phase + Context Snapshot + 5ステップ以上 or 長時間実行

## パターン選択ガイド

### 判断木

```
ステップ数が 4 以上か？
├─ YES → Context Snapshot を導入
└─ NO  → 省略可（会話コンテキストで十分）

各ステップについて:
├─ 複数の独立チェックがある？ → Composite + Specialists (並列 spawn)
├─ specialist spawn が必要？ → Composite (spawn 指示書)
├─ Web取得・大量データ処理？ → Subagent Delegation (specialist via composite)
├─ ユーザー対話が必要？ → Atomic (直接実行)
├─ ファイル編集が必要？ → Atomic (直接実行)
└─ 全ステップ共通の知識？ → Reference

per_phase ライフサイクルか？
├─ YES → Session Isolation を導入
│   └─ コンパクトリスクがあるか？（5ステップ以上 or 長時間実行）
│       ├─ YES → Compaction Recovery を導入
│       └─ NO  → Session Isolation のみ
└─ NO  → 省略可
```

### パターン適用マトリクス

| 特徴 | 推奨パターン | 理由 |
|------|------------|------|
| 複数観点の同時分析 | 並列レビュー (composite + specialists) | 品質向上 + 多角的評価 |
| Web/API からの情報取得 | Subagent Delegation | コンテキスト節約 |
| 長い処理パイプライン | Context Snapshot | 再現性 + 耐障害性 |
| ユーザー入力依存 | Atomic (inline) | 対話の即時性 |
| 単一ファイル編集 | Atomic (inline) | 直列安全性 |
| 複数ファイル並列編集 | 並列レビュー (composite + specialists) | 速度 + 所有権分離 |
| 共通ルール・仕様 | Reference | 常時参照 + 一貫性 |
| per_phase + 並行セッションリスク | Session Isolation | 名前空間衝突防止 |
| 長時間ワークフロー | Compaction Recovery | コンテキスト消失対策 |

### ハイブリッド設計の原則
- 全 controller に Context Snapshot を導入する必要はない（4ステップ未満なら不要）
- Subagent は「結果だけ必要で過程のコンテキストが不要」なステップに適用
- **ルーティングコントローラー非推奨**: 「Controller 設計原則」セクション参照。`co-{purpose}` として独立定義し、スキルマッチングに委任する
