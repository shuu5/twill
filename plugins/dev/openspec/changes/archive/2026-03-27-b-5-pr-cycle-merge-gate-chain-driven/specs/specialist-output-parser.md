## ADDED Requirements

### Requirement: specialist 出力パーサー

specialist の出力を共通スキーマ（status, findings[]）に基づいてパースする script 型コンポーネントを実装しなければならない（SHALL）。消費側（merge-gate / phase-review）はパーサー経由でのみ結果を取得する。

#### Scenario: 正常パース
- **WHEN** specialist の出力に `status: PASS` と JSON の findings ブロックが含まれる
- **THEN** パーサーは status と findings 配列を抽出する
- **AND** 各 finding の必須フィールド（severity, confidence, file, line, message, category）が検証される

#### Scenario: パース失敗のフォールバック
- **WHEN** specialist の出力が共通スキーマに準拠しない（status 行なし、JSON パースエラー等）
- **THEN** 出力全文が 1 つの WARNING finding（confidence=50）として扱われる（MUST）
- **AND** 手動レビューが要求される
- **AND** merge-gate のブロック閾値（confidence>=80）には達しないため自動 REJECT にはならない

#### Scenario: findings の severity 集約
- **WHEN** 複数 specialist の findings が集約される
- **THEN** severity=CRITICAL かつ confidence>=80 の finding が 1 件でもあれば merge-gate は REJECT 判定（SHALL）
- **AND** findings は specialist 名付きで一覧表示される

### Requirement: AI 裁量の排除

結果集約において AI による自由形式の変換を禁止しなければならない（MUST）。specialist 出力のパースと機械的フィルタのみで判定を行う。

#### Scenario: 機械的結果集約
- **WHEN** phase-review が全 specialist の結果を統合する
- **THEN** パーサーの出力（構造化データ）のみを使用する
- **AND** AI による severity の再判定、confidence の推定、finding の要約生成は行わない
