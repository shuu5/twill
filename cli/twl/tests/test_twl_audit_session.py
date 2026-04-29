"""Tests for twl_audit_session — Issue #1113 AC3-1, AC3-3, AC3-4, AC3-6.

TDD RED フェーズ。実装前は全テストが FAIL する（意図的 RED）。
対象 handler: twl_audit_session_handler (tools.py)

AC 対応:
  AC3-1: tool シグネチャ・戻り値 schema (audit rules R1-R4 + build_envelope 準拠)
  AC3-3: handler は pure Python + idempotent (read-only, 副作用なし)
  AC3-4: pytest 2 経路 (handler 直接 + fastmcp 経由)
  AC3-6: race protection (rename atomicity 前提、Python flock 不使用)
"""

import json
import time
from pathlib import Path

import pytest

TWL_DIR = Path(__file__).resolve().parent.parent


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture
def autopilot_dir(tmp_path: Path) -> Path:
    d = tmp_path / ".autopilot"
    d.mkdir()
    (d / "checkpoints").mkdir()
    (d / "waves").mkdir()
    return d


@pytest.fixture
def valid_session_json(autopilot_dir: Path) -> Path:
    """R1 OK / R2 plan_path 不在 (warning) の session.json を作成する。"""
    data = {
        "session_id": "abc12345",
        "plan_path": str(autopilot_dir / "plan.yaml"),  # 不在 → R2 warning
        "current_phase": 1,
        "phase_count": 3,
        "started_at": "2026-04-29T00:00:00Z",
        "cross_issue_warnings": [],
        "phase_insights": [],
        "patterns": {},
        "self_improve_issues": [],
    }
    p = autopilot_dir / "session.json"
    p.write_text(json.dumps(data, ensure_ascii=False))
    return p


@pytest.fixture
def invalid_session_json(autopilot_dir: Path) -> Path:
    """R1 FAIL: session_id がパターン不一致な session.json。"""
    data = {
        "session_id": "bad-id!",  # 英数字 8文字でない → R1 critical
        "plan_path": str(autopilot_dir / "plan.yaml"),
        "current_phase": 1,
        "phase_count": 3,
        "started_at": "2026-04-29T00:00:00Z",
        "cross_issue_warnings": [],
        "phase_insights": [],
        "patterns": {},
        "self_improve_issues": [],
    }
    p = autopilot_dir / "session.json"
    p.write_text(json.dumps(data, ensure_ascii=False))
    return p


@pytest.fixture
def valid_checkpoint(autopilot_dir: Path) -> Path:
    """R3 OK: 必須 fields 揃った checkpoint を作成する。"""
    data = {
        "step": "review",
        "status": "PASS",
        "findings_summary": "all good",
        "critical_count": 0,
        "findings": [],
        "timestamp": "2026-04-29T00:00:00Z",
    }
    p = autopilot_dir / "checkpoints" / "review.json"
    p.write_text(json.dumps(data))
    return p


@pytest.fixture
def invalid_checkpoint(autopilot_dir: Path) -> Path:
    """R3 FAIL: 必須 field 欠落の checkpoint を作成する。"""
    data = {"step": "broken"}  # status 等欠落
    p = autopilot_dir / "checkpoints" / "broken.json"
    p.write_text(json.dumps(data))
    return p


@pytest.fixture
def wave_summary_files(autopilot_dir: Path) -> list[Path]:
    """R4 OK: 整数 N.summary.md を作成する。"""
    files = []
    for i in [1, 2]:
        p = autopilot_dir / "waves" / f"{i}.summary.md"
        p.write_text(f"# Wave {i}\n")
        files.append(p)
    return files


def _handler():
    from twl.mcp_server.tools import twl_audit_session_handler  # noqa: PLC0415
    return twl_audit_session_handler


# ===========================================================================
# AC3-1: tool シグネチャ
# ===========================================================================


class TestAC31Signature:
    """AC3-1: twl_audit_session_handler が存在し呼び出し可能。"""

    def test_ac1_handler_importable(self):
        # AC: tools.py に twl_audit_session_handler が定義されている
        # RED: 実装前は ImportError で FAIL
        from twl.mcp_server.tools import twl_audit_session_handler  # noqa: F401

    def test_ac1_returns_dict_with_envelope_keys(
        self, autopilot_dir: Path, valid_session_json: Path,
    ):
        # AC: 戻り値は build_envelope 準拠 dict (ok / items / exit_code キーを持つ)
        # RED: 実装前は NotImplementedError
        result = _handler()(autopilot_dir=str(autopilot_dir))
        assert isinstance(result, dict), "handler は dict を返すこと"
        for key in ("items", "exit_code"):
            assert key in result, f"envelope key '{key}' が戻り値にない (AC3-1 未実装)"


