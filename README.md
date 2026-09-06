# Leptonica WASM Distribution

Public distribution repository for verified Leptonica WebAssembly production builds.

Production packages are published to target-specific `release/<target_id>` branches. Each branch has a matching target-derived tag and GitHub Release so concurrent production targets cannot overwrite one another.

Target IDs are opaque publication identities supplied by the pinned source release contract. They intentionally do not reveal private variant IDs, domains, customers, or lock mappings.

Development builds are not published to this public repository. They are promoted only to the private source repository's fixed `release-dev` channel.

The public release metadata intentionally identifies a build only by `source_revision`, `release_id`, `target_id`, and `build_role`; it does not reveal the private source repository or variant mapping. Authorized operators map an existing branch, tag, or target ID back to its variant with the private source repository's historical release-set inspection command.
