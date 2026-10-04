# Changelog

Notable changes to the KrakenKey cert-action. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/). Versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Documentation
- **Certificate Chain Files**: added a note on AIA chain repair — which clients fetch the AIA `caIssuers` URL and which never do, why `fullchain-path` is the correct deploy artifact regardless, and to verify with a non-AIA-fetching client.

### Advisory
- **SC100 — DNSSEC Validation Consolidation**: CA/B Forum ballot passed 2026-08-06, shipped in Baseline Requirements v2.3.0 effective 2026-09-07. Consolidates DNSSEC validation language into BR §4.2.2.2 and clarifies that mandatory DNSSEC validation applies only to a CA's Primary Network Perspective, not the Remote Network Perspectives used for Multi-Perspective Issuance Corroboration. No behavior change for CAs and no action for this action; relevant if a workflow's `renew` step fails on a DNSSEC-signed zone, where a `SERVFAIL` from the CA's primary perspective (during a DS/DNSKEY rollover, say) is a hard issuance block.
- **SC104 — AIA Relaxed to SHOULD**: CA/B Forum ballot passed unanimously 2026-09-03; IPR Review Period to 2026-10-03. `authorityInformationAccess` goes from MUST to SHOULD in the TLS subscriber certificate profile, and §7.1.2.7.7 gains an "If present" qualifier, so a compliant leaf may carry no `caIssuers` URL at all. No change to `chain-path` or `fullchain-path` behavior — both are populated from the chain KrakenKey delivers, not from an AIA fetch — but workflows deploying `cert-path` alone and relying on client-side chain repair should move to `fullchain-path`.
- **Mozilla Root Store Policy v3.1**: effective 2026-07-01; adds mass revocation planning (ballot SC-089), CP/CPS documentation requirements, and a five-year root key age cap. No action for Let's Encrypt subscribers.
- **HARICA CP/CPS drift, two chained mass revocations** (July 2026): a `clientAuth` EKU compliance lapse forced 66,105 revocations on 2026-07-20, followed by a missing OCSP AIA pointer incident forcing mass replacement by 2026-07-25. Not this action's issuer (Let's Encrypt), but it illustrates the operational case for CA-initiated renewal tolerance: workflows on a fixed `cron` absorb a forced mass renewal far worse than ones that also run on demand.
- **FreeRDP certificate validation bypass (CVE-2026-66402)**: fixed in FreeRDP 3.29.0 (2026-08-01). Client-side hostname-matching flaws (embedded-NUL SAN truncation, CN fallback ignoring a non-matching SAN, IP-literal targets matched against DNS SAN). Not an issuance defect; relevant only if a workflow deploys certificates to a FreeRDP-based gateway such as Guacamole or Remmina.

---

## [v1.3.0] — 2026-10-04

### Added
- `if-due` input for `renew`: renews only when the certificate is inside the plan's renewal window, so a daily schedule doesn't issue a new certificate on every run. Needs krakenkey-cli v0.7.0 or later. The new `renewed` output is `false` when nothing was renewed. The scheduled renewal example now runs daily with `if-due` and deploys only when `renewed` is `true`.
- Tests for the `renew` command with a fake CLI (`tests/renew_test.sh`) and for SAN input splitting (`tests/san_args_test.sh`), run in the Test workflow.

### Changed
- `renew` runs the CLI in a scratch directory. krakenkey-cli v0.7.0 saves `./<cn>.crt`, `.chain.crt` and `.fullchain.crt` after `renew --wait`; the action downloads to its own output paths, so those copies no longer end up in the workspace.
- `cert-id` and `status` outputs read the last JSON document that has the field, so a warning printed by the CLI before its result no longer breaks them.

### Fixed
- `san` input is now split on commas before it reaches the CLI. Each name is trimmed, empty entries are dropped, and every name is passed as its own `--san` flag. Previously the whole string went through as one SAN (for example `www.example.com,api.example.com`), so multi-domain certificates did not get the names the README describes.

---

## [v1.2.0] — 2026-09-04

### Fixed
- `renew` no longer swallows CLI errors — failures during renewal are surfaced with the CLI's error output, and certificate downloads only run after the wait for issuance succeeds. (#25)

### Changed
- Release pipeline: trigger restricted to `v[0-9]+.[0-9]+.[0-9]+` tags only; release notes auto-generated from CHANGELOG; `make_latest: true`.

### Advisory
- **SC-098v2 — CAA RFC 8657 Parameters**: `validationmethods` and `accounturi` CAA parameters; CA enforcement deadline March 2027; no cert-action config change required today.
- **Chrome EKU Separation**: serverAuth/clientAuth EKU separation enforced 2026-06-15; affects DigiCert/Sectigo chains; Let's Encrypt (used by this action) unaffected.
- **CT Mandatory Logging**: enforced 2026-06-15; DigiCert opt-out removed 2026-06-01; Let's Encrypt always CT-logged, no action required.
- **LE Merkle Tree Certificates**: announced 2026-06-03; staging late 2026, production 2027; MTC breaks the `chain.pem`/`fullchain.pem` model — `chain-path` and `fullchain-path` outputs will need updates before the LE production rollout.

### Build
- `softprops/action-gh-release` bumped to v3.0.3 (Node24 runtime), SHA-pinned. (#26)

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
