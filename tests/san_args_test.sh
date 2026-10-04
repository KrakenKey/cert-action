#!/usr/bin/env bash
# Unit tests for san_args in entrypoint.sh.
set -euo pipefail

# shellcheck source=entrypoint.sh
source "$(dirname "$0")/../entrypoint.sh"

failures=0

# check <description> <san input> [expected args...]
check() {
  local desc="$1" input="$2"
  shift 2
  local -a expected=("$@") actual=()
  mapfile -t actual < <(san_args "${input}")
  if [[ "${actual[*]-}" == "${expected[*]-}" && "${#actual[@]}" -eq "${#expected[@]}" ]]; then
    echo "ok   - ${desc}"
  else
    echo "FAIL - ${desc}"
    echo "       expected (${#expected[@]}): ${expected[*]-}"
    echo "       actual   (${#actual[@]}): ${actual[*]-}"
    failures=$((failures + 1))
  fi
}

check "empty input" ""
check "single name" "www.example.com" \
  --san www.example.com
check "comma-separated names" "www.example.com,api.example.com,cdn.example.com" \
  --san www.example.com --san api.example.com --san cdn.example.com
check "whitespace around names is trimmed" "  www.example.com , api.example.com	" \
  --san www.example.com --san api.example.com
check "empty entries are dropped" ",www.example.com,, ,api.example.com," \
  --san www.example.com --san api.example.com
check "only separators and spaces" " , ,, "
check "newlines are separators" $'www.example.com\napi.example.com,\ncdn.example.com\n' \
  --san www.example.com --san api.example.com --san cdn.example.com
check "wildcard and IP names pass through" "*.example.com, 192.0.2.10" \
  --san '*.example.com' --san 192.0.2.10

if [[ "${failures}" -gt 0 ]]; then
  echo "${failures} test(s) failed"
  exit 1
fi
echo "all san_args tests passed"
