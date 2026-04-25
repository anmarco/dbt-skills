#!/usr/bin/env bash
# scan_project.sh — Print a compact structural summary of a dbt project.
# Usage: bash scan_project.sh [project_root]

set -e

# ── Find project root ────────────────────────────────────────────────────────
find_root() {
  local dir="${1:-$(pwd)}"
  while [[ "$dir" != "/" ]]; do
    [[ -f "$dir/dbt_project.yml" ]] && echo "$dir" && return
    dir=$(dirname "$dir")
  done
  echo "${1:-$(pwd)}"  # fallback
}

ROOT=$(find_root "${1:-$(pwd)}")
PROJECT_FILE="$ROOT/dbt_project.yml"

if [[ ! -f "$PROJECT_FILE" ]]; then
  echo "WARNING: dbt_project.yml not found under $ROOT" >&2
fi

# ── Tiny yaml value extractor (key: value on same line) ─────────────────────
get_val() {
  grep -m1 "^${1}:" "$PROJECT_FILE" 2>/dev/null \
    | sed "s/^${1}:[[:space:]]*//" | tr -d "'\""
}

PROJECT_NAME=$(get_val "name")
VERSION=$(get_val "version")
PROFILE=$(get_val "profile")
MODEL_PATH=$(get_val "model-paths" | tr -d '[]' | tr ',' '\n' | head -1 | tr -d ' "' )
MODEL_PATH="${MODEL_PATH:-models}"
MACRO_PATH=$(get_val "macro-paths" | tr -d '[]' | tr ',' '\n' | head -1 | tr -d ' "')
MACRO_PATH="${MACRO_PATH:-macros}"

echo "=== dbt Project: ${PROJECT_NAME:-?} ==="
echo "Version : ${VERSION:-?}"
echo "Profile : ${PROFILE:-?}"
echo "Root    : $ROOT"
echo ""

# ── Models ───────────────────────────────────────────────────────────────────
MODELS_DIR="$ROOT/$MODEL_PATH"
if [[ -d "$MODELS_DIR" ]]; then
  echo "── Models ──"
  # Get top-level subdirectories (layers)
  while IFS= read -r layer_dir; do
    layer=$(basename "$layer_dir")
    # Count sql files in this layer
    count=$(find "$layer_dir" -name "*.sql" | wc -l | tr -d ' ')
    # Infer prefixes from filenames
    prefixes=$(find "$layer_dir" -name "*.sql" -exec basename {} .sql \; \
      | sed 's/_.*//' | sort -u | tr '\n' ',' | sed 's/,$//')
    prefix_str=""
    [[ -n "$prefixes" ]] && prefix_str="  [prefixes: $prefixes]"
    echo "  $layer/  ($count models)$prefix_str"
    # Show first 8 files
    find "$layer_dir" -name "*.sql" | sort | head -8 | while read -r f; do
      echo "    ${f#$MODELS_DIR/}"
    done
    if [[ $count -gt 8 ]]; then
      echo "    ... and $((count - 8)) more"
    fi
  done < <(find "$MODELS_DIR" -mindepth 1 -maxdepth 1 -type d | sort)

  # Models directly in models/ root (no sublayer)
  root_models=$(find "$MODELS_DIR" -maxdepth 1 -name "*.sql" | wc -l | tr -d ' ')
  if [[ $root_models -gt 0 ]]; then
    echo "  (root)/  ($root_models models)"
    find "$MODELS_DIR" -maxdepth 1 -name "*.sql" | sort | head -8 | while read -r f; do
      echo "    $(basename "$f")"
    done
  fi
  echo ""
fi

# ── Sources (from yml files) ─────────────────────────────────────────────────
if [[ -d "$MODELS_DIR" ]]; then
  source_count=$(grep -rl "^sources:" "$MODELS_DIR" 2>/dev/null | wc -l | tr -d ' ')
  if [[ $source_count -gt 0 ]]; then
    echo "── Sources ──"
    grep -rl "^sources:" "$MODELS_DIR" 2>/dev/null | while read -r yml; do
      # Extract source names crudely
      grep -E '^\s+- name:' "$yml" | head -5 | while read -r line; do
        name=$(echo "$line" | sed 's/.*name:[[:space:]]*//' | tr -d "'\"")
        echo "  $name  (from $(basename "$yml"))"
      done
    done
    echo ""
  fi
fi

# ── Macros ───────────────────────────────────────────────────────────────────
MACROS_DIR="$ROOT/$MACRO_PATH"
if [[ -d "$MACROS_DIR" ]]; then
  macro_count=$(find "$MACROS_DIR" -name "*.sql" | wc -l | tr -d ' ')
  if [[ $macro_count -gt 0 ]]; then
    echo "── Macros ── ($macro_count files)"
    find "$MACROS_DIR" -name "*.sql" | sort | head -5 | while read -r f; do
      echo "  ${f#$ROOT/}"
    done
    [[ $macro_count -gt 5 ]] && echo "  ... and $((macro_count - 5)) more"
    echo ""
  fi
fi

# ── Tests (count from yml) ───────────────────────────────────────────────────
if [[ -d "$MODELS_DIR" ]]; then
  test_count=$(grep -r "^\s*- (unique|not_null|accepted_values|relationships)" \
    "$MODELS_DIR" 2>/dev/null | wc -l | tr -d ' ')
  # simpler fallback
  if [[ -z "$test_count" || "$test_count" -eq 0 ]]; then
    test_count=$(grep -rh "tests:" "$MODELS_DIR" 2>/dev/null | wc -l | tr -d ' ')
  fi
  echo "── Tests ── (~$test_count test definitions found)"
  echo ""
fi

# ── Project vars ─────────────────────────────────────────────────────────────
if grep -q "^vars:" "$PROJECT_FILE" 2>/dev/null; then
  echo "── Project Vars ──"
  awk '/^vars:/{found=1; next} found && /^[^ ]/{exit} found{print}' "$PROJECT_FILE" \
    | grep -v "^$" | head -10
  echo ""
fi
