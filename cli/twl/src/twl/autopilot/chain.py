"""ChainRunner - chain step state machine.

Replaces: chain-runner.sh, chain-steps.sh

CLI usage:
    python3 -m twl.autopilot.chain <step-name> [args...]

Steps: init, worktree-create, board-status-update, board-archive, ac-extract,
       arch-ref, change-id-resolve, next-step, ts-preflight, pr-test,
       ac-verify, all-pass-check, pr-cycle-report, check, quick-guard,
       autopilot-detect, quick-detect
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

# ---------------------------------------------------------------------------
# Step definitions (SSOT — mirrors chain-steps.sh)
# ---------------------------------------------------------------------------

CHAIN_STEPS: list[str] = [
    "init",
    "board-status-update",
    "crg-auto-build",
    "arch-ref",
    "change-propose",
    "ac-extract",
    "change-id-resolve",
    "test-scaffold",
    "check",
    "change-apply",
    "post-change-apply",
    "prompt-compliance",
    "ts-preflight",
    "pr-test",
    "ac-verify",
    "all-pass-check",
    "pr-cycle-report",
]

QUICK_SKIP_STEPS: frozenset[str] = frozenset([
    "crg-auto-build",
    "arch-ref",
    "change-propose",
    "ac-extract",
    "change-id-resolve",
    "test-scaffold",
    "check",
    "change-apply",
    "prompt-compliance",
])

# Workflow boundary metadata (SSOT — mirrors chain-steps.sh)
STEP_TO_WORKFLOW: dict[str, str] = {
    "init": "setup",
    "board-status-update": "setup",
    "crg-auto-build": "setup",
    "arch-ref": "setup",
    "change-propose": "setup",
    "ac-extract": "setup",
    "change-id-resolve": "test-ready",
    "test-scaffold": "test-ready",
    "check": "test-ready",
    "change-apply": "test-ready",
    "post-change-apply": "test-ready",
    "prompt-compliance": "pr-verify",
    "ts-preflight": "pr-verify",
    "pr-test": "pr-verify",
    "ac-verify": "pr-verify",
    "all-pass-check": "pr-merge",
    "pr-cycle-report": "pr-merge",
}

WORKFLOW_NEXT_SKILL: dict[str, str] = {
    "setup": "workflow-test-ready",
    "test-ready": "workflow-pr-verify",
    "pr-verify": "workflow-pr-fix",
    "pr-fix": "workflow-pr-merge",
    "pr-merge": "",
}


class ChainError(Exception):
    """Raised for chain step errors."""


class ChainRunner:
    """Execute and manage chain steps for the autopilot workflow."""

    def __init__(
        self,
        scripts_root: Path | None = None,
        autopilot_dir: Path | None = None,
    ) -> None:
        self.scripts_root = scripts_root or self._detect_scripts_root()
        self.autopilot_dir = autopilot_dir or self._detect_autopilot_dir()

    # ------------------------------------------------------------------
    # Public step methods
    # ------------------------------------------------------------------

    def next_step(self, issue_num: str, current_step: str) -> str:
        """Return next step name given current step, respecting is_quick skips.

        Returns 'done' if all steps are complete.
        """
        if not issue_num or not re.match(r"^\d+$", issue_num):
            raise ChainError(f"issue_num は正の整数で指定してください: {issue_num!r}")

        is_quick = self._read_state_field(issue_num, "is_quick") == "true"

        found = False
        for step in CHAIN_STEPS:
            if found:
                if is_quick and step in QUICK_SKIP_STEPS:
                    continue
                return step
            if step == current_step:
                found = True

        if not found:
            # current_step not in list → return first step
            return CHAIN_STEPS[0]

        return "done"

    def validate_transition(
        self, issue_num: str, from_step: str, to_step: str
    ) -> None:
        """Raise ChainError if transition from_step → to_step is invalid."""
        if from_step not in CHAIN_STEPS:
            raise ChainError(f"不正な遷移元ステップ: {from_step}")
        if to_step not in CHAIN_STEPS and to_step != "done":
            raise ChainError(f"不正な遷移先ステップ: {to_step}")

        from_idx = CHAIN_STEPS.index(from_step) if from_step in CHAIN_STEPS else -1
        to_idx = CHAIN_STEPS.index(to_step) if to_step in CHAIN_STEPS else len(CHAIN_STEPS)

        if to_idx <= from_idx:
            raise ChainError(
                f"不正な遷移: {from_step} → {to_step} "
                f"(後退遷移は禁止: idx {from_idx} → {to_idx})"
            )

    def record_step(self, issue_num: str, step_id: str) -> None:
        """Record current_step in issue state JSON."""
        if not step_id or not re.match(r"^[a-z0-9-]+$", step_id):
            return
        if not issue_num:
            return
        self._write_state_field(issue_num, f"current_step={step_id}")

    # ------------------------------------------------------------------
    # Step: autopilot-detect
    # ------------------------------------------------------------------

    def step_autopilot_detect(self) -> None:
        """Print eval-able IS_AUTOPILOT=true/false to stdout."""
        issue_num = self._resolve_issue_num()
        if not issue_num:
            print("IS_AUTOPILOT=false")
            return
        status = self._read_state_field(issue_num, "status")
        value = "true" if status == "running" else "false"
        print(f"IS_AUTOPILOT={value}")

    # ------------------------------------------------------------------
    # Step: quick-detect
    # ------------------------------------------------------------------

    def step_quick_detect(self) -> None:
        """Print eval-able IS_QUICK=true/false to stdout."""
        issue_num = self._resolve_issue_num()
        if not issue_num:
            print("IS_QUICK=false")
            return
        is_quick = self._read_state_field(issue_num, "is_quick")
        if not is_quick:
            is_quick = self._detect_quick_label(issue_num)
        value = "true" if is_quick == "true" else "false"
        print(f"IS_QUICK={value}")

    # ------------------------------------------------------------------
    # Step: quick-guard
    # ------------------------------------------------------------------

    def step_quick_guard(self) -> int:
        """Return 0 if non-quick, 1 if quick Issue."""
        issue_num = self._resolve_issue_num()
        if not issue_num:
            return 0

        is_quick = self._read_state_field(issue_num, "is_quick")
        if not is_quick:
            is_quick = self._detect_quick_label(issue_num)

        return 1 if is_quick == "true" else 0

    # ------------------------------------------------------------------
    # Step: init
    # ------------------------------------------------------------------

    def step_init(self, issue_num: str = "") -> dict[str, Any]:
        """Determine development state and return recommended_action JSON."""
        self.record_step(issue_num, "init")

        branch = self._git_current_branch()
        is_quick = self._detect_quick_label(issue_num) if issue_num else "false"

        # Persist is_quick to state
        if issue_num and re.match(r"^\d+$", issue_num):
            self._write_state_field(issue_num, f"is_quick={is_quick}")

        if branch in ("main", "master"):
            result = {
                "recommended_action": "worktree",
                "branch": branch,
                "is_quick": is_quick == "true",
            }
            self._ok("init", f"recommended_action=worktree (branch={branch}, is_quick={is_quick})")
            return result

        root = self._project_root()
        deltaspec_dir = root / "deltaspec"

        if not deltaspec_dir.is_dir():
            result = {
                "recommended_action": "direct",
                "branch": branch,
                "deltaspec": False,
                "is_quick": is_quick == "true",
            }
            self._ok("init", f"recommended_action=direct (no deltaspec, is_quick={is_quick})")
            return result

        changes_dir = deltaspec_dir / "changes"
        if not changes_dir.is_dir() or not any(changes_dir.iterdir()):
            result = {
                "recommended_action": "propose",
                "branch": branch,
                "deltaspec": True,
                "change_exists": False,
                "is_quick": is_quick == "true",
            }
            self._ok("init", f"recommended_action=propose (no changes, is_quick={is_quick})")
            return result

        latest_dirs = sorted(
            [d for d in changes_dir.iterdir() if d.is_dir()],
            key=lambda d: d.stat().st_mtime,
            reverse=True,
        )
        if not latest_dirs:
            result = {
                "recommended_action": "propose",
                "branch": branch,
                "deltaspec": True,
                "change_exists": True,
                "is_quick": is_quick == "true",
            }
            self._ok("init", f"recommended_action=propose (no proposal, is_quick={is_quick})")
            return result

        latest = latest_dirs[0]
        proposal = latest / "proposal.md"

        if proposal.is_file():
            yaml_file = latest / ".deltaspec.yaml"
            if yaml_file.is_file() and "status: approved" in yaml_file.read_text():
                result = {
                    "recommended_action": "apply",
                    "branch": branch,
                    "deltaspec": True,
                    "change_id": latest.name,
                    "proposal_status": "approved",
                    "is_quick": is_quick == "true",
                }
                self._ok("init", f"recommended_action=apply (change={latest.name}, approved, is_quick={is_quick})")
            else:
                result = {
                    "recommended_action": "propose",
                    "branch": branch,
                    "deltaspec": True,
                    "change_id": latest.name,
                    "proposal_status": "pending",
                    "is_quick": is_quick == "true",
                }
                self._ok("init", f"recommended_action=propose (change={latest.name}, pending, is_quick={is_quick})")
        else:
            result = {
                "recommended_action": "propose",
                "branch": branch,
                "deltaspec": True,
                "change_exists": True,
                "is_quick": is_quick == "true",
            }
            self._ok("init", f"recommended_action=propose (no proposal, is_quick={is_quick})")

        return result

    # ------------------------------------------------------------------
    # Step: board-status-update
    # ------------------------------------------------------------------

    def step_board_status_update(
        self, issue_num: str, target_status: str = "In Progress"
    ) -> None:
        """Update Project Board status for an issue."""
        self.record_step(issue_num, "board-status-update")

        if not issue_num or not re.match(r"^\d+$", issue_num):
            return

        # Delegate to bash for gh CLI interactions (avoid duplicating complex gh logic)
        result = subprocess.run(
            ["bash", str(self.scripts_root / "chain-runner.sh"), "board-status-update", issue_num, target_status],
            env={**os.environ, "AUTOPILOT_DIR": str(self.autopilot_dir)},
            capture_output=False,
        )
        if result.returncode != 0:
            self._skip("board-status-update", "更新失敗")

    # ------------------------------------------------------------------
    # Step: ac-extract
    # ------------------------------------------------------------------

    def step_ac_extract(self, snapshot_dir: str = "") -> None:
        """Extract AC checklist from GitHub Issue."""
        self.record_step("", "ac-extract")

        issue_num = self._resolve_issue_num()
        if not issue_num:
            self._skip("ac-extract", "Issue 番号なし — スキップ")
            return

        if not snapshot_dir:
            root = self._project_root()
            snapshot_dir_path = root / ".dev-session"
        else:
            snapshot_dir_path = Path(snapshot_dir)

        snapshot_dir_path.mkdir(parents=True, exist_ok=True)
        output_file = snapshot_dir_path / "01.5-ac-checklist.md"

        if output_file.is_file() and output_file.stat().st_size > 0:
            self._ok("ac-extract", "既存 AC チェックリストを使用")
            return

        result = subprocess.run(
            ["bash", str(self.scripts_root / "parse-issue-ac.sh"), issue_num],
            capture_output=True,
            text=True,
        )
        if result.returncode == 0 and result.stdout.strip():
            output_file.write_text(
                f"## 受け入れ基準（Issue #{issue_num}）\n\n{result.stdout}\n",
                encoding="utf-8",
            )
            self._ok("ac-extract", f"AC 抽出完了 (Issue #{issue_num})")
        else:
            output_file.write_text("AC セクションなし — スキップ\n", encoding="utf-8")
            self._skip("ac-extract", "AC セクションなし — スキップ")

    # ------------------------------------------------------------------
    # Step: check
    # ------------------------------------------------------------------

    def step_check(self) -> bool:
        """Run preparation checks. Returns True if all pass."""
        self.record_step("", "check")
        root = self._project_root()
        has_fail = False

        # DeltaSpec
        deltaspec_dir = root / "deltaspec"
        if deltaspec_dir.is_dir():
            proposals = list((deltaspec_dir / "changes").glob("*/proposal.md")) if (deltaspec_dir / "changes").is_dir() else []
            if proposals:
                print("DeltaSpec: PASS")
            else:
                print("DeltaSpec: FAIL (proposal.md なし)")
                has_fail = True
        else:
            print("DeltaSpec: N/A")

        # Tests
        tests_dir = root / "tests"
        test_found = False
        if tests_dir.is_dir():
            for pattern in ("**/*.sh", "**/*.bats", "**/*.test.*", "**/*.R", "**/*.py"):
                if any(tests_dir.glob(pattern)):
                    test_found = True
                    break
        if test_found:
            print("Tests: PASS")
        else:
            print("Tests: FAIL (テストファイルなし)")
            has_fail = True

        # CI/CD
        workflows_dir = root / ".github" / "workflows"
        if any(workflows_dir.glob("*.yml")) if workflows_dir.is_dir() else False:
            print("CI/CD: PASS")
        else:
            print("CI/CD: WARN (ワークフローなし)")

        # Changes
        result = subprocess.run(
            ["git", "status", "--porcelain"],
            capture_output=True, text=True, cwd=root,
        )
        changes = len([l for l in result.stdout.splitlines() if l.strip()])
        print(f"Changes: {changes} files")

        if has_fail:
            self._skip("check", "FAIL 項目あり")
            return False
        else:
            self._ok("check", "準備完了")
            return True

    # ------------------------------------------------------------------
    # Step: change-id-resolve
    # ------------------------------------------------------------------

    def step_change_id_resolve(self) -> str:
        """Resolve the latest DeltaSpec change ID."""
        self.record_step("", "change-id-resolve")
        root = self._project_root()
        changes_dir = root / "deltaspec" / "changes"

        if not changes_dir.is_dir():
            self._err("change-id-resolve", "deltaspec/changes/ が存在しない")
            raise ChainError("deltaspec/changes/ が存在しない")

        dirs = sorted(
            [d for d in changes_dir.iterdir() if d.is_dir()],
            key=lambda d: d.stat().st_mtime,
            reverse=True,
        )
        if not dirs:
            self._err("change-id-resolve", "changes/ が空")
            raise ChainError("changes/ が空")

        latest = dirs[0].name
        print(latest)
        self._ok("change-id-resolve", latest)
        return latest

    # ------------------------------------------------------------------
    # Step: prompt-compliance
    # ------------------------------------------------------------------

    def step_prompt_compliance(self) -> bool:
        """Check refined_by hash integrity for changed .md files."""
        self.record_step("", "prompt-compliance")
        root = self._project_root()

        # 変更された .md ファイルを検出
        result = subprocess.run(
            ["git", "diff", "--name-only", "--diff-filter=AM", "origin/main", "--", "*.md"],
            capture_output=True, text=True, cwd=root,
        )
        changed_md = result.stdout.strip()

        if not changed_md:
            self._ok("prompt-compliance", "PASS (.md 変更なし — スキップ)")
            return True

        # ref-prompt-guide.md 自体が変更された場合
        if "refs/ref-prompt-guide.md" in changed_md:
            self._ok("prompt-compliance", "WARN (ref-prompt-guide.md 変更検出 — 全コンポーネントの refined_by が stale。Tier 2 audit を推奨)")
            return True

        # twl --audit --section 7 --format json を実行
        audit_result = subprocess.run(
            ["twl", "--audit", "--section", "7", "--format", "json"],
            capture_output=True, text=True, cwd=root,
        )
        try:
            data = json.loads(audit_result.stdout)
            items = data.get("items", [])
        except (json.JSONDecodeError, AttributeError):
            self._ok("prompt-compliance", "WARN (audit 出力のパース失敗 — スキップ)")
            return True

        error_count = sum(1 for i in items if i.get("severity") == "critical")
        stale_count = sum(1 for i in items if i.get("severity") == "warning")

        if error_count > 0:
            self._skip("prompt-compliance", f"FAIL (refined_by フォーマット不正: {error_count} 件)")
            return False
        elif stale_count > 0:
            self._ok("prompt-compliance", f"WARN (stale: {stale_count} 件 — twl refine で更新推奨)")
            return True
        else:
            self._ok("prompt-compliance", "PASS")
            return True

    # ------------------------------------------------------------------
    # Step: ts-preflight
    # ------------------------------------------------------------------

    def step_ts_preflight(self) -> bool:
        """Run TypeScript preflight checks."""
        self.record_step("", "ts-preflight")
        root = self._project_root()

        if not (root / "tsconfig.json").is_file():
            self._ok("ts-preflight", "PASS (TypeScript プロジェクトではない — スキップ)")
            return True

        failed = False
        results = []

        r = subprocess.run(["npx", "tsc", "--noEmit"], capture_output=True, cwd=root)
        if r.returncode != 0:
            failed = True
            results.append("tsc FAIL")

        for eslint_config in (".eslintrc", ".eslintrc.js", ".eslintrc.json", "eslint.config.js"):
            if (root / eslint_config).is_file():
                r = subprocess.run(["npx", "eslint", "."], capture_output=True, cwd=root)
                if r.returncode != 0:
                    failed = True
                    results.append("eslint FAIL")
                break

        if (root / "package.json").is_file():
            pkg = json.loads((root / "package.json").read_text())
            if "build" in pkg.get("scripts", {}):
                r = subprocess.run(["npm", "run", "build"], capture_output=True, cwd=root)
                if r.returncode != 0:
                    failed = True
                    results.append("build FAIL")

        if failed:
            self._skip("ts-preflight", f"FAIL ({'; '.join(results)})")
            return False
        self._ok("ts-preflight", "PASS")
        return True

    # ------------------------------------------------------------------
    # Step: pr-test
    # ------------------------------------------------------------------

    def step_pr_test(self) -> bool:
        """Run tests."""
        self.record_step("", "pr-test")
        root = self._project_root()
        exit_code = 0

        if (root / "tests" / "run-all.sh").is_file():
            r = subprocess.run(["bash", "tests/run-all.sh"], cwd=root)
            exit_code = r.returncode
        elif (root / "package.json").is_file():
            pkg = json.loads((root / "package.json").read_text())
            if "test" in pkg.get("scripts", {}):
                runner = "pnpm" if self._has_command("pnpm") else "npm"
                r = subprocess.run([runner, "test"], cwd=root)
                exit_code = r.returncode
            else:
                self._skip("pr-test", "WARN (テストファイルなし)")
                return True
        elif (root / "pytest.ini").is_file() or (root / "pyproject.toml").is_file():
            r = subprocess.run(["pytest"], cwd=root)
            exit_code = r.returncode
        else:
            test_scripts = list((root / "tests" / "scenarios").glob("*.test.sh")) if (root / "tests" / "scenarios").is_dir() else []
            if test_scripts:
                for ts in test_scripts:
                    r = subprocess.run(["bash", str(ts)], cwd=root)
                    if r.returncode != 0:
                        exit_code = r.returncode
            else:
                self._skip("pr-test", "WARN (テストファイルなし)")
                return True

        if exit_code == 0:
            self._ok("pr-test", "PASS")
            return True
        else:
            self._skip("pr-test", f"FAIL (exit code: {exit_code})")
            return False

    # ------------------------------------------------------------------
    # Step: all-pass-check
    # ------------------------------------------------------------------

    def step_all_pass_check(self, overall_result: str = "PASS") -> bool:
        """Evaluate overall result and update state."""
        self.record_step("", "all-pass-check")
        issue_num = self._resolve_issue_num()

        if not issue_num:
            if overall_result == "PASS":
                self._ok("all-pass-check", "PASS (non-autopilot)")
            else:
                self._skip("all-pass-check", "FAIL (non-autopilot)")
            return overall_result == "PASS"

        autopilot_status = self._read_state_field(issue_num, "status")
        is_autopilot = autopilot_status == "running"

        if overall_result == "PASS":
            self._write_state_field(issue_num, "status=merge-ready")
            if is_autopilot:
                self._ok("all-pass-check", "PASS — autopilot 配下: merge-ready 宣言。Pilot による merge-gate を待機")
            else:
                self._ok("all-pass-check", "PASS — merge-ready")
            return True
        else:
            self._write_state_field(issue_num, "status=failed")
            self._skip("all-pass-check", "FAIL — status=failed")
            return False

    # ------------------------------------------------------------------
    # Step: pr-cycle-report
    # ------------------------------------------------------------------

    def step_pr_cycle_report(self, pr_num: str = "", report: str = "") -> None:
        """Post PR cycle report as a comment."""
        self.record_step("", "pr-cycle-report")

        if not pr_num:
            result = subprocess.run(
                ["gh", "pr", "view", "--json", "number", "-q", ".number"],
                capture_output=True, text=True,
            )
            pr_num = result.stdout.strip() if result.returncode == 0 else ""

        if not pr_num:
            self._skip("pr-cycle-report", "PR 番号なし — スキップ")
            return

        if not re.match(r"^\d+$", pr_num):
            self._err("pr-cycle-report", f"不正な PR 番号: {pr_num}")
            raise ChainError(f"不正な PR 番号: {pr_num}")

        if not report:
            self._skip("pr-cycle-report", "レポート内容なし")
            return

        result = subprocess.run(
            ["gh", "pr", "comment", pr_num, "--body", report],
            capture_output=True,
        )
        if result.returncode == 0:
            self._ok("pr-cycle-report", f"PR #{pr_num} にレポート投稿")
        else:
            self._skip("pr-cycle-report", "PR コメント投稿失敗")

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _detect_scripts_root(self) -> Path:
        # Look relative to this file's location
        this_file = Path(__file__)
        # cli/twl/src/twl/autopilot/chain.py → go up to plugin root
        candidate = this_file.parents[5] / "scripts"
        if candidate.is_dir():
            return candidate
        # Try git root based approach
        try:
            root = subprocess.check_output(
                ["git", "rev-parse", "--show-toplevel"],
                stderr=subprocess.DEVNULL, text=True,
            ).strip()
            return Path(root) / "plugins" / "twl" / "scripts"
        except Exception:
            return Path.cwd() / "plugins" / "twl" / "scripts"

    def _detect_autopilot_dir(self) -> Path:
        env = os.environ.get("AUTOPILOT_DIR", "")
        if env:
            return Path(env)
        try:
            root = subprocess.check_output(
                ["git", "rev-parse", "--show-toplevel"],
                stderr=subprocess.DEVNULL, text=True,
            ).strip()
            return Path(root) / ".autopilot"
        except Exception:
            return Path.cwd() / ".autopilot"

    def _project_root(self) -> Path:
        try:
            return Path(subprocess.check_output(
                ["git", "rev-parse", "--show-toplevel"],
                stderr=subprocess.DEVNULL, text=True,
            ).strip())
        except Exception:
            return Path.cwd()

    def _git_current_branch(self) -> str:
        try:
            return subprocess.check_output(
                ["git", "branch", "--show-current"],
                stderr=subprocess.DEVNULL, text=True,
            ).strip() or "detached"
        except Exception:
            return "detached"

    def _resolve_issue_num(self) -> str:
        """Resolve issue number from env var or branch name."""
        # Priority 0: WORKER_ISSUE_NUM env var
        env_num = os.environ.get("WORKER_ISSUE_NUM", "").strip()
        if env_num and re.match(r"^\d+$", env_num):
            return env_num

        # Priority 1: current branch feat/N-...
        branch = self._git_current_branch()
        m = re.search(r"(?:feat|fix|chore)/(\d+)-", branch)
        if m:
            return m.group(1)

        # Priority 2: just a number in branch
        m = re.search(r"/(\d+)-", branch)
        if m:
            return m.group(1)

        return ""

    def _read_state_field(self, issue_num: str, field: str) -> str:
        """Read a field from issue state via Python module."""
        try:
            result = subprocess.run(
                [sys.executable, "-m", "twl.autopilot.state", "read",
                 "--type", "issue", "--issue", issue_num, "--field", field],
                capture_output=True, text=True,
                env={**os.environ, "AUTOPILOT_DIR": str(self.autopilot_dir)},
            )
            return result.stdout.strip() if result.returncode == 0 else ""
        except Exception:
            return ""

    def _write_state_field(self, issue_num: str, kv: str) -> None:
        """Write a field to issue state via Python module."""
        try:
            subprocess.run(
                [sys.executable, "-m", "twl.autopilot.state", "write",
                 "--type", "issue", "--issue", issue_num, "--role", "worker",
                 "--set", kv],
                capture_output=True,
                env={**os.environ, "AUTOPILOT_DIR": str(self.autopilot_dir)},
            )
        except Exception:
            pass

    def _detect_quick_label(self, issue_num: str) -> str:
        """Return 'true' if issue has quick label, else 'false'."""
        if not issue_num or not re.match(r"^\d+$", issue_num):
            return "false"
        try:
            result = subprocess.run(
                ["gh", "issue", "view", issue_num, "--json", "labels",
                 "--jq", ".labels[].name"],
                capture_output=True, text=True, timeout=10,
            )
            if result.returncode == 0 and "quick" in result.stdout.splitlines():
                return "true"
        except Exception:
            pass
        return "false"

    def _has_command(self, cmd: str) -> bool:
        try:
            subprocess.check_output(["which", cmd], stderr=subprocess.DEVNULL)
            return True
        except Exception:
            return False

    def _ok(self, step: str, msg: str) -> None:
        print(f"✓ {step}: {msg}")

    def _skip(self, step: str, msg: str) -> None:
        print(f"⚠️ {step}: {msg}")

    def _err(self, step: str, msg: str) -> None:
        print(f"✗ {step}: {msg}", file=sys.stderr)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main(argv: list[str] | None = None) -> int:
    args = argv if argv is not None else sys.argv[1:]

    if not args:
        print("Usage: python3 -m twl.autopilot.chain <step-name> [args...]", file=sys.stderr)
        print("Steps: init, next-step, quick-guard, check, change-id-resolve,", file=sys.stderr)
        print("       all-pass-check, prompt-compliance, ts-preflight, pr-test, pr-cycle-report,", file=sys.stderr)
        print("       board-status-update, ac-extract,", file=sys.stderr)
        print("       autopilot-detect, quick-detect", file=sys.stderr)
        return 1

    step = args[0]
    rest = args[1:]

    runner = ChainRunner()

    try:
        if step == "next-step":
            if len(rest) < 2:
                print("ERROR: next-step には issue_num と current_step が必要です", file=sys.stderr)
                return 1
            result = runner.next_step(rest[0], rest[1])
            print(result)
            return 0

        elif step == "autopilot-detect":
            runner.step_autopilot_detect()
            return 0

        elif step == "quick-detect":
            runner.step_quick_detect()
            return 0

        elif step == "quick-guard":
            code = runner.step_quick_guard()
            return code  # 0=非quick, 1=quick

        elif step == "init":
            issue_num = rest[0] if rest else ""
            result = runner.step_init(issue_num)
            print(json.dumps(result, ensure_ascii=False))
            return 0

        elif step == "check":
            ok = runner.step_check()
            return 0 if ok else 1

        elif step == "change-id-resolve":
            runner.step_change_id_resolve()
            return 0

        elif step == "all-pass-check":
            overall = rest[0] if rest else "PASS"
            ok = runner.step_all_pass_check(overall)
            return 0 if ok else 1

        elif step == "prompt-compliance":
            ok = runner.step_prompt_compliance()
            return 0 if ok else 1

        elif step == "ts-preflight":
            ok = runner.step_ts_preflight()
            return 0 if ok else 1

        elif step == "pr-test":
            ok = runner.step_pr_test()
            return 0 if ok else 1

        elif step == "pr-cycle-report":
            pr_num = rest[0] if rest else ""
            report = sys.stdin.read() if not sys.stdin.isatty() else ""
            runner.step_pr_cycle_report(pr_num, report)
            return 0

        elif step == "board-status-update":
            issue_num = rest[0] if rest else ""
            target = rest[1] if len(rest) > 1 else "In Progress"
            runner.step_board_status_update(issue_num, target)
            return 0

        elif step == "ac-extract":
            snapshot_dir = rest[0] if rest else ""
            runner.step_ac_extract(snapshot_dir)
            return 0

        elif step in ("change-propose", "change-apply", "post-change-apply", "test-scaffold", "ac-verify"):
            # LLM-executed steps: just record step
            issue_num = runner._resolve_issue_num()
            if issue_num:
                runner.record_step(issue_num, step)
            print(f"✓ {step}: LLM スキル実行（chain は ステップ記録のみ）")
            return 0

        else:
            print(f"ERROR: 未知のステップ: {step}", file=sys.stderr)
            return 1

    except ChainError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 1
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
