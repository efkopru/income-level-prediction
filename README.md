# Income Level Prediction Using R

A reproducible R comparison of a majority baseline, ridge logistic regression, a decision tree, a probability random forest, and a linear SVM on the [UCI Adult dataset](https://archive.ics.uci.edu/dataset/2/adult).

Esad Kopru built the original project as an independent learning exercise. Version 2 revised its evaluation and added grouped cross-validation, probability diagnostics, conditional uncertainty, and traceable outputs. Version 3 repeats the version 2 design with tuning grids widened past every setting version 2 selected. Both versions are reported. The [original script](archive/IncomeLevelPrediction_original.R) and [complete version 1 snapshot](archive/v1-2026-10-08/README.md) remain preserved.

**Scope:** a historical, unweighted classification study. The official test file was already examined in versions 1 and 2, so version 3 evaluates a **reused benchmark test** for the third time, not a fresh independent confirmation. This is not a current-income estimator or deployed decision system.

## Run the project

Use **R 4.6.1**. The checked-in `renv.lock` records 34 package versions, including `glmnet`, `ranger`, `rpart`, `e1071`, and `ggplot2`. From the repository directory:

```sh
Rscript --vanilla scripts/install_dependencies.R
Rscript --vanilla tests/run_tests.R
Rscript --vanilla scripts/verify_evidence.R
Rscript --vanilla IncomeLevelPrediction.R --download --smoke --output results/v3-smoke
Rscript --vanilla IncomeLevelPrediction.R --download --output results/v3-full
```

The installer restores recorded packages into the ignored project-local `.R-library` as needed. It requires internet access. The workflow verifies all locked package versions before fitting. `--vanilla` prevents restored workspaces and startup profiles from affecting execution.

Downloading is explicit. `--download` fetches `adult.data`, `adult.test`, and `adult.names` into `data/raw` and checks their recorded UCI hashes. Existing files supplied with that flag must also match. With local data:

```sh
Rscript --vanilla IncomeLevelPrediction.R --data-dir data/raw --output results/v3-local
```

Compatible custom inputs can run without `--download`; their reports and figures are marked as custom when their hashes differ. They cannot be exported as official-reference portfolio evidence.

| Option | Default and purpose |
| --- | --- |
| `--seed` | `12345`; deterministic random operations |
| `--trees` | `500`; probability-forest trees |
| `--folds` | `5`; grouped training cross-validation folds |
| `--bootstrap` | `1000`; paired raw-signature cluster-bootstrap replicates |
| `--smoke` | Sampled execution check with reduced computation |
| `--help` | Full command usage |

A smoke run uses at most 1,200 training and 600 test rows, 30 trees, three folds, 40 bootstrap replicates, and the first candidate per family. Its scores are not full-study evidence.

Default paths are project-local. Without `--output`, the output is `results/v3-YYYYMMDD-HHMMSS` using UTC. Explicit relative paths resolve from the invocation directory. Nonempty output directories are refused; use a new directory for each run. Creation and write access are checked before downloading or training.

Each new run's `methodology.md` compares effective settings with the historical reference plan and records smoke sampling or custom inputs. Overrides define a separate configuration. Matching the four numeric defaults alone does not establish that source code, inputs, or environment match the published experiment.

## Evaluation design

The detailed [version 2 protocol](docs/METHODOLOGY_V2.md) was written before the version 2 full run, after version 1 results had been inspected. It records the search grids, metric definitions, uncertainty assumptions, and interpretation limits. The [version 3 protocol](docs/METHODOLOGY_V3.md) was committed before the version 3 full run, after version 1 and 2 results had been inspected. It carries over the version 2 text except for the wider grids, stated tree growth limits, an SVM convergence check, and a rule for reporting where each selection sits in its grid. The design below applies to both versions.

- Preserve the official training/test boundary. Remove only identical full training records, retaining two conflicting-label rows for one raw predictor signature. This leaves 32,537 training records.
- Exclude test records matching any original training signature across all 14 raw predictor fields, without consulting test labels. Retain 16,255 test records and their remaining repeated signatures. Signatures are not person identifiers.
- Use five training folds grouped by those raw signatures, approximately balancing class counts. Fit imputation, category encoding, and scaling inside each analysis fold. Select settings by mean validation-fold balanced accuracy, then refit on all eligible training records.
- Apply fixed `log1p` transformations to capital gain and loss. Keep numeric education; exclude text education and `fnlwgt`. All models receive the same encoded predictor matrix. Report unweighted sample metrics.
- Keep classification thresholds fixed: probability `> 0.5` or oriented SVM margin `> 0` predicts `>50K`; ties predict `<=50K`. Test labels do not select grids, settings, or thresholds.

| Model | Implementation | Version 2 candidates | Version 3 adds |
| --- | --- | --- | --- |
| Majority baseline | Constant training prevalence | No tuning | No tuning |
| Ridge logistic regression | `glmnet`, positive ridge penalty, training-only standardization | `lambda` 0.1, 0.01, 0.001, 0.0001 | 0.00001, 0.000001 |
| Decision tree | `rpart`; minimum split 20, minimum leaf 7, maximum depth 30 | `cp` 0.01, 0.005, 0.001, 0.0005 | 0.0001, 0.00005, 0.00001, 0, and the fully grown tree (`cp = -1`) |
| Probability random forest | `ranger`, 500 trees, one thread | `mtry` = floor(sqrt(p)), floor(p / 3) | floor(p / 2), floor(2p / 3), p |
| Linear SVM | `e1071`, oriented uncalibrated decision margins | `cost` 0.1, 1, 10 | 30 |

Each run selects one candidate per family. Numerical nonconvergence or nonfinite ridge coefficients stop the run. In version 3, an SVM fit that reaches the `libsvm` iteration limit also stops the run; version 2 could not detect that condition. The forest operates on encoded columns rather than native categorical fields.

## What is measured

Accuracy, balanced accuracy, precision, recall, specificity, F1, confusion counts, ROC AUC, and average precision describe different aspects of classification and ranking. Average precision uses stepwise recall increments at tied-score thresholds; it is not trapezoidal PR area. Undefined metrics remain `NA`.

Probability-producing models also receive Brier scores, log loss, and ten-bin calibration summaries. SVM margins receive no probability metrics or calibration curve. Calibration plots are descriptive and do not fit a correction.

The default 1,000 paired bootstrap replicates resample clusters defined by all 14 raw predictor fields. Every model uses the same sampled clusters. Reported 95% percentile intervals and all six pairs of trained-model differences are **conditional on the fitted models and this reused test sample**. They exclude training and selection variability, prior test exposure, population shift, and unknown person-level dependence. They are not multiplicity-adjusted significance tests.

Recorded sex and race remain predictors. Subgroup tables include denominators and descriptive Wilson intervals. Separate matched-profile and novel-profile summaries use the 12 modeled raw fields without dropping either group. These checks do not certify fairness, establish causal discrimination, or identify repeated people.

## Version 2 results and conclusion

The full run completed on October 8, 2026 with 32,537 training and 16,255 reused-test records, seed `12345`, five folds, 500 forest trees, and 1,000 bootstrap replicates. The [results report](docs/evidence/v2-full-2026-10-08/report.md) and [exact metrics](docs/evidence/v2-full-2026-10-08/metrics.csv) are exported separately from version 1.

Training cross-validation preferred the probability random forest: mean balanced accuracy was 78.32%, compared with 78.23% for the tree. Selected settings were ridge `lambda = 0.0001`, tree `cp = 0.0005`, forest `mtry = floor(p / 3)` (28 columns in the final fit), and SVM `cost = 10`.

Each selected setting is the last candidate in its declared grid, so no grid brackets the value it chose. This matters most for the tree: its mean fold balanced accuracy rose from 76.82% to 78.23% between its final two `cp` values, while ridge and SVM scores had already flattened. Widening a grid would be a new experiment under a new protocol, not a correction to this one. Version 3, reported below, is that experiment.

| Model | Accuracy | Balanced accuracy | ROC AUC | Average precision |
| --- | ---: | ---: | ---: | ---: |
| Majority baseline | 76.38% | 50.00% | 0.5000 | 0.2362 |
| Ridge logistic regression | 84.66% | 75.79% | 0.8980 | 0.7354 |
| Decision tree | 86.42% | 77.92% | 0.8910 | 0.7615 |
| Probability random forest | 86.04% | 77.88% | 0.9090 | 0.7933 |
| Linear SVM | 84.80% | 75.94% | 0.8968 | 0.7357 |

The tree had the highest observed test accuracy and balanced accuracy. The CV-preferred forest had the highest ROC AUC and average precision, and the lowest Brier score (0.0971) and log loss (0.3137). The tree-minus-forest balanced-accuracy difference was only 0.043 percentage points, with a conditional 95% paired interval of -0.523 to 0.626 points. That interval includes zero; it does not establish a clear balanced-accuracy advantage.

At its fixed threshold, the forest missed 1,443 of 3,840 positive records and produced 827 false positives. Its recall was 62.42%. Strong ranking therefore did not eliminate classification errors. For log-loss calculation, 2,156 forest probabilities required clipping at the declared numerical bounds; lower aggregate probability error does not establish perfect calibration.

**Conclusion:** the reproducible comparison exposes tradeoffs among classification, ranking, probability quality, and subgroup errors. It supports the declared CV selection while preserving observed test differences and uncertainty. It does not establish a universal winner or independent confirmation on a fresh population.

The published run records 75 successful fits and no model warnings; its 18-check regression suite passed before publication. Independent auditing reproduced the saved prediction metrics and selection results, verified the manifests, and checked restored-model scoring. All six PNGs and all six rendered PDFs passed visual inspection. The [validation record](docs/VALIDATION.md) separates that historical validation from subsequent maintenance checks.

## Version 3 results

Version 3 asks one question of version 2: does a wider grid move any selection? It reruns the same design on the same records, folds, and seed, with 25 candidates in place of 14. Every version 2 candidate is among them, and all 70 version 2 fold records reappear unchanged in version 3. The full run completed on November 14, 2026 with 130 successful fits and no model warnings. The [results report](docs/evidence/v3-full-2026-11-14/report.md), [exact metrics](docs/evidence/v3-full-2026-11-14/metrics.csv), and [grid positions](docs/evidence/v3-full-2026-11-14/grid_position.csv) are exported separately from version 2, whose results above are unchanged.

### Where each selection sits in its grid

Three of the four selections are interior to their grids. The SVM selection is not.

| Model | Version 2 selection | Version 3 selection | Position in the version 3 grid | Mean fold margin over each adjacent candidate |
| --- | --- | --- | --- | --- |
| Ridge logistic regression | `lambda = 0.0001` | `lambda = 0.00001` | Interior, 5th of 6 | 0.0001 over `0.0001` and 0.0000 over `0.000001`: plateau on both sides |
| Decision tree | `cp = 0.0005` | `cp = 0.0005` | Interior, 4th of 9 | 0.0141 over `0.001` and 0.0088 over `0.0001`: separated on both sides |
| Probability random forest | `mtry = floor(p / 3)` | `mtry = floor(p / 3)` | Interior, 2nd of 5 | 0.0039 over `floor(sqrt(p))` and 0.0034 over `floor(p / 2)`: separated on both sides |
| Linear SVM | `cost = 10` | `cost = 30` | Grid edge, 4th of 4: not bracketed | 0.0001 over `10`: plateau |

The labels follow the rule declared in the [version 3 protocol](docs/METHODOLOGY_V3.md) before the run. A margin is the mean of the five paired fold differences in balanced accuracy, and a margin below 0.001 is labeled a plateau. The labels describe the fold scores; they are not significance tests.

- **Tree.** The version 2 setting was the peak of the curve, not a point on a rising slope. Mean fold balanced accuracy is 76.82% at `cp = 0.001`, 78.23% at `0.0005`, 77.34% at `0.0001`, and 76.32% for the fully grown tree.
- **Forest.** The version 2 rule is selected again, with lower means on both sides: 77.93% at `floor(sqrt(p))` and 77.98% at `floor(p / 2)`, against 78.32%.
- **Ridge.** The selection moved one step along a flat curve. Its fold balanced accuracies equal those at `0.000001` in all five folds, and the earlier candidate wins an exact tie by declaration order.
- **SVM.** The selection moved to the new last candidate, so the grid still does not bracket it, and the mean gained only 0.0001 from `10` to `30`. The grid could not be widened further: at `cost = 100` the solver stopped at its iteration limit in a training-only check, which the protocol treats as a failed fit.

### Reused-test results

| Model | Accuracy | Balanced accuracy | ROC AUC | Average precision | Against version 2 |
| --- | ---: | ---: | ---: | ---: | --- |
| Majority baseline | 76.38% | 50.00% | 0.5000 | 0.2362 | Identical |
| Ridge logistic regression | 84.66% | 75.78% | 0.8980 | 0.7354 | 918 false positives, was 917 |
| Decision tree | 86.42% | 77.92% | 0.8910 | 0.7615 | Identical: same setting |
| Probability random forest | 86.04% | 77.88% | 0.9090 | 0.7933 | Identical: same setting |
| Linear SVM | 84.81% | 75.95% | 0.8968 | 0.7357 | 900 false positives, was 901 |

Training cross-validation again preferred the forest, at 78.32% against 78.23% for the tree. The tree and forest are the same fitted settings as in version 2, so every version 2 statement about them above holds for version 3 without change. The ridge and SVM settings each moved one candidate along a plateau, and each differs from its version 2 confusion counts by a single false positive among 16,255 test records.

Version 3 widened four grids at once, so differences between the versions cannot be attributed to one change. A net difference of one false positive is also not evidence that a wider grid helps or harms: the test file has now been evaluated three times, and neither version is preferred because of its test scores. What version 3 adds is on the training side. The tree and forest selections are now bracketed, the ridge selection sits on a plateau, and the SVM selection remains at a grid edge that this solver cannot extend.

The version 3 run records 130 successful fits, including 21 SVM fits that finished within the solver's iteration limit, and no model warnings. Its six PNGs were visually inspected. The [validation record](docs/VALIDATION.md#version-3-experiment-november-14-2026) lists the checks, the declaration sequence, and two earlier attempts that were not exported.

## Evidence and figures

Each run saves the selected settings, fold scores, model diagnostics, evaluation tables, plots, input/source manifests, package versions, and a written results-and-conclusion report.

The verified version 2 run contains 40 local files. Its aggregate export contains 35 files, including its public manifest; row-level predictions, fold identifiers, model objects, and session details are excluded. The version 3 run contains 41 local files and its export 36; the additional file is `grid_position.csv`.

| Evidence | Main files |
| --- | --- |
| Results and selected settings | `report.md`, `metrics.csv`, `selected_parameters.csv` |
| Grouped model selection | `cv_metrics.csv`, `cv_summary.csv`, `diagnostics.csv`, and in version 3 `grid_position.csv` |
| Conditional uncertainty | `metric_intervals.csv`, `paired_differences.csv`, `bootstrap_design.csv` |
| Probability and subgroup checks | `calibration.csv`, `subgroup_metrics.csv` |
| Profile sensitivity | `profile_overlap.csv`, `profile_sensitivity.csv` |
| Data and provenance | `data_audit.csv`, `input_manifest.csv`, `source_manifest.csv`, `package_versions.csv`, `run_config.txt`, `methodology.md` |
| Local-only detail | `predictions.csv`, `oof_predictions.csv`, `fold_assignments.csv`, `split_assignments.csv`, `models.rds`, `session_info.txt` |

Six `ggplot2` figures are exported as **2400 x 1500 PNGs** and matching **12 x 7.5 inch vector PDFs**:

| File stem | Contents |
| --- | --- |
| `model_comparison` | Four metrics and conditional bootstrap intervals |
| `roc_pr_curves` | ROC and precision-recall curves |
| `confusion_matrices` | Class counts and within-class percentages |
| `calibration` | Probability reliability, bin sizes, and descriptive intervals |
| `cv_comparison` | Training-fold variability for selected settings |
| `subgroup_recall` | Recall by recorded sex and race with denominators and intervals |

PNGs are drawn on base R's `grDevices::png` device, named explicitly in `R/plots.R`. Left to choose, `ggsave()` switches to `ragg` whenever that package is installed, including outside the locked project library, which changes text metrics and every PNG byte. PNG bytes still depend on the operating system that renders them; the committed PNGs were rendered on Windows.

The workflow snapshots nine source, protocol, and lockfile hashes plus input hashes before fitting, then verifies them again before finalizing. Changed files prevent successful finalization. Run and public manifests record output hashes and byte sizes. New runs also record the R version and platform in `run_config.txt`. The published version 2 run predates those two fields; its R 4.6.1 runtime is recorded in the [validation record](docs/VALIDATION.md). The version 3 run records both.

The [preserved version 2 source](archive/v2-2026-10-08/README.md) matches the published run's nine source hashes. Current maintenance code has different hashes. A full rerun of the maintained code on November 13, 2026 reproduced every published aggregate table byte for byte, apart from wall-clock fit times in `cv_metrics.csv`; the [validation record](docs/VALIDATION.md) lists the files compared. `scripts/verify_evidence.R` checks committed evidence and archived provenance on both CI platforms without downloading records or fitting models. For version 3 it checks the run against the [preserved version 3 source](archive/v3-2026-11-14/README.md), recomputes every selection and grid position from the published fold scores, and requires all 70 version 2 fold records to reappear unchanged. For the complete original checkout, use publication commit `2ab72d12cf5290df1841da70b524740a70718c17` in a separate checkout.

The [supplemental uncertainty figures](docs/figures/v2-uncertainty-review/README.md) redraw the same saved estimates and intervals with clearer markers and all paired comparisons. They do not replace the original figures or report a new experiment.

![Paired model differences with conditional 95% intervals](docs/figures/v2-uncertainty-review/paired_differences.png)

### Additional results summary

The [new results gallery](docs/figures/v2-results-summary/index.html) contains **ten additional ggplot2 charts and eleven downloadable statistics tables**. Open the HTML file locally for the complete gallery, use the [file guide](docs/figures/v2-results-summary/README.md) on GitHub, or read the [ten-page PDF chart book](docs/figures/v2-results-summary/results_summary.pdf).

Charts cover the performance scorecard, classification errors, gains over baseline, precision and recall, probability quality, calibration gaps, all thirteen trained tuning configurations, subgroup errors, model-profile sensitivity, and sample composition. Additional statistics include errors per 1,000 records, MCC, negative predictive value, relative error reduction, average-precision lift, and Brier skill. All PNGs are **2400 x 1500 pixels**, with matching vector PDF pages.

These are descriptive views of the same verified published results. No models, thresholds, calibration corrections, or bootstrap intervals were re-estimated. Recreate the supplement with installed project dependencies and a new output directory:

```sh
Rscript --vanilla scripts/create_results_summary.R docs/evidence/v2-full-2026-10-08 results/new-results-summary
Rscript --vanilla tests/test_results_summary.R
Rscript --vanilla tests/test_results_summary_verifier.R
Rscript --vanilla scripts/verify_results_summary.R
```

![Seven-metric performance scorecard](docs/figures/v2-results-summary/01_performance_scorecard.png)

## Export aggregate evidence

After completing and inspecting a full run:

```sh
Rscript --vanilla scripts/export_evidence.R results/v3-full results/v3-full-public
```

Use the actual run directory and a new destination; the example matches the full-run command above and keeps the review copy in ignored `results/`. The exporter verifies artifact integrity, complete version 3 status, official input checksums, and successful model diagnostics, including SVM fits that finished within the solver's iteration limit. It copies a fixed allowlist of aggregate outputs and checks the copied files. Read the run-specific methodology before interpreting an export with modified settings. Record-level predictions, fold identifiers, fitted models, and session details stay local.

The default `data/raw/`, `results/`, and `.R-library/` directories are ignored by Git. Custom output directories require separate publication review. A checksum match establishes file integrity, not scientific validity or privacy review.

## Project history and layout

The original script mixed cleaned and uncleaned row indices, trained some models on evaluation records, applied a probability-style threshold to log odds, and used class labels in a ROC calculation. The [code review](docs/CODE_REVIEW.md) records those findings.

Version 1 corrected that workflow. Version 2 changes training retention, selection, transformations, logistic regularization, and the forest implementation. Score differences cannot be attributed to one change without a controlled comparison. Version 3 keeps the version 2 design and widens four tuning grids at once, so its differences from version 2 cannot be attributed to one grid either. Historical screenshots remain evidence of the original learning exercise.

```text
IncomeLevelPrediction.R          Command-line entry point
R/                              Data, models, evaluation, plots, reporting
renv.lock                       R and package version record
scripts/                        Restore, export, verification, supplemental plots
tests/                          Offline regression checks
data/README.md                  Source and processing policy
docs/METHODOLOGY_V2.md           Declared version 2 protocol
docs/METHODOLOGY_V3.md           Declared version 3 protocol
docs/VALIDATION.md               Observed checks and limits
docs/PORTFOLIO_HANDOFF.md        Copy and image specifications
archive/                        Original script, v1 snapshot, published v2 and v3 sources
```

The revised project is maintained in the public repository [efkopru/income-level-prediction](https://github.com/efkopru/income-level-prediction). Hosted Windows/Linux check results are available in [GitHub Actions](https://github.com/efkopru/income-level-prediction/actions/workflows/check.yml).

The [existing portfolio page](https://www.ekopru.com/income-level-prediction-using-r/index.html) still links to the historical [efkopru/ILPrediction](https://github.com/efkopru/ILPrediction). The live portfolio has not been changed; the [portfolio handoff](docs/PORTFOLIO_HANDOFF.md) contains the revised copy and assets.

## Attribution and code rights

Becker, B. and Kohavi, R. (1996). *Adult*. UCI Machine Learning Repository. [doi:10.24432/C5XW20](https://doi.org/10.24432/C5XW20). Data license: [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).

The historical labels, sampling, income threshold, and category definitions limit transfer to current populations. No code license has been selected; the data license does not license this project's code.

