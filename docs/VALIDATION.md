# Validation record: versions 2 and 3

Version 3, a separate experiment with wider tuning grids, is recorded in [its own section](#version-3-experiment-november-14-2026) at the end of this record. The version 2 record below is unchanged by it.

The version 2 full run completed on October 8, 2026 and is preserved in `results/v2-full-2026-10-08`. Its reviewed aggregate export is [`evidence/v2-full-2026-10-08`](evidence/v2-full-2026-10-08/). The [results and conclusion](evidence/v2-full-2026-10-08/report.md), [declared protocol](METHODOLOGY_V2.md), and audit records document the published experiment. Its nine source files are preserved in the [version 2 source snapshot](../archive/v2-2026-10-08/README.md); current maintenance code has separate hashes. The complete [version 1 validation record](../archive/v1-2026-10-08/docs/VALIDATION.md) remains unchanged.

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

PR review found that automatic CSV row-name inference could discard an extra leading field while preserving the expected column names. Stored-table parsing now explicitly disables row-name inference and row filling. Nine rejection-suite checks cover valid originals and temporary copies, extra leading fields in statistics and catalog CSVs, duplicate headers, blank rows, truncated rows, fixture restoration, and unchanged published bytes. Corruption cases refresh fixture hashes first, ensuring the tests exercise CSV validation. A fresh end-to-end render reproduced all ten PNGs and eleven derived tables byte for byte.

All ten PNGs were visually inspected at 2400 x 1500 pixels. All ten final PDF pages were rendered with Poppler and matched the inspected preview pages; extracted text stays within each 12 x 7.5 inch page. Local Poppler fallback-font messages did not produce missing labels or symbols. The HTML gallery was inspected at desktop and 390-pixel mobile viewport settings: text wraps, tables scroll within their containers, images preserve aspect ratio, and the page has no horizontal overflow. All 25 distinct local file links resolve.

Run the new offline checks from the project root:

```sh
Rscript --vanilla tests/test_results_summary.R
Rscript --vanilla tests/test_results_summary_verifier.R
Rscript --vanilla scripts/verify_results_summary.R
```

The Windows/Linux workflow runs all three commands and creates a new summary from the published aggregates in an ignored CI directory. Hosted check results for each revision are recorded on [PR #2](https://github.com/efkopru/income-level-prediction/pull/2).

## Maintenance review: November 13, 2026

This revision changes figure rendering, script startup, and recorded run metadata. Data handling, model fitting, selection, metrics, and uncertainty calculations are unchanged. Every file under `docs/evidence` and `archive` remains byte-identical.

### Published numbers reproduce

No full refit had been run since publication. A full run of the previous revision (commit `44a5f70`) and a full run of this revision's pipeline modules were each compared with the published export, using the checksum-verified inputs, default settings, and R 4.6.1 on Windows. Both completed with no model warnings. In both, fifteen aggregate tables and the warning record matched the published files byte for byte: `metrics`, `metric_intervals`, `paired_differences`, `bootstrap_design`, `calibration`, `subgroup_metrics`, `profile_overlap`, `profile_sensitivity`, `cv_summary`, `selected_parameters`, `diagnostics`, `data_audit`, `unseen_categories`, `input_manifest`, and `package_versions`. `cv_metrics.csv` matched in all 70 rows and every column except `elapsed_seconds`, which records wall-clock fit time. The report, recorded methodology, run configuration, and source manifest differ because maintenance changed their wording and the source hashes.

### Figure rendering no longer depends on an unlocked package

`ggplot2::ggsave()` selects its PNG device at run time and uses `ragg` whenever that package is installed. `ragg` is not in `renv.lock`, yet a copy in the user library stays on the library path under `--vanilla`. With `ragg` 1.5.2 installed there, the previous revision rendered every PNG with different bytes, larger files, and shifted text. All ten summary PNGs differed from the committed files, and so did the five pipeline PNGs whose plotting code is unchanged since publication. Hiding the user library restored exact matches for all ten summary PNGs.

`R/plots.R` now names `grDevices::png` in one helper shared by the pipeline and both supplement generators. With `ragg` still installed, the ten summary PNGs and both uncertainty PNGs matched their committed files byte for byte before any plot was edited. The full run of this revision reproduced five of the six published pipeline PNGs exactly; the sixth, `model_comparison`, was deliberately redesigned in the earlier maintenance revision. These are same-platform identities: PNG bytes remain specific to the operating system that renders them. The earlier byte-for-byte statement in this record held because `ragg` was not on the library path for that render.

### Regenerated supplements

Both supplement provenance records hash their rendering sources, so both folders were regenerated from the unchanged published aggregates. In `v2-uncertainty-review`, both PNGs are unchanged and both PDFs differ only in their embedded creation and modification dates. In `v2-results-summary`, nine PNGs, all eleven derived tables, the figure catalog, the gallery page, and the file guide are unchanged; `01_performance_scorecard.png` and the chart book changed. Provenance, render-context, and manifest files changed in both folders, and each render context now names the PNG device.

The scorecard change is cosmetic. Its legend title overlapped the first colorbar tick label, and grid-line stubs showed between tiles. Cell values, colors, and text are unchanged. The revised PNG and the first chart-book page were visually inspected.

### Script startup and run metadata

R's Unix front end reports a script path with each space written as `~+~`. On Linux and macOS, each entry point would therefore resolve a nonexistent project root when the repository path contains a space. All eleven self-locating scripts now decode that form. This failure was not observed directly: the Windows front end passes spaces unchanged, and a run from a spaced path succeeded on the machine used here both before and after the change. Two new subprocess checks run the pipeline entry point and the evidence verifier from directories containing spaces. Both passed in the hosted Linux and Windows jobs. A pass shows that the scripts start from a spaced path on Linux; it does not show that the earlier code failed there.

New runs record `r_version` and `platform` in `run_config.txt`. Exported evidence previously named no base R version, because `package_versions.csv` covers lockfile packages only and `session_info.txt` stays local.

### Checks

| Check | Result |
| --- | --- |
| Main regression suite | 22 checks passed |
| Evidence verifier suite | 37 checks passed |
| Supplemental plot suite | 9 checks passed, none skipped |
| Results summary suite | 24 checks passed |
| Results summary verifier suite | 9 checks passed |
| `scripts/verify_evidence.R` and `scripts/verify_results_summary.R` | Passed after regeneration |

All suites ran locally under R 4.6.1 on Windows with `--vanilla`, `LC_ALL=C`, and `TZ=UTC`. The new device check renders one plot through the shared helper and directly on `grDevices::png` and requires identical bytes; against the previous `ggsave()` call it fails on a machine with `ragg` installed.

Hosted checks for commit `7704f7c` then passed in all four Windows and Linux jobs on [PR #3](https://github.com/efkopru/income-level-prediction/pull/3). Both platforms reported the same five check counts, with no plot check skipped, and completed the downloaded-data smoke run. Hosted results for later revisions are recorded on that pull request.

## Version 3 experiment: November 14, 2026

Version 3 is a new experiment, not a correction of version 2. A review of the published version 2 cross-validation results on November 13, 2026 found that every tuned family had selected the last candidate in its declared grid, so no grid bracketed the setting it chose. Version 3 widens every grid past that edge under the [version 3 protocol](METHODOLOGY_V3.md). Nothing in the version 2 record above, its evidence, or its source snapshot was changed.

### Declaration sequence

| Step | Record |
| --- | --- |
| Design approval | The owner approved the grids, the grid-position rule, and the versioning plan before any version 3 code was committed. |
| Correction before declaration | The approved proposal said that `cp = 0` ends the tree grid. `rpart` accepts negative `cp` and then keeps splits that `cp = 0` removes, so the owner approved one more candidate, the fully grown tree, declared as `cp = -1`. |
| Endpoint change before declaration | SVM `cost = 100` stopped at the solver's iteration limit in a training-only check, which the approved rule treats as a failure that stops the run. The owner approved `cost = 30` instead. |
| Protocol | Commit `94bec24` added `docs/METHODOLOGY_V3.md` on its own, before any version 3 run. |
| Implementation | Commit `5d0c2e1`. The first two full runs were made from an exact export of that commit. |
| Report correction | Commit `1cdea72` changed one sentence of generated report text, as the run history below records. The published run was made from an exact export of that commit; its source manifest records the same nine file hashes. |

### Training-only checks before declaration

These fits used training rows only and recorded elapsed time, whether `libsvm` reached its iteration limit, and tree size. No validation or test rows were scored, so none of them measured predictive performance.

| Fit | Training rows | Elapsed | Result |
| --- | ---: | ---: | --- |
| SVM `cost = 10`, fold 1 analysis rows | 26,029 | 20 s | Within the iteration limit |
| SVM `cost = 100`, fold 1 analysis rows | 26,029 | 147 s | Stopped at the iteration limit |
| SVM `cost = 10`, each fold's analysis rows | 26,029 to 26,031 | 32 to 34 s | Within the limit in all five |
| SVM `cost = 30`, each fold's analysis rows | 26,029 to 26,031 | 69 to 75 s | Within the limit in all five |
| SVM `cost = 10` and `cost = 30`, full training set | 32,537 | 61 s and 119 s | Within the limit |
| Tree `cp = 0.0005`, `0`, and `-1`, fold 1 analysis rows | 26,029 | 0.4 s each | 89, 398, and 1,189 leaves |
| Forest `mtry = 84`, 500 trees, fold 1 analysis rows | 26,029 | 192 s | Completed |

Elapsed times varied between checks and are not stable measurements: `cost = 10` on the fold 1 analysis rows took 20 s in the first check and 33 s in the second. The checks also establish a point about version 2: its selected SVM setting, `cost = 10`, finishes within the iteration limit on every fold and on the full training set. Version 2 could not have detected a fit stopped at that limit, because `e1071` reports it only as console text.

### Run history

Three full runs were started. Only the third is published.

| Run | Source | Launched (UTC) | Outcome |
| --- | --- | --- | --- |
| First | Exact export of commit `5d0c2e1` | `2026-11-14T10:02:56Z` | Stopped during the last of five folds when the session that launched it ended. No file had been written and no test row had been scored. |
| Second | The same export | `2026-11-14T19:50:47Z` | Completed at `2026-11-14T20:35:25Z` with 130 accepted fits and no warnings. Not exported: its generated report said the official test file "was examined in version 1" and omitted version 2. |
| Third, published | Exact export of commit `1cdea72` | `2026-11-14T20:40:51Z` | Completed at `2026-11-14T21:09:29Z` with 130 accepted fits and no warnings. |

Commit `1cdea72` corrected that report sentence and added a regression check for it. Among the nine recorded source files only `R/reporting.R` differs between the two commits. The commit changed no grid, setting, or protocol text, and no code that produces a fitted value, a selection, or a metric. The protocol requires an implementation defect to be corrected, documented, and rerun, so the second run was set aside and the run was repeated.

The second run's results, including its reused-test scores, had been inspected before the third run started. They could not alter it: the third run uses the same declared grids and settings as the second, and it reproduced the second run exactly. Of the 41 files in each run directory, 29 are byte-identical, including every aggregate table except `cv_metrics.csv`, all six PNGs, and the record-level predictions. `cv_metrics.csv` is identical in every column except wall-clock fit time. `report.md` differs only in the corrected sentence, `run_config.txt` only in its two timestamps, `source_manifest.csv` only in the hash of `R/reporting.R`, and the six PDFs only in their embedded dates. The saved model file, which stores those fit times, and the run manifest differ as a consequence.

The second run is kept locally in `results/v3-full-2026-11-14-superseded-report-wording`. It is not evidence and is not published.

### Published run checks

| Check | Result |
| --- | --- |
| Offline regression suite | 27 checks passed, zero failures; R 4.6.1, `--vanilla`, C locale |
| Official-data smoke run | Completed through the entry point before each of the two commits that changed the run's sources |
| Full run | Completed with 32,537 training and 16,255 reused-test records |
| Fitting diagnostics | All 125 cross-validation fits and five final fits were accepted; all 31 ridge fits converged with finite coefficients; all 21 SVM fits finished within the solver's iteration limit |
| Model warnings | None recorded |
| Dependency verification | All 34 package versions match `renv.lock`; `run_config.txt` records R 4.6.1 on `x86_64-w64-mingw32` |
| Reproduction of version 2 | All 70 version 2 fold records reappear in version 3 with identical values in every column except fit time and the selection flag; `data_audit`, `profile_overlap`, `unseen_categories`, `input_manifest`, and `package_versions` are byte-identical to version 2 |
| Selections and grid positions | Recomputed from the published fold scores by `scripts/verify_evidence.R`, in code separate from the pipeline; all seven grid-position records match |
| Independent prediction audit | Final metrics for all five models and all 25 selected fold records recomputed from the saved predictions with separate code; maximum arithmetic difference `2e-15`; Brier score, log loss, and clipping counts match exactly |
| Fixed thresholds | Every one of the 81,275 saved test predictions follows the declared rule: probability `> 0.5` or margin `> 0` predicts `>50K` |
| Saved-model inference | In a fresh R process, the five saved models reproduced all 16,255 saved test classes and scores exactly |
| Source and input provenance | The nine source, protocol, and lockfile hashes match commit `1cdea72` and the `archive/v3-2026-11-14` snapshot; both official input hashes and sizes match |
| Output integrity | All 40 local manifest entries and 35 public manifest entries match their hashes and byte sizes |
| Final graphics | All six 2400 x 1500 PNGs visually inspected; PDF checks are described under graphics review |
| Historical preservation | Every file that the previous revision held under `docs/evidence` and `archive` is byte-identical; version 3 only adds two directories |

The prediction audit and the saved-model check read record-level files that stay local, as in version 2. Their helper scripts and output are kept beside the local run directory. They are not part of the committed test suites.

### Full-run configuration

| Setting | Recorded value |
| --- | --- |
| Runtime | R 4.6.1 on Windows (`x86_64-w64-mingw32`); 34 locked packages |
| Seed and random generator | `12345`; Mersenne-Twister, Inversion, Rejection |
| Start / completion | `2026-11-14T20:40:54Z` / `2026-11-14T21:09:29Z` |
| Cross-validation | The same five folds as version 2: approximately stratified, grouped by all 14 raw predictor fields |
| Candidate evaluations | 25 candidates across five folds, 125 fits, then five final fits |
| Selection criterion | Mean validation-fold balanced accuracy; declaration order breaks ties |
| Ridge logistic regression | Lambda `0.00001`, alpha `0` |
| Decision tree | Complexity `0.0005`; minimum split 20, minimum leaf 7, maximum depth 30; 94 leaves in the final fit |
| Probability forest | 500 trees, `mtry = 28`, minimum split-node size 10, one thread |
| Linear SVM | Cost `30`, oriented decision margins; 11,660 support vectors in the final fit |
| Positive class and thresholds | `>50K`; probability `>0.5`, margin `>0`; exact ties predict `<=50K` |
| Observation weights | None |
| Bootstrap | 1,000 paired cluster resamples, seed `13345`, percentile intervals |
| Plateau margin | `0.001`, recorded in `run_config.txt` |

Data handling is unchanged from version 2: 32,537 training rows in 32,536 groups, 16,255 test rows in 16,249 clusters, and the same validation-fold class counts as in the version 2 table above. No training group is split across folds. Every selected family has exactly one out-of-fold prediction per training row.

### Selections and grid positions

Mean validation-fold balanced accuracy for every candidate, with the selection in bold:

| Family | Candidates in declared order |
| --- | --- |
| Ridge `lambda` | 0.1: 0.6981; 0.01: 0.7520; 0.001: 0.7578; 0.0001: 0.7579; **0.00001: 0.7580**; 0.000001: 0.7580 |
| Tree `cp` | 0.01: 0.7296; 0.005: 0.7393; 0.001: 0.7682; **0.0005: 0.7823**; 0.0001: 0.7734; 0.00005: 0.7703; 0.00001: 0.7693; 0: 0.7693; -1: 0.7632 |
| Forest `mtry` | sqrt: 0.7793; **third: 0.7832**; half: 0.7798; two thirds: 0.7793; all: 0.7787 |
| SVM `cost` | 0.1: 0.7569; 1: 0.7574; 10: 0.7580; **30: 0.7581** |

| Family | Selection | Position | Adjacent candidate | Mean fold margin | Folds higher, tied | Label |
| --- | --- | --- | --- | ---: | --- | --- |
| Ridge | `lambda = 0.00001` | `interior`, 5 of 6 | `0.0001` | 0.00011 | 3 of 5, 1 tied | `plateau` |
| Ridge | `lambda = 0.00001` | `interior`, 5 of 6 | `0.000001` | 0.00000 | 0 of 5, 5 tied | `plateau` |
| Tree | `cp = 0.0005` | `interior`, 4 of 9 | `0.001` | 0.01409 | 5 of 5 | `separated` |
| Tree | `cp = 0.0005` | `interior`, 4 of 9 | `0.0001` | 0.00885 | 4 of 5 | `separated` |
| Forest | `mtry = floor(p / 3)` | `interior`, 2 of 5 | `floor(sqrt(p))` | 0.00387 | 4 of 5 | `separated` |
| Forest | `mtry = floor(p / 3)` | `interior`, 2 of 5 | `floor(p / 2)` | 0.00342 | 5 of 5 | `separated` |
| SVM | `cost = 30` | `grid_edge`, 4 of 4 | `10` | 0.00013 | 3 of 5, 2 tied | `plateau` |

Stated plainly under the declared rule:

- The **tree** and **forest** selections are interior and bracketed, with separated margins on both sides. Both equal their version 2 selections. The version 2 tree setting, which looked as if it might sit on a rising slope, is the peak of the wider curve.
- The **ridge** selection is interior and bracketed, but on a plateau on both sides. `lambda = 0.00001` and `0.000001` have identical balanced accuracy in every fold, and declaration order gives the tie to the earlier candidate.
- The **SVM** selection is at a grid edge and is not bracketed. Its margin over `cost = 10` is a plateau. `cost = 100` could not be a candidate, because the solver does not finish there within its iteration limit.

No candidate was added, removed, or evaluated again after these results were seen.

### Reused-test results and interpretation

| Model | Accuracy | Balanced accuracy | Recall >50K | ROC AUC | Average precision |
| --- | ---: | ---: | ---: | ---: | ---: |
| Majority baseline | 76.38% | 50.00% | 0.00% | 0.5000 | 0.2362 |
| Ridge logistic regression | 84.66% | 75.78% | 58.96% | 0.8980 | 0.7354 |
| Decision tree | 86.42% | 77.92% | 61.82% | 0.8910 | 0.7615 |
| Probability random forest | 86.04% | 77.88% | 62.42% | 0.9090 | 0.7933 |
| Linear SVM | 84.81% | 75.95% | 59.14% | 0.8968 | 0.7357 |

Training cross-validation preferred the forest, as in version 2: mean balanced accuracy 0.7832 against the tree's 0.7823. The majority, tree, and forest rows of `metrics.csv` are byte-identical to version 2, because those families selected the same settings and each fit sets its own seed. The tree-minus-forest balanced-accuracy difference is therefore again 0.043 percentage points, with a conditional 95% paired interval from -0.523 to 0.626 percentage points.

The ridge and SVM rows differ from version 2 by one false positive each. Ridge has 918 false positives where version 2 had 917; the SVM has 900 where version 2 had 901. Their true-positive and false-negative counts are unchanged. All 25 metric intervals and 30 paired contrasts use 1,000 finite replicate estimates.

Version 3 widened four grids at once, so a difference between the versions cannot be attributed to one of those changes. A one-record difference on a test file that has now been evaluated three times is not evidence that a wider grid helps or harms. Neither version is preferred because of its test scores. The intervals remain conditional on the fitted models and the retained historical sample, with the same exclusions as in version 2.

### Graphics review

The six figures are the same six as in version 2, each exported as a 2400 x 1500 PNG and a 12 x 7.5 inch PDF. `R/plots.R` is unchanged from the previous revision. All six PNGs were visually checked against their supporting tables: titles, axes, legends, values, subgroup denominators, and captions are complete and readable, with no missing content or clipping.

The six PDFs were not rendered for visual inspection, because the machine used here has no PDF renderer. Each was checked to be a single page of 864 x 540 points, which is 12 x 7.5 inches, and its extracted text was compared with the matching PNG: titles, subtitles, panel and axis labels, printed values, subgroup denominators, legend entries, and captions are all present. Apart from their embedded dates, the six PDFs are byte-identical to those of the second run. These checks cover page size and text. They do not show that the vector drawing matches the PNG.

### Artifact and publication boundaries

The local run directory contains 41 files, including its manifest. The public export in [`evidence/v3-full-2026-11-14`](evidence/v3-full-2026-11-14/) contains 36 files: 34 allowlisted aggregate artifacts, its README, and its public manifest. The one artifact that version 2 does not have is `grid_position.csv`. All copied artifacts match their local originals. The nine source files of the run are preserved in the [version 3 source snapshot](../archive/v3-2026-11-14/README.md), and every recorded package version matches the lockfile preserved there.

The export excludes raw records, final and out-of-fold predictions, split and fold identifiers, model objects, and session details, as in version 2. No existing file under `docs/evidence` or `archive` was changed; `archive/README.md` therefore does not mention the version 3 snapshot, which carries its own README.

### Verifier, tests, and regenerated supplement

`scripts/verify_evidence.R` now also checks version 3: its 35 public artifact hashes and sizes, its nine source hashes against the snapshot, its declared inputs and package versions, and its run record of 130 accepted fits. It recomputes every version 3 selection and grid position from the published fold scores and requires every version 2 fold record to reappear unchanged. It also checks the version 2 run record of 75 accepted fits.

| Suite | Result |
| --- | --- |
| Main regression suite | 27 checks passed |
| Evidence verifier suite | 49 checks passed |
| Supplemental plot suite | 9 checks passed, none skipped |
| Results summary suite | 24 checks passed |
| Results summary verifier suite | 9 checks passed |
| `scripts/verify_evidence.R` and `scripts/verify_results_summary.R` | Passed |

The five checks added to the main suite cover the declared grid and its version 2 prefix, the fully grown tree and stated growth limits, the SVM iteration limit and the restoration of the message stream, the grid-position rule, and the carry-over of the version 2 protocol text. The twelve checks added to the verifier suite cover a corrupted source snapshot, a missing table, and ten republished version 3 files whose manifests were refreshed, so that only the content checks can accept or reject them. Recomputed fold means and margins are compared within `1e-12`, the tolerance the results-summary verifier already uses; every other field must match exactly.

Changing `scripts/verify_evidence.R` changes one hash recorded by the results-summary provenance, so `docs/figures/v2-results-summary` was regenerated from the unchanged version 2 aggregates. Its ten PNGs, eleven derived tables, catalog, gallery page, and file guide are byte-identical to the previous revision. Only `provenance.csv`, `artifact_manifest.csv`, and the embedded dates of `results_summary.pdf` changed. `docs/figures/v2-uncertainty-review` does not record that script and is unchanged.

All suites ran locally under R 4.6.1 on Windows with `--vanilla`, `LC_ALL=C`, and `TZ=UTC`.

Hosted checks for commit `ca08698` then passed in all four Windows and Linux jobs on [PR #4](https://github.com/efkopru/income-level-prediction/pull/4). Both platforms reported the same five check counts as the table above, with no plot check skipped, and completed the downloaded-data smoke run. On both, `scripts/verify_evidence.R` verified the version 3 evidence, recomputed all seven grid-position records, and found all 70 version 2 fold records reproduced, so the recomputation holds on Linux as well as on Windows. Hosted results for later revisions are recorded on that pull request.
