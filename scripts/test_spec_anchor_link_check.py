"""Unit tests for spec-anchor-link-check.py

Phase 1B で追加。R-3 機械検証 (orphan detection) と classify_href の動作を保証する。
特に architecture-graph.html の SVG xlink:href 経由 inbound link の正しい抽出を verified する。

実行:
  python3 -m pytest scripts/test_spec_anchor_link_check.py -v
  または
  python3 scripts/test_spec_anchor_link_check.py
"""

import importlib.util
import sys
import tempfile
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
SCRIPT_PATH = SCRIPT_DIR / "spec-anchor-link-check.py"

# hyphen 含む module 名なので importlib.util で直接 load
_spec = importlib.util.spec_from_file_location("spec_anchor_link_check", SCRIPT_PATH)
module = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(module)


# ============================================================
# extract_hrefs tests
# ============================================================

def test_extract_hrefs_html_a():
    """HTML <a href> が拾われる"""
    with tempfile.TemporaryDirectory() as tmp:
        f = Path(tmp) / "x.html"
        f.write_text('<a href="target.html">link</a>')
        hrefs = module.extract_hrefs(f)
        assert len(hrefs) == 1
        assert hrefs[0].href == "target.html"


def test_extract_hrefs_svg_xlink():
    """SVG <a xlink:href> が拾われる (architecture-graph.html pattern、R-3 機械検証の根幹)"""
    with tempfile.TemporaryDirectory() as tmp:
        f = Path(tmp) / "graph.html"
        f.write_text("""<svg>
          <a xlink:href="overview.html"><title>overview</title>
            <g><circle r="22"/><text>OV</text></g>
          </a>
          <a xlink:href="boundary-matrix.html">
            <g><circle r="22"/><text>BM</text></g>
          </a>
        </svg>""")
        hrefs = module.extract_hrefs(f)
        assert len(hrefs) == 2
        assert {h.href for h in hrefs} == {"overview.html", "boundary-matrix.html"}


def test_extract_hrefs_md():
    """Markdown [text](href) が拾われる"""
    with tempfile.TemporaryDirectory() as tmp:
        f = Path(tmp) / "doc.md"
        f.write_text("see [target](target.html) for detail")
        hrefs = module.extract_hrefs(f)
        assert len(hrefs) == 1
        assert hrefs[0].href == "target.html"


# ============================================================
# classify_href tests
# ============================================================

def test_classify_href_cross_file_html():
    """foo.html は cross_file_html"""
    result = module.classify_href("foo.html")
    assert result["kind"] == "cross_file_html"
    assert result["file"] == "foo.html"
    assert result["fragment"] is None


def test_classify_href_dot_slash_html():
    """./foo.html は cross_file_html 分類 (Phase 1B fix で振り直し)"""
    result = module.classify_href("./foo.html")
    assert result["kind"] == "cross_file_html"
    assert result["file"] == "./foo.html"


def test_classify_href_dot_slash_html_with_fragment():
    """./foo.html#anchor も cross_file_html"""
    result = module.classify_href("./foo.html#s2")
    assert result["kind"] == "cross_file_html"
    assert result["fragment"] == "s2"


def test_classify_href_dot_slash_md():
    """./foo.md は cross_file_md"""
    result = module.classify_href("./foo.md")
    assert result["kind"] == "cross_file_md"


def test_classify_href_external_url():
    """https:// は external_url"""
    result = module.classify_href("https://example.com")
    assert result["kind"] == "external_url"


def test_classify_href_internal_anchor():
    """#anchor は internal_anchor"""
    result = module.classify_href("#section")
    assert result["kind"] == "internal_anchor"
    assert result["fragment"] == "section"


def test_classify_href_double_dot_slash():
    """../foo.html は external_relative (上位 dir、find_orphans 側で扱う)"""
    result = module.classify_href("../research/foo.html")
    assert result["kind"] == "external_relative"


def test_classify_href_stylesheet():
    """*.css は stylesheet"""
    result = module.classify_href("common.css")
    assert result["kind"] == "stylesheet"


# ============================================================
# find_orphans tests
# ============================================================

