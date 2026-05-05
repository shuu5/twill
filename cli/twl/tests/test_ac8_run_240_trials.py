"""
RED tests for Issue #1038 -- Phase1 Beta Trial Orchestration.

TDD RED フェーズ用テストスタブ。
実装前は全件 FAIL する（意図的 RED）。

AC1: ac8_run_240_trials.py の skeleton（main + run_trial + classify_failure + goldfile_match）が実装されている
AC2: cld -p で mcp__twl__twl_state_read を呼び出して exit 0 になることを 1 trial 検証する unit test
AC4: driver script で 12 trial（6 op × 2 route × 1 trial）が動作し、CSV に 12 行出力される
AC5: 12 trial の success=true 行が 12 件（goldfile 一致 100%）
AC6: ac8_data/<timestamp>.csv に 240 行（header 除く）が保存されている
AC7: CSV が REQUIRED_CSV_COLUMNS を全て含む
AC8: 6 操作 × 2 経路 × 20 trials の組合せ全て揃っている（pivot で 240/240 確認）
AC9: python3 ac8_significance_test.py --csv <path> が JSON 出力で完了し overall_judgment が正当な値
AC11: phase1-ai-failure-rate-protocol.md に「## 実測結果サマリ」section が追加されている
AC12a: test_issue_1027_followup.py の structure 系 8 tests が GREEN（mapping 記録のみ）
AC12b: test_issue_1027_followup.py の measurement-dependent 4 tests が GREEN（mapping 記録のみ）
"""

import csv
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

import pytest

# パス定義
REPO_ROOT = Path(__file__).resolve().parent.parent.parent.parent
CLI_TWL_DIR = REPO_ROOT / "cli" / "twl"
PLUGINS_TWL_DIR = REPO_ROOT / "plugins" / "twl"

SCRIPT_DIR = CLI_TWL_DIR / "tests" / "scripts"
AC8_RUN_SCRIPT = SCRIPT_DIR / "ac8_run_240_trials.py"
SIGNIFICANCE_SCRIPT = SCRIPT_DIR / "ac8_significance_test.py"
AC8_GOLDFILES_DIR = SCRIPT_DIR / "ac8_goldfiles"
AC8_DATA_DIR = SCRIPT_DIR / "ac8_data"
PROTOCOL_DOC = PLUGINS_TWL_DIR / "architecture" / "phases" / "phase1-ai-failure-rate-protocol.md"

REQUIRED_OPERATIONS = [
    "issue_init",
    "read_field",
    "status_transition",
    "rbac_violation",
    "failed_done_force",
    "sets_nested_key",
]
REQUIRED_ROUTES = ["cli", "mcp"]
TRIALS_PER_OP_ROUTE = 20
TOTAL_TRIALS = len(REQUIRED_OPERATIONS) * len(REQUIRED_ROUTES) * TRIALS_PER_OP_ROUTE  # 240

REQUIRED_CSV_COLUMNS = [
    "operation",
    "route",
    "trial_index",
    "success",
    "failure_pattern",
    "session_id",
    "timestamp",
]


# ---------------------------------------------------------------------------
# fixture: loaded_ac8_module
# ---------------------------------------------------------------------------