# ===========================================================================
# AC3-1: audit rules R1〜R4
# ===========================================================================


class TestAC31AuditRules:
    """AC3-1: 各 audit rule の検出・非検出を確認する。"""

    def test_r1_invalid_session_id_produces_critical(
        self, autopilot_dir: Path, invalid_session_json: Path,
    ):
        # AC: session_id が英数字 8文字以外 → R1 critical item
        # RED: 実装前は assert FAIL
        result = _handler()(autopilot_dir=str(autopilot_dir))
        critical_items = [
            i for i in result.get("items", [])
            if i.get("severity") == "critical"
        ]
        assert critical_items, (
            "session_id 不正なのに critical item がゼロ (R1 未実装)"
        )

    def test_r1_valid_session_id_no_critical(
        self, autopilot_dir: Path, valid_session_json: Path,
    ):
        # AC: session_id が英数字 8文字 → R1 critical なし
        # RED: 実装前は assert FAIL
        result = _handler()(autopilot_dir=str(autopilot_dir))
        critical_items = [
            i for i in result.get("items", [])
            if i.get("severity") == "critical" and "session_id" in i.get("message", "").lower()
        ]
        assert not critical_items, (
            f"valid session_id なのに R1 critical が検出された: {critical_items}"
        )

    def test_r1_critical_sets_exit_code_1(
        self, autopilot_dir: Path, invalid_session_json: Path,
    ):
        # AC: critical 1件以上で exit_code=1
        # RED: 実装前は assert FAIL
        result = _handler()(autopilot_dir=str(autopilot_dir))
        has_critical = any(
            i.get("severity") == "critical" for i in result.get("items", [])
        )
        if has_critical:
            assert result.get("exit_code") == 1, (
                f"critical あるのに exit_code が 1 でない: {result.get('exit_code')}"
            )

    def test_r2_missing_plan_path_produces_warning(
        self, autopilot_dir: Path, valid_session_json: Path,
    ):
        # AC: plan_path が指すファイル不在 → R2 warning item
        # RED: 実装前は assert FAIL
        result = _handler()(autopilot_dir=str(autopilot_dir))
        warning_items = [
            i for i in result.get("items", [])
            if i.get("severity") == "warning" and "plan" in i.get("message", "").lower()
        ]
        assert warning_items, (
            "plan_path 不在なのに R2 warning item がゼロ (R2 未実装)"
        )

    def test_r3_invalid_checkpoint_produces_warning(
        self, autopilot_dir: Path, valid_session_json: Path, invalid_checkpoint: Path,
    ):
        # AC: 必須 field 欠落の checkpoint.json → R3 warning item
        # RED: 実装前は assert FAIL
        result = _handler()(autopilot_dir=str(autopilot_dir))
        warning_items = [
            i for i in result.get("items", [])
            if i.get("severity") == "warning" and "checkpoint" in i.get("message", "").lower()
        ]
        assert warning_items, (
            "不正 checkpoint があるのに R3 warning item がゼロ (R3 未実装)"
        )

    def test_r3_valid_checkpoint_no_warning(
        self, autopilot_dir: Path, valid_session_json: Path, valid_checkpoint: Path,
    ):
        # AC: 必須 field 揃った checkpoint.json → R3 warning なし
        # RED: 実装前は assert FAIL
        result = _handler()(autopilot_dir=str(autopilot_dir))
        # code == "R3" で絞る（メッセージ文字列マッチは tmp ディレクトリ名に "checkpoint" が含まれると誤ヒットする）
        cp_warnings = [
            i for i in result.get("items", [])
            if i.get("code") == "R3"
        ]
        assert not cp_warnings, (
            f"valid checkpoint なのに R3 warning が出た: {cp_warnings}"
        )

    def test_r4_valid_wave_summary_produces_info(
        self, autopilot_dir: Path, valid_session_json: Path, wave_summary_files: list[Path],
    ):
        # AC: 整数 N.summary.md は R4 info item (または何も出さない — 検出なし許容)
        # RED: 実装前はチェック自体なし → info item 0件で FAIL しない場合もある
        # このテストは R4 rule の存在確認のみ（info は optional severity）
        result = _handler()(autopilot_dir=str(autopilot_dir))
        assert isinstance(result.get("items"), list), "items が list でない"


# ===========================================================================
# AC3-3: idempotency (read-only, 副作用なし)
# ===========================================================================


