#!/usr/bin/env bash
set -euo pipefail

# ── 1. Mask secrets ──────────────────────────────────────────────
mask_secrets() {
  if [[ -n "${INPUT_API_KEY:-}" ]]; then
    echo "::add-mask::${INPUT_API_KEY}"
  fi
}

# ── 2. Validate inputs ──────────────────────────────────────────
validate_inputs() {
  if [[ -n "${INPUT_API_KEY:-}" && ! "${INPUT_API_KEY}" =~ ^kk_ ]]; then
    echo "::error::Invalid api-key format — must start with 'kk_'"
    exit 1
  fi

  case "${INPUT_COMMAND}" in
    issue)
      if [[ -z "${INPUT_DOMAIN:-}" ]]; then
        echo "::error::Missing required input: domain (required for 'issue' command)"
        exit 1
      fi
      ;;
    renew|download)
      if [[ -z "${INPUT_CERT_ID:-}" ]]; then
        echo "::error::Missing required input: cert-id (required for '${INPUT_COMMAND}' command)"
        exit 1
      fi
      ;;
    *)
      echo "::error::Invalid command '${INPUT_COMMAND}' — must be: issue, renew, or download"
      exit 1
      ;;
  esac
}

# ── 2b. GitHub OIDC ──────────────────────────────────────────────
# Without an api-key, exchange the job's GitHub OIDC token for a KrakenKey
# key that lasts 15 minutes and carries the trust policy's limits.
resolve_api_key() {
  if [[ -n "${INPUT_API_KEY:-}" ]]; then
    return 0
  fi
  if [[ -z "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" || -z "${ACTIONS_ID_TOKEN_REQUEST_TOKEN:-}" ]]; then
    echo "::error::No api-key given and GitHub OIDC is not available. Either pass api-key, or add 'permissions: id-token: write' to the job and create a trust policy for this repository in the KrakenKey dashboard."
    exit 1
  fi

  local audience token body response status message
  audience=$(jq -rn --arg a "${INPUT_OIDC_AUDIENCE:-https://api.krakenkey.io}" '$a | @uri')
  if ! token=$(curl -fsS -H "Authorization: bearer ${ACTIONS_ID_TOKEN_REQUEST_TOKEN}" \
      "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=${audience}" | jq -r '.value // empty'); then
    token=""
  fi
  if [[ -z "${token}" ]]; then
    echo "::error::Could not get a GitHub OIDC token for this job."
    exit 1
  fi
  echo "::add-mask::${token}"

  body=$(jq -cn --arg t "${token}" --arg id "${INPUT_TRUST_ID:-}" \
    '{token: $t} + (if $id == "" then {} else {trustId: $id} end)')
  response=$(curl -sS -w '\n%{http_code}' -X POST \
    -H 'Content-Type: application/json' --data "${body}" \
    "${INPUT_API_URL%/}/auth/github-oidc") || {
    echo "::error::Could not reach ${INPUT_API_URL} to exchange the GitHub OIDC token."
    exit 1
  }
  status=$(tail -n1 <<<"${response}")
  body=$(sed '$d' <<<"${response}")
  if [[ "${status}" != "200" ]]; then
    message=$(jq -r '.message // empty' <<<"${body}" 2>/dev/null || true)
    case "${status}" in
      401) echo "::error::KrakenKey rejected the GitHub OIDC token (${message:-invalid token}). Check that oidc-audience matches the KrakenKey API." ;;
      # The API's messages have no final period; add one before the hint.
      403) message=${message:-No KrakenKey trust policy matches this repository}
           echo "::error::${message%.}. Create one in the KrakenKey dashboard, or check its branch, tag and environment conditions." ;;
      409) message=${message:-Several trust policies match this repository}
           echo "::error::${message%.}. Set the trust-id input to one of: $(jq -r '.trustIds // [] | join(", ")' <<<"${body}" 2>/dev/null)" ;;
      *)   echo "::error::GitHub OIDC exchange failed with HTTP ${status}${message:+: ${message}}" ;;
    esac
    exit 1
  fi

  INPUT_API_KEY=$(jq -r '.apiKey // empty' <<<"${body}")
  if [[ ! "${INPUT_API_KEY}" =~ ^kk_ ]]; then
    echo "::error::GitHub OIDC exchange returned no API key."
    exit 1
  fi
  echo "::add-mask::${INPUT_API_KEY}"
  export INPUT_API_KEY
  echo "Authenticated with GitHub OIDC (key valid until $(jq -r '.expiresAt' <<<"${body}"))." >&2
}

