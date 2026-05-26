# Changelog

Notable changes to the KrakenKey cert-action. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/). Versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Developer Notes
- Release workflow (`.github/workflows/release.yaml`) now restricts the trigger to semver tags matching `v[0-9]+.[0-9]+.[0-9]+`. Major-version pointer tags (e.g., `v1`) no longer re-trigger the pipeline.
- GitHub release notes are now auto-generated using `.github/release.yaml` changelog category labels (Features, Bug Fixes, Other Changes).
- Each release is now automatically marked as `latest` via `make_latest: true`.

### Compatibility Advisory — CAA Records (March 2027)
CA/Browser Forum **ballot SC-098v2** (passed 2026-05-13) requires all public CAs to enforce RFC 8657 CAA parameter extensions (`accounturi`, `validationmethods`) by **March 2027**. KrakenKey cert-action issues certificates via Let's Encrypt using ACME DNS-01.

If your domain's CAA record sets `validationmethods`, ensure `dns-01` is included:
```
0 issue "letsencrypt.org; validationmethods=dns-01"
```
A record restricting to `http-01` or `tls-alpn-01` only will block issuance via this action once enforcement begins. CAA records without the `validationmethods` parameter are unaffected.

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
