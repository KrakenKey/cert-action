# Changelog

Notable changes to the KrakenKey cert-action. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/). Versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Changed
- Release pipeline: trigger restricted to `v[0-9]+.[0-9]+.[0-9]+` tags only; release notes auto-generated from CHANGELOG; `make_latest: true`.

### Advisory
- **SC-098v2 — CAA RFC 8657 Parameters**: `validationmethods` and `accounturi` CAA parameters; CA enforcement deadline March 2027; no cert-action config change required today.
- **Chrome EKU Separation**: serverAuth/clientAuth EKU separation enforced 2026-06-15; affects DigiCert/Sectigo chains; Let's Encrypt (used by this action) unaffected.
- **CT Mandatory Logging**: enforced 2026-06-15; DigiCert opt-out removed 2026-06-01; Let's Encrypt always CT-logged, no action required.
- **LE Merkle Tree Certificates**: announced 2026-06-03; staging late 2026, production 2027; MTC breaks the `chain.pem`/`fullchain.pem` model — `chain-path` and `fullchain-path` outputs will need updates before the LE production rollout.

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