def test_find_orphans_basic():
    """orphan 検出: README から link されない file は orphan、README は entry point として除外"""
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        (tmp_path / "README.html").write_text('<a href="referenced.html">ref</a>')
        (tmp_path / "referenced.html").write_text("<p>ok</p>")
        (tmp_path / "orphan.html").write_text("<p>orphan</p>")
        orphans = module.find_orphans(tmp_path, entry_points={"README.html"})
        assert orphans == ["orphan.html"]
        # README は entry point として除外
        assert "README.html" not in orphans


def test_find_orphans_via_xlink_href():
    """SVG xlink:href も inbound link としてカウントされる (architecture-graph.html pattern)"""
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        (tmp_path / "README.html").write_text('<a href="graph.html">graph</a>')
        (tmp_path / "graph.html").write_text(
            '<svg><a xlink:href="target.html">link</a></svg>'
        )
        (tmp_path / "target.html").write_text("<p>target</p>")
        orphans = module.find_orphans(tmp_path, entry_points={"README.html"})
        # graph.html: README から link あり、orphan ではない
        # target.html: graph.html から xlink:href で link あり、orphan ではない
        assert orphans == []


def test_find_orphans_dot_slash_inbound():
    """./foo.html (same-dir relative) も inbound link としてカウントされる (Phase 1B W-2 fix)"""
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        (tmp_path / "README.html").write_text('<a href="./hub.html">hub</a>')
        (tmp_path / "hub.html").write_text('<a href="./target.html">target</a>')
        (tmp_path / "target.html").write_text("<p>target</p>")
        orphans = module.find_orphans(tmp_path, entry_points={"README.html"})
        # ./ prefix も inbound カウントされる
        assert orphans == []


def test_find_orphans_multiple_sorted():
    """複数 orphan 検出 + sorted 出力"""
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        (tmp_path / "README.html").write_text("<p>index</p>")
        (tmp_path / "b.html").write_text("<p>b</p>")
        (tmp_path / "a.html").write_text("<p>a</p>")
        (tmp_path / "c.html").write_text("<p>c</p>")
        orphans = module.find_orphans(tmp_path, entry_points={"README.html"})
        assert orphans == ["a.html", "b.html", "c.html"]  # sorted


def test_find_orphans_md_include():
    """include_md=True で .md file も検査対象"""
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        (tmp_path / "README.html").write_text('<a href="doc.md">doc</a>')
        (tmp_path / "doc.md").write_text("# doc")
        (tmp_path / "orphan.md").write_text("# orphan")
        orphans = module.find_orphans(
            tmp_path, entry_points={"README.html"}, include_md=True
        )
        assert "doc.md" not in orphans
        assert "orphan.md" in orphans


def test_find_orphans_multiple_entry_points():
    """複数 entry point も entry として除外される"""
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        (tmp_path / "README.html").write_text("<p>r</p>")
        (tmp_path / "index.html").write_text("<p>i</p>")
        (tmp_path / "orphan.html").write_text("<p>o</p>")
        orphans = module.find_orphans(
            tmp_path, entry_points={"README.html", "index.html"}
        )
        assert orphans == ["orphan.html"]


def test_find_orphans_fragment_link():
    """fragment 付き href (foo.html#anchor) でも file 本体が inbound カウントされる"""
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        (tmp_path / "README.html").write_text(
            '<a href="target.html#section">target section</a>'
        )
        (tmp_path / "target.html").write_text('<h2 id="section">sec</h2>')
        orphans = module.find_orphans(tmp_path, entry_points={"README.html"})
        assert orphans == []


# ============================================================
# main runner (pytest 不在環境用)
# ============================================================

if __name__ == "__main__":
    import inspect
    failures = 0
    for name, fn in inspect.getmembers(sys.modules[__name__], inspect.isfunction):
        if name.startswith("test_"):
            try:
                fn()
                print(f"PASS {name}")
            except AssertionError as e:
                failures += 1
                print(f"FAIL {name}: {e}")
            except Exception as e:
                failures += 1
                print(f"ERROR {name}: {e}")
    sys.exit(1 if failures else 0)