# ── 3. Download CLI binary ───────────────────────────────────────
download_cli() {
  local version="${INPUT_CLI_VERSION}"
  local os arch binary_name download_url checksums_url

  os=$(uname -s | tr '[:upper:]' '[:lower:]')
  arch=$(uname -m)
  case "${arch}" in
    x86_64)  arch="amd64" ;;
    aarch64) arch="arm64" ;;
  esac

  if [[ "${version}" == "latest" ]]; then
    version=$(curl -fsSL "https://api.github.com/repos/krakenkey/cli/releases/latest" | jq -r '.tag_name')
    echo "::debug::Resolved latest CLI version: ${version}"
  fi

  binary_name="krakenkey_${version#v}_${os}_${arch}.tar.gz"
  download_url="https://github.com/krakenkey/cli/releases/download/${version}/${binary_name}"
  checksums_url="https://github.com/krakenkey/cli/releases/download/${version}/checksums.txt"

  echo "::group::Downloading krakenkey-cli ${version} (${os}/${arch})"
  curl -fsSL "${download_url}" -o "/tmp/${binary_name}"
  curl -fsSL "${checksums_url}" -o /tmp/checksums.txt

  # Verify checksum
  (cd /tmp && grep "${binary_name}" checksums.txt | sha256sum -c -)
  tar -xzf "/tmp/${binary_name}" -C /tmp krakenkey
  chmod +x /tmp/krakenkey
  echo "::endgroup::"

  export PATH="/tmp:${PATH}"
}