@pytest.fixture
def loaded_ac8_module():
    if not AC8_RUN_SCRIPT.exists():
        pytest.skip(f"AC8_RUN_SCRIPT が存在しない: {AC8_RUN_SCRIPT}")
    spec = importlib.util.spec_from_file_location("ac8_run_240_trials", AC8_RUN_SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


# ---------------------------------------------------------------------------
# AC1: ac8_run_240_trials.py skeleton 実装確認
# ---------------------------------------------------------------------------

class TestAC1SkeletonImplemented:
    """AC1: ac8_run_240_trials.py の skeleton（main + run_trial + classify_failure + goldfile_match）
    が新規実装されている。

    ファイル未存在のため全件 FAIL する（RED）。
    """

    def test_ac1_script_file_exists(self):
        # AC: cli/twl/tests/scripts/ac8_run_240_trials.py が存在する
        # RED: 未実装のため FAIL
        assert AC8_RUN_SCRIPT.exists(), (
            f"ac8_run_240_trials.py が存在しない: {AC8_RUN_SCRIPT}"
        )

    @pytest.mark.parametrize("func_name", [
        "main", "run_trial", "classify_failure", "goldfile_match"
    ])
    def test_ac1_has_function(self, loaded_ac8_module, func_name):
        assert hasattr(loaded_ac8_module, func_name), f"{func_name}() 関数が定義されていない"
        assert callable(getattr(loaded_ac8_module, func_name)), f"{func_name} が callable でない"

    def test_ac1_script_importable(self):
        # AC: ac8_run_240_trials.py が import エラーなく読み込める
        # RED: ファイル未存在のため FAIL
        if not AC8_RUN_SCRIPT.exists():
            raise NotImplementedError("AC #1 未実装: ac8_run_240_trials.py が存在しない")
        result = subprocess.run(
            [sys.executable, "-c", f"import importlib.util; spec=importlib.util.spec_from_file_location('m','{AC8_RUN_SCRIPT}'); m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)"],
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, f"import 失敗: {result.stderr}"


# ---------------------------------------------------------------------------
# AC2: cld -p で mcp__twl__twl_state_read を呼び出して exit 0 になる PoC unit test
# ---------------------------------------------------------------------------

class TestAC2CldMcpPoC:
    """AC2: cld -p で mcp__twl__twl_state_read を呼び出して exit 0 になることを 1 trial 検証する unit test。

    RED: cld コマンドの PoC 動作が未確認のため FAIL する。
    """

    def test_ac2_cld_command_available(self):
        # AC: cld -p で mcp__twl__twl_state_read を呼び出して exit 0 になる PoC が完成している
        # RED: PoC 未実装のため FAIL（cld PATH 存在確認ではなく PoC 完了確認）
        raise NotImplementedError(
            "AC #2 未実装: cld -p による mcp__twl__twl_state_read PoC が未完了"
        )

    def test_ac2_cld_mcp_twl_state_read_exit0(self):
        # AC: cld -p で mcp__twl__twl_state_read を呼び出した際、exit 0 で終了する（1 trial 検証）
        # RED: PoC 動作未実装のため FAIL
        raise NotImplementedError(
            "AC #2 未実装: cld -p で mcp__twl__twl_state_read を呼び出す PoC が未実装"
        )

    def test_ac2_run_trial_with_mcp_route_succeeds(self, loaded_ac8_module):
        # AC: run_trial() を mcp 経路で実行した場合、success=True が返る
        # RED: ac8_run_240_trials.py 未実装のため SKIP → FAIL
        result = loaded_ac8_module.run_trial(operation="issue_init", route="mcp", trial_index=0)
        assert result.get("success") is True, f"MCP route で success=True が返らない: {result}"


# ---------------------------------------------------------------------------
# AC4: driver script で 12 trial（6 op × 2 route × 1 trial）が動作し CSV に 12 行出力
# ---------------------------------------------------------------------------

class TestAC4TwelveTrialSmoke:
    """AC4: driver script で 12 trial（6 op × 2 route × 1 trial）が動作し、CSV に 12 行（header 除く）出力される。

    RED: ac8_run_240_trials.py 未実装のため FAIL する。
    """

    def test_ac4_script_runs_12_trials(self):
        # AC: ac8_run_240_trials.py が --trials 1 オプションで 6×2=12 trial を実行できる
        # RED: 未実装のため FAIL
        if not AC8_RUN_SCRIPT.exists():
            raise NotImplementedError("AC #4 未実装: ac8_run_240_trials.py が存在しない")
        with tempfile.TemporaryDirectory() as tmpdir:
            out_csv = Path(tmpdir) / "smoke.csv"
            result = subprocess.run(
                [sys.executable, str(AC8_RUN_SCRIPT), "--trials", "1", "--output", str(out_csv)],
                capture_output=True,
                text=True,
                timeout=300,
            )
            assert result.returncode == 0, f"Script 失敗: {result.stderr}"
            assert out_csv.exists(), f"CSV が出力されていない: {out_csv}"
            with open(out_csv, newline="") as f:
                rows = list(csv.DictReader(f))
            assert len(rows) == 12, f"12 行期待、実際: {len(rows)} 行"

    def test_ac4_csv_has_12_rows_header_excluded(self):
        # AC: CSV の行数がヘッダを除いて 12 行である（6 op × 2 route × 1 trial）
        # RED: 未実装のため FAIL
        if not AC8_RUN_SCRIPT.exists():
            raise NotImplementedError("AC #4 未実装: ac8_run_240_trials.py が存在しない")
        with tempfile.TemporaryDirectory() as tmpdir:
            out_csv = Path(tmpdir) / "smoke.csv"
            subprocess.run(
                [sys.executable, str(AC8_RUN_SCRIPT), "--trials", "1", "--output", str(out_csv)],
                capture_output=True,
                text=True,
                timeout=300,
                check=True,
            )
            lines = out_csv.read_text().strip().splitlines()
            # lines[0] はヘッダ
            data_lines = lines[1:]
            assert len(data_lines) == 12, f"データ行 12 期待、実際: {len(data_lines)}"


# ---------------------------------------------------------------------------
# AC5: 12 trial の success=true 行が 12 件（goldfile 一致 100%）
# ---------------------------------------------------------------------------

class TestAC5SmokeSuccessRate:
    """AC5: 12 trial の success=true 行が 12 件（goldfile 一致 100%）。

    RED: ac8_run_240_trials.py 未実装のため FAIL する。
    """

    def test_ac5_all_12_trials_success(self):
        # AC: smoke run（12 trial）の全行で success=true である
        # RED: 未実装のため FAIL
        if not AC8_RUN_SCRIPT.exists():
            raise NotImplementedError("AC #5 未実装: ac8_run_240_trials.py が存在しない")
        with tempfile.TemporaryDirectory() as tmpdir:
            out_csv = Path(tmpdir) / "smoke.csv"
            subprocess.run(
                [sys.executable, str(AC8_RUN_SCRIPT), "--trials", "1", "--output", str(out_csv)],
                capture_output=True,
                text=True,
                timeout=300,
                check=True,
            )
            with open(out_csv, newline="") as f:
                rows = list(csv.DictReader(f))
            success_rows = [r for r in rows if r.get("success", "").lower() in ("true", "1", "yes")]
            assert len(success_rows) == 12, (
                f"success=true 行が 12 件期待、実際: {len(success_rows)} 件\n"
                f"失敗行: {[r for r in rows if r not in success_rows]}"
            )

    def test_ac5_goldfile_match_function_works(self, loaded_ac8_module):
        # AC: goldfile_match() 関数が goldfiles ディレクトリ内の既存ファイルに対して True を返す
        # RED: 未実装のため SKIP → FAIL
        goldfile = AC8_GOLDFILES_DIR / "issue_init_cli.txt"
        assert goldfile.exists(), f"goldfile が見つからない: {goldfile}"
        expected = goldfile.read_text()
        result = loaded_ac8_module.goldfile_match(output=expected, operation="issue_init", route="cli")
        assert result is True, f"goldfile_match が True を返さない: {result}"


# ---------------------------------------------------------------------------
# AC6: ac8_data/<timestamp>.csv に 240 行（header 除く）が保存されている
# ---------------------------------------------------------------------------

class TestAC6TwoHundredFortyRows:
    """AC6: cli/twl/tests/scripts/ac8_data/<timestamp>.csv に 240 行（header 除く）が保存されている。

    RED: 240 trial 実測未完了のため FAIL する。
    """

    def test_ac6_data_dir_has_csv(self):
        # AC: ac8_data/ ディレクトリに CSV ファイルが少なくとも 1 件存在する
        # RED: 実測未完了のため FAIL
        assert AC8_DATA_DIR.exists(), f"ac8_data/ ディレクトリが存在しない: {AC8_DATA_DIR}"
        csvs = list(AC8_DATA_DIR.glob("*.csv"))
        assert len(csvs) >= 1, f"ac8_data/ に CSV が存在しない（240 trial 実測待ち）"

    def test_ac6_csv_has_240_data_rows(self):
        # AC: ac8_data/ の最新 CSV（タイムスタンプ降順1件目）のデータ行数が 240 以上
        # RED: 実測未完了のため FAIL
        if not AC8_DATA_DIR.exists():
            raise NotImplementedError("AC #6 未実装: ac8_data/ ディレクトリが存在しない")
        csvs = sorted(AC8_DATA_DIR.glob("*.csv"), reverse=True)
        if not csvs:
            raise NotImplementedError("AC #6 未実装: ac8_data/ に CSV が存在しない")
        latest_csv = csvs[0]
        with open(latest_csv, newline="") as f:
            rows = list(csv.DictReader(f))
        assert len(rows) >= 240, (
            f"240 行期待（ヘッダ除く）、実際: {len(rows)} 行 ({latest_csv.name})"
        )


# ---------------------------------------------------------------------------
# AC7: CSV が REQUIRED_CSV_COLUMNS を全て含む
# ---------------------------------------------------------------------------

class TestAC7CsvColumns:
    """AC7: CSV が REQUIRED_CSV_COLUMNS (operation, route, trial_index, success,
    failure_pattern, session_id, timestamp) を全て含む。

    RED: 実測 CSV 未作成のため FAIL する。
    """

    def test_ac7_csv_has_all_required_columns(self):
        # AC: ac8_data/ の最新 CSV が REQUIRED_CSV_COLUMNS を全て含む
        # RED: 実測 CSV 未作成のため FAIL
        if not AC8_DATA_DIR.exists():
            raise NotImplementedError("AC #7 未実装: ac8_data/ ディレクトリが存在しない")
        csvs = sorted(AC8_DATA_DIR.glob("*.csv"), reverse=True)
        if not csvs:
            raise NotImplementedError("AC #7 未実装: ac8_data/ に CSV が存在しない")
        latest_csv = csvs[0]
        with open(latest_csv, newline="") as f:
            reader = csv.DictReader(f)
            fieldnames = reader.fieldnames or []
        missing = [c for c in REQUIRED_CSV_COLUMNS if c not in fieldnames]
        assert not missing, (
            f"CSV に必須カラムが不足: {missing} (CSV: {latest_csv.name})"
        )

    def test_ac7_run_script_outputs_required_columns(self):
        # AC: ac8_run_240_trials.py が出力する CSV に REQUIRED_CSV_COLUMNS が含まれる
        # RED: 未実装のため FAIL
        if not AC8_RUN_SCRIPT.exists():
            raise NotImplementedError("AC #7 未実装: ac8_run_240_trials.py が存在しない")
        with tempfile.TemporaryDirectory() as tmpdir:
            out_csv = Path(tmpdir) / "col_check.csv"
            subprocess.run(
                [sys.executable, str(AC8_RUN_SCRIPT), "--trials", "1", "--output", str(out_csv)],
                capture_output=True,
                text=True,
                timeout=300,
                check=True,
            )
            with open(out_csv, newline="") as f:
                reader = csv.DictReader(f)
                fieldnames = reader.fieldnames or []
            missing = [c for c in REQUIRED_CSV_COLUMNS if c not in fieldnames]
            assert not missing, f"出力 CSV に必須カラムが不足: {missing}"


# ---------------------------------------------------------------------------
# AC8: 6 操作 × 2 経路 × 20 trials の組合せ全て揃っている（pivot で 240/240 確認）
# ---------------------------------------------------------------------------

class TestAC8AllCombinations:
    """AC8: 6 操作 × 2 経路 × 20 trials の組合せ全て揃っている。

    RED: 実測 CSV 未作成のため FAIL する。
    """

    def test_ac8_all_operation_route_combinations_present(self):
        # AC: CSV の操作×経路ピボットで 12 組合せ全てに 20 以上の trial が存在する
        # RED: 実測 CSV 未作成のため FAIL
        if not AC8_DATA_DIR.exists():
            raise NotImplementedError("AC #8 未実装: ac8_data/ ディレクトリが存在しない")
        csvs = sorted(AC8_DATA_DIR.glob("*.csv"), reverse=True)
        if not csvs:
            raise NotImplementedError("AC #8 未実装: ac8_data/ に CSV が存在しない")
        latest_csv = csvs[0]
        with open(latest_csv, newline="") as f:
            rows = list(csv.DictReader(f))
        # pivot: {(operation, route): count}
        pivot: dict[tuple[str, str], int] = {}
        for row in rows:
            key = (row.get("operation", ""), row.get("route", ""))
            pivot[key] = pivot.get(key, 0) + 1
        missing_combos = []
        for op in REQUIRED_OPERATIONS:
            for route in REQUIRED_ROUTES:
                count = pivot.get((op, route), 0)
                if count < TRIALS_PER_OP_ROUTE:
                    missing_combos.append((op, route, count))
        assert not missing_combos, (
            f"20 trial 未満の組合せが存在: {missing_combos}"
        )

    def test_ac8_total_trial_count_is_240(self):
        # AC: CSV の総 trial 数（ヘッダ除く）が 240 である
        # RED: 実測 CSV 未作成のため FAIL
        if not AC8_DATA_DIR.exists():
            raise NotImplementedError("AC #8 未実装: ac8_data/ ディレクトリが存在しない")
        csvs = sorted(AC8_DATA_DIR.glob("*.csv"), reverse=True)
        if not csvs:
            raise NotImplementedError("AC #8 未実装: ac8_data/ に CSV が存在しない")
        latest_csv = csvs[0]
        with open(latest_csv, newline="") as f:
            rows = list(csv.DictReader(f))
        assert len(rows) == TOTAL_TRIALS, (
            f"総 trial 数 {TOTAL_TRIALS} 期待、実際: {len(rows)}"
        )


# ---------------------------------------------------------------------------
# AC9: ac8_significance_test.py が JSON 出力で完了し overall_judgment が正当な値
# ---------------------------------------------------------------------------

class TestAC9SignificanceTestOutput:
    """AC9: python3 ac8_significance_test.py --csv <path> が JSON 出力で完了。
    overall_judgment が "全達成"|"部分達成"|"未達成" のいずれかで記載されている。

    注: script 自体は実装済み。実測 CSV を使った overall_judgment 確認が RED 状態。
    """

    def test_ac9_significance_script_exists(self):
        # AC: ac8_significance_test.py が存在する
        assert SIGNIFICANCE_SCRIPT.exists(), (
            f"ac8_significance_test.py が存在しない: {SIGNIFICANCE_SCRIPT}"
        )

    def test_ac9_overall_judgment_valid_with_real_csv(self):
        # AC: 実測 CSV を渡した場合に overall_judgment が "全達成"|"部分達成"|"未達成" のいずれかである
        # RED: 実測 CSV 未作成のため FAIL
        if not AC8_DATA_DIR.exists():
            raise NotImplementedError("AC #9 未実装: ac8_data/ ディレクトリが存在しない")
        csvs = sorted(AC8_DATA_DIR.glob("*.csv"), reverse=True)
        if not csvs:
            raise NotImplementedError("AC #9 未実装: ac8_data/ に実測 CSV が存在しない")
        latest_csv = csvs[0]
        result = subprocess.run(
            [sys.executable, str(SIGNIFICANCE_SCRIPT), "--csv", str(latest_csv)],
            capture_output=True,
            text=True,
            timeout=120,
        )
        assert result.returncode == 0, f"Script 失敗: {result.stderr}"
        output = json.loads(result.stdout)
        assert "overall_judgment" in output, "overall_judgment キーが JSON に存在しない"
        valid_judgments = {"全達成", "部分達成", "未達成"}
        assert output["overall_judgment"] in valid_judgments, (
            f"overall_judgment が正当な値でない: {output['overall_judgment']}"
        )


# ---------------------------------------------------------------------------
# AC11: phase1-ai-failure-rate-protocol.md に「## 実測結果サマリ」section が追加されている
# ---------------------------------------------------------------------------

class TestAC11ProtocolDocSummarySection:
    """AC11: phase1-ai-failure-rate-protocol.md に「## 実測結果サマリ」section が追加されている。

    RED: section 未追加のため FAIL する。
    """

    def test_ac11_protocol_doc_exists(self):
        # AC: phase1-ai-failure-rate-protocol.md が存在する
        assert PROTOCOL_DOC.exists(), f"Protocol doc が存在しない: {PROTOCOL_DOC}"

    def test_ac11_protocol_doc_has_measured_result_section(self):
        # AC: phase1-ai-failure-rate-protocol.md に「## 実測結果サマリ」section が存在する
        # RED: section 未追加のため FAIL
        assert PROTOCOL_DOC.exists(), f"Protocol doc が存在しない: {PROTOCOL_DOC}"
        content = PROTOCOL_DOC.read_text(encoding="utf-8")
        assert "## 実測結果サマリ" in content, (
            "phase1-ai-failure-rate-protocol.md に「## 実測結果サマリ」section が存在しない"
        )

    def test_ac11_summary_section_has_overall_judgment(self):
        # AC: 「## 実測結果サマリ」section に overall_judgment の記載がある
        # RED: section 未追加のため FAIL
        assert PROTOCOL_DOC.exists(), f"Protocol doc が存在しない: {PROTOCOL_DOC}"
        content = PROTOCOL_DOC.read_text(encoding="utf-8")
        assert "## 実測結果サマリ" in content, (
            "phase1-ai-failure-rate-protocol.md に「## 実測結果サマリ」section が存在しない"
        )
        # overall_judgment の記載確認
        section_start = content.index("## 実測結果サマリ")
        section_content = content[section_start:]
        assert "overall_judgment" in section_content or "全達成" in section_content or "部分達成" in section_content or "未達成" in section_content, (
            "実測結果サマリ section に overall_judgment または判定結果の記載がない"
        )

    def test_ac11_summary_section_has_per_operation_table(self):
        # AC: 「## 実測結果サマリ」section に per_operation 表が存在する
        # RED: section 未追加のため FAIL
        assert PROTOCOL_DOC.exists(), f"Protocol doc が存在しない: {PROTOCOL_DOC}"
        content = PROTOCOL_DOC.read_text(encoding="utf-8")
        assert "## 実測結果サマリ" in content, (
            "phase1-ai-failure-rate-protocol.md に「## 実測結果サマリ」section が存在しない"
        )
        section_start = content.index("## 実測結果サマリ")
        section_content = content[section_start:]
        # Markdown テーブルの存在確認（| で始まる行）
        table_lines = [ln for ln in section_content.splitlines() if ln.strip().startswith("|")]
        assert len(table_lines) >= 2, (
            "実測結果サマリ section に per_operation 表（Markdown テーブル）が存在しない"
        )
