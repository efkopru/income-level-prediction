# Additional results summary

Open `index.html` for the responsive gallery and statistics, or `results_summary.pdf` for the ten-page chart book.
All ten PNGs are 2400 x 1500 pixels; the PDF pages are 12 x 7.5 inches. These additional views use verified published aggregates without changing the original evidence.

## Results

- The decision tree made 2,208 classification errors, versus 2,270 for the forest. Its error count was 42.5% lower than the majority baseline's.
- The forest had the highest observed ROC AUC (0.9090) and average precision (0.7933). Its 62.42% recall still left 1,443 of 3,840 >50K records undetected.
- Relative to the tree, the forest found 23 additional positive records and produced 85 additional false positives at the fixed thresholds.
- Training cross-validation preferred the forest by 0.095 percentage points of mean balanced accuracy over the tree. These are selection scores, not independent performance estimates.
- The tree-minus-forest test balanced-accuracy difference was 0.043 percentage points; the saved conditional 95% paired interval was -0.523 to 0.626 points. It includes zero and does not establish equivalence.
- Probability error, calibration, classification, and ranking describe different properties. A constant prevalence predictor can have a small binned calibration error while providing no ranking information.

## Figures

| Figure | Reading purpose |
| --- | --- |
| [Seven metrics give complementary views of performance](01_performance_scorecard.png) | Read a column down to compare models on that metric. Values across unlike metrics are not a composite ranking. |
| [False negatives outnumber false positives in every model](02_classification_errors.png) | Compare error types within a model, then compare models on the common count scale. Different actual-class sizes prevent reading counts as rates. |
| [Every trained model improves on the majority baseline](03_improvement_over_baseline.png) | The left panel measures absolute accuracy improvement; the right panel measures the fraction of baseline mistakes avoided. Units differ. |
| [Precision and recall describe the saved decisions](04_precision_recall_tradeoff.png) | Higher precision and recall describe this fixed decision rule. The chart does not tune thresholds or establish a superior threshold policy. |
| [Probability quality improves beyond the constant baseline](05_probability_quality.png) | Lower values are better within each score. Probability quality includes both calibration and discrimination; clipping affects log loss. |
| [Calibration gaps show overprediction and underprediction](06_calibration_gaps.png) | Positive gaps indicate overprediction and negative gaps underprediction. Large intervals signal sparse bins; a constant baseline can match prevalence. |
| [All 13 trained configurations in the validation search](07_hyperparameter_search.png) | Selected means maximize the declared training-CV selection metric within each family. Fold spread is descriptive and selection-biased, not a confidence interval. |
| [Random forest errors vary across historical groups](08_subgroup_errors.png) | Group estimates describe this historical sample. Inspect interval width and positive/negative denominators before comparing rates; this is not fairness certification. |
| [Test results differ between seen and novel model profiles](09_profile_sensitivity.png) | The profile subsets differ in case mix and prevalence. Their differences do not isolate causality or show that matching records are the same people. |
| [Sample retention and class balance define the denominators](10_sample_composition.png) | Each retention share is relative to raw rows, while class shares are relative to retained rows. Counts across these panels should not be summed. |

## Statistics

- [model_summary](model_summary.csv)
- [error_composition](error_composition.csv)
- [class_balance](class_balance.csv)
- [data_flow](data_flow.csv)
- [calibration_summary](calibration_summary.csv)
- [calibration_gaps](calibration_gaps.csv)
- [cv_candidates](cv_candidates.csv)
- [cv_selected_folds](cv_selected_folds.csv)
- [subgroup_rates](subgroup_rates.csv)
- [profile_comparison](profile_comparison.csv)
- [headline_statistics](headline_statistics.csv)

## Definitions

- Error reduction: 100 x (baseline errors - model errors) / baseline errors. Accuracy gains are percentage-point differences.
- Errors per 1,000: 1,000 x (false positives + false negatives) / evaluation sample size. These are sample summaries, not projected deployment counts.
- MCC: (TP x TN - FP x FN) / sqrt((TP+FP)(TP+FN)(TN+FP)(TN+FN)). Undefined denominators remain missing.
- Negative predictive value: TN / (TN+FN). False discovery rate: FP / (TP+FP). False omission rate: FN / (TN+FN). These depend on sample prevalence.
- Average-precision lift: average precision / observed positive prevalence. The baseline is the constant-score average precision; this is not a top-k lift statistic.
- Brier skill versus baseline: 1 - model Brier score / majority-baseline Brier score. It measures relative squared probability error on this sample.
- Binned ECE: sum over occupied bins of (bin size / total size) x absolute(mean prediction - observed rate), using the original ten fixed probability bins. It is bin-dependent and can hide within-bin errors; it is not an overall model ranking.
- Calibration gap: mean prediction - observed rate. Positive values indicate overprediction in that bin. Displayed limits transform the existing Wilson interval for the observed rate, holding the mean prediction fixed.
- CV fold points are dependent selection scores. Fold ranges and standard deviations are not confidence intervals or independent confirmation.
- Model-profile subsets have different case mixes. Their score differences do not measure the effect of removing duplicates or prove leakage.

## Scope

These are unweighted summaries of a reused historical UCI Adult benchmark. No models were fitted and no bootstrap intervals were recalculated for this supplement. Existing bootstrap intervals condition on fitted models and this sample; they omit training and selection uncertainty. Group and calibration intervals are the published descriptive Wilson intervals. Group comparisons do not establish fairness or causal discrimination. Matching profiles do not identify people.

## Reproduce

Run from the repository root using installed locked dependencies and a new destination:

```sh
Rscript --vanilla scripts/create_results_summary.R docs/evidence/v2-full-2026-10-08 results/new-results-summary
```

The generator supports the preserved published version 2 evidence, or an exact copy. It verifies source artifact hashes before reading tables and rejects nonempty destinations or destinations inside the source evidence. Input, code, environment, and output manifests accompany the results.
The original and earlier supplemental graphics retain their separate provenance. This summary does not rerun training, tune thresholds, recalibrate models, or recompute bootstrap intervals.
