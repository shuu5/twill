#!/usr/bin/env python3
"""spec-anchor-link-check.py — spec ディレクトリの anchor broken link 検出

機械検証:
  HTML/MD ファイルの <a href> と id 宣言を突き合わせ、broken link を報告する。

使用方法:
  python3 scripts/spec-anchor-link-check.py [--spec-dir DIR] [--output {text,json}]
                                             [--no-skip-svg-ids] [--no-external]
                                             [--no-include-md]

終了コード:
  0 = clean (broken link 0 件)
  1 = broken link あり
  2 = wrapper-level error (spec_dir not found 等)
"""

import argparse
import json
import re
import subprocess
import sys
from html.parser import HTMLParser
from pathlib import Path
from typing import NamedTuple, Optional


class BrokenLink(NamedTuple):
    source_file: str   # spec_dir 相対パス
    line: int
    href: str
    reason: str        # "anchor_not_found" / "file_not_found" / "file_and_anchor_not_found"


class HrefInfo(NamedTuple):
    href: str
    source_file: str   # absolute path
    line: int


class _IdExtractor(HTMLParser):
    """HTML から id 属性を収集する。SVG marker id は --skip-svg-ids で除外可能。"""

    def __init__(self, skip_svg_ids: bool = True) -> None:
        super().__init__()
        self.ids: set[str] = set()
        self._in_svg_defs = 0          # <defs> ネスト深度
        self._skip_svg_ids = skip_svg_ids

    def handle_starttag(self, tag: str, attrs: list[tuple]) -> None:
        attr_dict = dict(attrs)

        if tag == "defs":
            self._in_svg_defs += 1

        if self._skip_svg_ids and tag == "marker":
            return

        if self._skip_svg_ids and self._in_svg_defs > 0:
            return

        id_val = attr_dict.get("id") or attr_dict.get("ID")
        if id_val and id_val.strip():
            self.ids.add(id_val.strip())

    def handle_endtag(self, tag: str) -> None:
        if tag == "defs" and self._in_svg_defs > 0:
            self._in_svg_defs -= 1


def extract_ids(filepath: Path, skip_svg_ids: bool = True) -> set[str]:
    """filepath (HTML) から有効な id 宣言を抽出する。"""
    try:
        text = filepath.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return set()

    parser = _IdExtractor(skip_svg_ids=skip_svg_ids)
    try:
        parser.feed(text)
    except Exception:
        pass
    return parser.ids


class _HrefExtractor(HTMLParser):
    """HTML から <a href=...> と <link href=...> を (href, line) で収集する。"""

    def __init__(self) -> None:
        super().__init__()
        self.hrefs: list[tuple[str, int]] = []

    def handle_starttag(self, tag: str, attrs: list[tuple]) -> None:
        # "a" は HTML <a href> + SVG <a xlink:href> 両方を捕捉
        if tag not in ("a", "link"):
            return
        attr_dict = dict(attrs)
        href = attr_dict.get("href") or attr_dict.get("HREF") or attr_dict.get("xlink:href")
        if href and href.strip():
            line, _ = self.getpos()
            self.hrefs.append((href.strip(), line))


def extract_hrefs(filepath: Path) -> list[HrefInfo]:
    """filepath の全 href を (href, source_file, line) リストで返す。

    Markdown ファイルは [text](href) パターンを正規表現で抽出。
    """
    suffix = filepath.suffix.lower()
    source = str(filepath)

    if suffix in (".html", ".htm"):
        try:
            text = filepath.read_text(encoding="utf-8", errors="replace")
        except OSError:
            return []
        parser = _HrefExtractor()
        try:
            parser.feed(text)
        except Exception:
            pass
        return [HrefInfo(h, source, ln) for h, ln in parser.hrefs]

    elif suffix == ".md":
        try:
            lines = filepath.read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError:
            return []
        results: list[HrefInfo] = []
        md_link_re = re.compile(r'\[(?:[^\]]*)\]\(([^)]+)\)')
        for ln, line in enumerate(lines, 1):
            for m in md_link_re.finditer(line):
                results.append(HrefInfo(m.group(1).strip(), source, ln))
        return results

    return []


