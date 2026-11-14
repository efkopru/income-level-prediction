# Version 3 published-run source snapshot

This folder preserves the nine files identified by the [published source manifest](../../docs/evidence/v3-full-2026-11-14/source_manifest.csv) for the completed version 3 run on 2026-11-14. Every preserved file matched that manifest's MD5 when it was copied. Files retain their original bytes and relative paths.

The snapshot includes `IncomeLevelPrediction.R`, the six modules in `R/`, `renv.lock`, and `docs/METHODOLOGY_V3.md`. This README is explanatory metadata and is not one of the nine recorded source files. The run was made from an exact export of commit `1cdea7269d892f6ade4147c840a7427a1a612356`. This folder is not a complete historical checkout or a newly executed analysis.

The [published aggregate evidence](../../docs/evidence/v3-full-2026-11-14/) remains unchanged. Later maintenance belongs in the repository's active source files. `Rscript --vanilla scripts/verify_evidence.R`, run from the repository root, checks the published source hashes against this snapshot and the recorded package versions against this preserved lockfile. It also recomputes every version 3 selection and grid position from the published fold scores, and checks that every version 2 fold record reappears unchanged in version 3.

The version 1 snapshot, the version 2 snapshot, and their evidence are preserved separately and were not changed by version 3. The [archive overview](../README.md) was left byte-identical, so it predates version 3 and does not describe this folder. The official test subset was reused across project iterations, and version 3 is its third evaluation. Preservation of source and output bytes establishes provenance and integrity; it does not establish an independent replication or a fresh confirmatory test.
