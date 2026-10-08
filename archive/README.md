# Historical source

`IncomeLevelPrediction_original.R` preserves the original R script supplied with this project before modernization. It credits Esad Kopru as the author and is retained unchanged as evidence of the historical learning project.

Original script SHA-256:

```text
3AD3BB786273CA05425185D9CFFE789960CE00D0FEB317FCAA2AA246978DBB5F
```

The script contains a placeholder working directory, interactive analysis steps, inconsistent split handling, and evaluation defects described in the root README. It is not the supported entry point. The current workflow runs from the repository root with `Rscript --vanilla IncomeLevelPrediction.R`; its design is documented in the [version 2 protocol](../docs/METHODOLOGY_V2.md).

The original presentation, `A Comparative Analyses of Income Level Prediction.pptx.pdf`, is retained at the project root. The [existing portfolio page](https://www.ekopru.com/income-level-prediction-using-r/index.html) presents 26 historical slide images. Those images document the original analysis and must remain labeled as historical exploratory results. They are not output from the revised code.

## Version 1 snapshot

[`v1-2026-10-08`](v1-2026-10-08/) preserves the complete version 1 source and documentation snapshot, including its aggregate evidence, tests, dependency installer, and CI configuration. [`snapshot_manifest.csv`](v1-2026-10-08/snapshot_manifest.csv) records SHA-256 hashes for its 30 files. Snapshot contents remain unchanged; the original historical script remains separately preserved above.

Version 1 excluded two training rows with conflicting labels and used one internal validation split. Version 2 retains those rows, uses grouped cross-validation and fixed capital-value transformations, and changes logistic regularization and the forest implementation. The official test subset is reused. Differences between versions are not independent confirmation and cannot be attributed to one modeling change without a controlled comparison.

The current R 4.6.1 environment and 34-package `renv.lock` belong to version 2. They do not retroactively lock the archived version 1 environment. Consult the snapshot's own README, runtime records, and manifests when interpreting its results.

Two historical relative links no longer resolve from the relocated snapshot. The `archive/IncomeLevelPrediction_original.R` link in [`v1-2026-10-08/README.md`](v1-2026-10-08/README.md) and the `../archive/IncomeLevelPrediction_original.R` link in [`v1-2026-10-08/docs/CODE_REVIEW.md`](v1-2026-10-08/docs/CODE_REVIEW.md) both refer to the [original script preserved here](IncomeLevelPrediction_original.R). Their correct targets from those archived documents would be `../IncomeLevelPrediction_original.R` and `../../IncomeLevelPrediction_original.R`, respectively. This note supplies the corrected destinations while preserving the 30 snapshot files and their published hashes.

## Version 2 evidence source snapshot

[`v2-2026-10-08`](v2-2026-10-08/) preserves the nine source files recorded in the [published v2 source manifest](../docs/evidence/v2-full-2026-10-08/source_manifest.csv), byte for byte, before subsequent maintenance. It includes the entry point, six R modules, the methodology document, and `renv.lock`. It is a source-provenance snapshot for that completed run, not a second completed model run or a full checkout. Published evidence remains in [`docs/evidence/v2-full-2026-10-08`](../docs/evidence/v2-full-2026-10-08/).

Run `Rscript --vanilla scripts/verify_evidence.R` from the repository root to verify public artifact hashes and byte sizes, the version 1 SHA-256 snapshot, the original script's published SHA-256, both versions' source provenance, declared input references, and recorded package evidence. Version 1 source hashes resolve against `archive/v1-2026-10-08`; version 2 source hashes resolve against `archive/v2-2026-10-08`, not the maintained current source. The verifier uses base R 4.6.1 and the locked `renv` dependency and does not download inputs, install packages, fit models, or rewrite evidence. Input checks validate the published reference declarations; they do not claim to recheck absent raw data. Version 1 has observed package records without a lockfile; version 2 package records are checked against the preserved lockfile.

The verifier also checks the separately committed [supplemental uncertainty figures](../docs/figures/v2-uncertainty-review/) against their output manifest, aggregate input hashes, and current renderer and plotting-source hashes. This provenance is separate from the preserved full-run source.

The standalone fixture checks run with `Rscript --vanilla tests/test_evidence_verifier.R`. Both commands run in the Windows and Linux CI jobs before the existing offline tests and downloaded-data smoke run. CI also runs `Rscript --vanilla tests/test_review_plots.R` for the supplemental rendering checks.

No original authorship or deployment claim has been expanded by this modernization.
