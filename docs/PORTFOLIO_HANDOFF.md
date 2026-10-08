# Portfolio handoff: version 2

The [existing portfolio page](https://www.ekopru.com/income-level-prediction-using-r/index.html) describes Esad Kopru's independent R learning project, links to [efkopru/ILPrediction](https://github.com/efkopru/ILPrediction), and contains 26 historical presentation images. Preserve that ownership and history. The original script and complete version 1 source/evidence snapshot remain under `archive/`.

The revised project's public repository is [efkopru/income-level-prediction](https://github.com/efkopru/income-level-prediction). This document supplies the portfolio update copy and assets from the completed version 2 run. Independent output auditing and visual inspection of all six PNG/PDF pairs are complete. The live website remains unchanged.

## Copy for the project page

### Title

Income Level Prediction Using R

### Short description

An R classification study comparing ridge logistic regression, a decision tree, a probability random forest, and a linear SVM against a majority baseline on historical UCI Adult records.

### My contribution

I built the original R learning project to compare classifiers for an income-category task. I later revised it into a reproducible workflow with explicit data handling, grouped cross-validation, locked package versions, model diagnostics, and results that distinguish classification, ranking, probability quality, and subgroup errors.

### Methods

I preserved the official training/test boundary, removed repeated training records with identical outcomes, and kept ambiguous predictor profiles with conflicting labels. Version 2 retains 32,537 training records and evaluates the same 16,255-record benchmark test subset used in version 1. Because the test file was already examined, this is a reused benchmark rather than fresh independent confirmation.

Model selection uses five folds grouped by all 14 raw predictor fields. Each fold learns its own imputation, category encoding, and scaling. Capital gain and loss receive fixed `log1p` transformations. Numeric education is retained; redundant text education and `fnlwgt` are excluded. All reported metrics are unweighted.

The comparison uses ridge logistic regression through `glmnet`, a decision tree through `rpart`, a 500-tree probability forest through `ranger`, a linear SVM through `e1071`, and a majority baseline. Settings are selected by mean fold balanced accuracy. Classification thresholds remain fixed at probability greater than 0.5 or an oriented SVM margin greater than zero.

Conditional uncertainty uses 1,000 paired bootstrap resamples of raw 14-field predictor-signature clusters. All models share each resample. Intervals describe variability in this reused test sample conditional on the fitted models; they exclude model-training, selection, prior-test-exposure, and population-shift uncertainty. All six pairs among the trained models are reported.

### Results

The version 2 run completed on October 8, 2026. Grouped training cross-validation preferred the probability random forest, with mean balanced accuracy of 78.32% versus 78.23% for the decision tree. The selected forest used 500 trees and 28 candidate columns per split. Other selected settings were ridge `lambda = 0.0001`, tree `cp = 0.0005`, and linear-SVM `cost = 10`.

| Model | Accuracy | Balanced accuracy | ROC AUC | Average precision |
| --- | ---: | ---: | ---: | ---: |
| Majority baseline | 76.38% | 50.00% | 0.5000 | 0.2362 |
| Ridge logistic regression | 84.66% | 75.79% | 0.8980 | 0.7354 |
| Decision tree | 86.42% | 77.92% | 0.8910 | 0.7615 |
| Probability random forest | 86.04% | 77.88% | 0.9090 | 0.7933 |
| Linear SVM | 84.80% | 75.94% | 0.8968 | 0.7357 |

On the reused benchmark test, the tree had the highest observed accuracy and balanced accuracy. The forest had the highest ROC AUC and average precision, plus the lowest Brier score (0.0971) and log loss (0.3137). The tree-minus-forest balanced-accuracy gap was 0.043 percentage points; its conditional 95% paired interval ranged from -0.523 to 0.626 points and included zero.

At its fixed threshold, the CV-preferred forest identified 2,397 of 3,840 positive records, missed 1,443, and produced 827 false positives. Its recall was 62.42%, despite ROC AUC of 0.9090. Forest probabilities required clipping for 2,156 records when calculating finite log loss. This numerical safeguard and the aggregate probability scores do not establish perfect calibration.

The [results report](evidence/v2-full-2026-10-08/report.md), [exact metrics](evidence/v2-full-2026-10-08/metrics.csv), [selected settings](evidence/v2-full-2026-10-08/selected_parameters.csv), and [paired differences](evidence/v2-full-2026-10-08/paired_differences.csv) support these values. Version 1 and original-slide scores remain separate experiments.

### Conclusion

The study shows why an income-classification comparison needs more than accuracy. Training cross-validation selected the forest, which provided the strongest observed ranking and lowest aggregate probability errors, while the tree achieved slightly higher test classification scores. The conditional interval did not establish a clear balanced-accuracy difference between them. The forest still missed more than one third of positive records at the declared threshold.

The contribution is a reproducible, inspectable comparison with explicit data handling, grouped selection, fixed-threshold error analysis, probability diagnostics, and conditional uncertainty. It does not establish a universal winner, a fairness certification, a current-income estimator, or a deployed system. The reused test sample limits independent confirmation.

### Limits

This is an educational evaluation of historical census-derived records. The retained test data were reused after an earlier project iteration, and matching predictor profiles are not verified person identities. The study does not estimate current income, population prevalence, or causal effects. Sex and race remain predictors; descriptive subgroup comparisons do not establish fairness or causal discrimination. The income threshold is historical and is not adjusted to current dollars.

### Tools

R 4.6.1; a 34-package `renv.lock`; `glmnet`, `ranger`, `rpart`, `e1071`, and `ggplot2`; automated regression checks; explicit input, source, protocol, and artifact manifests.

## Evidence and reproduction

The full [version 2 protocol](METHODOLOGY_V2.md) defines the experiment. The [validation record](VALIDATION.md) records the verification scope and limits. Numeric claims here refer to the completed version 2 aggregate export. Run diagnostics record 75 successful fits and no model warnings; all 18 offline checks passed.

Independent auditing verified the final and out-of-fold prediction metrics, 70 candidate-fold evaluations across 14 declared candidates, saved-model scoring checks, and file integrity. The completed run has 40 local files; the public export has 35. Provenance verification includes nine source/protocol/lockfile hashes, two input hashes, 34 package versions, the preserved version 1 snapshot, and the original script. All six PNGs and six rendered PDFs were visually checked for complete, readable content.

Commands from the repository root:

```sh
Rscript --vanilla scripts/install_dependencies.R
Rscript --vanilla tests/run_tests.R
Rscript --vanilla scripts/verify_evidence.R
Rscript --vanilla IncomeLevelPrediction.R --download --output results/v2-reproduction
Rscript --vanilla scripts/export_evidence.R results/v2-reproduction results/v2-reproduction-public
```

Use new run and export directories when rerunning. Both example destinations are local review copies under ignored `results/`; neither overwrites committed evidence. Current maintenance code records deviations from reference settings in `methodology.md`. Exact historical code is preserved under `archive/v2-2026-10-08`, with the complete original checkout available at commit `2ab72d12cf5290df1841da70b524740a70718c17`. The exporter requires a completed version 2 full run, official input checksums, successful model diagnostics, and artifact hashes and byte sizes that match the manifest. It copies a fixed allowlist and verifies the copies. Raw data, record-level and out-of-fold predictions, fold identifiers, model objects, session details, and local dependencies remain outside the public export.

Run provenance covers the entry point, six R modules, protocol, and lockfile, plus the two data inputs. Changes during execution prevent finalization. File integrity checks do not replace scientific review, figure inspection, or review of publication contents.

## Version 2 gallery assets

The six figures were generated in R with `ggplot2` and exported with the completed run. Every PNG is 2400 x 1500 pixels, and each matching PDF is a 12 x 7.5 inch vector export. All PNGs and rendered PDFs passed visual inspection, with no missing content or clipping. The links below point to the verified version 2 evidence files.

| Figure | PNG / PDF | Caption and alt text |
| --- | --- | --- |
| Model comparison | [PNG](evidence/v2-full-2026-10-08/model_comparison.png) / [PDF](evidence/v2-full-2026-10-08/model_comparison.pdf) | Accuracy, balanced accuracy, ROC AUC, and average precision for five classifiers on the reused Adult test sample, with conditional 95% cluster-bootstrap intervals. |
| ROC and precision-recall curves | [PNG](evidence/v2-full-2026-10-08/roc_pr_curves.png) / [PDF](evidence/v2-full-2026-10-08/roc_pr_curves.pdf) | ROC and precision-recall curves for five classifiers; SVM ranking uses oriented margins, and the precision-recall reference line shows test positive prevalence. |
| Confusion matrices | [PNG](evidence/v2-full-2026-10-08/confusion_matrices.png) / [PDF](evidence/v2-full-2026-10-08/confusion_matrices.pdf) | Confusion matrices showing class counts and within-class percentages for five classifiers at the fixed probability or margin thresholds. |
| Probability calibration | [PNG](evidence/v2-full-2026-10-08/calibration.png) / [PDF](evidence/v2-full-2026-10-08/calibration.pdf) | Observed versus predicted positive rates in fixed probability bins, with bin sizes and descriptive Wilson intervals for probability-producing models; SVM margins are excluded. |
| Grouped cross-validation | [PNG](evidence/v2-full-2026-10-08/cv_comparison.png) / [PDF](evidence/v2-full-2026-10-08/cv_comparison.pdf) | Balanced accuracy across the five grouped training validation folds for each model's selected settings, showing fold variability rather than independent confidence intervals. |
| Subgroup recall | [PNG](evidence/v2-full-2026-10-08/subgroup_recall.png) / [PDF](evidence/v2-full-2026-10-08/subgroup_recall.pdf) | Recall for recorded sex and race groups, with positive-class denominators and descriptive 95% Wilson intervals; these comparisons do not certify fairness. |

Copy assets from `docs/evidence/v2-full-2026-10-08/` into the portfolio assets directory. Preserve the PNG originals and offer the matching PDFs as accessible download links. Keep dataset attribution in the technical details. These plots belong to the revised project and must not be labeled as original historical slides.

Two [supplemental uncertainty figures](figures/v2-uncertainty-review/README.md) redraw the original aggregate tables without changing estimates or intervals. The updated metric comparison exposes narrow intervals; the paired-difference figure shows all six trained-model pairs across five metrics, with zero as the reference. Positive values mean model A minus model B. Use these in an explicitly labeled supplement with the same 2400 x 1500 dimensions and gallery behavior below. Preserve the original six-figure evidence gallery and identify the supplement as a presentation update, not a new model run.

## Layout and interaction specifications

Use a separate **Version 2 analysis** gallery. Give all six figures equal card widths, equal preview dimensions, and equal initial zoom. Place each PNG in a `16 / 10` container with `object-fit: contain`; do not crop axes, titles, legends, intervals, or captions. Use intrinsic image attributes `width="2400"` and `height="1500"`, responsive width, and automatic image height.

Use two columns above 800 CSS pixels and one column at or below 800 pixels. Check layouts at 360, 768, and 1280 CSS pixels. Preview dimensions and internal chart scale must remain consistent. Dense labels may require the full-size view; shrinking one figure differently to fit its preview is not acceptable.

Each image opens the full-resolution PNG in a keyboard-accessible viewer. Provide meaningful alt text, a visible caption, a named close button, Escape-to-close behavior, and focus restoration to the originating link. Keep visible keyboard focus and support zoom and fit-to-screen controls. Verify titles, axes, legends, interval labels, and subgroup denominators at full size.

Retain the 26 existing images in a separate **Original historical presentation** gallery. Preserve slide order, historical captions, the existing full-size viewer, and their 1440 x 810 preview ratio without cropping. Their historical accuracy figures are not version 2 results.

## Publication checks

- Match every result claim to the completed version 2 report, metric tables, selected settings, and uncertainty tables.
- Keep the reused-test disclosure visible beside the results. Keep unweighted sampling, conditional intervals, historical categories, and fixed-threshold errors in the technical details.
- Inspect all six PNGs and corresponding PDFs for missing labels, clipping, overlap, and readable chart text.
- Verify exported hashes and byte sizes, then inspect the publication tree for raw records, private paths, model files, secrets, and unsupported claims.
- Keep the original script and version 1 snapshot unchanged. Do not infer a version 2 improvement caused by one modification when several parts of the experiment changed.
- Preserve UCI attribution. Select a code license explicitly if open-source reuse is intended.
- When publication is authorized, verify the remote target, visibility, final uploaded contents, live source link, and matching gallery assets. A local successful run or configured CI workflow does not establish a remote publication or CI pass.