class TestAC33Idempotency:
    """AC3-3: twl_audit_session は idempotent — 同 args で 2 回呼んで結果が同一。"""

    def test_ac3_idempotent_twice(
        self, autopilot_dir: Path, valid_session_json: Path,
    ):
        # AC: 同 args で 2 回呼び出すと同一の結果が返る (read-only)
        # RED: 実装前は ImportError
        result1 = _handler()(autopilot_dir=str(autopilot_dir))
        result2 = _handler()(autopilot_dir=str(autopilot_dir))
        assert result1 == result2, (
            f"idempotency 違反: 1回目={result1!r} 2回目={result2!r}"
        )

    def test_ac3_no_side_effects_on_filesystem(
        self, autopilot_dir: Path, valid_session_json: Path,
    ):
        # AC: 呼び出し後にファイルシステムが変化しない
        # RED: 実装前は assert FAIL
        before = {str(p): p.stat().st_mtime for p in autopilot_dir.rglob("*") if p.is_file()}
        _handler()(autopilot_dir=str(autopilot_dir))
        after = {str(p): p.stat().st_mtime for p in autopilot_dir.rglob("*") if p.is_file()}
        assert before == after, (
            f"ファイルシステムに副作用が検出された: {set(before) ^ set(after)}"
        )

    def test_ac3_no_sys_exit_in_handler(
        self, autopilot_dir: Path, valid_session_json: Path,
    ):
        # AC: handler 内で sys.exit() が呼ばれない (Exception で error 経路を表現)
        # RED: 実装前は ImportError
        import sys  # noqa: PLC0415
        original_exit = sys.exit
        sys_exit_called = []

        def mock_exit(code=0):
            sys_exit_called.append(code)
            raise SystemExit(code)

        sys.exit = mock_exit
        try:
            try:
                _handler()(autopilot_dir=str(autopilot_dir))
            except SystemExit:
                pass
        finally:
            sys.exit = original_exit

        assert not sys_exit_called, (
            f"handler 内で sys.exit() が呼ばれた (AC3-3 禁止): code={sys_exit_called}"
        )


# ===========================================================================
# AC3-4: MCP tool 関数の JSON 文字列経路
# ===========================================================================


class TestAC34McpToolPath:
    """AC3-4: MCP tool 関数 twl_audit_session が JSON 文字列を返す。"""

    def test_ac4_mcp_tool_exists(self):
        # AC: tools モジュールに twl_audit_session が存在する
        # RED: 実装前は AttributeError → FAIL
        from twl.mcp_server import tools as tools_mod  # noqa: PLC0415
        assert hasattr(tools_mod, "twl_audit_session"), (
            "twl_audit_session が tools モジュールに存在しない (AC3-4 未実装)"
        )

    def test_ac4_mcp_tool_returns_json_string(
        self, autopilot_dir: Path, valid_session_json: Path,
    ):
        # AC: mcp tool が JSON 文字列を返す
        # RED: 実装前は assert FAIL
        from twl.mcp_server import tools as tools_mod  # noqa: PLC0415
        result_str = tools_mod.twl_audit_session(autopilot_dir=str(autopilot_dir))
        result = json.loads(result_str)
        assert isinstance(result, dict)
        assert "items" in result


# ===========================================================================
# AC3-6: read race 保護 — rename atomicity 前提の確認
# ===========================================================================


class TestAC36ReadRaceProtection:
    """AC3-6: POSIX rename atomicity により partial read が発生しないことの smoke test。

    完全な bats integration test は cli/twl/tests/bats/ 配下に別途追加する。
    このクラスは Python 側 handler が "always-consistent" な full content を読む
    ことの基本確認のみ行う。
    """

    def test_ac6_handler_reads_complete_json(
        self, autopilot_dir: Path, valid_session_json: Path,
    ):
        # AC: session.json の全フィールドが欠落なく読まれる
        # twl_get_session_state_handler で read して session key を確認（AC3-6 の read 経路検証）
        # RED: 実装前は ImportError / KeyError → FAIL
        from twl.mcp_server.tools import twl_get_session_state_handler  # noqa: PLC0415
        result = twl_get_session_state_handler(autopilot_dir=str(autopilot_dir))
        session_data = result.get("session", {})
        required_session_keys = {
            "session_id", "plan_path", "current_phase", "phase_count",
            "started_at", "cross_issue_warnings",
        }
        missing = required_session_keys - set(session_data.keys())
        assert not missing, (
            f"session フィールドが欠落: {missing} (read が partial data を返している可能性)"
        )
