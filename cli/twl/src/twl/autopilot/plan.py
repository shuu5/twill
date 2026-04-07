"""Plan generation for autopilot execution.

Replaces: autopilot-plan.sh, autopilot-plan-board.sh

CLI usage:
    python3 -m twl.autopilot.plan --explicit "19,18 → 20 → 23" --project-dir DIR --repo-mode MODE
    python3 -m twl.autopilot.plan --issues "84 78 83" --project-dir DIR --repo-mode MODE
    python3 -m twl.autopilot.plan --board --project-dir DIR --repo-mode MODE
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import uuid
from pathlib import Path
from typing import Any


class PlanError(Exception):
    """Raised for plan generation errors (exit code 1)."""


class PlanArgError(Exception):
    """Raised for argument errors (exit code 2)."""


# ---------------------------------------------------------------------------
# Issue reference resolution
# ---------------------------------------------------------------------------

def _resolve_issue_ref(
    ref: str,
    repos: dict[str, dict[str, str]],
    cross_repo: bool,
) -> tuple[str, str]:
    """Resolve issue reference → (repo_id, number).

    Formats: bare int, #N, repo_id#N, owner/repo#N
    """
    # repo_id#N
    m = re.match(r"^([a-zA-Z0-9_-]+)#(\d+)$", ref)
    if m:
        repo_id, number = m.group(1), m.group(2)
        if cross_repo and repo_id not in repos:
            raise PlanError(f"不明な repo_id: {repo_id}")
        return repo_id, number

    # owner/repo#N
    m = re.match(r"^([a-zA-Z0-9_-]+)/([a-zA-Z0-9_.-]+)#(\d+)$", ref)
    if m:
        owner, name, number = m.group(1), m.group(2), m.group(3)
        for rid, rinfo in repos.items():
            if rinfo.get("owner") == owner and rinfo.get("name") == name:
                return rid, number
        raise PlanError(f"repos セクションに {owner}/{name} が見つかりません")

    # bare int or #N
    m = re.match(r"^#?(\d+)$", ref)
    if m:
        return "_default", m.group(1)

    raise PlanError(f"不正な Issue 参照: {ref}")


def _issue_uid(repo_id: str, number: str) -> str:
    if repo_id == "_default":
        return number
    return f"{repo_id}#{number}"


def _gh_repo_flag(repo_id: str, repos: dict[str, dict[str, str]], cross_repo: bool) -> list[str]:
    if repo_id == "_default" or not cross_repo:
        return []
    r = repos.get(repo_id, {})
    if r.get("owner") and r.get("name"):
        return ["-R", f"{r['owner']}/{r['name']}"]
    return []


def _validate_issue(
    number: str,
    repo_id: str,
    repos: dict[str, dict[str, str]],
    cross_repo: bool,
) -> None:
    flags = _gh_repo_flag(repo_id, repos, cross_repo)
    result = subprocess.run(
        ["gh", "issue", "view", number] + flags + ["--json", "number", "-q", ".number"],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        uid = _issue_uid(repo_id, number)
        raise PlanError(f"Issue {uid} が存在しません")


def _issue_touches_deps_yaml(
    number: str,
    repo_id: str,
    repos: dict[str, dict[str, str]],
    cross_repo: bool,
    body: str = "",
    comments: str = "",
) -> bool:
    flags = _gh_repo_flag(repo_id, repos, cross_repo)
    if not body:
        r = subprocess.run(
            ["gh", "issue", "view", number] + flags + ["--json", "body", "-q", ".body"],
            capture_output=True, text=True,
        )
        body = r.stdout if r.returncode == 0 else ""

    if not comments:
        if repo_id != "_default" and cross_repo and repo_id in repos:
            r = repos[repo_id]
            api_path = f"repos/{r['owner']}/{r['name']}/issues/{number}/comments"
        else:
            api_path = f"repos/{{owner}}/{{repo}}/issues/{number}/comments"
        result = subprocess.run(
            ["gh", "api", api_path, "--jq", "[.[].body] | join(\"\\n\")"],
            capture_output=True, text=True,
        )
        comments = result.stdout if result.returncode == 0 else ""

    combined = f"{body}\n{comments}".lower()
    return "deps.yaml" in combined


# ---------------------------------------------------------------------------
# Touched-files extraction (for arbitrary file conflict prediction)
# ---------------------------------------------------------------------------

# Extension whitelist for plain-text path detection (false positive 抑制).
_TOUCHED_FILE_EXT_WHITELIST = {
    ".py", ".sh", ".md", ".ts", ".tsx", ".js", ".yaml", ".yml",
    ".json", ".toml", ".bats",
}

# Path-like token: 1+ slash-separated segment, ends with whitelisted extension.
_PATH_TOKEN_RE = re.compile(
    r"(?<![\w./-])"  # left boundary: not part of an identifier/path
    r"([a-zA-Z0-9_][\w./-]*?\.[a-zA-Z0-9]{1,5})"
    r"(?![\w./-])"
)


def _is_whitelisted_path(token: str) -> bool:
    if "/" not in token:
        return False
    dot = token.rfind(".")
    if dot < 0:
        return False
    ext = token[dot:].lower()
    return ext in _TOUCHED_FILE_EXT_WHITELIST


def _extract_touched_files_section(body: str) -> set[str]:
    """Extract paths from a `## Touched files` section (highest priority)."""
    result: set[str] = set()
    lines = body.splitlines()
    in_section = False
    for line in lines:
        stripped = line.strip()
        # Section header detection (case-insensitive, allow trailing content).
        if re.match(r"^#+\s*Touched files\b", stripped, re.IGNORECASE):
            in_section = True
            continue
        if in_section:
            # New header → end of section.
            if re.match(r"^#+\s+\S", stripped):
                break
            # Bullet item: extract first path-like token (allow backticks /
            # surrounding prose).
            m = re.match(r"^[-*+]\s+(.+?)\s*$", stripped)
            if m:
                content = m.group(1)
                pm = _PATH_TOKEN_RE.search(content)
                if pm:
                    token = pm.group(1)
                    if _is_whitelisted_path(token):
                        result.add(token)
    return result


def _extract_touched_files(body: str, comments: str = "") -> set[str]:
    """Extract touched file paths from issue body / comments.

    Priority:
        1. `## Touched files` section bullet items (most reliable).
        2. Any path-like token in body+comments matching the extension whitelist.
    """
    section = _extract_touched_files_section(body)
    if section:
        return section

    text = f"{body}\n{comments}"
    result: set[str] = set()
    for m in _PATH_TOKEN_RE.finditer(text):
        token = m.group(1)
        if _is_whitelisted_path(token):
            result.add(token)
    return result


def _separate_touched_files_phases(
    phases: list[list[str]],
    touched_map: dict[str, set[str]],
) -> list[list[str]]:
    """Split phases to avoid file collisions.

    For each phase, if multiple issues touch the same file path, keep the first
    occurrence in the current phase and push later conflicting issues into a
    newly inserted subsequent phase. Repeats until no in-phase conflict remains.
    Generalises `_separate_deps_yaml_phases` to arbitrary files.
    """
    new_phases: list[list[str]] = []

    for phase_issues in phases:
        # Greedy bin-packing: keep splitting the current phase into sub-phases
        # such that no sub-phase contains two issues touching the same file.
        sub_phases: list[list[str]] = []
        for uid in phase_issues:
            files = touched_map.get(uid, set())
            placed = False
            for sub in sub_phases:
                conflict = any(
                    touched_map.get(other, set()) & files
                    for other in sub
                )
                if not conflict:
                    sub.append(uid)
                    placed = True
                    break
            if not placed:
                sub_phases.append([uid])

        if len(sub_phases) > 1:
            collisions = [
                uid for sub in sub_phases[1:] for uid in sub
            ]
            print(
                f"⚠ Phase 分離: ファイル衝突予測により Issue {collisions} を後続 Phase に押し出し",
                file=sys.stderr,
            )

        new_phases.extend(sub_phases)

    return new_phases


# ---------------------------------------------------------------------------
# Topological sort (Kahn's algorithm)
# ---------------------------------------------------------------------------

def _topological_phases(
    issue_uids: list[str],
    deps: dict[str, list[str]],
) -> list[list[str]]:
    """Return list of phases where each phase contains issues with all deps resolved."""
    remaining = list(issue_uids)
    sorted_uids: list[str] = []
    phases: list[list[str]] = []

    while remaining:
        ready = []
        next_remaining = []
        for uid in remaining:
            dep_list = deps.get(uid, [])
            if all(d in sorted_uids for d in dep_list):
                ready.append(uid)
            else:
                next_remaining.append(uid)

        if not ready:
            raise PlanError(f"循環依存が検出されました。残り: {remaining}")

        phases.append(ready)
        sorted_uids.extend(ready)
        remaining = next_remaining

    return phases


def _separate_deps_yaml_phases(
    phases: list[list[str]],
    deps_yaml_issues: set[str],
) -> list[list[str]]:
    """Split phases to avoid deps.yaml conflicts."""
    new_phases: list[list[str]] = []

    for phase_issues in phases:
        dyi = [i for i in phase_issues if i in deps_yaml_issues]
        non_dyi = [i for i in phase_issues if i not in deps_yaml_issues]

        if len(dyi) <= 1:
            new_phases.append(phase_issues)
        else:
            print(f"⚠ Phase 分離: deps.yaml 変更 Issue {dyi} を sequential 化", file=sys.stderr)
            if non_dyi:
                new_phases.append(non_dyi)
            for di in dyi:
                new_phases.append([di])

    return new_phases


# ---------------------------------------------------------------------------
# YAML output helpers
# ---------------------------------------------------------------------------

def _emit_repos_yaml(repos: dict[str, dict[str, str]], cross_repo: bool) -> str:
    if not cross_repo:
        return ""
    lines = ["repos:"]
    for repo_id, rinfo in repos.items():
        lines.append(f"  {repo_id}:")
        lines.append(f'    owner: "{rinfo.get("owner", "")}"')
        lines.append(f'    name: "{rinfo.get("name", "")}"')
        lines.append(f'    path: "{rinfo.get("path", "")}"')
    return "\n".join(lines)


def _emit_issue_yaml(uid: str, cross_repo: bool) -> str:
    if cross_repo:
        if "#" in uid:
            repo_id, number = uid.split("#", 1)
            return f"    - {{ number: {number}, repo: {repo_id} }}"
        else:
            return f"    - {{ number: {uid}, repo: _default }}"
    return f"    - {uid}"


# ---------------------------------------------------------------------------
# Plan modes
# ---------------------------------------------------------------------------

class PlanGenerator:
    def __init__(
        self,
        project_dir: str,
        repo_mode: str,
        repos: dict[str, dict[str, str]] | None = None,
    ) -> None:
        self.project_dir = project_dir
        self.repo_mode = repo_mode
        self.repos: dict[str, dict[str, str]] = repos or {}
        self.cross_repo = bool(repos)

        if not project_dir:
            raise PlanArgError("--project-dir は必須です")
        if not repo_mode:
            raise PlanArgError("--repo-mode は必須です")

        self.autopilot_dir = Path(project_dir) / ".autopilot"
        self.autopilot_dir.mkdir(parents=True, exist_ok=True)
        self.plan_file = self.autopilot_dir / "plan.yaml"
        self.session_id = uuid.uuid4().hex[:8]

    def parse_explicit(self, input_str: str) -> None:
        """Parse "19,18 → 20 → 23" format."""
        # Split by → (UTF-8 arrow)
        phases_raw = re.split(r"\s*→\s*", input_str)
        all_phases: list[list[str]] = []
        all_uids: list[str] = []
        deps: dict[str, list[str]] = {}

        for phase_str in phases_raw:
            if not phase_str.strip():
                continue
            phase_uids: list[str] = []
            tokens = [t.strip() for t in re.split(r"[,\s]+", phase_str) if t.strip()]
            for token in tokens:
                repo_id, number = _resolve_issue_ref(token, self.repos, self.cross_repo)
                _validate_issue(number, repo_id, self.repos, self.cross_repo)
                uid = _issue_uid(repo_id, number)
                phase_uids.append(uid)
                all_uids.append(uid)
            all_phases.append(phase_uids)

        # Build dependencies: each phase depends on previous phase
        for i, phase_issues in enumerate(all_phases):
            if i == 0:
                continue
            prev_issues = all_phases[i - 1]
            for uid in phase_issues:
                deps[uid] = list(prev_issues)

        self._write_plan(all_phases, deps, all_uids)
        print(f"plan.yaml 生成完了: {self.plan_file}")
        print(f"  Session: {self.session_id}")
        print(f"  Phases: {len(all_phases)}")
        print(f"  Issues: {len(all_uids)}")

    def parse_issues(self, input_str: str) -> None:
        """Parse space-separated issue list and auto-detect dependencies."""
        tokens = input_str.split()
        issue_uids: list[str] = []
        issue_repos: dict[str, str] = {}
        issue_nums: dict[str, str] = {}

        for token in tokens:
            repo_id, number = _resolve_issue_ref(token, self.repos, self.cross_repo)
            _validate_issue(number, repo_id, self.repos, self.cross_repo)
            uid = _issue_uid(repo_id, number)
            issue_uids.append(uid)
            issue_repos[uid] = repo_id
            issue_nums[uid] = number

        if not issue_uids:
            raise PlanError("Issue 番号が指定されていません")

        deps_yaml_issues: set[str] = set()
        touched_map: dict[str, set[str]] = {}
        deps: dict[str, list[str]] = {}
        issues_set = set(issue_uids)

        for uid in issue_uids:
            repo_id = issue_repos[uid]
            number = issue_nums[uid]
            flags = _gh_repo_flag(repo_id, self.repos, self.cross_repo)

            body_r = subprocess.run(
                ["gh", "issue", "view", number] + flags + ["--json", "body", "-q", ".body"],
                capture_output=True, text=True,
            )
            body = body_r.stdout if body_r.returncode == 0 else ""

            if repo_id != "_default" and self.cross_repo:
                r = self.repos.get(repo_id, {})
                api_path = f"repos/{r.get('owner','')}/{r.get('name','')}/issues/{number}/comments"
            else:
                api_path = f"repos/{{owner}}/{{repo}}/issues/{number}/comments"

            comments_r = subprocess.run(
                ["gh", "api", api_path, "--jq", "[.[].body] | join(\"\\n\")"],
                capture_output=True, text=True,
            )
            comments = comments_r.stdout if comments_r.returncode == 0 else ""

            if _issue_touches_deps_yaml(number, repo_id, self.repos, self.cross_repo, body, comments):
                deps_yaml_issues.add(uid)

            touched_map[uid] = _extract_touched_files(body, comments)

            search_text = f"{body}\n{comments}"
            dep_uids: list[str] = []

            # Detect dependency keywords: #N
            dep_nums = re.findall(
                r'(?:depends\s+on|after|requires|blocked\s+by)\s*#(\d+)',
                search_text, re.IGNORECASE,
            )
            dep_nums += re.findall(r'#(\d+)\s*が前提', search_text)
            dep_nums += re.findall(r'#(\d+)\s*完了後', search_text)

            for dep_num in dep_nums:
                dep_uid = _issue_uid(repo_id, dep_num)
                if dep_uid in issues_set and dep_uid != uid and dep_uid not in dep_uids:
                    dep_uids.append(dep_uid)

            # Cross-repo dependencies
            if self.cross_repo:
                cross_refs = re.findall(r'[a-zA-Z0-9_-]+/[a-zA-Z0-9_.-]+#\d+', search_text)
                for cross_ref in cross_refs:
                    try:
                        cr_id, cr_num = _resolve_issue_ref(cross_ref, self.repos, self.cross_repo)
                        cr_uid = _issue_uid(cr_id, cr_num)
                        if cr_uid in issues_set and cr_uid != uid and cr_uid not in dep_uids:
                            dep_uids.append(cr_uid)
                    except PlanError:
                        pass

            if dep_uids:
                deps[uid] = dep_uids

        phases = _topological_phases(issue_uids, deps)

        if len(deps_yaml_issues) >= 2:
            phases = _separate_deps_yaml_phases(phases, deps_yaml_issues)

        phases = _separate_touched_files_phases(phases, touched_map)

        self._write_plan(phases, deps, issue_uids)
        print(f"plan.yaml 生成完了: {self.plan_file}")
        print(f"  Session: {self.session_id}")
        print(f"  Phases: {len(phases)}")
        print(f"  Issues: {len(issue_uids)}")

    def fetch_board_issues(self) -> None:
        """Fetch non-Done issues from Project Board and call parse_issues."""
        # Detect project board
        detect_script = self._detect_scripts_root() / "lib" / "resolve-project.sh"
        result = subprocess.run(
            ["bash", "-c",
             f'source "{detect_script}" && resolve_project'],
            capture_output=True, text=True,
        )
        if result.returncode != 0:
            raise PlanError(f"Project Board 検出失敗: {result.stderr}")

        parts = result.stdout.strip().split()
        if len(parts) < 5:
            raise PlanError("Project Board 情報が不足しています")
        project_num, _project_id, repo_owner, repo_name, current_repo = parts[0], parts[1], parts[2], parts[3], parts[4]

        # Fetch board items
        items_r = subprocess.run(
            ["gh", "project", "item-list", project_num, "--owner", repo_owner,
             "--format", "json", "--limit", "200"],
            capture_output=True, text=True,
        )
        if items_r.returncode != 0:
            raise PlanError(f"Project #{project_num} の item-list 取得に失敗しました")

        items_data = json.loads(items_r.stdout)
        filtered = [
            item for item in items_data.get("items", [])
            if item.get("content", {}).get("type") == "Issue"
            and item.get("status") != "Done"
        ]

        if not filtered:
            raise PlanError("Board に未完了の Issue がありません")

        # Build cross-repo config
        issue_list: list[str] = []
        cross_repos: dict[str, dict[str, str]] = {}
        parent_dir = str(Path(self.project_dir).parent)

        for item in filtered:
            item_repo = item.get("content", {}).get("repository", "")
            item_number = str(item.get("content", {}).get("number", ""))

            if not re.match(r"^\d+$", item_number):
                print(f"⚠ スキップ: 不正な Issue 番号: {item_number}", file=sys.stderr)
                continue

            if item_repo == current_repo:
                issue_list.append(item_number)
            else:
                cross_owner = item_repo.split("/")[0] if "/" in item_repo else ""
                cross_name = item_repo.split("/")[1] if "/" in item_repo else item_repo

                if not re.match(r"^[a-zA-Z0-9_-]+$", cross_owner):
                    print(f"⚠ スキップ: 不正な owner: {cross_owner}", file=sys.stderr)
                    continue
                if not re.match(r"^[a-zA-Z0-9_][a-zA-Z0-9_.-]*$", cross_name):
                    print(f"⚠ スキップ: 不正な name: {cross_name}", file=sys.stderr)
                    continue

                rid = cross_name
                cr_path = ""
                candidate = Path(parent_dir) / cross_name
                if candidate.is_dir():
                    cr_path = str(candidate)
                else:
                    print(f"⚠ クロスリポジトリ {cross_owner}/{cross_name} のローカルパスが見つかりません", file=sys.stderr)

                cross_repos[rid] = {"owner": cross_owner, "name": cross_name, "path": cr_path}
                issue_list.append(f"{rid}#{item_number}")

        if cross_repos:
            self.repos = cross_repos
            self.cross_repo = True

        self.parse_issues(" ".join(issue_list))

    def _write_plan(
        self,
        phases: list[list[str]],
        deps: dict[str, list[str]],
        all_uids: list[str],
    ) -> None:
        lines = [
            f'session_id: "{self.session_id}"',
            f'repo_mode: "{self.repo_mode}"',
            f'project_dir: "{self.project_dir}"',
        ]

        repos_yaml = _emit_repos_yaml(self.repos, self.cross_repo)
        if repos_yaml:
            lines.append(repos_yaml)

        lines.append("phases:")
        for i, phase_issues in enumerate(phases, 1):
            lines.append(f"  - phase: {i}")
            for uid in phase_issues:
                lines.append(_emit_issue_yaml(uid, self.cross_repo))

        lines.append("dependencies:")
        for uid in all_uids:
            dep_list = deps.get(uid, [])
            if dep_list:
                lines.append(f"  {uid}:")
                for dep in dep_list:
                    lines.append(f"  - {dep}")

        self.plan_file.write_text("\n".join(lines) + "\n", encoding="utf-8")

    def _detect_scripts_root(self) -> Path:
        try:
            root = subprocess.check_output(
                ["git", "rev-parse", "--show-toplevel"],
                stderr=subprocess.DEVNULL, text=True,
            ).strip()
            return Path(root) / "plugins" / "twl" / "scripts"
        except Exception:
            return Path.cwd() / "plugins" / "twl" / "scripts"


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def _parse_args(argv: list[str]) -> dict[str, Any]:
    args: dict[str, Any] = {
        "mode": "",
        "input": "",
        "project_dir": "",
        "repo_mode": "",
        "repos_json": "",
    }
    value_opts = {"--explicit", "--issues", "--project-dir", "--repo-mode", "--repos"}
    i = 0
    while i < len(argv):
        a = argv[i]
        if a in ("-h", "--help"):
            print("Usage: python3 -m twl.autopilot.plan --explicit|--issues|--board ...")
            sys.exit(0)
        elif a in ("--explicit", "--issues"):
            if args["mode"]:
                raise PlanArgError("--explicit/--issues/--board は同時に指定できません")
            if i + 1 >= len(argv):
                raise PlanArgError(f"{a} には値が必要です")
            args["mode"] = "explicit" if a == "--explicit" else "issues"
            args["input"] = argv[i + 1]; i += 2
        elif a == "--board":
            if args["mode"]:
                raise PlanArgError("--explicit/--issues/--board は同時に指定できません")
            args["mode"] = "board"; i += 1
        elif a in ("--project-dir", "--repo-mode", "--repos"):
            if i + 1 >= len(argv):
                raise PlanArgError(f"{a} には値が必要です")
            if a == "--project-dir":
                args["project_dir"] = argv[i + 1]
            elif a == "--repo-mode":
                args["repo_mode"] = argv[i + 1]
            elif a == "--repos":
                args["repos_json"] = argv[i + 1]
            i += 2
        else:
            raise PlanArgError(f"不明な引数: {a}")
    return args


def main(argv: list[str] | None = None) -> int:
    args_list = argv if argv is not None else sys.argv[1:]

    try:
        parsed = _parse_args(args_list)
    except PlanArgError as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1

    mode = parsed["mode"]
    if not mode:
        print("Error: --explicit, --issues, または --board を指定してください", file=sys.stderr)
        return 1

    project_dir = parsed["project_dir"]
    repo_mode = parsed["repo_mode"]

    if mode == "board":
        if not project_dir or not repo_mode:
            print("Usage: python3 -m twl.autopilot.plan --board --project-dir DIR --repo-mode MODE", file=sys.stderr)
            return 1
    elif not mode or not parsed["input"] or not project_dir or not repo_mode:
        print("Usage: python3 -m twl.autopilot.plan --explicit|--issues INPUT --project-dir DIR --repo-mode MODE", file=sys.stderr)
        return 1

    repos: dict[str, dict[str, str]] = {}
    if parsed["repos_json"]:
        try:
            raw = json.loads(parsed["repos_json"])
            for repo_id, rinfo in raw.items():
                if not re.match(r"^[a-zA-Z0-9_-]+$", repo_id):
                    raise PlanError(f"不正な repo_id: {repo_id}")
                if not re.match(r"^[a-zA-Z0-9_-]+$", rinfo.get("owner", "")):
                    raise PlanError(f"不正な owner: {rinfo.get('owner')} (repo_id={repo_id})")
                if not re.match(r"^[a-zA-Z0-9_.-]+$", rinfo.get("name", "")):
                    raise PlanError(f"不正な name: {rinfo.get('name')} (repo_id={repo_id})")
                repos[repo_id] = rinfo
        except json.JSONDecodeError as e:
            print(f"Error: --repos JSON 解析エラー: {e}", file=sys.stderr)
            return 1

    try:
        generator = PlanGenerator(project_dir=project_dir, repo_mode=repo_mode, repos=repos)

        if mode == "explicit":
            generator.parse_explicit(parsed["input"])
        elif mode == "issues":
            generator.parse_issues(parsed["input"])
        elif mode == "board":
            generator.fetch_board_issues()

        return 0

    except PlanArgError as e:
        print(f"Error: {e}", file=sys.stderr)
        return 2
    except PlanError as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
