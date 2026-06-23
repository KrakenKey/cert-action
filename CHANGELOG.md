# Changelog

Notable changes to the KrakenKey cert-action. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/). Versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Changed
- **Release Pipeline**: release trigger restricted to `v[0-9]+.[0-9]+.[0-9]+` tags only; major-version pointer tags (e.g. `v1`) no longer retrigger the workflow. Structured release notes auto-generated from CHANGELOG using `.github/release.yaml` label categories. Each release marked `latest` via `make_latest: true`.

### PKI Advisories

- **SC-098v2 — CAA RFC 8657 Parameters**: CA/B Forum ballot SC-098v2 (passed 2026-05-13) makes RFC 8657 `validationmethods` and `accounturi` CAA record parameters mandatory for all public CAs by **March 2027**. This action issues certificates via Let's Encrypt ACME DNS-01. If a user's CAA record sets `validationmethods`, it must include `dns-01`. No configuration change required today.
- **Chrome EKU Separation — enforced 2026-06-15**: TLS intermediates must be `serverAuth`-only (no `clientAuth`). Let's Encrypt intermediates (used by this action) are already compliant. Users issuing via DigiCert or Sectigo should re-issue affected certificates.
- **CT Mandatory Logging — enforced 2026-06-15**: Chrome Root Program Policy v1.8 §1.3.4.1 requires precertificate CT logging before issuance. DigiCert removed opt-out settings 2026-06-01. Let's Encrypt always CT-logs; no action required for users of this action.
- **LE Merkle Tree Certificates — announced 2026-06-03**: Let's Encrypt announced that Merkle Tree Certificates (MTC) are their planned post-quantum issuance path. Staging: late 2026; production: 2027. MTC does not use the traditional `chain.pem` / `fullchain.pem` model. **This action will require updates before the production rollout.**

---

## [v1.1.0] — 2026-05-18

### Added
- `chain-path` input (default `./chain.pem`) — path to save the intermediate CA chain PEM alongside the leaf certificate.
- `fullchain-path` input (default `./fullchain.pem`) — path to save the full chain PEM (leaf + intermediates).
- `chain-path` output — absolute path to the saved intermediate chain file, suitable for downstream scp / secrets-manager upload steps.
- `fullchain-path` output — absolute path to the saved full chain PEM.
- `issue`, `renew`, and `download` commands now produce all three certificate output files (leaf, chain, fullchain).
- **Certificate Chain Files** section in README explaining each output file and when to use it.
- **Deploy with full chain** usage example (nginx/HAProxy) in README.

### Changed
- `cert-path` output description clarified to "leaf certificate PEM" (was "certificate PEM").

### Depends on
- KrakenKey/cli v0.2.0 or later (for `--chain-out` / `--fullchain-out` flags)
- KrakenKey/app v0.4.0 or later (for `GET /certs/tls/:id/chain` backend endpoint)

---

## [v1.0.0] — 2026-04-13

### Added
- Initial release: `issue`, `renew`, and `download` commands.
- Automatic CSR generation and submission via the KrakenKey API.
- API key masking (`::add-mask::`) to prevent key leakage in workflow logs.
- Private key files written with `0600` permissions.
- SHA-256 checksum verification of the `krakenkey-cli` binary before execution.
- Configurable poll interval and poll timeout for certificate issuance and renewal.
- `cert-path`, `key-path`, and `csr-path` inputs and outputs.
- SHA-pinned third-party action dependencies (`actions/checkout`, `softprops/action-gh-release`).
- CLI invoked via `KK_API_KEY` environment variable to prevent the API key appearing in `ps` output.
