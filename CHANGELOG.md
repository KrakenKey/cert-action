# Changelog

Notable changes to the KrakenKey cert-action. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/). Versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Release Pipeline

- Release workflow now triggers only on full semver tags (`v[0-9]+.[0-9]+.[0-9]+`); major-version pointer tags (e.g. `v1`) no longer re-trigger the release.
- Structured release notes auto-generated using `.github/release.yaml` label categories (Features, Bug Fixes, Other Changes).
- Each release is automatically marked as latest on GitHub via `make_latest: true`.

### Advisory — CA/B Forum SC-098v2 (enforcement: March 2027)

CA/B Forum ballot SC-098v2 passed 2026-05-13. All public CAs must enforce RFC 8657 CAA `accounturi` and `validationmethods` parameter extensions by March 2027. KrakenKey uses Let's Encrypt ACME DNS-01. If your DNS CAA record sets `validationmethods`, it must include `dns-01` for issuance to succeed after the enforcement date. CAA records without these parameters are unaffected.

### Advisory — Chrome EKU Separation (effective June 15, 2026)

Chrome Root Program Policy v1.8 requires TLS intermediates to carry only `serverAuth` EKU — intermediates that also include `clientAuth` are no longer valid for public TLS. Commercial CAs retired multi-purpose intermediates in May/June 2026. **Let's Encrypt intermediates (E5/E6/R10/R11) are dedicated TLS-only and are not affected.** Certificates issued via cert-action through KrakenKey and Let's Encrypt are fully compliant.

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