def classify_href(href: str) -> dict:
    """href を種別分類する。

    種別:
      internal_anchor   — #fragment のみ
      cross_file_html   — file.html または file.html#anchor
      cross_file_md     — file.md または file.md#anchor
      external_relative — ../ や ./ から始まる相対
      external_url      — https:// / http:// / mailto: 等
      stylesheet        — .css 由来
      bare_file         — 拡張子なし or 未知拡張子
    """
    h = href

    if re.match(r'^(?:https?|ftp|mailto):', h):
        return {"kind": "external_url", "file": None, "fragment": None}

    if h.endswith(".css"):
        return {"kind": "stylesheet", "file": h, "fragment": None}

    if h.startswith("../") or h.startswith("./"):
        fragment = None
        if "#" in h:
            h, fragment = h.rsplit("#", 1)
        return {"kind": "external_relative", "file": h, "fragment": fragment}

    if h.startswith("#"):
        return {"kind": "internal_anchor", "file": None, "fragment": h[1:]}

    if "#" in h:
        file_part, fragment = h.rsplit("#", 1)
    else:
        file_part, fragment = h, None

    ext = Path(file_part).suffix.lower()
    if ext in (".html", ".htm"):
        return {"kind": "cross_file_html", "file": file_part, "fragment": fragment}
    elif ext == ".md":
        return {"kind": "cross_file_md", "file": file_part, "fragment": fragment}
    elif ext == "":
        return {"kind": "bare_file", "file": file_part, "fragment": fragment}
    else:
        return {"kind": "external_relative", "file": file_part, "fragment": fragment}


def _extract_md_ids(filepath: Path) -> set[str]:
    """Markdown ファイルから HTML id 属性 (インライン HTML) を抽出する。"""
    try:
        text = filepath.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return set()
    return set(re.findall(r'id="([^"]+)"', text))


def _check_single_href(
    href_info: HrefInfo,
    src_file: Path,
    spec_dir: Path,
    id_map: dict[str, set[str]],
    check_external: bool,
) -> Optional[BrokenLink]:
    """1 href を検証し broken なら BrokenLink を返す。None = valid。"""
    href = href_info.href
    classified = classify_href(href)
    kind = classified["kind"]

    def rel(p: Path) -> str:
        try:
            return str(p.relative_to(spec_dir))
        except ValueError:
            return str(p)

    src_rel = rel(src_file)

    if kind in ("external_url", "stylesheet"):
        return None

    if kind == "bare_file":
        candidate = spec_dir / classified["file"]
        if not candidate.exists():
            return BrokenLink(
                source_file=src_rel,
                line=href_info.line,
                href=href,
                reason="file_not_found",
            )
        return None

    if kind == "internal_anchor":
        fragment = classified["fragment"]
        file_ids = id_map.get(str(src_file), set())
        if fragment not in file_ids:
            return BrokenLink(
                source_file=src_rel,
                line=href_info.line,
                href=href,
                reason="anchor_not_found",
            )
        return None

    if kind in ("cross_file_html", "cross_file_md"):
        target_path = spec_dir / classified["file"]
        file_exists = target_path.exists()
        fragment = classified["fragment"]

        if not file_exists and fragment is None:
            return BrokenLink(src_rel, href_info.line, href, "file_not_found")

        if not file_exists and fragment is not None:
            return BrokenLink(src_rel, href_info.line, href, "file_and_anchor_not_found")

        if file_exists and fragment is not None:
            target_ids = id_map.get(str(target_path), set())
            if not target_ids:
                target_ids = (
                    extract_ids(target_path) if target_path.suffix in (".html", ".htm")
                    else _extract_md_ids(target_path)
                )
            if fragment not in target_ids:
                return BrokenLink(src_rel, href_info.line, href, "anchor_not_found")
        return None

    if kind == "external_relative":
        if not check_external:
            return None
        target_path = (spec_dir / classified["file"]).resolve()
        if not target_path.exists():
            return BrokenLink(src_rel, href_info.line, href, "file_not_found")
        fragment = classified["fragment"]
        if fragment:
            target_ids = id_map.get(str(target_path), set())
            if not target_ids:
                if target_path.suffix in (".html", ".htm"):
                    target_ids = extract_ids(target_path)
                else:
                    target_ids = _extract_md_ids(target_path)
            if fragment not in target_ids:
                return BrokenLink(src_rel, href_info.line, href, "anchor_not_found")
        return None

    return None