# ── 4. Execute command ───────────────────────────────────────────
# Split the comma-separated san input into one "--san <name>" pair per line.
# The CLI takes repeated --san flags and does not split values itself, so
# passing the raw input would request a single SAN like "a.com,b.com".
# Whitespace around each name is trimmed, empty entries are dropped, and
# newlines are accepted as separators too.
san_args() {
  local raw="${1//$'\n'/,}" entry
  local -a entries=()
  IFS=',' read -r -a entries <<< "${raw}"
  for entry in "${entries[@]}"; do
    entry="${entry#"${entry%%[![:space:]]*}"}"
    entry="${entry%"${entry##*[![:space:]]}"}"
    if [[ -n "${entry}" ]]; then
      printf '%s\n' --san "${entry}"
    fi
  done
}

execute_issue() {
  local args=(
    --api-url "${INPUT_API_URL}"
    --output json
    --no-color
    cert issue
    --domain "${INPUT_DOMAIN}"
    --key-type "${INPUT_KEY_TYPE}"
    --poll-interval "${INPUT_POLL_INTERVAL}"
    --poll-timeout "${INPUT_POLL_TIMEOUT}"
    --key-out "${INPUT_KEY_PATH}"
    --csr-out "${INPUT_CSR_PATH}"
    --out "${INPUT_CERT_PATH}"
    --chain-out "${INPUT_CHAIN_PATH}"
    --fullchain-out "${INPUT_FULLCHAIN_PATH}"
  )
  [[ "${INPUT_AUTO_RENEW}" == "true" ]] && args+=(--auto-renew)
  [[ "${INPUT_WAIT}" == "true" ]] && args+=(--wait)
  local -a sans=()
  mapfile -t sans < <(san_args "${INPUT_SAN:-}")
  args+=("${sans[@]}")
  [[ -n "${INPUT_SUBJECT_ORG}" ]] && args+=(--org "${INPUT_SUBJECT_ORG}")
  [[ -n "${INPUT_SUBJECT_OU}" ]] && args+=(--ou "${INPUT_SUBJECT_OU}")
  [[ -n "${INPUT_SUBJECT_COUNTRY}" ]] && args+=(--country "${INPUT_SUBJECT_COUNTRY}")

  KK_API_KEY="${INPUT_API_KEY}" krakenkey "${args[@]}"
}

# Prints "false" when the CLI reported a skipped renewal (--if-due and the
# certificate is outside the renewal window), otherwise "true". The CLI's JSON
# output can hold several documents (e.g. a warning before the result).
renew_outcome() {
  if echo "$1" | jq -se 'any(.[]; type == "object" and .skipped == true)' >/dev/null 2>&1; then
    echo "false"
  else
    echo "true"
  fi
}

execute_renew() {
  local result rc=0 renew_args=() workdir
  [[ "${INPUT_WAIT}" == "true" ]] && renew_args+=(--wait)
  [[ "${INPUT_IF_DUE:-false}" == "true" ]] && renew_args+=(--if-due)
  # CLI v0.7.0+ saves ./<cn>.crt and friends after renew --wait. The action
  # downloads to its own output paths below, so run renew in a scratch
  # directory to keep those copies out of the workspace.
  workdir=$(mktemp -d "${RUNNER_TEMP:-/tmp}/krakenkey-renew.XXXXXX")
  # Capture output but never let a CLI failure abort before we can print it.
  # Under set -e, a plain result=$(...) exits on failure and the CLI's error
  # message (stdout in --output json mode) is lost with it.
  result=$(cd "${workdir}" && KK_API_KEY="${INPUT_API_KEY}" krakenkey \
    --api-url "${INPUT_API_URL}" \
    --output json \
    --no-color \
    cert renew "${INPUT_CERT_ID}" \
    "${renew_args[@]}" \
    --poll-interval "${INPUT_POLL_INTERVAL}" \
    --poll-timeout "${INPUT_POLL_TIMEOUT}") || rc=$?
  rm -rf "${workdir}"
  echo "${result}"
  if [[ "${rc}" -ne 0 ]]; then
    echo "::error::krakenkey cert renew exited with code ${rc}"
    exit "${rc}"
  fi

  # With --wait the CLI prints the initial response ("renewing") and only
  # returns 0 once the renewal reached a good terminal state, so success of
  # the command is the signal. Without --wait, fall back to the reported status.
  local status
  status=$(echo "${result}" | jq -r '.status' 2>/dev/null | head -n1 || true)
  if [[ "${INPUT_WAIT}" == "true" || "${status}" == "issued" ]]; then
    KK_API_KEY="${INPUT_API_KEY}" krakenkey \
      --api-url "${INPUT_API_URL}" \
      --output json \
      --no-color \
      cert download "${INPUT_CERT_ID}" \
      --out "${INPUT_CERT_PATH}" > /dev/null

    KK_API_KEY="${INPUT_API_KEY}" krakenkey \
      --api-url "${INPUT_API_URL}" \
      --output json \
      --no-color \
      cert download "${INPUT_CERT_ID}" \
      --format chain \
      --out "${INPUT_CHAIN_PATH}" 2>/dev/null || true

    KK_API_KEY="${INPUT_API_KEY}" krakenkey \
      --api-url "${INPUT_API_URL}" \
      --output json \
      --no-color \
      cert download "${INPUT_CERT_ID}" \
      --format fullchain \
      --out "${INPUT_FULLCHAIN_PATH}" 2>/dev/null || true
  fi
}

execute_download() {
  KK_API_KEY="${INPUT_API_KEY}" krakenkey \
    --api-url "${INPUT_API_URL}" \
    --output json \
    --no-color \
    cert download "${INPUT_CERT_ID}" \
    --out "${INPUT_CERT_PATH}"

  KK_API_KEY="${INPUT_API_KEY}" krakenkey \
    --api-url "${INPUT_API_URL}" \
    --output json \
    --no-color \
    cert download "${INPUT_CERT_ID}" \
    --format chain \
    --out "${INPUT_CHAIN_PATH}" 2>/dev/null || true

  KK_API_KEY="${INPUT_API_KEY}" krakenkey \
    --api-url "${INPUT_API_URL}" \
    --output json \
    --no-color \
    cert download "${INPUT_CERT_ID}" \
    --format fullchain \
    --out "${INPUT_FULLCHAIN_PATH}" 2>/dev/null || true
}

# ── 5. Parse output and set Action outputs ───────────────────────
set_outputs() {
  local result="$1"
  local cert_id status

  # Take the last JSON document that carries the field; the CLI may print a
  # warning document first.
  cert_id=$(echo "${result}" | jq -rs 'map(select(type == "object" and has("id"))) | last | .id // empty' 2>/dev/null || true)
  status=$(echo "${result}" | jq -rs 'map(select(type == "object" and has("status"))) | last | .status // empty' 2>/dev/null || true)

  {
    echo "cert-id=${cert_id}"
    echo "status=${status}"
  } >> "${GITHUB_OUTPUT}"

  if [[ "${INPUT_COMMAND}" == "renew" ]]; then
    echo "renewed=$(renew_outcome "${result}")" >> "${GITHUB_OUTPUT}"
  fi

  if [[ "${status}" == "issued" ]]; then
    local details
    details=$(KK_API_KEY="${INPUT_API_KEY}" krakenkey \
      --api-url "${INPUT_API_URL}" \
      --output json \
      --no-color \
      cert show "${cert_id}" 2>/dev/null || true)

    if [[ -n "${details}" ]]; then
      {
        echo "domain=$(echo "${details}" | jq -r '.details.subject // empty' | sed 's/CN=//')"
        echo "sans=$(echo "${details}" | jq -r '[.details.sans[]? // empty] | join(",")' 2>/dev/null || echo "")"
        echo "issuer=$(echo "${details}" | jq -r '.details.issuer // empty')"
        echo "serial-number=$(echo "${details}" | jq -r '.details.serialNumber // empty')"
        echo "expires=$(echo "${details}" | jq -r '.details.validTo // .expiresAt // empty')"
        echo "fingerprint=$(echo "${details}" | jq -r '.details.fingerprint // empty')"
        echo "key-type=$(echo "${details}" | jq -r '.details.keyType // empty')"
        echo "key-size=$(echo "${details}" | jq -r '.details.keySize // empty')"
      } >> "${GITHUB_OUTPUT}"
    fi
  fi

  {
    echo "cert-path=$(realpath "${INPUT_CERT_PATH}" 2>/dev/null || echo "${INPUT_CERT_PATH}")"
    echo "chain-path=$(realpath "${INPUT_CHAIN_PATH}" 2>/dev/null || echo "${INPUT_CHAIN_PATH}")"
    echo "fullchain-path=$(realpath "${INPUT_FULLCHAIN_PATH}" 2>/dev/null || echo "${INPUT_FULLCHAIN_PATH}")"
    echo "key-path=$(realpath "${INPUT_KEY_PATH}" 2>/dev/null || echo "${INPUT_KEY_PATH}")"
    echo "csr-path=$(realpath "${INPUT_CSR_PATH}" 2>/dev/null || echo "${INPUT_CSR_PATH}")"
  } >> "${GITHUB_OUTPUT}"

  [[ -f "${INPUT_KEY_PATH}" ]] && chmod 0600 "${INPUT_KEY_PATH}"
  [[ -f "${INPUT_CERT_PATH}" ]] && chmod 0644 "${INPUT_CERT_PATH}"
  [[ -f "${INPUT_CHAIN_PATH}" ]] && chmod 0644 "${INPUT_CHAIN_PATH}"
  [[ -f "${INPUT_FULLCHAIN_PATH}" ]] && chmod 0644 "${INPUT_FULLCHAIN_PATH}"
}

# ── 6. Error handler ────────────────────────────────────────────
handle_error() {
  local exit_code="$1"
  case "${exit_code}" in
    0) return 0 ;;
    2) echo "::error::Authentication failed — verify the api-key secret is set and valid, or that the GitHub OIDC trust policy grants this command's scopes" ;;
    3) echo "::error::Certificate or resource not found — check cert-id input" ;;
    4) echo "::error::Rate limited by KrakenKey API — wait and retry, or upgrade your plan" ;;
    5) echo "::error::Configuration error — check action inputs" ;;
    *) echo "::error::Command failed (exit code ${exit_code}) — check logs above for details" ;;
  esac
  exit "${exit_code}"
}

