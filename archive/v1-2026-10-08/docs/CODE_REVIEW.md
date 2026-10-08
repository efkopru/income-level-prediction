# Original code review

The preserved source is [`archive/IncomeLevelPrediction_original.R`](../archive/IncomeLevelPrediction_original.R). The line numbers below refer to that archive, not the revised entry point. These findings concern implementation validity. The original presentation remains a historical artifact; its reported results must not be presented as results from the revised workflow.

| Severity | Original lines | Finding | Revised approach |
| --- | --- | --- | --- |
| High | 33-37 | `inc_clean` is used before it is created, preventing execution in a clean R session. | Parse, validate, and clean data before exploration or modeling. |
| High | 50-52 | Positions sampled from `inc_clean` are used to subset the uncleaned `inc`, selecting different rows and reintroducing missing records. | Split the validated records with explicit, disjoint row identifiers. |
| High | 82-84, 162 | The training-only tree is overwritten with a tree trained on all cleaned records before holdout scoring. | Fit trees and select complexity using training data only. |
| High | 112, 171 | The first forest is trained on all cleaned records, so its later evaluation overlaps training data. | Restrict every fit to the training partition. |
| High | 116 | `tuneRF` receives a predictor table that still contains the target `incomelevel`. | Construct predictors separately from the outcome before tuning or fitting. |
| High | 148-149 | `predict.glm()` defaults to log odds. A cutoff of `0.5` on these values corresponds to a probability near `0.622`, not `0.5`. | Convert the linear predictor with `plogis()` and use the declared probability cutoff. |
| High | 60, 75, 80, 91, 101, 112, 116, 122 | Several functions are called without loading or qualifying their packages. | Use explicit package namespaces and check dependencies. |
| Medium | 96-101 | Cross-validation is computed, but the pruned tree size is hardcoded to five. | Select the tuning parameter from saved training-only validation results. |
| Medium | 116-120 | The forest tuning result is ignored in favor of a hardcoded `mtry=4`. `improve=TRUE` supplies a numeric threshold of one rather than a sensible fractional threshold. | Compare explicit candidates on the training validation partition and use the selected value. |
| Medium | 207 | SVM ROC receives class labels, discarding the continuous ranking needed for ROC analysis. | Use oriented decision margins, with higher values consistently indicating `>50K`. |
| Medium | 11, 23 | The script depends on a placeholder working directory and an undocumented `adult2.data` input. | Use documented source files, explicit paths, and saved input provenance. |
| Medium | 145-207 | Evaluation lacks consistent metrics, a majority baseline, an explicit positive class, and saved comparison artifacts. | Evaluate every model with the same labels, holdout rows, and metric definitions. |

The first tree call at line 80 also includes `nativecountry`, which the replacement formula at lines 82-84 excludes. That redundant fit is removed. The old comment about a universal 32-level random-forest limit is not carried forward as a current package claim.

## Verification priorities

Regression checks should establish cleaned partition integrity; prohibit the target from predictor tables; verify that changing holdout labels cannot alter fitting or tuning; test logistic probability thresholds; check confusion metrics and ties-correct AUC against known examples; exercise category and constant-column handling; confirm selected parameters come from recorded training validation results; and run all model families from a fresh R session.

## Modeling conventions

The positive class is `>50K`. Probability scores use a cutoff of `0.5`; the linear SVM uses a cutoff of zero on its oriented decision margin. Exact cutoff ties map to `<=50K`. SVM margins are ranking scores, not calibrated probabilities. The score orientation follows the fitted e1071/libsvm label order, without consulting held-out outcomes: see [e1071 R prediction code](https://github.com/cran/e1071/blob/master/R/svm.R) and [libsvm voting code bundled with e1071](https://github.com/cran/e1071/blob/master/src/svm.cpp).

Logistic regression selects an estimable predictor basis from the training design matrix before fitting. Structural aliases are recorded as dropped columns; any additional aliases identified during fitting contribute zero to the linear predictor. Nonconvergence remains visible as a warning and stored diagnostic. This is an unpenalized predictive baseline, and its coefficients should not be interpreted as causal effects.

Undefined metric denominators return `NA`. ROC AUC and balanced accuracy are undefined for a one-class evaluation subset; the ROC helper returns no curve for that subset. Tied scores receive half-credit in rank-based ROC AUC and enter the ROC curve together.
