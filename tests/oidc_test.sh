#!/usr/bin/env bash
# Tests for GitHub OIDC authentication in entrypoint.sh, using a fake curl.
set -euo pipefail

# shellcheck source=entrypoint.sh
source "$(dirname "$0")/../entrypoint.sh"

failures=0
ok()   { echo "ok   - $1"; }
fail() { echo "FAIL - $1"; failures=$((failures + 1)); }

tmp=$(mktemp -d)
trap 'rm -rf "${tmp}"' EXIT
mkdir -p "${tmp}/bin"
cat > "${tmp}/bin/curl" <<'FAKE'
#!/usr/bin/env bash
echo "$*" >> "${FAKE_LOG}"
for a in "$@"; do
  if [[ "${a}" == *"audience="* ]]; then
    [[ "${FAKE_NO_TOKEN:-}" == "1" ]] && { echo '{}'; exit 0; }
    echo '{"value":"gh.oidc.jwt"}'; exit 0
  fi
done
data=""; prev=""
for a in "$@"; do [[ "${prev}" == "--data" ]] && data="${a}"; prev="${a}"; done
echo "${data}" > "${FAKE_BODY}"
case "${FAKE_STATUS:-200}" in
  200) printf '%s\n200' '{"apiKey":"kk_short_lived","expiresAt":"2026-10-06T00:15:00.000Z","trustId":"t1","scopes":null}' ;;
  401) printf '%s\n401' '{"statusCode":401,"message":"Invalid GitHub OIDC token"}' ;;
  403) printf '%s\n403' '{"statusCode":403,"message":"No KrakenKey trust policy matches this repository, ref and environment"}' ;;
  409) printf '%s\n409' '{"statusCode":409,"message":"Several trust policies match this repository; pass trust-id to choose one","trustIds":["t1","t2"]}' ;;
esac
FAKE
chmod +x "${tmp}/bin/curl"

# Runs resolve_api_key in a subshell; prints its stdout/stderr then the key.
run() {
  (
    export PATH="${tmp}/bin:${PATH}" FAKE_LOG="${tmp}/log" FAKE_BODY="${tmp}/body"
    export INPUT_API_URL=https://api.example.test/ INPUT_OIDC_AUDIENCE=https://api.example.test
    resolve_api_key
    echo "KEY=${INPUT_API_KEY}"
  ) 2>&1
}

# An explicit api-key skips OIDC
: > "${tmp}/log"
out=$(INPUT_API_KEY=kk_given ACTIONS_ID_TOKEN_REQUEST_URL=x ACTIONS_ID_TOKEN_REQUEST_TOKEN=y run)
if [[ "${out}" == *"KEY=kk_given"* && ! -s "${tmp}/log" ]]; then ok "api-key wins, no OIDC calls"; else fail "api-key path: ${out}"; fi

# No api-key and no id-token permission
out=$(INPUT_API_KEY='' ACTIONS_ID_TOKEN_REQUEST_URL='' ACTIONS_ID_TOKEN_REQUEST_TOKEN='' run || true)
if [[ "${out}" == *"id-token: write"* && "${out}" != *"KEY="* ]]; then ok "explains the missing permission"; else fail "no permission: ${out}"; fi

# Successful exchange
: > "${tmp}/log"
out=$(INPUT_API_KEY='' INPUT_TRUST_ID='' ACTIONS_ID_TOKEN_REQUEST_URL='https://gh.test/token?v=1' ACTIONS_ID_TOKEN_REQUEST_TOKEN=req run)
if [[ "${out}" == *"KEY=kk_short_lived"* ]]; then ok "exchanges the token for a key"; else fail "exchange: ${out}"; fi
if [[ "${out}" == *"::add-mask::gh.oidc.jwt"* && "${out}" == *"::add-mask::kk_short_lived"* ]]; then ok "masks the OIDC token and the key"; else fail "masking: ${out}"; fi
if grep -q 'audience=https%3A%2F%2Fapi.example.test' "${tmp}/log"; then ok "requests the configured audience, URL-encoded"; else fail "audience: $(cat "${tmp}/log")"; fi
if grep -q 'https://api.example.test/auth/github-oidc' "${tmp}/log"; then ok "posts to <api-url>/auth/github-oidc"; else fail "exchange URL: $(cat "${tmp}/log")"; fi
if [[ "$(cat "${tmp}/body")" == '{"token":"gh.oidc.jwt"}' ]]; then ok "sends no trustId by default"; else fail "body: $(cat "${tmp}/body")"; fi

out=$(INPUT_API_KEY='' INPUT_TRUST_ID=t2 ACTIONS_ID_TOKEN_REQUEST_URL='https://gh.test/token?v=1' ACTIONS_ID_TOKEN_REQUEST_TOKEN=req run)
if [[ "$(cat "${tmp}/body")" == '{"token":"gh.oidc.jwt","trustId":"t2"}' ]]; then ok "sends trust-id when set"; else fail "trust-id body: $(cat "${tmp}/body")"; fi

# Errors
for case in "401:oidc-audience" "403:ref and environment. Create one in the KrakenKey dashboard" "409:trust-id input to one of: t1, t2"; do
  code=${case%%:*}; want=${case#*:}
  out=$(FAKE_STATUS=${code} INPUT_API_KEY='' INPUT_TRUST_ID='' ACTIONS_ID_TOKEN_REQUEST_URL='https://gh.test/token?v=1' ACTIONS_ID_TOKEN_REQUEST_TOKEN=req run || true)
  if [[ "${out}" == *"${want}"* && "${out}" != *"KEY="* ]]; then ok "HTTP ${code} explained"; else fail "HTTP ${code}: ${out}"; fi
done

out=$(FAKE_NO_TOKEN=1 INPUT_API_KEY='' ACTIONS_ID_TOKEN_REQUEST_URL='https://gh.test/token?v=1' ACTIONS_ID_TOKEN_REQUEST_TOKEN=req run || true)
if [[ "${out}" == *"Could not get a GitHub OIDC token"* ]]; then ok "reports a missing OIDC token"; else fail "no token: ${out}"; fi

if [[ ${failures} -gt 0 ]]; then
  echo "${failures} failure(s)"
  exit 1
fi
