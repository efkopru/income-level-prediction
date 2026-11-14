# Recorded run methodology

The settings and data summary below describe this execution. The historical version 3
reference plan follows separately; its fixed settings and sample counts must not override this summary.

Run mode: full.
Inputs: checksum-verified UCI reference files.
Actual retained sample: 32537 training rows and 16255 test rows.

| Setting | Historical reference | Actual run | Comparison |
| --- | ---: | ---: | --- |
| seed | 12345 | 12345 | Matches |
| trees | 500 | 500 | Matches |
| folds | 5 | 5 | Matches |
| bootstrap | 1000 | 1000 | Matches |

The four recorded settings match the historical reference plan.
Full mode uses the complete declared candidate grid.

Matching settings alone do not reproduce the published experiment: input and source hashes,
runtime, and packages also matter. Consult source_manifest.csv, input_manifest.csv,
package_versions.csv, and run_config.txt. The historical benchmark remains reused.

## Historical reference plan

The text below is the original reference plan, retained for context. Any differences listed above
are run-specific deviations; its declaration date is not a preregistration of this execution.

# Version 3 analysis protocol

Declared on November 14, 2026 before the version 3 full benchmark run. Version 1 and version 2 results, including their reused-test scores, had already been inspected when this protocol was written. This is a documented analysis plan for a revised educational benchmark, not a preregistered study or a new independent test. The saved source manifest identifies the exact protocol and code used by a completed run.

## Changes from version 2

A review of the published version 2 cross-validation results found that every tuned family had selected the last candidate in its declared grid: ridge `lambda = 0.0001`, tree `cp = 0.0005`, forest `mtry = floor(p / 3)`, and SVM `cost = 10`. No grid bracketed the setting it selected. Version 3 is a new experiment with wider grids. It neither corrects nor replaces version 2.

Version 3 differs from version 2 in these declared points and in nothing else:

1. Candidate grids. Every version 2 candidate is kept in its published order, and new candidates are appended to each tuned family.
2. Tree growth limits. The `rpart` limits that version 2 used as unstated package defaults are now stated, because they bind at small `cp`. The pipeline also accepts `cp = -1`, which version 2 code rejected.
3. SVM convergence. A linear SVM fit that stops at its solver's iteration limit is detected and treated as a numerical failure. Version 2 did not detect that condition.
4. Grid position. Each run records where every selected setting sits in its grid, under a rule declared here before the run.
5. Failure and versioning rules. Both are restated for version 3.

Data handling, preprocessing, the five grouped folds and their seed, the selection criterion and tie-break, both classification thresholds, the forest size, every metric, and the bootstrap design are unchanged. Every line of the version 2 protocol (`docs/METHODOLOGY_V2.md`) is carried over word for word and in order, except nine: its title, its opening paragraph, its paragraph on test reuse, the four tuned rows of the candidate table, and the two paragraphs of its versioning section. Where a carried-over passage names version 2, it records when that rule was first declared.

## Question and scope

Compare four supervised classifiers and a majority baseline on the historical UCI Adult income classes. The positive class is `>50K`. The primary selection criterion is mean validation-fold balanced accuracy at fixed classification thresholds. Accuracy, ranking, probability quality, and subgroup errors answer different questions and are reported separately.

