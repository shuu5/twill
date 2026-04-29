"""Tests for twl_get_session_state — Issue #1113 AC3-1, AC3-2, AC3-4, AC3-5, AC3-11, AC3-12.

TDD RED フェーズ。実装前は全テストが FAIL する（意図的 RED）。
対象 handler: twl_get_session_state_handler (tools.py または tools_state.py)

AC 対応:
  AC3-1: tool シグネチャ・戻り値 schema
  AC3-2: 既存 twl_state_read との責務分離 (aggregate keys の存在)
  AC3-4: pytest 2 経路 (handler 直接 + fastmcp 経由)
  AC3-5: ADR-028 整合 (read-only、no flock 必要)
  AC3-11: SessionAggregateView TypedDict 型定義の準拠確認
  AC3-12: archived session 不在時の error envelope
"""

import json
import os
import tempfile
from pathlib import Path

import pytest

TWL_DIR = Path(__file__).resolve().parent.parent
TOOLS_PY = TWL_DIR / "src" / "twl" / "mcp_server" / "tools.py"


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture
def autopilot_dir(tmp_path: Path) -> Path:
    d = tmp_path / ".autopilot"
    d.mkdir()
    (d / "issues").mkdir()
    (d / "checkpoints").mkdir()
    (d / "waves").mkdir()
    (d / "archive").mkdir()
    return d


@pytest.fixture
def session_json(autopilot_dir: Path) -> Path:
    """active session.json を作成する。"""
    data = {
        "session_id": "abc12345",
        "plan_path": str(autopilot_dir / "plan.yaml"),
        "current_phase": 2,
        "phase_count": 4,
        "started_at": "2026-04-29T00:00:00Z",
        "cross_issue_warnings": [
            {"issue": 42, "target_issue": 43, "file": "foo.py", "reason": "test"},
        ],
        "phase_insights": [],
        "patterns": {},
        "self_improve_issues": [],
    }
    p = autopilot_dir / "session.json"
    p.write_text(json.dumps(data, ensure_ascii=False))
    return p


@pytest.fixture
def issue_files(autopilot_dir: Path) -> list[Path]:
    """active_issues および done issue を作成する。"""
    statuses = [
        ("1", "in_progress"),
        ("2", "done"),
        ("3", "pending"),
    ]
    files = []
    for num, status in statuses:
        data = {"issue": int(num), "status": status, "branch": "", "pr": None}
        p = autopilot_dir / "issues" / f"issue-{num}.json"
        p.write_text(json.dumps(data))
        files.append(p)
    return files


@pytest.fixture
def checkpoint_files(autopilot_dir: Path) -> list[Path]:
    """FAIL checkpoint と PASS checkpoint を作成する。"""
    items = [
        ("review", "FAIL", 2),
        ("test", "PASS", 0),
    ]
    files = []
    for step, status, critical_count in items:
        data = {
            "step": step,
            "status": status,
            "findings_summary": f"summary for {step}",
            "critical_count": critical_count,
            "findings": [],
            "timestamp": "2026-04-29T00:00:00Z",
        }
        p = autopilot_dir / "checkpoints" / f"{step}.json"
        p.write_text(json.dumps(data))
        files.append(p)
    return files


@pytest.fixture
def wave_summary_files(autopilot_dir: Path) -> list[Path]:
    """wave summary files を作成する。"""
    files = []
    for i in [6, 7]:
        p = autopilot_dir / "waves" / f"{i}.summary.md"
        p.write_text(f"# Wave {i} Summary\n")
        files.append(p)
    return files


def _handler():
    """twl_get_session_state_handler を遅延 import する。"""
    from twl.mcp_server.tools import twl_get_session_state_handler  # noqa: PLC0415
    return twl_get_session_state_handler


# ===========================================================================
# AC3-1: tool シグネチャと基本戻り値スキーマ
# ===========================================================================


class TestAC31Signature:
    """AC3-1: twl_get_session_state_handler が存在し呼び出し可能。"""

    def test_ac1_handler_importable(self):
        # AC: tools.py に twl_get_session_state_handler が定義されている
        # RED: 実装前は ImportError で FAIL
        from twl.mcp_server.tools import twl_get_session_state_handler  # noqa: F401

    def test_ac1_handler_callable_with_none_session_id(
        self, autopilot_dir: Path, session_json: Path,
        issue_files: list[Path], checkpoint_files: list[Path],
        wave_summary_files: list[Path],
    ):
        # AC: session_id=None で呼び出すと active session.json を読み成功する
        # RED: 実装前は NotImplementedError
        result = _handler()(autopilot_dir=str(autopilot_dir))
        assert isinstance(result, dict), "handler は dict を返すこと"


