# Validation record: version 2

The full run completed on October 8, 2026 and is preserved in `results/v2-full-2026-10-08`. Its reviewed aggregate export is [`evidence/v2-full-2026-10-08`](evidence/v2-full-2026-10-08/). The [results and conclusion](evidence/v2-full-2026-10-08/report.md), [declared protocol](METHODOLOGY_V2.md), and audit records document the published experiment. Its nine source files are preserved in the [version 2 source snapshot](../archive/v2-2026-10-08/README.md); current maintenance code has separate hashes. The complete [version 1 validation record](../archive/v1-2026-10-08/docs/VALIDATION.md) remains unchanged.

## Published experiment checks

| Check | Result |
| --- | --- |
| Offline regression suite | 18 checks passed, zero failures; R 4.6.1, `--vanilla`, C locale |
| Corrected reference-data smoke run | Completed on 1,199 training and 599 test records, three folds, 30 trees, 40 bootstrap replicates |
| Full run | Completed with 32,537 training and 16,255 reused-test records |
| Fitting diagnostics | All 70 cross-validation fits and five final fits succeeded; all ridge fits converged with finite coefficients |
| Model warnings | None recorded in the completed full run |
| Dependency verification | All 34 package versions match `renv.lock`; R 4.6.1 recorded |
| Independent prediction audit | Recomputed final, selected out-of-fold, subgroup, and profile metrics; maximum arithmetic difference `2.55e-15` |
| Saved-model inference | In a fresh R process, the first 25 retained test records across all five saved models produced identical classes and scores |
| Source and input provenance | Nine preserved version 2 source/protocol/lockfile hashes and both official input hashes and sizes match the completed run |
| Output integrity | All 39 local manifest entries and 34 public manifest entries match their hashes and byte sizes |
| Final graphics | All six 2400 x 1500 PNGs and six corresponding vector PDFs visually inspected |
| Historical preservation | All 30 version 1 snapshot SHA-256 entries and the original script SHA-256 match |

The suite covers parsing, label-independent test retention, training duplicate policy, grouped folds, fold-local preprocessing, model schemas and score orientation, fixed thresholds, tied-score AUC/AP, 100,000-row AUC arithmetic, probability scoring, paired cluster bootstrap, random-state preservation, CLI validation, candidate selection, out-of-fold coverage, saved-model inference, numeric serialization, pipeline generation, source/input guards, and export integrity.

A separate read-only review found no consequential issue in the revised selection, metric, uncertainty, reporting, or export logic. Its 100 randomized integer-weight, tied-score fixtures matched literal row expansion within `1e-12`. The corrected smoke run's final and selected out-of-fold metrics independently reproduced within `7.77e-16`. These checks supplement the full-run evidence; synthetic and smoke scores are not reported as benchmark results.

## Full-run configuration

| Setting | Recorded value |
| --- | --- |
| Runtime | R 4.6.1 on Windows; 34 locked packages |
| Seed and random generator | `12345`; Mersenne-Twister, Inversion, Rejection |
| Start / completion | `2026-10-08T13:53:26Z` / `2026-10-08T14:13:02Z` |
| Cross-validation | Five approximately stratified folds grouped by all 14 raw predictor fields |
| Candidate evaluations | 14 candidates across five folds, 70 fits |
| Selection criterion | Mean validation-fold balanced accuracy; declaration order breaks ties |
| Ridge logistic regression | Lambda `0.0001`, alpha `0` |
| Decision tree | Complexity `0.0005` |
| Probability forest | 500 trees, `mtry = 28`, minimum split-node size 10, one thread |
| Linear SVM | Cost `10`, oriented decision margins |
| Positive class and thresholds | `>50K`; probability `>0.5`, margin `>0`; exact ties predict `<=50K` |
| Observation weights | None |
| Bootstrap | 1,000 paired cluster resamples, seed `13345`, percentile intervals |

The original files contain 32,561 training and 16,281 test rows. The policy removes 24 identical complete training records, keeps the two conflicting-label records for one raw predictor signature, and excludes 26 test rows matching original training predictors. Six extra raw-signature repetitions remain in the test subset. There are 32,536 training groups and 16,249 test clusters. These signatures do not identify people or establish person-level independence.

The validation-fold class counts were independently checked:

| Fold | <=50K | >50K | Total |
| --- | ---: | ---: | ---: |
| 1 | 4,940 | 1,568 | 6,508 |
| 2 | 4,940 | 1,568 | 6,508 |
| 3 | 4,940 | 1,568 | 6,508 |
| 4 | 4,939 | 1,568 | 6,507 |
| 5 | 4,939 | 1,567 | 6,506 |

Every training raw signature stays in one validation fold. Every selected family has exactly one out-of-fold prediction per training row. These checks cover 162,685 selected out-of-fold predictions and 81,275 final test predictions.

