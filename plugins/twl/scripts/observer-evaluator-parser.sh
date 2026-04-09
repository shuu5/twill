#!/usr/bin/env bash
# observer-evaluator-parser.sh
# observer-evaluator の出力 JSON を検証・正規化する
#
# 処理内容:
#   - quote フィールドが空または欠落の評価を warnings 配列に移動
#   - confidence > 75 を 75 にクランプ
#   - 必須フィールド (specialist, llm_evaluations, summary) 不在で exit 1
#   - malformed JSON は exit 1
#
# Usage: observer-evaluator-parser.sh < input.json
#        observer-evaluator-parser.sh input.json

set -euo pipefail

# --- Input -------------------------------------------------------------------

INPUT_FILE="${1:--}"

if [[ "$INPUT_FILE" == "-" ]]; then
  RAW_JSON="$(cat)"
else
  if [[ ! -f "$INPUT_FILE" ]]; then
    echo "Error: file not found: $INPUT_FILE" >&2
    exit 1
  fi
  RAW_JSON="$(cat "$INPUT_FILE")"
fi

# --- JSON parse check --------------------------------------------------------

if ! echo "$RAW_JSON" | jq empty 2>/dev/null; then
  echo "Error: malformed JSON input" >&2
  exit 1
fi

# --- Required fields check ---------------------------------------------------

MISSING_FIELDS=()

for field in specialist llm_evaluations summary; do
  if ! echo "$RAW_JSON" | jq -e "has(\"$field\")" >/dev/null 2>&1; then
    MISSING_FIELDS+=("$field")
  fi
done

if [[ ${#MISSING_FIELDS[@]} -gt 0 ]]; then
  echo "Error: missing required fields: ${MISSING_FIELDS[*]}" >&2
  exit 1
fi

# --- Process: quote-missing demotion + confidence clamp ----------------------

# jq script:
#   1. Split llm_evaluations into valid (has non-empty quote) and quote-missing
#   2. Move quote-missing evaluations to .warnings array
#   3. Clamp confidence > 75 to 75 in llm_evaluations
#   4. Clamp confidence > 75 to 75 in root_cause_candidates

RESULT="$(echo "$RAW_JSON" | jq '
  # Initialize warnings array if absent
  . + { warnings: (.warnings // []) } |

  # Separate quote-missing evaluations from llm_evaluations
  .llm_evaluations as $evals |
  ([$evals[] | select((.quote // "") != "")] ) as $valid |
  ([$evals[] | select((.quote // "") == "")] ) as $missing |

  # Move quote-missing to warnings with demotion reason
  .warnings += [$missing[] | . + { demoted_reason: "quote field missing or empty" }] |

  # Keep only valid evaluations
  .llm_evaluations = $valid |

  # Clamp confidence in llm_evaluations
  .llm_evaluations = [.llm_evaluations[] |
    if (.confidence // 0) > 75 then .confidence = 75 else . end
  ] |

  # Clamp confidence in root_cause_candidates (if present)
  if has("root_cause_candidates") then
    .root_cause_candidates = [.root_cause_candidates[] |
      if (.confidence // 0) > 75 then .confidence = 75 else . end
    ]
  else . end
')"

echo "$RESULT"
