# Changelog

Notable changes to the KrakenKey cert-action. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/). Versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Release Pipeline

- Release workflow restricted to semver tags only (`v[0-9]+.[0-9]+.[0-9]+`); major-version pointer tags (e.g. `v1`) no longer re-trigger the pipeline.
- Structured release notes auto-generated via `.github/release.yaml` label categories (Features, Bug Fixes, Other Changes).
- Each release marked as latest via `make_latest: true`.

### PKI Advisory — SC-098v2 (CAA RFC 8657)

CA/B Forum ballot SC-098v2 passed 2026-05-13. All public CAs must enforce RFC 8657 CAA `accounturi` and `validationmethods` parameter extensions by **March 2027**.

This action issues certificates via Let's Encrypt using ACME DNS-01. If your domain's CAA record sets `validationmethods`, it must include `dns-01` for certificate issuance to continue after the enforcement deadline. CAA records without these parameters are unaffected.

### PKI Advisory — Chrome EKU Separation

**Enforced 2026-06-15.** TLS server intermediates may no longer carry `clientAuth` EKU alongside `serverAuth`. DigiCert and Sectigo retired multi-purpose intermediates. Let's Encrypt E5/E6/R10/R11 intermediates were already `serverAuth`-only — this action is not impacted.

### PKI Advisory — CT Mandatory Logging

**Enforced 2026-06-15** (Chrome Root Program Policy v1.8 §1.3.4.1). DigiCert removed CT opt-out settings from CertCentral on 2026-06-01. Let's Encrypt has always logged all certificates to public CT logs; this action is fully compliant.

Note: internal hostnames on publicly-trusted certificates are permanently visible in public CT logs. If your workflows issue certificates for internal hostnames on public CAs, those hostnames are in CT log history with no opt-out path.

### PKI Advisory — Let's Encrypt Merkle Tree Certificates (Post-Quantum Path)

Let's Encrypt announced on **2026-06-03** that their post-quantum issuance path will use Merkle Tree Certificates (MTC), not ML-DSA X.509 (RFC 9881). MTC uses Merkle inclusion proofs instead of a certificate chain; staging is planned for late 2026, production for 2027.

The `chain-path` and `fullchain-path` inputs and outputs of this action apply to the current X.509 chain model. They will not apply to MTC-issued certificates once that path goes live. No action is needed now; monitor [letsencrypt.org](https://letsencrypt.org) for the MTC timeline.

### Suggested next release

**v1.2.0** — minor: new release-pipeline behaviour documented above.

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
