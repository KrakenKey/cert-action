# Changelog

Notable changes to the KrakenKey cert-action. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/). Versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Changed

- Release workflow restricted to tag-triggered runs (`v*.*.*` pattern only); manual dispatch and branch push triggers no longer create releases.
- Release notes use structured Added / Changed / Fixed sections and publish with `make_latest: true`.

### PKI Advisory — SC-098v2 (CA/B Forum, RFC 8657 CAA, enforcement March 2027)

CA/B Forum Ballot SC-098v2 will require `accounturi` and `validationmethods` CAA parameters for all new issuances from March 2027. KrakenKey uses Let's Encrypt with `dns-01` challenges; no action is required for this action itself, but users who manage their own CAA records should add the required parameters before March 2027. See [RFC 8657](https://www.rfc-editor.org/rfc/rfc8657) for syntax.

### PKI Advisory — Chrome EKU Separation (effective 2026-06-15)

Chrome Root Program Policy v1.8, Section 1.3.2: TLS intermediates must be `serverAuth`-only. DigiCert and Sectigo intermediates that bundled `clientAuth` require re-issuance. Let's Encrypt E5/E6/R10/R11 intermediates are already compliant; certificates issued via this action are unaffected.

### PKI Advisory — Certificate Transparency Mandatory Logging (effective 2026-06-15)

Chrome Root Program Policy v1.8, Section 1.3.4.1: precertificate CT logging is mandatory before issuance for all Root Program participants. DigiCert removed CT opt-out settings from CertCentral on 2026-06-01. Let's Encrypt has always logged all certificates to CT by default; certificates issued via this action are already compliant. Certificate hostnames and SAN values are permanently public record in CT logs — this is by design for all publicly-trusted certificates.

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