Adult was extracted from a 1994 Census database. The official repository documents the extraction restrictions, missing fields, historical categories, and dataset attribution. The income threshold refers to this historical task. The study does not estimate current income or population prevalence. All metrics are unweighted sample statistics; `fnlwgt` is neither a predictor nor an observation weight. [UCI Adult documentation](https://archive.ics.uci.edu/dataset/2/adult).

## Data integrity and partitions

1. Verify `adult.data` and `adult.test` against the recorded source checksums. Parse the official training and test files separately. Normalize whitespace, `?` missing values, and the period appended to test labels.
2. In training data, remove only repeated complete records with identical values in all 14 raw predictor fields and the outcome. Keep different outcomes observed for the same raw predictor signature. Conflicting outcomes are legitimate ambiguity in these data, not sufficient evidence of an invalid record.
3. Exclude test rows whose 14-field raw predictor signature occurs anywhere in the original training file, without inspecting test outcomes. This preserves the version 1 benchmark test subset. Keep duplicate multiplicities within that remaining test subset and record their count.
4. Retain 32,537 training rows after removing 24 complete-record duplicates. Retain 16,255 test rows after excluding 26 training-overlap rows. The two training rows with one conflicting raw predictor signature remain. There are six extra raw-signature duplicate rows within the retained test subset.
5. Report signatures built from the 12 model input fields separately. Identical age, demographic, employment, and capital profiles can represent different people. Do not equate a matching model input profile with a duplicate person or remove these profiles from the primary evaluation. Report matched-profile and novel-profile subsets as a descriptive sensitivity analysis; they are different case mixes, not randomized comparisons.

The dataset contains no usable person identifier. Neither raw signatures nor model input profiles prove entity independence. The official test file was used in version 1 and again in version 2. It remains a **reused benchmark test**, and version 3 is its third evaluation. Within version 3, its labels do not select preprocessing, candidate grids, hyperparameters, model families, or thresholds. Prior inspection still limits any claim of independent confirmation, and a third evaluation on the same file adds none.

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

A wider grid makes the highest fold mean more optimistic, because it is the maximum over more candidates.

| Family | Fixed design | Candidate order |
| --- | --- | --- |
| Majority baseline | Training positive prevalence as a constant probability | No tuning |
| Ridge logistic regression | `glmnet`, binomial family, `alpha = 0`, intercept, training-only standardization, finite converged fit required | Lambda `0.1`, `0.01`, `0.001`, `0.0001`, `0.00001`, `0.000001` |
| Decision tree | `rpart`, classification, internal cross-validation disabled, `minsplit = 20`, `minbucket = 7`, `maxdepth = 30` | Complexity `0.01`, `0.005`, `0.001`, `0.0005`, `0.0001`, `0.00005`, `0.00001`, `0`, then `-1` for the fully grown tree |
| Probability random forest | `ranger`, 500 trees, `min.node.size = 10`, one thread, encoded numeric predictors | `mtry = floor(sqrt(p))`, `floor(p / 3)`, `floor(p / 2)`, `floor(2 * p / 3)`, then `p`, each bounded below by one |
| Linear SVM | `e1071`, linear kernel, external fold-local scaling, uncalibrated oriented margin, fit within the solver's iteration limit required | Cost `0.1`, `1`, `10`, `30` |

For forest candidates, `p` is the number of encoded columns available in that fit. The selected rule is recomputed against the final training matrix. `min.node.size` is the minimum size for attempting a split; it does not guarantee that terminal nodes contain at least ten observations. A probability forest averages tree probability estimates. [Ranger reference](https://imbs-hl.github.io/ranger/reference/ranger.html).

In the published version 2 run the full training matrix had 84 encoded columns and one fold had 83. The five rules then resolve to 9, 28, 42, 56, and 84 columns, or to 9, 27, 41, 55, and 83.

For tree candidates, `cp` is the factor by which a split must reduce the overall lack of fit to be attempted. At `cp = 0` a split is still removed when the subtree it starts does not lower training misclassification. A negative `cp` removes that requirement as well. Every negative value gives the same fully grown tree, in which a node stops splitting only when no split improves it or when `minsplit`, `minbucket`, or `maxdepth` prevents a split. The grid ends with that tree, declared as `cp = -1`. Those three limits are the `rpart` defaults that version 2 used without stating them. They are fixed design settings, not tuned.

For ridge regression, positive penalization regularizes the unstable unpenalized estimates seen in version 1. Numerical nonconvergence or nonfinite coefficients stop the run; they are not accepted as benchmark evidence. Ridge shrinkage is a predictive modeling choice, not evidence that coefficients describe causal effects. [Glmnet reference](https://glmnet.stanford.edu/articles/glmnet.html).

For the linear SVM, `e1071` reports that its `libsvm` solver stopped at the iteration limit only as console text, `WARNING: reaching max number of iterations`. It raises no R warning, and the fitted object has no convergence field. Version 3 captures the solver console text of every SVM fit. A fit that reports the iteration limit is a numerical failure. Any other solver text is passed through to the console unchanged.

Refit each selected family on all eligible training rows, then score the reused benchmark test. No threshold optimization, post-test recalibration, oversampling, or additional model search is part of this protocol. Probabilities greater than `0.5` and oriented SVM margins greater than zero predict `>50K`; exact threshold ties predict `<=50K`. SVM orientation follows the trained model's label order, without consulting held-out outcomes.

Random operations explicitly use Mersenne-Twister, Inversion, and Rejection settings and restore the caller's prior random state. The forest runs with one thread. Ranger seed zero has special nondeterministic meaning, so a user-requested seed of zero is mapped to one for that engine. Run evidence records actual package and runtime versions.

## How the grids were chosen

The grids were chosen from the published version 2 training cross-validation results in `docs/evidence/v2-full-2026-10-08`, using `cv_summary.csv` for fold means and `cv_metrics.csv` for fold scores and fit times, and from the range each parameter can take. Version 2 reused-test scores were already public when this protocol was written. They did not decide which families were extended, in which direction, or where a grid ends: all four tuned families are extended, each past the edge on which its version 2 selection sat.

| Family | Published fold means at the last two version 2 candidates | Added candidates | Reason for the endpoint |
| --- | --- | --- | --- |
| Ridge logistic regression | 0.7578 at `0.001`, 0.7579 at `0.0001` | `0.00001`, `0.000001` | Two further decades below a value at which the mean had already flattened. A zero penalty is excluded by the fixed design. |
| Decision tree | 0.7682 at `0.001`, 0.7823 at `0.0005` | `0.0001`, `0.00005`, `0.00001`, `0`, `-1` | Three further steps of the version 2 spacing, then zero, then the fully grown tree, beyond which `cp` changes nothing. |
| Probability random forest | 0.7793 at `floor(sqrt(p))`, 0.7832 at `floor(p / 3)` | `floor(p / 2)`, `floor(2 * p / 3)`, `p` | `p` is the highest value `mtry` can take: every encoded column is a split candidate. |
| Linear SVM | 0.7574 at `1`, 0.7580 at `10` | `30` | Cost has no upper limit, but the solver has an iteration limit. A training-only check found that at `100` the solver stopped at that limit on the fold 1 analysis rows, so `100` cannot be fitted under this protocol. `30`, half a decade above `10`, finished within the limit on all five analysis sets and on the full training set. |

Before this protocol was committed, fits on training rows only checked run time and solver limits. On the fold 1 analysis rows they fitted the SVM at costs `10` and `100`, the forest at `mtry = p`, and the tree at `cp = 0.0005`, `0`, and `-1`. On all five analysis sets and on the full training set they fitted the SVM at costs `10` and `30`. Each check recorded elapsed time, whether the solver reached its iteration limit, and tree size. No validation or test rows were scored, so none of these fits measured predictive performance.

With about 26,000 analysis rows and 84 encoded columns, the ridge and SVM fold means are expected to level off as regularization weakens rather than turn down. A wider grid can show such a plateau, but no finite grid guarantees an interior optimum for these two families. The tree and forest grids end at a limit of their parameter, so a selection there cannot be improved by widening the same parameter.

## Grid position of each selected setting

For each tuned family, take the candidates in their declared order and record where the selected candidate sits:

- `interior`: a declared candidate precedes the selection and another follows it. Only an `interior` selection is described as bracketed.
- `parameter_limit`: the selection is the fully grown tree, `cp = -1`, or the forest rule `p`. It is described as at the limit of its parameter, which a wider grid cannot extend. It is not described as bracketed.
- `grid_edge`: any other first or last candidate of a family. It is described as not bracketed.

For each declared candidate adjacent to the selection, record the margin: the mean over the five folds of the selection's validation balanced accuracy minus the adjacent candidate's on the same fold. Record also the number of folds in which the selection scored strictly higher and the number of exact fold ties. Label a margin below `0.001` as `plateau` and any other margin as `separated`. A `grid_edge` or `parameter_limit` selection whose margin is `separated` is described as still improving at that end.

The value `0.001` was fixed from the published version 2 fold means. The last-step gains that had flattened were 0.0001 for ridge and 0.0006 for the SVM; those that had not were 0.0039 for the forest and 0.0141 for the tree. It is a descriptive threshold, well below the fold standard deviations of 0.007 to 0.012 recorded for the selected version 2 settings. It is not a statistical test.

Whatever the position and labels, the selection stands. No candidate is added, removed, or evaluated again after version 3 cross-validation or test results are seen. A further change of grid is a new version with its own protocol.

Save these records as `grid_position.csv`. The run report, the README, and the validation record state each family's position and labels as recorded. A smoke run evaluates one candidate per family and records `single_candidate`.

## Numerical failures and corrections

A run is evidence only if every fit succeeds. The run stops when a ridge fit does not converge or returns a nonfinite coefficient, when an SVM fit reports the solver's iteration limit, or when any fit or prediction raises an error or returns a nonfinite score. Cross-validation fits and final fits all complete before the test sample is scored, so a fitting failure stops the run before any test score exists.

A stopped run is not reported as a result, and its partial output is not exported. If a declared candidate causes the stop, the only permitted change to the grids is a dated amendment at the end of this document that removes that candidate from its family and records the observed failure. An amendment may not add or alter a candidate or change any other setting. It is committed before the run restarts from the beginning, and the validation record and README report it. An implementation defect is corrected, documented, and rerun in the same way; it is not hidden as successful optimization.

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

Preserve the original project, the version 1 snapshot and evidence, the version 2 evidence, and the version 2 source snapshot without changing a byte. Save version 3 to a new result directory and a new aggregate evidence directory, and preserve the sources named in its source manifest in a new archive directory. Report the results and conclusion only after tests, the full run, export verification, and graphic inspection complete.

The version 3 grids contain every version 2 candidate, and each fit sets its own seed. The thirteen tuned version 2 candidates must therefore reproduce their published fold metrics exactly, apart from recorded fit time. A difference is investigated and reported before any export. It is not a reason to change a grid.

Do not tune this protocol against observed version 2 or version 3 test scores. Report version 3 beside version 2, not in place of it, and prefer neither because of its test scores. Version 3 widens four grids at once. A difference between the two versions' results cannot be attributed to one of those changes, and a difference on the reused test is not evidence about wider grids in general. The differences between versions 1 and 2 remain as the version 2 protocol records them.

## Amendments

None at declaration.
