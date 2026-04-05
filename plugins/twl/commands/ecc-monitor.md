# /twl:ecc-monitor - ECC知識モニター

ECCリポジトリ（everything-claude-code）の変更を検知し、dev pluginへの取り込み候補を評価する。

## 使用方法

```
/twl:ecc-monitor check      # 変更検知のみ
/twl:ecc-monitor evaluate   # 変更検知 + 関連性評価 + レポート生成
/twl:ecc-monitor             # デフォルト: evaluate
```

## サブコマンド

### check

ECCリポジトリの最新変更をカテゴリ別にリストする。

**実行フロー（MUST）:**

1. スクリプト実行:
   ```bash
   bash "$SCRIPTS_ROOT/ecc-monitor.sh" check
   ```

2. JSON出力をパース:
   - `status: "no_changes"` → 「新しい変更はありません」と報告して終了
   - `status: "has_changes"` → カテゴリ別にサマリー表示

3. チェックポイント保存:
   ```bash
   bash "$SCRIPTS_ROOT/ecc-monitor.sh" save-checkpoint
   ```

4. 出力形式:
   ```
   ## ECC変更検知結果

   期間: <from_commit:7>...<to_commit:7>
   変更ファイル数: N件

   | カテゴリ | 件数 | ファイル例 |
   |---------|------|-----------|
   | skills  | 5    | skills/foo/SKILL.md |
   | rules   | 2    | rules/bar.md |
   ...
   ```

### evaluate

check結果に基づき、各変更のdev plugin関連性を3段階評価する。

**実行フロー（MUST）:**

1. まず `check` を実行（上記フロー）
2. 変更なしの場合は終了

3. 各変更のdiffを取得:
   ```bash
   git -C ~/.claude/cache/ecc/ diff <from>..<to> -- <path>
   ```

4. dev pluginの現在構造を把握:
   ```bash
   ls claude/plugins/dev/commands/
   ls claude/plugins/dev/skills/
   ls claude/plugins/dev/agents/
   ```

5. 各変更を3段階で評価:

   | 評価 | 基準 |
   |------|------|
   | **必須** | dev pluginの既存機能に直接影響（バグ修正、破壊的変更、セキュリティ） |
   | **推奨** | dev pluginの改善に活用可能（新パターン、ベストプラクティス更新） |
   | **不要** | dev pluginに無関係（UI専用、特定IDE向け、インフラ/CI） |

6. ECCカテゴリとdev pluginのマッピング:

   | ECCカテゴリ | dev plugin対応先 |
   |------------|-----------------|
   | skills/    | skills/, commands/ |
   | rules/     | agents/ のworker定義、スキル内ルール記述 |
   | agents/    | agents/ |
   | hooks/     | hooks/ |
   | commands/  | commands/ |
   | contexts/  | commands/ 内のコンテキスト参照 |
   | docs/      | スキル・コマンドのドキュメント |
   | root       | CLAUDE.md、README.md等 |

7. Markdownレポート生成:
   ```bash
   mkdir -p docs/ecc-analysis/updates
   ```

   レポートファイル: `docs/ecc-analysis/updates/YYYY-MM-DD.md`

   レポート構造:
   ```markdown
   # ECC更新レポート YYYY-MM-DD

   ## サマリー

   | 評価 | 件数 |
   |------|------|
   | 必須 | N |
   | 推奨 | N |
   | 不要 | N |

   期間: <from_commit:7>...<to_commit:7>

   ## 必須

   ### <ファイルパス>
   - **変更種別**: A/M/D
   - **関連コンポーネント**: <dev pluginの対応先>
   - **理由**: <評価理由>
   - **推奨アクション**: <具体的な取り込みアクション>

   ## 推奨

   ### <ファイルパス>
   - **変更種別**: A/M/D
   - **関連コンポーネント**: <dev pluginの対応先>
   - **理由**: <評価理由>

   ## 不要

   - <ファイルパス>: <理由（1行）>
   ```

8. レポートをgit addしてコミット対象に含める

## 変数

```
SCRIPTS_ROOT = このコマンドファイルと同じプラグインの scripts/ ディレクトリ
```

`SCRIPTS_ROOT` の解決:
```bash
SCRIPTS_ROOT=$(dirname "$(find ~/.claude/plugins/dev -name "ecc-monitor.sh" -path "*/scripts/*")")
```

## 禁止事項（MUST NOT）

- 評価結果を自動適用（Issue作成やコード変更）してはならない
- check結果を見ずにevaluateを開始してはならない
- レポートの評価理由を省略してはならない
