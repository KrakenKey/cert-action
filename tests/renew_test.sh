#!/usr/bin/env bash
# Tests for the renew command in entrypoint.sh, using a fake krakenkey binary.
set -euo pipefail

# shellcheck source=entrypoint.sh
source "$(dirname "$0")/../entrypoint.sh"

failures=0
ok()   { echo "ok   - $1"; }
fail() { echo "FAIL - $1"; failures=$((failures + 1)); }

# --- renew_outcome ---------------------------------------------------------
check_outcome() {
  local desc="$1" input="$2" want="$3" got
  got=$(renew_outcome "${input}")
  if [[ "${got}" == "${want}" ]]; then ok "${desc}"; else fail "${desc} (got ${got}, want ${want})"; fi
}
check_outcome "skipped renewal" '{"id":42,"status":"issued","skipped":true,"reason":"not_due"}' false
check_outcome "renewal ran" '{"id":42,"status":"issued"}' true
check_outcome "renewal ran, skipped false" '{"id":42,"status":"renewing","skipped":false}' true
check_outcome "warning document before a skipped result" $'{"warning":"x"}\n{"id":42,"skipped":true}' false
check_outcome "non-JSON output" 'not json' true

# --- execute_renew with a fake CLI -----------------------------------------
tmp=$(mktemp -d)
trap 'rm -rf "${tmp}"' EXIT
mkdir -p "${tmp}/bin" "${tmp}/workspace" "${tmp}/runner"
cat > "${tmp}/bin/krakenkey" <<'FAKE'
#!/usr/bin/env bash
echo "$(pwd)|$*" >> "${FAKE_LOG}"
if [[ " $* " == *" cert renew "* ]]; then
  # Like CLI v0.7.0, renew --wait saves a copy in the current directory.
  [[ " $* " == *" --wait "* ]] && echo leaf > ./example.com.crt
  if [[ " $* " == *" --if-due "* ]]; then
    echo '{"id":42,"status":"issued","skipped":true,"reason":"not_due","renewalWindowDays":30}'
  else
    echo '{"id":42,"status":"issued"}'
  fi
elif [[ " $* " == *" cert download "* ]]; then
  out=""; prev=""
  for a in "$@"; do [[ "${prev}" == "--out" ]] && out="${a}"; prev="${a}"; done
  echo pem > "${out}"
fi
FAKE
chmod +x "${tmp}/bin/krakenkey"

run_renew() {
  (
    cd "${tmp}/workspace"
    export PATH="${tmp}/bin:${PATH}" FAKE_LOG="${tmp}/log" RUNNER_TEMP="${tmp}/runner"
    INPUT_API_KEY=kk_test INPUT_API_URL=https://api.example.test INPUT_CERT_ID=42
    INPUT_WAIT=true INPUT_IF_DUE="$1" INPUT_POLL_INTERVAL=1s INPUT_POLL_TIMEOUT=1m
    INPUT_CERT_PATH=./cert.pem INPUT_CHAIN_PATH=./chain.pem INPUT_FULLCHAIN_PATH=./fullchain.pem
    execute_renew
  )
}

: > "${tmp}/log"
out=$(run_renew true)
renew_line=$(grep " cert renew " "${tmp}/log")
if [[ "${renew_line}" == *"--if-due"* ]]; then ok "if-due passes --if-due"; else fail "if-due passes --if-due: ${renew_line}"; fi
if [[ "${renew_line%%|*}" != "${tmp}/workspace" ]]; then ok "renew runs outside the workspace"; else fail "renew ran in the workspace"; fi
if [[ ! -e "${tmp}/workspace/example.com.crt" ]]; then ok "no stray certificate copy in the workspace"; else fail "stray example.com.crt in the workspace"; fi
if [[ -z "$(ls -A "${tmp}/runner")" ]]; then ok "scratch directory removed"; else fail "scratch directory left in RUNNER_TEMP"; fi
if [[ -f "${tmp}/workspace/cert.pem" && -f "${tmp}/workspace/fullchain.pem" ]]; then ok "current certificate still downloaded"; else fail "cert.pem/fullchain.pem not written"; fi
if [[ "$(renew_outcome "${out}")" == "false" ]]; then ok "skipped result reported"; else fail "skipped result not reported: ${out}"; fi

: > "${tmp}/log"
rm -f "${tmp}/workspace/"*.pem
run_renew false >/dev/null
renew_line=$(grep " cert renew " "${tmp}/log")
if [[ "${renew_line}" != *"--if-due"* ]]; then ok "no --if-due by default"; else fail "--if-due sent by default"; fi

if [[ ${failures} -gt 0 ]]; then
  echo "${failures} failure(s)"
  exit 1
fi