# ── Main ─────────────────────────────────────────────────────────
main() {
  mask_secrets
  validate_inputs
  resolve_api_key
  download_cli

  local result=""
  local exit_code=0

  echo "::group::KrakenKey ${INPUT_COMMAND}"
  case "${INPUT_COMMAND}" in
    issue)    result=$(execute_issue)    || exit_code=$? ;;
    renew)    result=$(execute_renew)    || exit_code=$? ;;
    download) result=$(execute_download) || exit_code=$? ;;
  esac
  echo "::endgroup::"

  if [[ ${exit_code} -ne 0 ]]; then
    handle_error "${exit_code}"
  fi

  set_outputs "${result}"

  echo "### KrakenKey Certificate" >> "${GITHUB_STEP_SUMMARY}"
  echo "" >> "${GITHUB_STEP_SUMMARY}"
  if [[ "${INPUT_COMMAND}" == "issue" ]]; then
    {
      echo "| Field | Value |"
      echo "|-------|-------|"
      echo "| **Command** | \`${INPUT_COMMAND}\` |"
      echo "| **Domain** | \`${INPUT_DOMAIN}\` |"
      echo "| **Cert ID** | \`$(echo "${result}" | jq -r '.id // "—"')\` |"
      echo "| **Status** | \`$(echo "${result}" | jq -r '.status // "—"')\` |"
      echo "| **Key Type** | \`${INPUT_KEY_TYPE}\` |"
    } >> "${GITHUB_STEP_SUMMARY}"
  else
    {
      echo "| Field | Value |"
      echo "|-------|-------|"
      echo "| **Command** | \`${INPUT_COMMAND}\` |"
      echo "| **Cert ID** | \`${INPUT_CERT_ID}\` |"
      echo "| **Status** | \`$(echo "${result}" | jq -r '.status // "—"')\` |"
    } >> "${GITHUB_STEP_SUMMARY}"
  fi
}

# Only run when executed directly, so tests can source this file.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
