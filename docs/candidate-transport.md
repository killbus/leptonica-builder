# Candidate Transport Operations

## Scope

The public builder executes every source-dispatched target, including `dev` and `prod`. Cross-job candidate transport uses `envelope-v1` so that plaintext candidate payloads are not uploaded as public workflow artifacts. Protection applies only to transport; the final package published to the source-private `release-dev` channel is a normal plaintext package.

Public workflow and UI labels use neutral terms: **prepare**, **materialize**, **promote**, and **finalize**. Technically, `envelope-v1` provides authenticated confidentiality and integrity through the pinned upstream `age` X25519 format.

## Required GitHub Configuration

Configure these values before enabling dispatched builds:

| Scope | Name | Purpose |
|---|---|---|
| `Candidate Build` environment variable | `CANDIDATE_MATERIALIZATION_RECIPIENT` | Public age X25519 recipient used to prepare candidate transport. |
| `Candidate Build` environment variable | `CANDIDATE_MATERIALIZATION_KEY_ID` | Public, non-secret identifier for the active recipient. |
| `Candidate Promotion` environment variable | `CANDIDATE_MATERIALIZATION_KEY_IDS` | Comma- or whitespace-separated allowlist of supported key IDs. |
| `Candidate Promotion` environment secret | `CANDIDATE_MATERIALIZATION_IDENTITIES` | One or more age identity lines used only while materializing accepted candidates. |
| Repository secret | `SOURCE_REPOSITORY` | Private control-plane route in `owner/repository` form, used only for source checkout and dev publication. |
| `Candidate Build` environment secret | `SOURCE_READ_DEPLOY_KEY` | Read-only access used to checkout the private compilation source. |
| `Candidate Promotion` environment secret | `SOURCE_RELEASE_DEPLOY_KEY` | Write access used only after the prepared dev release tree is complete. |

The source repository dispatch payload supplies only public contract fields: source revision, release ID, target IDs, build roles, expected outputs, and transport profile. The builder must not accept `BUILD_VARIANT`, `PRODUCT_LOCK`, customer, domain, private variant IDs, or `target_seed`. `SOURCE_REPOSITORY` is trusted control-plane configuration, not provenance: it must not appear in dispatch payloads, release-set manifests, candidate or accepted evidence, transport metadata, prepared package files, release notes, tags, branches, artifact names, or workflow logs. Do not replace it with a hash; repository names are low-entropy identifiers.

## Provisioning

1. Install the same pinned age release used by `ci/install-age.sh` on a trusted administrative machine.
2. Generate an X25519 identity and derive its public recipient.
3. Choose a neutral public key ID such as `candidate-2026-07`.
4. Store the recipient and key ID in the `Candidate Build` environment variables.
5. Store the identity in the protected `Candidate Promotion` environment secret.
6. Add the key ID to `CANDIDATE_MATERIALIZATION_KEY_IDS`.
7. Require deployment approval for `Candidate Promotion` when organizational policy requires a human gate.

Never commit identities, place them in dispatch payloads, upload them as artifacts, or echo them in workflow logs. Keep source checkout and source publication on separate deploy keys; the build key must be read-only, and the release key must not be available during candidate package installation or build scripts. The final private `release-dev` package is materialized plaintext for normal consumption, but it still contains no private source repository owner/name; authorized operators resolve opaque target IDs through private source-repository tooling instead of public builder metadata.

## Rotation and Revocation

For routine rotation:

1. Generate a new identity/recipient pair and a new key ID.
2. Add the new identity to `CANDIDATE_MATERIALIZATION_IDENTITIES` while retaining the previous identity.
3. Add both IDs to `CANDIDATE_MATERIALIZATION_KEY_IDS`.
4. Switch `CANDIDATE_MATERIALIZATION_RECIPIENT` and `CANDIDATE_MATERIALIZATION_KEY_ID` to the new pair.
5. Wait until all transports created under the previous key have either promoted or expired.
6. Remove the previous key ID and identity.

For emergency revocation, remove the compromised identity and key ID immediately and replace the active build recipient. In-flight transports for the revoked key must fail closed and be rebuilt under the replacement key.

## Retention and Cleanup

Candidate transport, evidence, and acceptance artifacts use one-day retention. The release workflow deletes each candidate transport only after successful promotion. Deletion failure emits a warning but does not mark an already completed publication as failed, preventing retry from creating a duplicate publication. Retention expiration is the cleanup fallback.

The materialization identity file is removed by a step-local exit trap immediately after materialization, with the final `always()` cleanup as a fallback. Candidate package installation and build scripts run only in the unprivileged build job, which has no source write key or write-capable GitHub credential. The protected promotion job never executes candidate package scripts: it verifies and materializes an already-built static package, assembles the release tree with trusted shell, `jq`, and `git` commands, and only then introduces publication credentials. Materialized and prepared plaintext trees are removed in the final `always()` cleanup step.

## Publication Routing

- The sole `dev` target publishes only to the source-private `release-dev` branch/tag and never creates a public builder GitHub Release.
- Every `prod` target publishes to `release/<target_id>` in the public builder repository.
- Production versions and tags include the complete opaque target digest: `1.0.0-<source7>.<target-hash64>` and `v1.0.0-<source7>.<target-hash64>`.
- Multiple production targets therefore cannot overwrite one another. Opaque target IDs do not disclose their private variant, domain, or customer mapping.

## Retry and Failure Behavior

- Invalid schemas, unknown key IDs, wrong identities, metadata substitution, digest mismatch, wrong release/target/role, or artifact identity mismatch stop before publication.
- A failed materialization can be rerun while the immutable transport and accepted evidence still exist and the key remains supported.
- A failed source-private push or public release can be rerun against the same immutable release and target identity.
- Before pushing, promotion checks that the triggering run is still the latest successful `repository_dispatch` build on `main`; ordinary push-only contract-test runs do not supersede a dispatched release.
- Target-derived refs make promotion idempotent for the same source revision and target. Dev intentionally replaces its fixed private `release-dev` channel.
- Cleanup failure is observable but does not invalidate a publication that already succeeded.

## Rollback

Disable the `Candidate Promotion` environment or the release workflow to stop promotion without changing accepted evidence. A builder rollback must pin a known builder revision and rebuild the same source contract; it must not accept artifacts or manifests from another run, release ID, target ID, or source revision.
