#!/usr/bin/env bash
# safe_profiles.sh — Read profiles.yml redacting sensitive credentials.
# Keeps only: profile names, target names, adapter type, schema, database, threads.
# Usage: bash safe_profiles.sh [path/to/profiles.yml]

PROFILES_FILE="${1:-$HOME/.dbt/profiles.yml}"

if [[ ! -f "$PROFILES_FILE" ]]; then
  if [[ -f "profiles.yml" ]]; then
    PROFILES_FILE="profiles.yml"
  else
    echo "ERROR: profiles.yml not found at $PROFILES_FILE" >&2
    exit 1
  fi
fi

# Keys whose values are always redacted (case-insensitive match)
SENSITIVE_PATTERN='token|password|pass\b|private_key|keyfile|client_id|client_secret|refresh_token|access_token|http_path|oauth|secret\b|api_key|credential|account_info'

while IFS= read -r line; do
  # Extract the key part (before the colon)
  key=$(echo "$line" | sed 's/^[[:space:]]*//' | cut -d':' -f1 | tr '[:upper:]' '[:lower:]')

  if echo "$key" | grep -qiE "$SENSITIVE_PATTERN"; then
    # Replace the value with <REDACTED>, preserving indentation and key
    indent=$(echo "$line" | sed 's/\(^[[:space:]]*\).*/\1/')
    echo "${indent}${key}: <REDACTED>"
  else
    # Heuristic: long opaque strings on value side look like secrets
    value=$(echo "$line" | cut -d':' -f2- | sed 's/^[[:space:]]*//')
    if echo "$value" | grep -qE '^[A-Za-z0-9+/=_\-\.]{41,}$'; then
      indent=$(echo "$line" | sed 's/\(^[[:space:]]*\).*/\1/')
      echo "${indent}${key}: <REDACTED>"
    else
      echo "$line"
    fi
  fi
done < "$PROFILES_FILE"