# ===========================================================================
# AC3-2: 既存 twl_state_read との責務分離 — aggregate keys の存在
# ===========================================================================


class TestAC32AggregateSeparation:
    """AC3-2: 戻り値に aggregate keys が存在し、低レベル passthrough と区別できる。"""

    def test_ac2_aggregate_keys_present(
        self, autopilot_dir: Path, session_json: Path,
        issue_files: list[Path], checkpoint_files: list[Path],
        wave_summary_files: list[Path],
    ):
        # AC: active_issues / pending_checkpoints / cross_issue_warnings / wave_summaries_count の
        #     4 keys が戻り値に存在する
        # RED: 実装前は KeyError
        result = _handler()(autopilot_dir=str(autopilot_dir))
        for key in ("active_issues", "pending_checkpoints", "cross_issue_warnings", "wave_summaries_count"):
            assert key in result, f"aggregate key '{key}' が戻り値にない (AC3-2 未実装)"

    def test_ac2_active_issues_excludes_done(
        self, autopilot_dir: Path, session_json: Path,
        issue_files: list[Path], checkpoint_files: list[Path],
        wave_summary_files: list[Path],
    ):
        # AC: active_issues は status != "done" のもののみ
        # RED: 実装前は assert FAIL
        result = _handler()(autopilot_dir=str(autopilot_dir))
        active = result["active_issues"]
        assert all(
            i.get("status") != "done" for i in active
        ), "active_issues に done ステータスが混入している (AC3-2 未実装)"

    def test_ac2_pending_checkpoints_are_fail_only(
        self, autopilot_dir: Path, session_json: Path,
        issue_files: list[Path], checkpoint_files: list[Path],
        wave_summary_files: list[Path],
    ):
        # AC: pending_checkpoints は status == "FAIL" のもののみ
        # RED: 実装前は assert FAIL
        result = _handler()(autopilot_dir=str(autopilot_dir))
        pending = result["pending_checkpoints"]
        assert all(
            cp.get("status") == "FAIL" for cp in pending
        ), "pending_checkpoints に非 FAIL が混入している (AC3-2 未実装)"

    def test_ac2_wave_summaries_count_correct(
        self, autopilot_dir: Path, session_json: Path,
        issue_files: list[Path], checkpoint_files: list[Path],
        wave_summary_files: list[Path],
    ):
        # AC: wave_summaries_count は waves/*.summary.md のファイル数
        # RED: 実装前は assert FAIL
        result = _handler()(autopilot_dir=str(autopilot_dir))
        assert result["wave_summaries_count"] == len(wave_summary_files), (
            f"wave_summaries_count mismatch: {result['wave_summaries_count']} != {len(wave_summary_files)}"
        )


# ===========================================================================
# AC3-4: pytest 2 経路 (handler 直接 + fastmcp 経由)
# ===========================================================================


class TestAC34TwoInvocationPaths:
    """AC3-4: handler 直接呼出と MCP tool 関数の 2 経路でテスト。"""

    def test_ac4_direct_handler_returns_dict(
        self, autopilot_dir: Path, session_json: Path,
        issue_files: list[Path], checkpoint_files: list[Path],
        wave_summary_files: list[Path],
    ):
        # AC: handler 直接呼出で dict が返る
        # RED: 実装前は ImportError
        result = _handler()(autopilot_dir=str(autopilot_dir))
        assert isinstance(result, dict)

    def test_ac4_mcp_tool_function_returns_json_string(
        self, autopilot_dir: Path, session_json: Path,
        issue_files: list[Path], checkpoint_files: list[Path],
        wave_summary_files: list[Path],
    ):
        # AC: mcp tool 関数 twl_get_session_state が JSON 文字列を返す
        # RED: 実装前は ImportError または AttributeError
        from twl.mcp_server import tools as tools_mod  # noqa: PLC0415
        assert hasattr(tools_mod, "twl_get_session_state"), (
            "twl_get_session_state が tools モジュールに存在しない (AC3-4 未実装)"
        )
        fn = tools_mod.twl_get_session_state
        result_str = fn(autopilot_dir=str(autopilot_dir))
        # JSON 文字列であること
        result = json.loads(result_str)
        assert isinstance(result, dict)