## Results and interpretation

| Model | Accuracy | Balanced accuracy | Recall >50K | ROC AUC | Average precision |
| --- | ---: | ---: | ---: | ---: | ---: |
| Majority baseline | 76.38% | 50.00% | 0.00% | 0.5000 | 0.2362 |
| Ridge logistic regression | 84.66% | 75.79% | 58.96% | 0.8980 | 0.7354 |
| Decision tree | 86.42% | 77.92% | 61.82% | 0.8910 | 0.7615 |
| Probability random forest | 86.04% | 77.88% | 62.42% | 0.9090 | 0.7933 |
| Linear SVM | 84.80% | 75.94% | 59.14% | 0.8968 | 0.7357 |

Training cross-validation preferred the forest: mean balanced accuracy 0.7832, compared with the tree's 0.7823. On the reused test, the tree had the highest observed accuracy and balanced accuracy. The forest had the highest ROC AUC and average precision, and the lowest Brier score and log loss among probability-producing models. These are distinct criteria; they do not establish one universally superior model.

The tree-minus-forest balanced-accuracy difference is 0.043 percentage points, with a conditional 95% paired interval from -0.523 to 0.626 percentage points. That interval includes zero. The forest's balanced-accuracy interval is 77.07% to 78.70%, and its ROC-AUC interval is 0.9042 to 0.9142. At its fixed threshold the forest missed 1,443 of 3,840 positive records and produced 827 false positives.

All 25 metric intervals and 30 paired contrasts use 1,000 finite replicate estimates. The resamples are shared across models and operate on raw-signature clusters. Intervals condition on the fitted models and retained historical sample. They exclude training, selection, population-shift, prior-test-exposure, and unknown person-level uncertainty; pairwise intervals are not adjusted for multiple comparisons.

Probability scoring and calibration were independently recomputed. The forest's Brier score is 0.0971 and its log loss is 0.3137. Log-loss clipping affects 2,156 forest probabilities and 127 tree probabilities; ridge and majority probabilities require no clipping. This numerical handling is disclosed and does not establish perfect calibration. SVM margins receive neither probability scores nor a calibration plot.

The audit also reproduced 31 calibration bins, 35 subgroup rows and their Wilson intervals, and profile-sensitivity metrics. There are 2,953 test records with modeled raw profiles seen in training and 13,302 novel profiles. These are different case mixes, not randomized groups or verified repeated identities. Sex and race remain predictors; subgroup results do not certify fairness or establish causal discrimination.

## Graphics review

The reviewed figures are `model_comparison`, `roc_pr_curves`, `confusion_matrices`, `calibration`, `cv_comparison`, and `subgroup_recall`, each exported as a 2400 x 1500 PNG and a 12 x 7.5 inch PDF.

All six PNGs were visually checked against their supporting tables. All six PDF pages were rendered and visually inspected separately. Titles, axes, legends, values, subgroup denominators, and captions are complete and readable, with no missing content or clipping. Narrow metric intervals are available precisely in `metric_intervals.csv`; the comparison chart retains a common zero-to-one metric scale.

Poppler emitted local fallback-font warnings for Symbol and ArialUnicode during rendering. All used labels and symbols rendered correctly in the inspected pages. These are rendering-environment messages, separate from the full run's empty model-warning record.

## Integration repairs

- Forest prediction originally advanced the caller's random state. Supplying its recorded seed fixes that side effect.
- Default CSV formatting merged two adjacent forest scores in the initial smoke run, altering reconstructed average precision by approximately `2.03e-5`. All double-valued CSV fields now use 17 significant digits. The corrected full run reproduces its metrics from saved predictions.
- Model objects reloaded in a fresh R session lacked registered prediction methods until their backend package was loaded. Prediction now loads the required namespace explicitly.
- A figure caption incorrectly described stratified rather than cluster-bootstrap intervals. The caption was corrected before the final full run.

A preliminary full run was interrupted before test evaluation when the serialization defect was confirmed. The corrected implementation reran from the beginning with the same declared model search and thresholds. No settings were optimized against version 2 full-test outcomes.

## Artifact and publication boundaries

The full local directory contains 40 files, including its manifest. The public export contains 35 files: 33 allowlisted aggregate artifacts, its README, and its public manifest. All copied artifacts match their local originals. Preserved version 2 source and input hashes also match, and all recorded package versions match the archived lockfile.

The public export excludes raw records, final and out-of-fold predictions, split/fold identifiers, model objects, session details, local libraries, and temporary audit files. Exact predictions and model objects remain in ignored local directories. The original detailed prediction-audit helpers remain under ignored `tmp/`; their observed results are recorded here. The committed `scripts/verify_evidence.R` now makes public artifact and archived-source integrity checks repeatable without those local records.

