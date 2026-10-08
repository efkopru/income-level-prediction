# Engineering audit for methodology version 2

Audit date: October 8, 2026. This audit examined the local R source, command-line entry point, dependency installer, tests, workflow, evidence exporter, documentation, and saved version 1 artifacts. It did not publish a repository or change the live portfolio.

## Baseline independently checked

- All 24 pre-existing offline regression checks passed under R 4.6.1 with `LC_ALL=C` and `Rscript --vanilla`.
- Every entry in the local full-run artifact manifest and public evidence manifest matched its recorded MD5 and byte size.
- Recomputed metrics from all 81,275 saved model predictions matched the saved figures to a maximum absolute difference of `4.44e-16`.
- The prior run's accuracy and ROC AUC arithmetic was valid for its evaluated sample size. The findings below distinguish defects from improvements to the experimental design.
- The unchanged legacy script remains in `archive/IncomeLevelPrediction_original.R`. The version 1 modern implementation is separately preserved in `archive/v1-2026-10-08/` so that replacing current code does not discard the source behind the prior evidence.

## Findings and remediation requirements

| Finding | Evidence | Required resolution |
| --- | --- | --- |
| ROC AUC overflow for larger evaluations | The old rank formula multiplied integer class counts. A 100,000-row fixture with 50,000 records in each class and perfect ranking returned `NA` instead of AUC 1. | Use double-precision count products and retain the 100,000-row regression check. |
| A seed alone did not fix the random generator | Identical seed 12345 under Mersenne-Twister and L'Ecuyer produced only four common indices in a 20-row validation subset. | Pin and record the RNG algorithms; use `--vanilla` in execution instructions and CI; verify independence from the caller's RNG choice. |
| Probability-forest prediction consumed the caller's random stream | The first version 2 integration run passed 15 checks and failed the random-state contract: forest fitting restored the state, but `ranger` prediction with its default seed changed it. | Supply an explicit deterministic prediction seed. The repaired implementation passes the cross-generator fit/predict state regression. |
| CSV output merged distinct probability scores | In a real-data smoke run, forest scores `0.39491679675822894` and `0.39491679675822888` serialized to the same value with ordinary `write.csv`. Recomputed average precision changed from 0.634138069723148 to 0.634158327160247; ROC AUC happened to remain unchanged because both observations were positive. | Serialize double columns with 17 significant digits, preserving missing values. Verify exact score round trips and average precision from saved predictions. |
| Deserialized models required manually loaded backend packages | In a fresh R process, `readRDS` followed by the prediction wrapper failed to dispatch the saved forest's prediction method until its package namespace was loaded. | Load the appropriate backend namespace inside the prediction wrapper and verify all five saved model families in a fresh R subprocess. |
| One validation split gave no estimate of selection stability | Model settings were chosen from one internal split and small search grids. | Use fold-local preprocessing and grouped stratified cross-validation, record each fold and every candidate, and report fold variability. |
| Conflicting-label rows were removed based on the outcome | Version 1 excluded two training rows sharing predictors but carrying opposite labels. | Retain distinct conflicting outcomes, remove exact full-record training duplicates, and keep matching raw-predictor groups in the same fold. |
| Model feature patterns repeat across the official partitions | In version 1, 2,953 of 16,255 test rows matched a retained training modeled-feature pattern; 1,165 of 6,506 validation rows matched an analysis pattern. | Describe the raw-predictor grouping scope and audit overlap of the predictors actually modeled. Do not equate matching coarse feature patterns with identified people. |
| Unpenalized logistic regression reported extreme fitted probabilities | The final version 1 fit converged but warned that fitted probabilities were numerically zero or one. | Evaluate a regularized logistic baseline and record model diagnostics for every cross-validation and final fit. |
| Point estimates alone did not show evaluation uncertainty | Existing charts and tables contained accuracy, balanced accuracy, and ROC AUC without intervals or paired comparisons. | Add deterministic paired cluster-bootstrap intervals, state their conditional nature, and preserve the historical benchmark-reuse limitation. |
| The dependency environment floated | The installer accepted installed versions or downloaded current missing packages; only selected dependency versions were recorded. | Retain an explicit dependency lock and a complete record of the environment actually used. |
| Export integrity checked hashes but omitted manifest sizes | Version 1 ignored the artifact manifest's `bytes` field. | Require well-formed size/hash metadata, completed-run status, expected artifacts, and acceptable model diagnostics before exporting. |
| Tests used synthetic exporter files rather than a completed analysis | Synthetic fixtures covered allowlisting and tampering, but did not connect pipeline generation to plotting and manifest creation. | Exercise a small end-to-end run and inspect its saved metrics, plots, and artifact manifest. Keep this distinct from the full-data evidence run. |

