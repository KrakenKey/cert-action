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
mkdir -p "${tmp}/bin" "${tmp}/workspace" "${tmp}/runner" "${tmp}/state"
cat > "${tmp}/bin/krakenkey" <<'FAKE'
#!/usr/bin/env bash
echo "$(pwd)|$*" >> "${FAKE_LOG}"
if [[ " $* " == *" cert renew "* ]]; then
  # Like CLI v0.7.0, renew --wait saves a copy in the current directory.
  [[ " $* " == *" --wait "* ]] && echo leaf > ./example.com.crt
  # FAKE_RENEWAL=ok replaces the leaf; failed keeps it, like an API that
  # keeps the current certificate after a failed renewal. Unset: cert show
  # prints nothing, like a key that can't read the certificate.
  [[ "${FAKE_RENEWAL:-}" == "ok" && " $* " != *" --if-due "* ]] && touch "${FAKE_STATE}/renewed"
  if [[ " $* " == *" --if-due "* ]]; then
    echo '{"id":42,"status":"issued","skipped":true,"reason":"not_due","renewalWindowDays":30}'
  else
    echo '{"id":42,"status":"issued"}'
  fi
elif [[ " $* " == *" cert show "* ]]; then
  [[ -n "${FAKE_RENEWAL:-}" ]] || exit 0
  pem="OLD-LEAF"
  [[ -e "${FAKE_STATE}/renewed" ]] && pem="NEW-LEAF"
  jq -n --arg pem "${pem}" '{id: 42, status: "issued", crtPem: $pem, expiresAt: "2026-11-20T10:00:00Z"}
    + (if $pem == "OLD-LEAF" and env.FAKE_RENEWAL == "failed" then {failureReason: "CAA record for example.com prevents issuance"} else {} end)'
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
    export PATH="${FAKE_BIN:-${tmp}/bin}:${PATH}" FAKE_LOG="${tmp}/log" RUNNER_TEMP="${tmp}/runner" FAKE_STATE="${tmp}/state"
    INPUT_API_KEY=kk_test INPUT_API_URL=https://api.example.test INPUT_CERT_ID=42
    INPUT_WAIT="${2:-true}" INPUT_IF_DUE="$1" INPUT_POLL_INTERVAL=1s INPUT_POLL_TIMEOUT=1m
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

# --- failed renewal that kept the current certificate ----------------------
# An older CLI exits 0 when the certificate ends issued after a failed
# renewal. The action compares the leaf before and after.
: > "${tmp}/log"
rm -f "${tmp}/workspace/"*.pem "${tmp}/state/"*
rc=0
err=$(FAKE_RENEWAL=failed run_renew false 2>&1 >/dev/null) || rc=$?
if [[ "${rc}" -eq 1 ]]; then ok "failed renewal fails the step"; else fail "failed renewal exit code ${rc}, want 1"; fi
if [[ "${err}" == *"::error::Renewal of certificate 42 failed: CAA record for example.com prevents issuance. The current certificate is still in place (expires 2026-11-20T10:00:00Z)."* ]]; then
  ok "failed renewal error names the reason"
else
  fail "failed renewal error: ${err}"
fi
if [[ ! -e "${tmp}/workspace/cert.pem" ]]; then ok "nothing downloaded after a failed renewal"; else fail "cert.pem written after a failed renewal"; fi
if [[ "$(grep -c " cert show " "${tmp}/log")" -eq 2 ]]; then ok "certificate read before and after"; else fail "cert show calls: $(grep -c " cert show " "${tmp}/log")"; fi

: > "${tmp}/log"
rm -f "${tmp}/workspace/"*.pem "${tmp}/state/"*
rc=0
FAKE_RENEWAL=ok run_renew false >/dev/null 2>&1 || rc=$?
if [[ "${rc}" -eq 0 && -f "${tmp}/workspace/cert.pem" ]]; then ok "successful renewal passes the check"; else fail "successful renewal: exit ${rc}"; fi

# A skipped renewal is not checked: the leaf is expected to be unchanged.
: > "${tmp}/log"
rm -f "${tmp}/workspace/"*.pem "${tmp}/state/"*
rc=0
FAKE_RENEWAL=failed run_renew true >/dev/null 2>&1 || rc=$?
if [[ "${rc}" -eq 0 ]]; then ok "skipped renewal is not a failure"; else fail "skipped renewal exit ${rc}"; fi

# Without wait nothing is compared, and cert show is not called.
: > "${tmp}/log"
rc=0
FAKE_RENEWAL=failed run_renew false false >/dev/null 2>&1 || rc=$?
if [[ "${rc}" -eq 0 ]] && ! grep -q " cert show " "${tmp}/log"; then ok "no check without wait"; else fail "without wait: exit ${rc}, log: $(cat "${tmp}/log")"; fi

# The CLI's own failure (newer CLI releases exit 1) is passed through.
mkdir -p "${tmp}/bin2"
cat > "${tmp}/bin2/krakenkey" <<'FAKE'
#!/usr/bin/env bash
if [[ " $* " == *" cert renew "* ]]; then
  echo '{"error":"renewal failed for certificate 42: CAA record for example.com prevents issuance; the current certificate is still in place (expires 2026-11-20)"}' >&2
  exit 1
fi
FAKE
chmod +x "${tmp}/bin2/krakenkey"
rc=0
err=$(FAKE_BIN="${tmp}/bin2" run_renew false 2>&1 >/dev/null) || rc=$?
if [[ "${rc}" -eq 1 && "${err}" == *"renewal failed for certificate 42"* && "${err}" == *"::error::krakenkey cert renew exited with code 1"* ]]; then
  ok "CLI failure passed through with its message"
else
  fail "CLI failure: exit ${rc}, stderr ${err}"
fi

if [[ ${failures} -gt 0 ]]; then
  echo "${failures} failure(s)"
  exit 1
fi
