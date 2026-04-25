#!/usr/bin/env bash
# filter_logs.sh — Strip noise from dbt run/test/compile output.
# Reads from stdin or a file argument.
# Usage:
#   dbt run --select my_model 2>&1 | bash filter_logs.sh
#   bash filter_logs.sh run.log

INPUT="${1:-/dev/stdin}"

# Patterns for lines to always KEEP (checked first)
keep() {
  echo "$1" | grep -qiE \
    'ERROR|FAIL|WARN|\bOK\b|SKIP|PASS|Done\. PASS=|FAIL [0-9]+|ERROR [0-9]+|Failure in test|Got [0-9]+ result'
}

# Patterns for lines to DROP
drop() {
  echo "$1" | grep -qiE \
    'Running with dbt=|Registered adapter|Unable to do partial pars|Partial parse|^Found [0-9]+ model|Concurrency: [0-9]+ thread|dbt hub|check for a new version|Your existing profiles|Loaded profile|profile loaded|Finding state|Checking state|Updating state|[0-9]+ of [0-9]+ START|^Completed successfully|^Finished running [0-9]+' \
  || echo "$1" | grep -qE '^[[:space:]]*[-=]{10,}[[:space:]]*$' \
  || echo "$1" | grep -qE '^\s*\.\s*$' \
  || echo "$1" | grep -qE $'^\x1b'
}

strip_ansi() {
  sed 's/\x1b\[[0-9;]*[mGKHFJA-Za-z]//g'
}

prev_blank=0

while IFS= read -r raw_line; do
  line=$(printf '%s' "$raw_line" | strip_ansi)
  trimmed=$(echo "$line" \
    | sed 's/^[0-9][0-9]:[0-9][0-9]:[0-9][0-9][[:space:]]*//' \
    | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

  # Always keep decision-relevant lines
  if keep "$trimmed"; then
    echo "$trimmed"
    prev_blank=0
    continue
  fi

  # Drop noise
  if drop "$trimmed"; then
    continue
  fi

  # Collapse blank lines
  if [[ -z "$trimmed" ]]; then
    if [[ $prev_blank -eq 0 ]]; then
      echo ""
      prev_blank=1
    fi
    continue
  fi

  prev_blank=0
  echo "$trimmed"
done < "$INPUT"
