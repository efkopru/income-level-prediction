# Version 2 published-run source snapshot

This folder preserves the nine files identified by the [published source manifest](../../docs/evidence/v2-full-2026-10-08/source_manifest.csv) for the completed version 2 run on 2026-10-08. Every preserved file matched that manifest's MD5 before it was copied. Files retain their original bytes and relative paths.

The snapshot includes `IncomeLevelPrediction.R`, the six modules in `R/`, `renv.lock`, and `docs/METHODOLOGY_V2.md`. This README is explanatory metadata and is not one of the nine recorded source files. This folder is not a complete historical checkout or a newly executed analysis.

The [published aggregate evidence](../../docs/evidence/v2-full-2026-10-08/) remains unchanged. Later maintenance belongs in the repository's active source files. `Rscript --vanilla scripts/verify_evidence.R`, run from the repository root, checks the published source hashes against this snapshot and checks the recorded package versions against this preserved lockfile. The [archive overview](../README.md) explains the checks and the separate version 1 provenance.

The official test subset was reused across project iterations. Preservation of source and output bytes establishes provenance and integrity; it does not establish an independent replication or a fresh confirmatory test.
