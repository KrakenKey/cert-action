#!/usr/bin/env bash
# Tests for the arguments execute_issue passes to the CLI, using a fake
# krakenkey binary that records them.
set -euo pipefail

# shellcheck source=entrypoint.sh
source "$(dirname "$0")/../entrypoint.sh"

failures=0
ok()   { echo "ok   - $1"; }
fail() { echo "FAIL - $1"; failures=$((failures + 1)); }

tmp=$(mktemp -d)
trap 'rm -rf "${tmp}"' EXIT
mkdir -p "${tmp}/bin"
cat > "${tmp}/bin/krakenkey" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${FAKE_ARGS}"
echo '{"id":42,"status":"issued"}'
FAKE
chmod +x "${tmp}/bin/krakenkey"

run_issue() {
  (
    export PATH="${tmp}/bin:${PATH}" FAKE_ARGS="${tmp}/args"
    INPUT_API_KEY=kk_test INPUT_API_URL=https://api.example.test INPUT_DOMAIN=example.com
    INPUT_KEY_TYPE=ecdsa-p256 INPUT_POLL_INTERVAL=1s INPUT_POLL_TIMEOUT=1m INPUT_WAIT=true
    INPUT_KEY_PATH=./key.pem INPUT_CSR_PATH=./csr.pem INPUT_CERT_PATH=./cert.pem
    INPUT_CHAIN_PATH=./chain.pem INPUT_FULLCHAIN_PATH=./fullchain.pem
    INPUT_SAN='' INPUT_SUBJECT_ORG='' INPUT_SUBJECT_OU='' INPUT_SUBJECT_COUNTRY=''
    INPUT_AUTO_RENEW="$1"
    execute_issue >/dev/null
  )
}

for case in "true:--auto-renew=true" "false:--auto-renew=false" "False:--auto-renew=false" "TRUE:--auto-renew=true"; do
  input=${case%%:*}; want=${case#*:}
  run_issue "${input}"
  if grep -qx -- "${want}" "${tmp}/args"; then ok "auto-renew '${input}' passes ${want}"; else fail "auto-renew '${input}': $(grep auto-renew "${tmp}/args" || echo 'no flag')"; fi
  if [[ $(grep -c -- '--auto-renew' "${tmp}/args") -eq 1 ]]; then ok "auto-renew '${input}' passes the flag once"; else fail "auto-renew '${input}' flag count"; fi
done

if [[ ${failures} -gt 0 ]]; then
  echo "${failures} failure(s)"
  exit 1
fi
