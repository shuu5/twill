## MODIFIED Requirements

### Requirement: supervision-mermaid-full-spawn-paths

supervision.md の Supervisor 常駐ループ mermaid 図は、全 controller（co-self-improve / co-utility / co-project を含む）への spawn パスを持たなければならない（SHALL）。

#### Scenario: 常駐ループ図に全 controller spawn が表示される
- **WHEN** supervision.md の「Supervisor 常駐ループ」mermaid 図を参照する
- **THEN** co-autopilot / co-issue / co-architect / co-self-improve / co-utility / co-project の 6 つ全ての controller への spawn パスノードが存在する

### Requirement: supervision-spawn-mechanism-explicit

supervision.md は su-observer が co-self-improve を session:spawn 経由で起動することを明記しなければならない（SHALL）。

#### Scenario: 委譲関係に spawn メカニズムが明記される
- **WHEN** supervision.md の「co-self-improve との境界」セクションを参照する
- **THEN** 「session:spawn 経由」という記述が委譲関係の説明に含まれている

### Requirement: supervision-co-autopilot-active-observe

supervision.md は co-autopilot のみが能動 observe の対象であり、他の controller は spawn 後即指示待ちであることを記述しなければならない（SHALL）。

#### Scenario: co-autopilot と他 controller の observe 差異が明記される
- **WHEN** supervision.md の常駐ループまたは境界説明を参照する
- **THEN** co-autopilot のみが能動 observe 対象で、他は spawn 後即指示待ちという差異が記載されている

### Requirement: observation-spawn-origin-explicit

observation.md の Observe ループ mermaid 図は、co-self-improve が su-observer から session:spawn で起動される関係を明示しなければならない（SHALL）。

#### Scenario: Observe ループの起点に su-observer spawn が表示される
- **WHEN** observation.md の「Observe ループ」mermaid 図を参照する
- **THEN** 最初のノードが「su-observer: session:spawn で co-self-improve を起動」または等価の記述である

### Requirement: context-map-spawn-observe-explicit

context-map.md の Supervision → Live Observation エッジは「session:spawn → observe」の具体的なメカニズムを示さなければならない（SHALL）。

#### Scenario: Context Map 図にセッション spawn 関係が表示される
- **WHEN** context-map.md の依存関係 mermaid 図を参照する
- **THEN** SOBS から OBS へのエッジラベルに「session:spawn → observe」が含まれている

#### Scenario: Context Map テーブルに spawn 関係が記載される
- **WHEN** context-map.md の「関係の詳細」テーブルを参照する
- **THEN** Supervision → Live Observation の行のインターフェース列に「session:spawn」が含まれている

### Requirement: model-supervisor-type-correct

model.md の Supervisor クラスの type フィールドは `supervisor` でなければならない（SHALL）。

#### Scenario: model.md の Supervisor type が supervisor である
- **WHEN** model.md のクラス図を参照する
- **THEN** Supervisor クラスの `type` フィールドの値が `supervisor` である（`observer` ではない）
