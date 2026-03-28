## 1. switchover.sh スクリプト作成

- [x] 1.1 `scripts/switchover.sh` のスケルトン作成（サブコマンド分岐: check/switch/rollback/retire）
- [x] 1.2 `check` サブコマンド実装（loom validate/check 実行、autopilot セッション検出、symlink パス確認）
- [x] 1.3 `switch` サブコマンド実装（check 実行 → バックアップ作成 → 旧状態ファイル cleanup → symlink 差替え）
- [x] 1.4 `rollback` サブコマンド実装（バックアップ存在確認 → 新状態ファイル cleanup → symlink 復元）
- [x] 1.5 `retire` サブコマンド実装（確認プロンプト → バックアップ削除 → アーカイブ案内表示）

## 2. ドキュメント作成

- [x] 2.1 `docs/switchover-guide.md` 作成（並行検証手順、切替手順、ロールバック手順、退役手順）
- [x] 2.2 `docs/design-decisions.md` 作成（旧 controller SKILL.md からの設計経緯転記）

## 3. deps.yaml 更新・検証

- [x] 3.1 deps.yaml に switchover.sh を追加
- [x] 3.2 `loom check` で構造検証 pass を確認
- [x] 3.3 `loom update-readme` で README 更新