# ===========================================================================
# AC3-11: SessionAggregateView TypedDict 型定義の準拠確認
# ===========================================================================


class TestAC311TypedDictCompliance:
    """AC3-11: 戻り値が SessionAggregateView TypedDict の required keys に準拠する。"""

    REQUIRED_KEYS = {
        "session",
        "active_issues",
        "current_phase",
        "phase_count",
        "cross_issue_warnings",
        "pending_checkpoints",
        "wave_summaries_count",
        "resolved_session_id",
        "autopilot_dir",
        "is_archived",
    }

    def test_ac11_all_required_keys_present(
        self, autopilot_dir: Path, session_json: Path,
        issue_files: list[Path], checkpoint_files: list[Path],
        wave_summary_files: list[Path],
    ):
        # AC: SessionAggregateView の全 required keys が戻り値に存在する
        # RED: 実装前は KeyError
        result = _handler()(autopilot_dir=str(autopilot_dir))
        missing = self.REQUIRED_KEYS - set(result.keys())
        assert not missing, f"SessionAggregateView required keys が欠落: {missing}"

    def test_ac11_session_aggregate_view_importable(self):
        # AC: SessionAggregateView TypedDict が tools.py から import できる
        # RED: 実装前は ImportError
        from twl.mcp_server.tools import SessionAggregateView  # noqa: F401

    def test_ac11_is_archived_false_for_active(
        self, autopilot_dir: Path, session_json: Path,
        issue_files: list[Path], checkpoint_files: list[Path],
        wave_summary_files: list[Path],
    ):
        # AC: active session の場合 is_archived=False
        # RED: 実装前は assert FAIL
        result = _handler()(autopilot_dir=str(autopilot_dir))
        assert result["is_archived"] is False, (
            f"active session で is_archived が True になっている: {result.get('is_archived')}"
        )


# ===========================================================================
# AC3-12: archived session 不在時の error path
# ===========================================================================


class TestAC312ArchiveNotFound:
    """AC3-12: archive/<session_id>/session.json 不在時の error envelope。"""

    def test_ac12_missing_archive_returns_error_envelope(self, autopilot_dir: Path):
        # AC: archive にない session_id を渡すと {"ok": False, "error_type": "archive_not_found", "exit_code": 2}
        # RED: 実装前は KeyError または Exception
        result = _handler()(session_id="nonexistent", autopilot_dir=str(autopilot_dir))
        assert result.get("ok") is False, (
            f"archive 不在で ok=True になっている: {result}"
        )
        assert result.get("error_type") == "archive_not_found", (
            f"error_type が archive_not_found でない: {result.get('error_type')}"
        )
        assert result.get("exit_code") == 2, (
            f"exit_code が 2 でない: {result.get('exit_code')}"
        )
        assert "error" in result and result["error"], (
            "error フィールドにパスが含まれていない"
        )

    def test_ac12_error_envelope_has_concrete_path(self, autopilot_dir: Path):
        # AC: error フィールドに具体的なパスが含まれる
        # RED: 実装前は assert FAIL
        result = _handler()(session_id="nonexistent", autopilot_dir=str(autopilot_dir))
        assert "nonexistent" in result.get("error", ""), (
            f"error に session_id 'nonexistent' が含まれていない: {result.get('error')}"
        )

    def test_ac12_existing_archive_succeeds(
        self, autopilot_dir: Path, session_json: Path,
        issue_files: list[Path], checkpoint_files: list[Path],
        wave_summary_files: list[Path],
    ):
        # AC: 存在する archive session_id を渡すと ok=True で is_archived=True
        # RED: 実装前は assert FAIL
        session_id = "abc12345"
        archive_dir = autopilot_dir / "archive" / session_id
        archive_dir.mkdir(parents=True)
        # archive に session.json をコピー
        import shutil  # noqa: PLC0415
        shutil.copy(session_json, archive_dir / "session.json")
        result = _handler()(session_id=session_id, autopilot_dir=str(autopilot_dir))
        assert result.get("ok") is True, f"archive session 読み込みが ok=False: {result}"
        assert result.get("is_archived") is True, "archive session で is_archived が False"
