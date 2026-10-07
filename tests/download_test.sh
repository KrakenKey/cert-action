#!/usr/bin/env bash
# Tests for the download command in entrypoint.sh, using a fake krakenkey binary.
set -euo pipefail

# shellcheck source=entrypoint.sh
source "$(dirname "$0")/../entrypoint.sh"

failures=0
ok()   { echo "ok   - $1"; }
fail() { echo "FAIL - $1"; failures=$((failures + 1)); }

tmp=$(mktemp -d)
trap 'rm -rf "${tmp}"' EXIT
mkdir -p "${tmp}/bin" "${tmp}/workspace"
cat > "${tmp}/bin/krakenkey" <<'FAKE'
#!/usr/bin/env bash
echo "$*" >> "${FAKE_LOG}"
if [[ " $* " == *" cert download "* ]]; then
  # Like the CLI, download reports the saved file, not the certificate.
  out=""; prev=""
  for a in "$@"; do [[ "${prev}" == "--out" ]] && out="${a}"; prev="${a}"; done
  echo pem > "${out}"
  printf '{"path":"%s"}\n' "${out}"
elif [[ " $* " == *" cert show "* ]]; then
  echo '{"id":42,"status":"issued","expiresAt":"2027-01-05T11:13:01.000Z","details":{"subject":"CN=example.com","validTo":"2027-01-05T11:13:01.000Z","sans":["example.com"]}}'
fi
FAKE
chmod +x "${tmp}/bin/krakenkey"

out_file="${tmp}/github_output"
: > "${out_file}"
(
  cd "${tmp}/workspace"
  export PATH="${tmp}/bin:${PATH}" FAKE_LOG="${tmp}/log" GITHUB_OUTPUT="${out_file}"
  INPUT_API_KEY=kk_test INPUT_API_URL=https://api.example.test INPUT_CERT_ID=42 INPUT_COMMAND=download
  INPUT_CERT_PATH=./cert.pem INPUT_CHAIN_PATH=./chain.pem INPUT_FULLCHAIN_PATH=./fullchain.pem
  INPUT_KEY_PATH=./key.pem INPUT_CSR_PATH=./csr.pem
  result=$(execute_download)
  set_outputs "${result}"
)

has() { grep -qx -- "$1" "${out_file}"; }
if has "cert-id=42"; then ok "sets cert-id"; else fail "cert-id: $(grep cert-id "${out_file}")"; fi
if has "status=issued"; then ok "sets status"; else fail "status: $(grep '^status' "${out_file}")"; fi
if has "expires=2027-01-05T11:13:01.000Z"; then ok "sets expires"; else fail "expires: $(grep expires "${out_file}" || echo missing)"; fi
if has "domain=example.com"; then ok "sets domain"; else fail "domain: $(grep domain "${out_file}" || echo missing)"; fi
for f in cert.pem chain.pem fullchain.pem; do
  if [[ -s "${tmp}/workspace/${f}" ]]; then ok "writes ${f}"; else fail "missing ${f}"; fi
done

if [[ ${failures} -gt 0 ]]; then
  echo "${failures} failure(s)"
  exit 1
fi
