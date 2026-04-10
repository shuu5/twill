## Requirements

### Requirement: pyproject.toml 作成

`cli/twl/pyproject.toml` を作成し、パッケージメタデータ・依存定義・エントリポイントを定義しなければならない（SHALL）。

- `[project]` セクション: name="twl"、requires-python=">=3.10"
- `[project.dependencies]`: PyYAML を必須依存として含めなければならない（SHALL）
- `[project.optional-dependencies]`: tiktoken、rich をオプショナル依存として定義しなければならない（SHALL）
- `[project.scripts]`: `twl = "twl.cli:run"` を定義しなければならない（SHALL）
- `[build-system]`: setuptools を使用しなければならない（SHALL）

#### Scenario: pip install -e . が成功する
- **WHEN** `cli/twl/` ディレクトリで `pip install -e .` を実行する
- **THEN** エラーなくインストールが完了し、`twl` コマンドが使用可能になる

#### Scenario: PyYAML 依存が定義されている
- **WHEN** `pyproject.toml` の `[project.dependencies]` を確認する
- **THEN** PyYAML が依存として含まれている

### Requirement: src/twl/ ディレクトリ構造作成

`cli/twl/src/twl/` ディレクトリ構造を作成し、Python パッケージとして認識されなければならない（SHALL）。

- `src/twl/__init__.py` を作成しなければならない（SHALL）
- `src/twl/__main__.py` を作成しなければならない（SHALL）
- `src/twl/cli.py` を作成しなければならない（SHALL）

#### Scenario: パッケージとして認識される
- **WHEN** `pip install -e .` 後に `import twl` を実行する
- **THEN** エラーなくインポートが成功する

### Requirement: python3 -m twl エントリポイント

`python3 -m twl <args>` で既存の TWiLL CLI 機能を呼び出せなければならない（SHALL）。

`src/twl/__main__.py` は `src/twl/cli.py` の `run()` を呼び出し、`run()` は `twl-engine.py` の `main()` に委譲しなければならない（SHALL）。

#### Scenario: --help が表示される
- **WHEN** `python3 -m twl --help` を実行する
- **THEN** 既存の twl ヘルプテキストが表示される（exit code 0）

#### Scenario: 既存コマンドが動作する
- **WHEN** `python3 -m twl check` 等の既存コマンドを実行する
- **THEN** twl-engine.py 経由で正常に動作する

## MODIFIED Requirements

### Requirement: 既存テストの継続動作

既存の `pytest tests/` がそのまま通過しなければならない（SHALL）。パッケージ構造追加による既存テストへの破壊的変更があってはならない（MUST NOT）。

#### Scenario: pytest が通過する
- **WHEN** `cli/twl/` ディレクトリで `pytest tests/` を実行する
- **THEN** 全テストが pass する（新規追加ファイルの影響なし）


### Requirement: 既存テストの継続動作

既存の `pytest tests/` がそのまま通過しなければならない（SHALL）。パッケージ構造追加による既存テストへの破壊的変更があってはならない（MUST NOT）。

#### Scenario: pytest が通過する
- **WHEN** `cli/twl/` ディレクトリで `pytest tests/` を実行する
- **THEN** 全テストが pass する（新規追加ファイルの影響なし）
