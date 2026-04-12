"""resolve_next_workflow — orchestrator が inject_next_workflow で呼び出すモジュール。

CLI usage:
    python3 -m twl.autopilot.resolve_next_workflow --issue <N>

state ファイルの current_step フィールドを読み取り、
TERMINAL_STEP_TO_NEXT_SKILL マッピングから次の workflow skill 名を決定する。
重複 inject 防止のため workflow_injected フィールドも参照する（ADR-018）。

Output:
    - 成功: /twl:workflow-<name> を stdout に出力、exit 0
    - 失敗(terminal step でない / 既に inject 済み): stdout 空、exit 1
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys


def _read_state(issue_num: str, field: str, autopilot_dir: str) -> str:
    """state ファイルからフィールドを読み取る。失敗時は空文字を返す。"""
    env = {**os.environ}
    if autopilot_dir:
        env["AUTOPILOT_DIR"] = autopilot_dir
    try:
        result = subprocess.run(
            [sys.executable, "-m", "twl.autopilot.state", "read",
             "--type", "issue", "--issue", issue_num, "--field", field],
            capture_output=True, text=True, env=env,
        )
        return result.stdout.strip() if result.returncode == 0 else ""
    except Exception:
        return ""


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="orchestrator inject 用 next workflow resolver (current_step ベース, ADR-018)"
    )
    parser.add_argument("--issue", required=True, help="Issue 番号")
    args = parser.parse_args(argv)

    issue_num = args.issue.lstrip("#")
    if not re.match(r"^\d+$", issue_num):
        print(f"ERROR: 不正な issue 番号: {issue_num}", file=sys.stderr)
        return 1

    autopilot_dir = os.environ.get("AUTOPILOT_DIR", "")

    # current_step を読み取り、terminal step かどうかを判定 (ADR-018)
    current_step = _read_state(issue_num, "current_step", autopilot_dir)
    if not current_step or current_step == "null":
        print(
            f"ERROR: issue-{issue_num} の current_step が未設定または null",
            file=sys.stderr,
        )
        return 1

    from twl.autopilot.chain import TERMINAL_STEP_TO_NEXT_SKILL
    next_skill_name = TERMINAL_STEP_TO_NEXT_SKILL.get(current_step, "")
    if not next_skill_name:
        # non-terminal step — inject 不要
        print(
            f"ERROR: current_step={current_step} は terminal step ではない（inject 不要）",
            file=sys.stderr,
        )
        return 1

    # is_quick チェック: quick issue は test-ready をスキップ
    is_quick_str = _read_state(issue_num, "is_quick", autopilot_dir)
    is_quick = is_quick_str.lower() == "true"
    if is_quick and next_skill_name == "workflow-test-ready":
        print(
            f"ERROR: quick issue のため workflow-test-ready をスキップ",
            file=sys.stderr,
        )
        return 1

    # 重複 inject 防止: workflow_injected に既に同じ skill が記録されていれば skip
    workflow_injected = _read_state(issue_num, "workflow_injected", autopilot_dir)
    if workflow_injected and f"/twl:{next_skill_name}" in workflow_injected:
        print(
            f"ERROR: /twl:{next_skill_name} は既に inject 済み (workflow_injected={workflow_injected})",
            file=sys.stderr,
        )
        return 1

    next_skill = f"/twl:{next_skill_name}"
    print(next_skill)
    return 0


if __name__ == "__main__":
    sys.exit(main())
