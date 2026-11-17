# Organization API key backend readiness

Read-only findings from November 17, 2026. This is a review package, not approval or evidence of deployment.

## Tested candidate

- Source: `8d4a97007427119dbceb5df281146b59285373dc`, includes committed key-management implementation `d4632e9`.
- Main CI: https://github.com/abui-am/turtle-identification-be/actions/runs/44043096598, attempt 1; tests and image jobs succeeded. Development deployment was skipped.
- Image: `ghcr.io/abui-am/turtle-identification-be@sha256:c88fd89e83241aed8d5340bbd49de633f08ed0640f006a6ee02f2fb95d80f7c4`.
- Build artifact `build-manifest-1` is retained until February 15, 2027. No stable version tags, prepared release manifests, or production promotion runs exist. A release must be prepared before promotion, following backend release conventions.

## Production uncertainty and required access

Hosted OpenAPI omits key management and `/api/integration/v1` routes. Public GET `/api/v1/organization/api-key` returned HTTP 404. These checks do not prove authenticated runtime behavior.

The latest GitHub production deployment record identifies `d1d05120101e767c6d5e6688b4481e0ac2b6d080` (October 27). Backend recovery documentation records later manually patched immutable images and a `resource-overrides.yml`; the deployment record cannot establish the running image or database revision.

A narrow SSH check used the configured deployment variables with `BatchMode=yes` and `StrictHostKeyChecking=yes`. The host was reached, but authentication failed with `Permission denied (publickey,password)` (exit 255). No remote command executed. An authorized existing SSH identity/agent or operator-provided read-only output is needed for the running API image/digest, release marker and Alembic revision. Do not dump environment files or credentials.

## Candidate migration and change scope

The recorded baseline ends at migration 008. Relative to that baseline, the candidate adds:

- 009: nullable capture timestamps on identity and sighting photos.
- 010: matching-result snapshots and indexes.
- 011: nullable identity-photo embedding fingerprints.
- 012: organization API key digests and issuance metadata.

These migrations do not create keys or backfill fingerprints. The candidate also changes v2 APIs, matching/fingerprint behavior, storage/runtime and deployment processes. It is not an API-key-only release. Full recorded-baseline comparison:

https://github.com/abui-am/turtle-identification-be/compare/d1d05120101e767c6d5e6688b4481e0ac2b6d080...8d4a97007427119dbceb5df281146b59285373dc

Inspect actual live state before presenting a final production diff/migration approval. Follow `deploy/vps/README.md`, including tested immutable release preparation, PostgreSQL backup, ordered migrations, readiness checks and documented recovery. A changed schema can require manual recovery; image rollback alone is not a schema rollback. Preserve unrelated dirty backend documentation/archive files.

## QA organization and acceptance

Provision `AdaPenyu Integration QA`, slug `adapenyu-integration-qa`, owner name `Integration QA Owner`, owner email `qa@adapenyu.com`, `adopt_legacy_data:false`. Generate a strong password securely and retain it through a secure local credential handoff; do not put it in shell arguments, chat or logs.

Use `app.cli.bootstrap_organization --config-stdin --validate-only`, then the documented administrative provisioning command through private stdin. No public signup exists. Bootstrap sends no email, prints no credentials, rejects ownership/email conflicts and does not reset active-owner passwords. Do not substitute a different owner or reset an existing account when rerunning.

Retain only synthetic QA data. Issue a key through the Mac Settings screen, read a known synthetic turtle with `X-API-Key`, rotate and verify old-key rejection/new-key access, then revoke and verify rejection. Leave QA without an active key. Do not use operational organization keys.

## Current status

No releases, tags, deployments, credentials, QA organizations or database changes were created. Production rollout and live end-to-end acceptance remain pending access and concrete release review.
