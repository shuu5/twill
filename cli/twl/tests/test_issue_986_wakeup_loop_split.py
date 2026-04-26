"""
RED tests for Issue #986: autopilot-pilot-wakeup-loop atomic split (token_bloat 解消)

AC 1件 = 1 test。実装前は全件 FAIL する。
"""

import subprocess
import os
import re
from pathlib import Path

# プロジェクトルート
REPO_ROOT = Path(__file__).parent.parent.parent.parent
PLUGINS_TWL = REPO_ROOT / "plugins" / "twl"
COMMANDS_DIR = PLUGINS_TWL / "commands"
DEPS_YAML = PLUGINS_TWL / "deps.yaml"

BOOTSTRAP = COMMANDS_DIR / "autopilot-pilot-wakeup-bootstrap.md"
POLL = COMMANDS_DIR / "autopilot-pilot-wakeup-poll.md"
HEARTBEAT = COMMANDS_DIR / "autopilot-pilot-wakeup-heartbeat.md"
OLD_LOOP = COMMANDS_DIR / "autopilot-pilot-wakeup-loop.md"

TOKEN_WARN_THRESHOLD = 1500


def _approx_tokens(path: Path) -> int:
    """単純なトークン近似: 単語数 × 1.3 (GPT tokenizer 近似)"""
    text = path.read_text(encoding="utf-8")
    words = len(text.split())
    return int(words * 1.3)


def test_ac1_token_bloat_each_sub_atomic_below_warn():
    # AC: split 後の各 sub-atomic が token_bloat warn 閾値以下 (≤ 1500 tok / 各)
    # RED: 新ファイルが存在しないため fail
    missing = [p for p in [BOOTSTRAP, POLL, HEARTBEAT] if not p.exists()]
    assert not missing, f"未実装ファイル: {missing}"

    for path in [BOOTSTRAP, POLL, HEARTBEAT]:
        tok = _approx_tokens(path)
        assert tok <= TOKEN_WARN_THRESHOLD, (
            f"{path.name}: {tok} tok > {TOKEN_WARN_THRESHOLD} (token_bloat warn)"
        )


def test_ac2_files_placed_at_correct_paths():
    # AC: split 後の各ファイルは commands/autopilot-pilot-wakeup-{bootstrap,poll,heartbeat}.md に配置
    # RED: ファイルが存在しないため fail
    for path in [BOOTSTRAP, POLL, HEARTBEAT]:
        assert path.exists(), f"path 適正 NG: {path} が存在しない"


def test_ac3_deps_yaml_has_new_sub_atomics():
    # AC: 新 sub-atomic を deps.yaml に登録し、呼出元の requires 参照を書き換え
    # RED: deps.yaml に新エントリが存在しないため fail
    assert DEPS_YAML.exists(), "deps.yaml が存在しない"
    content = DEPS_YAML.read_text(encoding="utf-8")

    for name in ["autopilot-pilot-wakeup-bootstrap", "autopilot-pilot-wakeup-poll", "autopilot-pilot-wakeup-heartbeat"]:
        assert name in content, f"deps.yaml に {name} が未登録"

    # 呼出元 (co-autopilot) の requires が旧 loop から新 sub-atomics に切り替わっている
    assert "autopilot-pilot-wakeup-loop" not in content, (
        "deps.yaml に旧 autopilot-pilot-wakeup-loop への参照が残っている"
    )


def test_ac4_smoke_test_old_loop_replaced():
    # AC: 動作変更なし smoke test — 旧 atomic が削除され新 3-atomic に置換されていること
    # RED: 旧ファイルがまだ存在するため fail
    assert not OLD_LOOP.exists(), (
        f"旧 autopilot-pilot-wakeup-loop.md がまだ存在する: {OLD_LOOP}"
    )
    for path in [BOOTSTRAP, POLL, HEARTBEAT]:
        assert path.exists(), f"新 sub-atomic 未配置: {path}"


def test_ac5_hotfix_732_invariant_preserved_in_bootstrap():
    # AC: bootstrap atomic の nohup/disown + 絶対パスコードブロックを完全保持
    # RED: bootstrap.md が存在しないため fail
    assert BOOTSTRAP.exists(), f"bootstrap.md が存在しない: {BOOTSTRAP}"

    content = BOOTSTRAP.read_text(encoding="utf-8")

    assert "nohup" in content, "bootstrap.md に nohup が含まれない (HOTFIX #732 保持 NG)"
    assert "disown" in content, "bootstrap.md に disown が含まれない (HOTFIX #732 保持 NG)"
    assert "${CLAUDE_PLUGIN_ROOT}/scripts/autopilot-orchestrator.sh" in content, (
        "bootstrap.md に絶対パス指定が含まれない (HOTFIX #732 保持 NG)"
    )
    assert "#732" in content or "HOTFIX" in content, (
        "bootstrap.md に HOTFIX #732 コメントが含まれない"
    )


def test_ac6_twl_check_deps_integrity_ok():
    # AC: `twl --check --deps-integrity` errors=0
    result = subprocess.run(
        ["python3", "-m", "twl", "--check", "--deps-integrity"],
        cwd=PLUGINS_TWL,
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, (
        f"twl --check --deps-integrity 失敗:\n{result.stdout}\n{result.stderr}"
    )
    assert "Missing: 0" in result.stdout or "error" not in result.stdout.lower(), (
        f"deps-integrity エラーあり:\n{result.stdout}"
    )


def test_ac7_twl_check_no_dangling_reference():
    # AC: `twl --check` コンポーネント存在検証 PASS（旧 atomic への dangling reference なし）
    result = subprocess.run(
        ["python3", "-m", "twl", "--check"],
        cwd=PLUGINS_TWL,
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, (
        f"twl --check 失敗:\n{result.stdout}\n{result.stderr}"
    )
    # dangling reference の文字列チェック
    assert "dangling" not in result.stdout.lower(), (
        f"dangling reference 検出:\n{result.stdout}"
    )


def test_ac8_specialist_review_stubs():
    # AC: specialist review 全 PASS (worker-architecture 必須 + issue-critic + issue-feasibility)
    # RED: 実装前のため review は未実施、このテストはプレースホルダーとして FAIL させる
    raise NotImplementedError(
        "AC #8: specialist review は実装完了後に /twl:workflow-pr-verify で実施する。"
        "実装前はこの stub が RED を維持する。"
    )