def check_all(
    spec_dir: Path,
    skip_svg_ids: bool = True,
    check_external: bool = True,
    include_md: bool = True,
) -> list[BrokenLink]:
    """spec_dir 配下の全ファイルを走査し broken link を返す。"""
    broken: list[BrokenLink] = []

    html_files = sorted(spec_dir.glob("*.html"))
    md_files = sorted(spec_dir.glob("*.md")) if include_md else []
    all_files = html_files + md_files

    id_map: dict[str, set[str]] = {}
    for f in html_files:
        id_map[str(f)] = extract_ids(f, skip_svg_ids=skip_svg_ids)
    for f in md_files:
        id_map[str(f)] = _extract_md_ids(f)

    for src_file in all_files:
        hrefs = extract_hrefs(src_file)
        for href_info in hrefs:
            result = _check_single_href(
                href_info, src_file, spec_dir, id_map, check_external,
            )
            if result is not None:
                broken.append(result)

    return broken


def _resolve_git_root(cwd: Optional[Path] = None) -> Optional[Path]:
    try:
        r = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            cwd=str(cwd or Path.cwd()),
            capture_output=True, text=True, timeout=5,
        )
        if r.returncode == 0:
            return Path(r.stdout.strip())
    except Exception:
        pass
    return None


def main() -> int:
    parser = argparse.ArgumentParser(
        description="spec ディレクトリの anchor broken link を機械検証する",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--spec-dir", metavar="PATH",
        help="検査対象ディレクトリ (default: <git_root>/architecture/spec/twill-plugin-rebuild)",
    )
    parser.add_argument(
        "--output", choices=["text", "json"], default="text",
        help="出力形式 (default: text)",
    )
    parser.add_argument(
        "--no-skip-svg-ids", action="store_true", default=False,
        help="SVG marker id も anchor として扱う (default: SVG id をスキップ)",
    )
    parser.add_argument(
        "--no-external", action="store_true", default=False,
        help="../ 相対パスの存在チェックをスキップ",
    )
    parser.add_argument(
        "--no-include-md", action="store_true", default=False,
        help=".md ファイルのスキャンを無効化",
    )
    args = parser.parse_args()

    skip_svg_ids = not args.no_skip_svg_ids
    check_external = not args.no_external
    include_md = not args.no_include_md

    if args.spec_dir:
        spec_dir = Path(args.spec_dir).resolve()
    else:
        git_root = _resolve_git_root()
        if git_root is None:
            print("ERROR: git root が検出できません。--spec-dir を指定してください。",
                  file=sys.stderr)
            return 2
        spec_dir = git_root / "architecture" / "spec" / "twill-plugin-rebuild"

    if not spec_dir.is_dir():
        print(f"ERROR: spec-dir が存在しません: {spec_dir}", file=sys.stderr)
        return 2

    broken = check_all(
        spec_dir,
        skip_svg_ids=skip_svg_ids,
        check_external=check_external,
        include_md=include_md,
    )

    if args.output == "json":
        payload = {
            "broken": [
                {
                    "source_file": b.source_file,
                    "line": b.line,
                    "href": b.href,
                    "reason": b.reason,
                }
                for b in broken
            ],
            "broken_count": len(broken),
        }
        print(json.dumps(payload, ensure_ascii=False, indent=2))
    else:
        for b in broken:
            print(f"ERROR: {b.source_file}:{b.line} -> {b.href}  [{b.reason}]")
        print()
        print(f"broken: {len(broken)}")

    return 1 if broken else 0


if __name__ == "__main__":
    sys.exit(main())