The unchanged original script SHA-256 is `3ad3bb786273ca05425185d9cffe789960ce00d0feb317fcaa2aa246978dbb5f`. The 30-file version 1 snapshot and its evidence remain separately preserved. Results across versions reflect several simultaneous methodological changes and cannot identify the effect of any one change.

This record establishes local analysis validation. The public project repository is [efkopru/income-level-prediction](https://github.com/efkopru/income-level-prediction); subsequent hosted Windows/Linux check results are recorded in [GitHub Actions](https://github.com/efkopru/income-level-prediction/actions/workflows/check.yml). Publication preserves exact file bytes so that source and evidence hashes remain valid across Git checkouts. The live portfolio remains unchanged.

The official test file was already inspected in version 1; this remains a reused historical benchmark rather than fresh independent confirmation.

## Maintenance review

The maintenance revision preserves every original full-run artifact and all version 1 snapshot bytes. The nine exact version 2 source files are retained under `archive/v2-2026-10-08`; the original complete checkout is commit `2ab72d12cf5290df1841da70b524740a70718c17`. No full model refit, new model search, recalibration, or new uncertainty calculation was performed for this revision.

The main regression suite now has 20 passing checks. Added cases reject an impossible output parent before data loading or training, simulate denied write access, verify probe cleanup, and check default/modified run settings. The synthetic end-to-end case requests settings above the smoke limits and verifies that the recorded methodology contains effective values of 30 trees, three folds, and 40 bootstrap replicates. Custom inputs record unknown evaluation history rather than claiming the official benchmark's history.

The committed evidence verifier checks both public evidence directories, version 1 snapshot SHA-256 entries, preserved source hashes, declared input checksums and sizes, package records, the original script hash, and supplemental plotting provenance. Its standalone suite has 36 passing checks, including corrupt, missing, duplicate, unsafe-path, and inconsistent-provenance fixtures. These are file-integrity and metadata checks, not recomputation of private prediction records.

The supplemental figures redraw the unchanged aggregate estimates and interval endpoints. Eight plot checks passed locally; a ninth directory-alias case was explicitly skipped because this Windows sandbox denied junction creation. That symlink case is mandatory in Linux CI. The checks cover complete model/metric coverage, all 30 paired differences, sign orientation, symmetric axes, foreground intervals, source-table validation, and destination protection. Both PNGs and both PDF pages were visually inspected; PDF text fits within the page. Separate input, rendering-source, and figure manifests document this presentation update.

Run the maintenance checks from the project root:

```sh
Rscript --vanilla tests/run_tests.R
Rscript --vanilla scripts/verify_evidence.R
Rscript --vanilla tests/test_evidence_verifier.R
Rscript --vanilla tests/test_review_plots.R
```

The Windows/Linux workflow executes all four commands and the official-data smoke run. Hosted results are available on the pull request and in GitHub Actions. The live portfolio remains unchanged.

## Additional summary and results graphics

The additional gallery at `docs/figures/v2-results-summary` uses only verified public version 2 aggregate tables. It contains ten ggplot2 PNGs, one ten-page vector PDF, eleven derived statistics CSVs, an HTML gallery, a file guide, and provenance metadata: 29 files in total. No model fitting, threshold search, recalibration, or new bootstrap calculation was performed.

The new summary suite passed 24 offline checks under R 4.6.1 on Windows. Checks cover confusion-derived denominators, percentage-point and relative gains, preserved missing values, calibration weighting, CV selection arithmetic, subgroup and profile counts, paired-interval orientation, invalid input rejection, destination protection, and unchanged source evidence. An independent read-only review confirmed the derived statistics and interpretation limits.

`scripts/verify_results_summary.R` verified all 28 manifested output hashes and sizes, 20 input/source provenance records, eleven recomputed derived tables, ten catalog entries, and package-version metadata. The existing evidence verifier also passed for both historical runs, archived sources, and the earlier supplemental figures.

All ten PNGs were visually inspected at 2400 x 1500 pixels. All ten final PDF pages were rendered with Poppler and matched the inspected preview pages; extracted text stays within each 12 x 7.5 inch page. Local Poppler fallback-font messages did not produce missing labels or symbols. The HTML gallery was inspected at desktop and 390-pixel mobile viewport settings: text wraps, tables scroll within their containers, images preserve aspect ratio, and the page has no horizontal overflow. All 25 distinct local file links resolve.

Run the new offline checks from the project root:

```sh
Rscript --vanilla tests/test_results_summary.R
Rscript --vanilla scripts/verify_results_summary.R
```

Both commands have been added to the Windows/Linux workflow. These additional changes and outputs were validated locally; hosted CI has not run for this revision.
