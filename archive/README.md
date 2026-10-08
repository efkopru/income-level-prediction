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

No original authorship or deployment claim has been expanded by this modernization.
