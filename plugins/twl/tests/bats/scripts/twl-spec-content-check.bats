#!/usr/bin/env bats
# twl-spec-content-check.bats - twl_spec_content_check MCP tool handler 静的 + smoke test (C10)
# change 001-spec-purify Specialist phase 4 (b)

load '../helpers/common'

setup() {
  common_setup
  TWILL_ROOT="$(cd "$REPO_ROOT/../.." && pwd)"
  TOOLS_SPEC="$TWILL_ROOT/cli/twl/src/twl/mcp_server/tools_spec.py"
  TOOLS_PY="$TWILL_ROOT/cli/twl/src/twl/mcp_server/tools.py"
}

teardown() {
  common_teardown
}

@test "tools_spec.py exists" {
  [ -f "$TOOLS_SPEC" ]
}

@test "tools_spec.py Python syntax valid" {
  python3 -m py_compile "$TOOLS_SPEC"
}

@test "tools_spec.py imports html.parser (std lib only)" {
  grep -q "from html.parser import" "$TOOLS_SPEC"
}

@test "tools_spec.py has twl_spec_content_check_handler" {
  grep -q "def twl_spec_content_check_handler" "$TOOLS_SPEC"
}

@test "tools_spec.py has 5 check functions" {
  grep -q "def check_past_narration" "$TOOLS_SPEC"
  grep -q "def check_demo_code" "$TOOLS_SPEC"
  grep -q "def check_declarative" "$TOOLS_SPEC"
  grep -q "def check_changes_lifecycle" "$TOOLS_SPEC"
  grep -q "def check_respec_markup" "$TOOLS_SPEC"
}

@test "tools.py registers twl_spec_content_check" {
  grep -q "def twl_spec_content_check" "$TOOLS_PY"
}

@test "DATA_STATUS_ENUM contains 4 values" {
  grep -q "DATA_STATUS_ENUM" "$TOOLS_SPEC"
  grep -q '"verified"' "$TOOLS_SPEC"
  grep -q '"deduced"' "$TOOLS_SPEC"
  grep -q '"inferred"' "$TOOLS_SPEC"
  grep -q '"experiment-verified"' "$TOOLS_SPEC"
}

@test "smoke: invoke on README.html (PASS expected)" {
  cd "$TWILL_ROOT"
  OUT=$(python3 -c "
import sys
sys.path.insert(0, 'cli/twl/src')
from twl.mcp_server.tools_spec import twl_spec_content_check_handler
r = twl_spec_content_check_handler('architecture/spec/README.html', check_types=['changes_lifecycle'])
print(r['ok'])
")
  [ "$OUT" = "True" ]
}

@test "smoke: R-14 violation detection in temp file" {
  cd "$TWILL_ROOT"
  TMP_FILE="$(mktemp --suffix=.html)"
  cat > "$TMP_FILE" <<'HTML'
<!DOCTYPE html>
<html><body>
<p>以前は phase だった。</p>
</body></html>
HTML
  OUT=$(python3 -c "
import sys
sys.path.insert(0, 'cli/twl/src')
from twl.mcp_server.tools_spec import twl_spec_content_check_handler
r = twl_spec_content_check_handler('$TMP_FILE', check_types=['past_narration'])
print(r['exit_code'])
" 2>&1)
  rm -f "$TMP_FILE"
  [ "$OUT" = "1" ]
}

@test "Finding category is spec-temporal" {
  grep -qE 'category.*spec-temporal' "$TOOLS_SPEC"
}

@test "false positive fix: CSS class 'pending' is NOT flagged (R-14 inside <style>)" {
  cd "$TWILL_ROOT"
  TMP_FILE="$(mktemp --suffix=.html)"
  cat > "$TMP_FILE" <<'HTML'
<!DOCTYPE html>
<html>
<head><style>.pending { color: red; }</style></head>
<body><p>本仕様は declarative である。</p></body>
</html>
HTML
  OUT=$(python3 -c "
import sys
sys.path.insert(0, 'cli/twl/src')
from twl.mcp_server.tools_spec import twl_spec_content_check_handler
r = twl_spec_content_check_handler('$TMP_FILE', check_types=['declarative'])
findings = r.get('findings', [])
pending_hits = [f for f in findings if 'pending' in f.get('message', '')]
print(len(pending_hits))
")
  rm -f "$TMP_FILE"
  [ "$OUT" = "0" ]
}

@test "false positive fix: date marker '(2026-05-16)' is NOT flagged (legitimate change identifier)" {
  cd "$TWILL_ROOT"
  TMP_FILE="$(mktemp --suffix=.html)"
  cat > "$TMP_FILE" <<'HTML'
<!DOCTYPE html>
<html><body>
<p>change 001-spec-purify (2026-05-16) で確定した規律を本 spec が反映する。</p>
</body></html>
HTML
  OUT=$(python3 -c "
import sys
sys.path.insert(0, 'cli/twl/src')
from twl.mcp_server.tools_spec import twl_spec_content_check_handler
r = twl_spec_content_check_handler('$TMP_FILE', check_types=['past_narration'])
print(len(r.get('findings', [])))
")
  rm -f "$TMP_FILE"
  [ "$OUT" = "0" ]
}

@test "false positive fix: <pre> without data-status is INFO (not WARNING)" {
  cd "$TWILL_ROOT"
  TMP_FILE="$(mktemp --suffix=.html)"
  cat > "$TMP_FILE" <<'HTML'
<!DOCTYPE html>
<html><body>
<pre><code>{"id": "example-schema", "type": "json"}</code></pre>
</body></html>
HTML
  OUT=$(python3 -c "
import sys
sys.path.insert(0, 'cli/twl/src')
from twl.mcp_server.tools_spec import twl_spec_content_check_handler
r = twl_spec_content_check_handler('$TMP_FILE', check_types=['demo_code'])
findings = r.get('findings', [])
warn = [f for f in findings if f['severity'] == 'WARNING']
info = [f for f in findings if f['severity'] == 'INFO']
print(f'WARN={len(warn)} INFO={len(info)}')
")
  rm -f "$TMP_FILE"
  [ "$OUT" = "WARN=0 INFO=1" ]
}

@test "regression: shebang inside <pre> is still flagged as WARNING (R-15 howto code)" {
  cd "$TWILL_ROOT"
  TMP_FILE="$(mktemp --suffix=.html)"
  cat > "$TMP_FILE" <<'HTML'
<!DOCTYPE html>
<html><body>
<pre><code>#!/usr/bin/env bash
echo "howto example"</code></pre>
</body></html>
HTML
  OUT=$(python3 -c "
import sys
sys.path.insert(0, 'cli/twl/src')
from twl.mcp_server.tools_spec import twl_spec_content_check_handler
r = twl_spec_content_check_handler('$TMP_FILE', check_types=['demo_code'])
findings = r.get('findings', [])
warn_count = sum(1 for f in findings if f['severity'] == 'WARNING' and 'howto' in f.get('message', '').lower())
print(warn_count)
")
  rm -f "$TMP_FILE"
  [ "$OUT" = "1" ]
}
