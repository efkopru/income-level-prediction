# Validation record

This record covers the revised local R implementation and the full run exported to [`evidence/full-2026-10-08`](evidence/full-2026-10-08/). It does not validate the original presentation's numeric results or imply a remote publication.

## Observed checks

| Check | Result |
| --- | --- |
| Offline regression suite | 24 passed, zero failed on R 4.6.1 |
| Final smoke run | Completed from outside the project directory with 1,199 training and 599 test rows; 30 forest trees |
| Full reference-data run | Completed with 32,535 training and 16,255 test rows; 200 forest trees |
| Aggregate evidence export | Completed; 16 files, including README and public artifact manifest |
| Independent output audit | Recomputed prediction metrics, partition membership, file hashes, byte sizes, and PNG dimensions successfully |
| Model-comparison figure | 2400 x 1500 pixels; visually inspected for readable labels, legend, and complete content |
| ROC figure | 2400 x 1500 pixels; visually inspected for readable labels, legend, and complete content |
| Original script preservation | SHA-256 matches the recorded original |

The offline suite checks parsing failures and missing values; label-independent overlap removal; deterministic stratified splitting; training-only preprocessing; unseen categories and constant columns; metric definitions and tied-score AUC; logistic probability thresholds and aliases; all five model families; SVM margin orientation; schema and option validation; parameter selection; output preservation; provenance changes; custom-input chart labeling; export exclusions and integrity; and evaluation that cannot change fitted models or their predictions when only test labels are changed.

Commands for reproducing the checks from the project directory:

```sh
Rscript --vanilla tests/run_tests.R
Rscript IncomeLevelPrediction.R --download --smoke --output results/smoke-check
Rscript IncomeLevelPrediction.R --download --output results/full-check
Rscript scripts/export_evidence.R results/full-check docs/evidence/full-check
```

Output directories must be new or empty. The completed local smoke output is `results/smoke-final-2026-10-08`; the completed full output is `results/full-2026-10-08`. The generic `Rscript` commands work when R is on the command path. The CLI also resolves its project files correctly when invoked by absolute path from another directory.

## Full-run configuration and data

The full run completed on October 8, 2026 at 00:59:18 America/Chicago; the stored UTC completion timestamp is `2026-10-08T05:59:18Z`.

| Item | Recorded value |
| --- | --- |
| Runtime | R 4.6.1, Windows 11 x64 |
| Seed | 12345 |
| Validation fraction | 0.2 |
| Analysis/validation rows | 26,029 / 6,506 |
| Final training/test rows | 32,535 / 16,255 |
| Selection metric | Validation balanced accuracy |
| Tree setting | `cp = 0.001` |
| Forest settings | `mtry = 9`, 200 trees |
| SVM setting | Linear kernel, `cost = 1` |
| Positive class | `>50K` |
| Classification thresholds | Probability `> 0.5`; oriented SVM margin `> 0` |
| Exact threshold ties | `<=50K` |
| Observation weights | None |
| Collation | C |

The official input files contained 32,561 training and 16,281 test rows. The predeclared duplicate policy excluded two training rows from one conflicting-label signature, 24 further training duplicates, and 26 test rows whose predictors matched the original training file. Six duplicate rows remain within the retained test partition. Signatures use all 14 raw predictor fields; they are not person identifiers or proof of entity independence. See [`data_audit.csv`](evidence/full-2026-10-08/data_audit.csv).

Input checksums match the recorded UCI reference files:

| File | MD5 |
| --- | --- |
| `adult.data` | `5d7c39d7b8804f071cdd1f2a7c460872` |
| `adult.test` | `35238206dfdf7f1fe215bbb874adecdc` |

Recorded modeling dependencies were `rpart 4.1.27`, `randomForest 4.7.1.2`, `e1071 1.7.17`, and `proxy 0.4.29`. These are observed versions, not an environment lockfile.

## Held-out results

| Model | Accuracy | Balanced accuracy | ROC AUC |
| --- | ---: | ---: | ---: |
| Majority baseline | 76.38% | 50.00% | 0.5000 |
| Logistic regression | 85.27% | 76.57% | 0.9040 |
| Decision tree | 85.89% | 75.63% | 0.8862 |
| Random forest | 86.40% | 77.69% | 0.8922 |
| Linear SVM | 85.27% | 76.34% | 0.9027 |

The random forest had the highest accuracy and balanced accuracy among these models on this split. Logistic regression had the highest ROC AUC. These are distinct evaluation criteria and do not establish a universally best model. Exact values, confusion counts, recall, precision, specificity, and F1 appear in [`metrics.csv`](evidence/full-2026-10-08/metrics.csv). Settings were selected using training validation data and then refitted before final evaluation.

## Independent artifact audit

A separate Python audit verified all 18 entries in the local run manifest and all 15 entries in the public manifest against their MD5 hashes and byte sizes. Including the manifests themselves, the run contains 19 files and the public export contains 16. Current source and input hashes match the completed run.

The audit independently recomputed confusion counts, accuracy, balanced accuracy, and ties-aware ROC AUC from all 81,275 predictions, matching the saved metrics within `1e-12`. Training and test identifiers were disjoint, with 32,535 and 16,255 records respectively, and every model scored the same test set. Both PNG headers confirmed 2400 x 1500 pixels. The export excludes row-level records, model objects, and session details; the original script checksum remains unchanged.

## Logistic-regression diagnostics

The final logistic model converged in 13 iterations, with `boundary = FALSE` and rank 84. The training design identified `occupation___MISSING__` as a structural alias and dropped it before fitting. The recorded warning was:

```text
glm.fit: fitted probabilities numerically 0 or 1 occurred
```

This warning occurred during validation and final fitting; the warnings file stores the distinct message once. No nonconvergence warning was reported. Convergence does not establish probability calibration, coefficient stability, or causal interpretability. The unpenalized logistic model remains a predictive baseline. See [`warnings.txt`](evidence/full-2026-10-08/warnings.txt).

## Provenance and publication boundaries

The workflow snapshots source and input checksums before fitting and checks them again before finalizing the run. Changed or missing files cause a failure rather than a finalized result with mismatched provenance. Source hashes are in [`source_manifest.csv`](evidence/full-2026-10-08/source_manifest.csv); input hashes are in [`input_manifest.csv`](evidence/full-2026-10-08/input_manifest.csv).

The exporter verifies the completed run's artifact hashes, requires full mode and official reference inputs, copies a fixed allowlist, verifies the copied files, and writes [`public_artifact_manifest.csv`](evidence/full-2026-10-08/public_artifact_manifest.csv). The 16-file public export contains aggregate results, plots, settings, and provenance. It excludes raw data, row-level predictions, split identifiers, model objects, machine-specific session details, and local dependencies. Predictions, split identifiers, model objects, and session details remain in the full local run under the ignored `results/` directory; raw data and dependencies remain in their separate ignored directories.

The original script's SHA-256 was verified as:

```text
3AD3BB786273CA05425185D9CFFE789960CE00D0FEB317FCAA2AA246978DBB5F
```

GitHub Actions is configured for Windows and Linux using release R. This workflow has not been executed remotely. This work did not initialize Git, push a repository, change repository visibility, or edit the live portfolio. The local checks do not demonstrate those remote actions.

This is a single-split, unweighted evaluation of historical data. It includes sex and race as predictors and descriptive subgroup metrics, without fairness certification, causal claims, or deployment validation. Historical presentation scores are not directly comparable to this revised evaluation.
