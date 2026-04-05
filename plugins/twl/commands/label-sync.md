# /twl:label-sync - Architecture Spec → GitHub ラベル自動同期

architecture spec を SSOT として GitHub ラベルを作成・同期する atomic コマンド。

## 使用方法

```
/twl:label-sync
/twl:label-sync --dry-run
```

## 引数

| 引数 | 必須 | 説明 |
|------|------|------|
| --dry-run | No | 作成予定ラベルを表示するのみ（実際には作成しない） |

---

## 処理フロー（MUST）

### Step 0: 引数解析

`$ARGUMENTS` から `--dry-run` フラグを検出。

```
DRY_RUN = false
IF $ARGUMENTS contains "--dry-run"
THEN DRY_RUN = true
```

### Step 1: architecture/ ディレクトリ検出

3つのソースからラベル候補を収集する。

#### 1a. Bounded Context ラベル（ctx/*）

`plugins/twl/architecture/domain/contexts/*.md` を Glob で検出。

```
FOR each file IN plugins/twl/architecture/domain/contexts/*.md:
  NAME = ファイル名（拡張子なし）
  TYPE = ファイル冒頭の ## Responsibility セクションから1行目を抽出（推定用）
  ラベル名: ctx/<NAME>
  color: C5DEF5
  description: "Context: <NAME> (<TYPE の先頭20文字>)"
```

#### 1b. Contract ラベル（ctx/*）

`plugins/twl/architecture/contracts/*.md` を Glob で検出。

```
FOR each file IN plugins/twl/architecture/contracts/*.md:
  NAME = ファイル名（拡張子なし）
  ラベル名: ctx/<NAME>
  color: C5DEF5
  description: "Context: <NAME> (contract)"
```

#### 1c. Scope ラベル（scope/*）

ルートレベル `architecture/domain/context-map.md` を Read し、Mermaid ブロック内のノード定義からコンポーネントパスを抽出。

```
FOR each node IN context-map.md mermaid ブロック:
  # ノード定義例: TWL_CLI["cli/twl<br/>構造検証 CLI"]
  # → パス部分: cli/twl
  COMPONENT_PATH = ノードラベルの最初の行（<br/>より前）
  LABEL_NAME = COMPONENT_PATH のスラッシュをハイフンに変換
  ラベル名: scope/<LABEL_NAME>
  color: D4C5F9
  description: "Scope: <COMPONENT_PATH>"
```

### Step 2: 固定ラベルリスト構築

以下の固定ラベルを追加:

**What軸:**
| ラベル名 | color | description |
|----------|-------|-------------|
| enhancement | A2EEEF | "New feature or improvement" |
| bug | D73A4A | "Something isn't working" |
| documentation | 0075CA | "Documentation update" |
| refactor | E4E669 | "Code refactoring" |
| tech-debt/warning | FBCA04 | "Tech debt: warning level" |
| tech-debt/deferred-high | B60205 | "Tech debt: deferred high priority" |

**Maturity軸:**
| ラベル名 | color | description |
|----------|-------|-------------|
| arch/skeleton | BFD4F2 | "Architecture: skeleton phase" |
| arch/refined | 0E8A16 | "Architecture: refined phase" |

**その他:**
| ラベル名 | color | description |
|----------|-------|-------------|
| refined | 0E8A16 | "Issue refined and ready" |
| quick | 7057FF | "Quick task (< 30min)" |
| chore | EDEDED | "Maintenance task" |
| cleanup | EDEDED | "Cleanup task" |

### Step 3: 既存ラベル取得

```bash
gh label list --json name,description,color --limit 200
```

結果を `EXISTING_LABELS` に格納（name のリストとして保持）。

### Step 4: 差分算出

```
TO_CREATE = []
FOR each label IN (ctx/* ラベル + scope/* ラベル + 固定ラベル):
  IF label.name NOT IN EXISTING_LABELS
  THEN TO_CREATE.append(label)
```

差分がない場合:
```
✅ すべてのラベルが同期済みです（N 個）
```

### Step 5: ラベル作成

```
FOR each label IN TO_CREATE:
  IF DRY_RUN:
    echo "[dry-run] would create: ${label.name} (${label.color}) - ${label.description}"
  ELSE:
    gh label create "${label.name}" --color "${label.color}" --description "${label.description}" --force
```

`--force` により既存ラベルの色・説明が更新される（名前が一致する場合）。

### Step 6: 結果テーブル出力

```markdown
## Label Sync Results

| Action | Label | Color | Description |
|--------|-------|-------|-------------|
| ✅ Created | ctx/autopilot | C5DEF5 | Context: autopilot (...) |
| ⏭️ Exists | enhancement | A2EEEF | New feature or improvement |
| ... | ... | ... | ... |

**Summary**: Created N / Skipped M / Total T
```

`--dry-run` 時は Action 列を `🔍 Would create` に変更。