## Interpretation boundaries

Raw-predictor signatures are not person identifiers. Removing exact overlaps cannot establish unique-person, household, geographic, or temporal independence. Excluding the Census sampling-weight field from predictors means some different raw records have identical modeled covariates. Such coincidences alone do not prove leakage.

The official test benchmark has already been inspected in earlier project iterations. It remains outside the version 2 tuning functions, but it is a reused benchmark rather than a fresh confirmatory holdout. Cross-validation, grouped resampling, and confidence intervals do not erase that history.

Bootstrap intervals describe uncertainty conditional on the fitted models, retained historical sample, and stated grouping/resampling policy. They do not include retraining uncertainty or establish performance in current populations. Descriptive sex/race results and sensitive-feature choices do not certify fairness.

## Validation record

The completed version 2 offline suite passed **18 checks with zero failures** under R 4.6.1, `LC_ALL=C`, and `Rscript --vanilla`. It exercised the parser and duplicate policy, group boundaries, preprocessing isolation, analytic metrics and ties, 100,000-row AUC arithmetic, exact double-precision CSV round trips, probability scoring, model schemas and random-state preservation, fresh-process saved-model inference, SVM orientation, paired cluster-bootstrap calculations, CLI validation, full-grid cross-validation and out-of-fold coverage, complete synthetic-run generation, exporter integrity, and source/input provenance guards.

After the serialization repair, an independent Python standard-library calculation recomputed every final metric and every selected out-of-fold metric from the new real-data smoke run's CSV files. The maximum absolute difference from the recorded R values was `7.77e-16`; the forest average-precision discrepancy was eliminated. This verifies the repaired arithmetic and serialization on that smoke run, not the full benchmark results.

The synthetic run generated all 33 expected aggregate artifacts, six private artifacts, and its artifact manifest. Its six PNGs had the required 2400 by 1500 dimensions, and the six PDF outputs were present and nonempty. All manifest hashes and byte sizes matched. Metrics independently recomputed from saved predictions matched the generated metric table. These synthetic checks establish execution and consistency, not benchmark performance. Visual inspection of the actual full-run figures and verification of the actual full-run export remain separate requirements.

The exporter was tested against changed contents, changed byte sizes, unsafe manifest paths, smoke/incomplete/obsolete runs, false input provenance, unsuccessful fits, missing final models, and nonconverged or nonfinite ridge diagnostics. The allowlist excludes record-level predictions, out-of-fold predictions, split/fold identifiers, fitted models, and session details. A successful public export contains 33 copied aggregate artifacts, its generated README, and the public manifest: 35 files in total.

The completed full run and [public export](evidence/v2-full-2026-10-08/report.md) subsequently passed an independent Python standard-library audit. All 39 full-run manifest entries and 34 public-manifest entries matched both hashes and sizes, giving 40 local run files and 35 public files including the manifests. All nine recorded source/protocol/lockfile hashes, both official input hashes and sizes, 34 locked package versions, 30 baseline snapshot SHA-256 entries, and the original script's SHA-256 matched.

That audit recomputed metrics from all 81,275 final predictions and 162,685 selected out-of-fold predictions, including tied-score average precision, Brier score, and clipped log loss where applicable. It also checked subgroup and profile-sensitivity metrics, calibration counts and probabilities, and Wilson intervals. The largest absolute numerical difference from the recorded R results was `2.55e-15`.

All 14 candidate configurations had five recorded folds, all 70 fold evaluations agreed with the recorded selection rule, and matching raw-predictor groups stayed together. Training contained 32,537 records in 32,536 raw-predictor groups. Evaluation contained 16,255 records in 16,249 raw-predictor groups. All 25 metric intervals and 30 paired contrasts recorded 1,000 valid replicates, and all 75 fit-diagnostic rows passed the stated health checks. These are checks of recorded calculations and assignments, not independent regeneration of the bootstrap draws.

In a separate fresh R process, the actual saved model bundle reproduced every class and score for the first 25 retained test records across all five model families, with maximum score difference zero. All six full-run PNG headers reported 2400 by 1500 pixels, and all six PDFs had valid file envelopes. Header/envelope checks do not establish visual quality; figure inspection is recorded separately in the main validation record.

The current full-run diagnostics and evidence paths are recorded in [VALIDATION.md](VALIDATION.md). The version 1 verification above is preserved as an audit baseline; it must not be substituted for verification of version 2. The configured Windows/Linux GitHub workflow has not been executed remotely as part of this local audit.
