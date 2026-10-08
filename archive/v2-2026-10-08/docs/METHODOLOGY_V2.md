# Version 2 analysis protocol

Declared on October 8, 2026 before the version 2 full benchmark run. Version 1 results had already been inspected when this protocol was written. This is a documented analysis plan for a revised educational benchmark, not a preregistered study or a new independent test. The saved source manifest identifies the exact protocol and code used by a completed run.

## Question and scope

Compare four supervised classifiers and a majority baseline on the historical UCI Adult income classes. The positive class is `>50K`. The primary selection criterion is mean validation-fold balanced accuracy at fixed classification thresholds. Accuracy, ranking, probability quality, and subgroup errors answer different questions and are reported separately.

Adult was extracted from a 1994 Census database. The official repository documents the extraction restrictions, missing fields, historical categories, and dataset attribution. The income threshold refers to this historical task. The study does not estimate current income or population prevalence. All metrics are unweighted sample statistics; `fnlwgt` is neither a predictor nor an observation weight. [UCI Adult documentation](https://archive.ics.uci.edu/dataset/2/adult).

## Data integrity and partitions

1. Verify `adult.data` and `adult.test` against the recorded source checksums. Parse the official training and test files separately. Normalize whitespace, `?` missing values, and the period appended to test labels.
2. In training data, remove only repeated complete records with identical values in all 14 raw predictor fields and the outcome. Keep different outcomes observed for the same raw predictor signature. Conflicting outcomes are legitimate ambiguity in these data, not sufficient evidence of an invalid record.
3. Exclude test rows whose 14-field raw predictor signature occurs anywhere in the original training file, without inspecting test outcomes. This preserves the version 1 benchmark test subset. Keep duplicate multiplicities within that remaining test subset and record their count.
4. Retain 32,537 training rows after removing 24 complete-record duplicates. Retain 16,255 test rows after excluding 26 training-overlap rows. The two training rows with one conflicting raw predictor signature remain. There are six extra raw-signature duplicate rows within the retained test subset.
5. Report signatures built from the 12 model input fields separately. Identical age, demographic, employment, and capital profiles can represent different people. Do not equate a matching model input profile with a duplicate person or remove these profiles from the primary evaluation. Report matched-profile and novel-profile subsets as a descriptive sensitivity analysis; they are different case mixes, not randomized comparisons.

The dataset contains no usable person identifier. Neither raw signatures nor model input profiles prove entity independence. The official test file was used in version 1 and is now a **reused benchmark test**. Within version 2, its labels do not select preprocessing, hyperparameters, model families, or thresholds. Prior inspection still limits any claim of independent confirmation.

## Preprocessing

Fit every learned transformation using only the analysis rows of the relevant cross-validation fold. Refit once on all eligible training rows after settings have been selected.

- Exclude the text `education` field because `educationnum` represents the same education ordering. Exclude `fnlwgt` as described above. The retained predictor fields include recorded sex and race.
- Apply the fixed `log1p` transformation to nonnegative `capitalgain` and `capitalloss`. This reduces skew before linear-model fitting and is declared independently of version 2 test results. The other numeric fields retain their original functional form.
- Replace missing numeric values with analysis-partition medians, then center and scale with analysis-partition means and standard deviations. A constant numeric field uses scale one before constant encoded columns are removed.
- Treat observed categorical missing values as `__MISSING__`. Learn category levels and the most common reference category from analysis data. Map any later unseen category, including an unseen missing marker, to the learned mode and record the mapping count.
- Use treatment-coded indicator columns and remove constant columns. All model families receive the same encoded predictors. This makes the forest a forest over encoded columns, not a native-factor forest. Multilevel fields therefore contribute several candidate columns during feature subsampling.
- Ridge logistic regression additionally uses `glmnet`'s standardization inside each training fit so that the penalty is defined on comparable scales for binary and continuous encoded columns. This standardization never fits on validation or test rows.

## Model selection and final fitting

Use five deterministic cross-validation folds within eligible official training data, seed `12345`. Keep every raw predictor signature in one fold. Allocate groups to balance positive and negative class counts approximately; require both classes in every analysis and validation partition. Save fold assignments, group counts, and class counts. Grouping takes precedence over exact class proportions.

Every candidate is evaluated on all five validation folds, with fold-specific preprocessing. Select each model family's candidate with the highest arithmetic mean of fold balanced accuracy. Break exact ties by the declaration order below. Candidate fold scores and their standard deviation describe this particular selection procedure; they are not independent performance estimates or confidence intervals after selection.

| Family | Fixed design | Candidate order |
| --- | --- | --- |
| Majority baseline | Training positive prevalence as a constant probability | No tuning |
| Ridge logistic regression | `glmnet`, binomial family, `alpha = 0`, intercept, training-only standardization, finite converged fit required | Lambda `0.1`, `0.01`, `0.001`, `0.0001` |
| Decision tree | `rpart`, classification, internal cross-validation disabled | Complexity `0.01`, `0.005`, `0.001`, `0.0005` |
| Probability random forest | `ranger`, 500 trees, `min.node.size = 10`, one thread, encoded numeric predictors | `mtry = floor(sqrt(p))`, then `floor(p / 3)`, each bounded below by one |
| Linear SVM | `e1071`, linear kernel, external fold-local scaling, uncalibrated oriented margin | Cost `0.1`, `1`, `10` |

For forest candidates, `p` is the number of encoded columns available in that fit. The selected rule is recomputed against the final training matrix. `min.node.size` is the minimum size for attempting a split; it does not guarantee that terminal nodes contain at least ten observations. A probability forest averages tree probability estimates. [Ranger reference](https://imbs-hl.github.io/ranger/reference/ranger.html).

For ridge regression, positive penalization regularizes the unstable unpenalized estimates seen in version 1. Numerical nonconvergence or nonfinite coefficients stop the run; they are not accepted as benchmark evidence. Ridge shrinkage is a predictive modeling choice, not evidence that coefficients describe causal effects. [Glmnet reference](https://glmnet.stanford.edu/articles/glmnet.html).

Refit each selected family on all eligible training rows, then score the reused benchmark test. No threshold optimization, post-test recalibration, oversampling, or additional model search is part of this protocol. Probabilities greater than `0.5` and oriented SVM margins greater than zero predict `>50K`; exact threshold ties predict `<=50K`. SVM orientation follows the trained model's label order, without consulting held-out outcomes.

Random operations explicitly use Mersenne-Twister, Inversion, and Rejection settings and restore the caller's prior random state. The forest runs with one thread. Ranger seed zero has special nondeterministic meaning, so a user-requested seed of zero is mapped to one for that engine. Run evidence records actual package and runtime versions.

## Metrics and graphics

Report confusion counts, sample size, positive and negative denominators, positive prevalence, accuracy, balanced accuracy, precision, recall, specificity, F1, ROC AUC, and average precision for every family. Undefined denominators produce `NA`, never an invented zero.

ROC AUC uses continuous scores with half credit for tied positive-negative pairs. Average precision is the sum of each tied-score recall increment multiplied by the precision after that score group enters. It is stepwise precision-recall integration, not trapezoidal PR area. A constant-score baseline has ROC AUC 0.5 when both classes occur and average precision equal to observed test prevalence.

For probability-producing models only, report the Brier score and natural-log loss. Use probabilities as returned for Brier scoring. For logarithms, clip at `1e-15` and `1 - 1e-15`, and report the number of changed probabilities. SVM decision margins receive neither probability metrics nor calibration curves.

Calibration uses ten fixed equal-width bins spanning zero to one. Omit empty bins and save bin counts, positive counts, mean predicted probability, observed positive rate, and 95% Wilson intervals for the observed rate. These are descriptive reliability plots. They do not fit a calibration correction or establish calibrated probabilities.

Generate the result figures in R with `ggplot2`: metric comparisons, ROC and precision-recall curves, calibration, confusion matrices, cross-validation variability, and subgroup error rates. Keep consistent model labels, colors, caption wording, and exported image dimensions. Display uncertainty and subgroup denominators where relevant.

## Conditional uncertainty and paired comparisons

Use 1,000 paired nonparametric bootstrap replicates of the retained test raw predictor-signature clusters. Draw the same number of clusters with replacement for each replicate, and retain all rows in every drawn cluster. Cluster multiplicity becomes a row weight. Resample the same clusters for all model families. The resulting number of rows can vary when cluster sizes differ.

Compute 95% percentile intervals, using R's type 7 quantiles, for accuracy, balanced accuracy, recall, ROC AUC, and average precision. Record the number of finite replicate estimates. Calculate the same five metric differences for all six pairs among the four trained families, with sign `model_a - model_b`. Include all declared pairs to avoid selecting comparisons after seeing a winning test score.

These intervals are conditional on already fitted models and this historical evaluation sample. They omit uncertainty from training data, hyperparameter selection, previous test inspection, and unknown person-level dependencies. They are descriptive unadjusted intervals, not a multiple-comparison testing procedure. A difference interval that excludes zero does not establish universal superiority or a production advantage. Model selection itself can create optimistic assessments; additional independent data would be required to confirm generalization beyond this benchmark. [Cawley and Talbot, 2010](https://www.jmlr.org/papers/v11/cawley10a.html).

## Recorded sex and race

Preserve the dataset's historical category labels when reporting descriptive group results. Report group sample size, positive and negative denominators, positive prevalence, predicted-positive rate, true-positive rate, false-positive rate, and precision. Provide 95% Wilson intervals for true-positive rate, false-positive rate, and precision where denominators are nonzero.

Wilson intervals are approximate binomial intervals. Small group denominators, retained repeated profiles, unavailable entity identities, historical sampling, and label limitations restrict their interpretation. These intervals do not account for model fitting or multiple comparisons. The study does not define a fairness target, certify fairness, or infer discrimination causally. Removing sex and race alone would not eliminate information carried by correlated predictors.

## Versioning and interpretation rules

Preserve the original project, the full version 1 source snapshot, and version 1 evidence. Save version 2 to a new result directory and a new aggregate evidence directory. Report the updated results and conclusion only after tests, the full run, export verification, and graphic inspection complete.

Do not tune this protocol against the observed version 2 test scores. Corrections for an implementation failure must be documented and rerun as a correction, not hidden as successful optimization. Version 1 and version 2 differ in training retention, capital transformations, selection, ridge regularization, and forest implementation. Their score differences cannot be assigned to any one of those changes without a separate controlled experiment.
