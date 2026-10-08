# Version 2 audit

Audit date: October 8, 2026. Scope: original script, revised version 1 data handling, training, evaluation, saved evidence, interpretation, and the code changes required for version 2. The [version 1 snapshot](../archive/v1-2026-10-08/) preserves the prior implementation. The original implementation findings remain in [CODE_REVIEW.md](CODE_REVIEW.md).

This document records issues and the chosen corrections. The completed run and validation record provide execution evidence; a planned correction is not itself evidence of a successful rerun.

## Methodology and result interpretation

| Priority | Finding | Evidence and consequence | Version 2 decision |
| --- | --- | --- | --- |
| High | The benchmark test has already been inspected. | Version 1 publishes results for the official test subset. A revised analysis cannot recover pristine test independence by rescoring it. | Label it a reused benchmark test. Declare the version 2 protocol before running it and prohibit tuning against its results. |
| High | One split controls hyperparameter choice. | Version 1 selects each family on one 6,506-row validation set. Small setting differences may reflect that split. | Five training-only folds with identical fold assignments across candidates, fold-local preprocessing, saved fold results, and a declared tie rule. |
| High | Unpenalized logistic regression reports probabilities numerically equal to zero or one. | The full version 1 run converged but emitted this warning. Convergence alone does not remove separation and coefficient instability concerns. | Use ridge logistic regression with declared positive penalties, training-only standardization, and a hard stop for failed convergence or nonfinite coefficients. |
| Medium | Training conflicts are discarded based on outcome disagreement. | Version 1 removes two rows sharing one raw predictor signature with different labels. Equal observed predictors need not imply equal income. | Remove only completely identical records. Retain both conflicting-label rows and keep their raw signature in a single CV fold. |
| Medium | Raw duplicate handling and identical model inputs are easily confused. | Version 1 raw signatures include `fnlwgt` and `education`, which its models omit. The retained version 1 data contain 4,043 repeated model-input training profiles, 603 conflicting model-input signatures, and 2,953 test rows with model-input profiles seen in training. | Distinguish raw signatures from 12-field model inputs. Keep common demographic profiles in the primary task and report profile-overlap sensitivity. Do not claim these counts identify repeated people or prove leakage. |
| Medium | Tree and forest inputs are indicator columns. | Feature sampling acts on encoded columns; fields with many categories have several opportunities to be sampled. This is a modeling convention, not an invalid model. | Retain the shared encoding and disclose it. Use `ranger` probability forests, a declared split-node-size setting, and rules for `mtry` recomputed from each fit's encoded dimension. |
| Medium | Numerical scale and skew affect linear models. | Capital gain and loss have many zeros and large positive values. Unpenalized fitting and fixed-cost SVM comparisons depend on their representation. | Declare `log1p` for both capital variables, fitted numeric imputation and scaling within each fold, and ridge's additional internal scaling. |
| Medium | Accuracy and ROC AUC do not describe the same tradeoff. | The majority baseline is about 76% accurate while never identifying the positive class. Version 1's best accuracy and best AUC come from different families. | Keep balanced accuracy as the declared selection metric; show minority-class recall, precision, AP, confusion counts, and continuous-score AUC. Keep fixed thresholds. |
| Medium | Ranking scores are not evidence of calibrated probabilities. | SVM outputs a margin. AUC is unaffected by many changes that can alter probability quality. | Assess Brier score, log loss, and reliability bins only for actual probability outputs. Exclude SVM margins from those calculations. |
| Medium | Point estimates omit sampling uncertainty. | Version 1 has no confidence intervals or paired model-difference estimates. Its six extra duplicate test rows also make naive row-independence assumptions imperfect. | Paired raw-signature cluster bootstrap, 1,000 replicates, five declared metrics, all six trained-family pairs. State that uncertainty is conditional and unadjusted. |
| Medium | Group averages can hide small denominators. | Version 1 reports recorded sex/race metrics but lacks uncertainty and explicit positive/negative support. | Add group denominators, predicted-positive rates, and Wilson intervals for recall, false-positive rate, and precision. Interpret descriptively, without fairness certification. |
| Medium | Historical scores can be mistaken for current income prediction. | The data come from a restricted historical sample with a historical dollar threshold. Excluding `fnlwgt` does not produce population estimates. | Describe an unweighted educational classification benchmark, with no contemporary, causal, or deployment claim. |

The model-profile counts above were measured on the preserved version 1 partitions. They are audit evidence, not the version 2 sample counts. Of the 6,506 version 1 validation rows, 1,165 share an effective model-input profile with the analysis partition. Repeated observable profiles do not establish repeated entities, so they are not removed as an automatic leakage correction.

## Numerical and implementation checks added

- Compute rank-based AUC denominator products with double precision, avoiding integer overflow on larger valid inputs.
- Treat tied scores consistently in ROC points, average precision, and bootstrap estimates.
- Reject probabilities outside zero to one and report numerical clipping used only for log loss.
- Keep class-score orientation independent of evaluation outcomes.
- Require identical row identifiers, row order, and truth across models before paired bootstrap comparisons.
- Use shared cluster resamples for every model, including known identical-prediction cases whose paired difference must remain zero.
- Pin and restore random-number-generator kind and seed for standalone model fitting and bootstrap evaluation.
- Preserve source data, model settings, selected parameters, diagnostics, and artifact checksums for every run. Require finite converged ridge fits for publication evidence.

## Retained limitations

The five-fold candidate search is small and not nested. Its selected fold score is therefore an internal selection statistic, not an unbiased generalization claim. Categories unseen during fitting map to the learned mode; these mappings are recorded but do not eliminate distribution-shift risk. The shared indicator encoding is retained for the forest. Test uncertainty excludes training variability and unknown person-level dependence. Subgroup intervals are approximate and unadjusted. Prior test exposure persists regardless of the care used in the revised implementation.

The [version 2 protocol](METHODOLOGY_V2.md) specifies the exact retained design, metric definitions, graphics, and interpretation limits. Results must be described as outcomes of that declared comparison, not as proof of a universally best model.
