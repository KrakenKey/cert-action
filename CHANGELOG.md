# Changelog

Notable changes to the KrakenKey cert-action. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/). Versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Fixed
- `auto-renew: 'false'` is now passed to the CLI as `--auto-renew=false`. Before, the action only passed the flag for `true`, so the certificate kept the API default (auto-renew on). Turning it off also needs a CLI release with the fix for KrakenKey/cli#60.
- `download` now sets the `cert-id`, `status`, `expires`, `domain` and other certificate outputs. They were empty because `krakenkey cert download` reports the saved file, not the certificate.
- GitHub OIDC errors no longer run the API's message into the hint ("...ref and environment Create one..."). (#39)

---

## [v1.4.0] — 2026-10-06

### Added
- GitHub OIDC authentication (#32). With no `api-key`, the action requests a GitHub OIDC token (the job needs `permissions: id-token: write`) and exchanges it with the KrakenKey API for a key that lasts 15 minutes and carries the repository's trust policy limits. New inputs `oidc-audience` (default `https://api.krakenkey.io`) and `trust-id`. `api-key` is no longer required. Errors say what to fix: a missing permission, no matching trust policy, a wrong audience, or several matching policies. Needs the KrakenKey API with GitHub OIDC support (KrakenKey/app).

### Documentation
- **Certificate Chain Files**: added a note on AIA chain repair: why a leaf-only deploy can pass a browser check and still fail in `curl`, Go or Java clients, and how to check the served chain with `openssl s_client`.
- **Usage Examples**: the basic deploy example now copies `fullchain-path` instead of the leaf-only `cert-path`, matching the guidance in Certificate Chain Files.
- **ACME challenge delegation**: Prerequisites now list the `_acme-challenge` CNAME each name on the certificate needs, and a new section covers the target format, wildcards, and what to do after a `delegation missing` or `delegation mismatch` failure (for `renew`, retry the failed certificate instead of running `renew` again).
- **Troubleshooting**: the timeout row now quotes the actual CLI message and explains that KrakenKey keeps working after `poll-timeout`. For `renew`, fetch the result with `command: download` instead of running `renew` again; for `issue`, raise `poll-timeout`.

### Advisory
- **SC104 (AIA relaxed to SHOULD)**: CA/B Forum ballot passed 2026-09-03 and takes effect once its IPR review ends and it is published in the Baseline Requirements. The `authorityInformationAccess` extension goes from MUST to SHOULD in TLS subscriber certificates, so a compliant leaf may carry no `caIssuers` URL for clients to fetch a missing intermediate from. `chain-path` and `fullchain-path` are unaffected (they come from the chain KrakenKey stores, not from an AIA fetch). Workflows that deploy `cert-path` alone should switch to `fullchain-path`.
- **SC100 (DNSSEC validation consolidation)**: CA/B Forum ballot passed 2026-08-06, published in Baseline Requirements v2.3.0 (2026-09-07). Consolidates the DNSSEC validation rules into BR section 4.2.2.2 and clarifies that mandatory validation applies to the CA's primary network perspective only. No change in CA behavior and nothing to change in workflows. If a `renew` or `issue` step fails on a DNSSEC-signed zone, a broken DS/DNSKEY rollover that makes the zone return `SERVFAIL` blocks issuance.
- **HARICA mass revocations** (July 2026): HARICA found 66,105 TLS certificates issued with a `clientAuth` EKU after its own CP/CPS cutoff and revoked 63,525 of them by 2026-07-20, then had to replace another batch by 2026-07-25 over a missing OCSP URL in AIA. HARICA is not this action's issuer (KrakenKey uses Let's Encrypt), but the same thing can happen to any CA. `if-due` looks only at the expiry date, so a scheduled `renew` with `if-due: true` will not replace a certificate the CA revoked early. Adding a `workflow_dispatch` trigger that runs `renew` without `if-due` gives you a way to force a renewal.

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
