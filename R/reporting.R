# Narrative is generated from the current run, never copied from older scores.
write_run_methodology <- function(options, official, n_training, n_test) {
  settings <- income_run_settings(options)
  rows <- vapply(seq_len(nrow(settings)), function(i) sprintf("| %s | %s | %s | %s |",
    settings$setting[i], settings$reference[i], settings$actual[i],
    if (settings$changed[i]) "Changed" else "Matches"), character(1))
  text <- c("# Recorded run methodology", "",
    "The settings and data summary below describe this execution. The historical version 3",
    "reference plan follows separately; its fixed settings and sample counts must not override this summary.", "",
    paste("Run mode:", if (options$smoke) "**SMOKE: sampled execution check, not benchmark evidence.**" else "full."),
    paste("Inputs:", if (official) "checksum-verified UCI reference files." else
      "**CUSTOM: input files differ from the UCI reference checksums; historical sample counts do not apply.**"),
    sprintf("Actual retained sample: %s training rows and %s test rows.", n_training, n_test), "",
    "| Setting | Historical reference | Actual run | Comparison |",
    "| --- | ---: | ---: | --- |", rows, "",
    if (any(settings$changed))
      "**Settings differ from the historical reference plan. Interpret this run as a separate configuration.**" else
      "The four recorded settings match the historical reference plan.",
    if (options$smoke) paste("Smoke mode also limits training/test rows and evaluates only the first candidate",
      "per family. The table records effective settings after smoke limits, not the originally requested values.") else
      "Full mode uses the complete declared candidate grid.", "",
    "Matching settings alone do not reproduce the published experiment: input and source hashes,",
    "runtime, and packages also matter. Consult source_manifest.csv, input_manifest.csv,",
    "package_versions.csv, and run_config.txt. The historical benchmark remains reused.", "",
    "## Historical reference plan", "",
    "The text below is the original reference plan, retained for context. Any differences listed above",
    "are run-specific deviations; its declaration date is not a preregistration of this execution.", "",
    readLines(file.path(options$root, income_protocol()), warn = FALSE))
  writeLines(text, file.path(options$output, "methodology.md"))
}

# What a report may say about earlier use of its evaluation sample. Versions 1 and 2
# both published results on the official test file before version 3 scored it.
income_test_history <- function(official) if (official)
  c("The official benchmark test was examined in versions 1 and 2, so this is its third evaluation.",
    "It is a **reused benchmark test**, not a fresh independent validation sample.") else
  "These are caller-supplied files. Their independence and history of prior evaluation are not established."

write_run_report <- function(evaluation, bundle, audit, options, warnings, official) {
  labels <- c(majority = "Majority baseline", logistic = "Ridge logistic regression",
    tree = "Decision tree", forest = "Probability random forest", svm = "Linear SVM")
  metrics <- evaluation$metrics
  selected <- bundle$selected_parameters
  preferred <- selected$model[which.max(selected$mean_balanced_accuracy)]
  chosen <- metrics[metrics$model == preferred, , drop = FALSE]
  interval <- function(model, metric) {
    row <- evaluation$metric_intervals[evaluation$metric_intervals$model == model &
      evaluation$metric_intervals$metric == metric, , drop = FALSE]
    if (!nrow(row)) return("not available")
    sprintf("%.3f to %.3f", row$lower[1], row$upper[1])
  }
  metric_rows <- vapply(seq_len(nrow(metrics)), function(i) sprintf(
    "| %s | %.2f%% | %.2f%% | %.2f%% | %.2f%% | %.4f | %.4f |",
    labels[metrics$model[i]], 100 * metrics$accuracy[i], 100 * metrics$balanced_accuracy[i],
    100 * metrics$precision[i], 100 * metrics$recall[i], metrics$roc_auc[i], metrics$average_precision[i]), character(1))
  cv_rows <- vapply(seq_len(nrow(selected)), function(i) sprintf("| %s | %s | %.4f | %.4f |",
    labels[selected$model[i]], selected$candidate[i], selected$mean_balanced_accuracy[i],
    selected$sd_balanced_accuracy[i]), character(1))
  probability <- metrics[metrics$model != "svm", , drop = FALSE]
  probability_rows <- vapply(seq_len(nrow(probability)), function(i) sprintf("| %s | %.4f | %.4f | %s |",
    labels[probability$model[i]], probability$brier_score[i], probability$log_loss[i],
    probability$probability_clipped_n[i]), character(1))
  grid <- bundle$grid_position
  shown <- function(value, format = "%s") if (is.na(value)) "not assessed" else sprintf(format, value)
  grid_rows <- vapply(seq_len(nrow(grid)), function(i) sprintf("| %s | %s | %s (%s of %s) | %s | %s | %s | %s | %s |",
    labels[grid$model[i]], grid$selected_candidate[i], grid$position[i], grid$selected_index[i],
    grid$n_candidates[i], if (isTRUE(grid$bracketed[i])) "yes" else "no", shown(grid$neighbour_candidate[i]),
    shown(grid$margin[i], "%.5f"), if (is.na(grid$nfolds[i])) "not assessed" else
      sprintf("%s of %s, %s tied", grid$folds_selection_higher[i], grid$nfolds[i], grid$folds_tied[i]),
    shown(grid$margin_label[i])), character(1))
  grid_text <- if (all(grid$position == "single_candidate"))
    "This run evaluated one candidate per family, so no grid position is assessed." else c(
    "Positions and labels follow the rule declared in the protocol before the run; they do not change any selection.",
    "Only an interior selection is bracketed by evaluated candidates on both sides. A grid edge is an end of the",
    "declared grid, so the grid does not bracket that selection. A parameter limit (`cp=-1` or `mtry=all`) is the end",
    "of the parameter's range, which a wider grid cannot extend. The margin is the mean of the paired fold differences",
    sprintf("in balanced accuracy, selection minus adjacent candidate. Margins below %s are labelled plateau.",
      format(grid_plateau_margin())), "These labels are descriptive; they are not significance tests.")
  top_accuracy <- metrics$model[which.max(metrics$accuracy)]
  top_auc <- metrics$model[which.max(metrics$roc_auc)]
  top_ap <- metrics$model[which.max(metrics$average_precision)]
  profile <- evaluation$profile_overlap
  text <- c("# Income Level Prediction Using R: results and conclusion", "",
    if (options$smoke) "**SMOKE RUN. Sampled execution check only; do not use these values as final study results.**" else
      "**Version 3.** Version 2's grouped training cross-validation, fixed thresholds, and evaluation, with every tuning grid widened past its version 2 edge.", "",
    "## Study question and scope", "",
    "How do a majority baseline, ridge logistic regression, a decision tree, a probability random forest,",
    "and a linear SVM compare when predicting the historical UCI Adult income category >50K?",
    "This evaluates classification, ranking, and probability quality as separate properties.", "",
    income_test_history(official),
    "The pipeline selects model settings from training folds only; it does not select settings or thresholds from test scores.",
    "Caller-supplied overrides are separate configurations, not a new preregistered experiment.", "",
    "## Data and methods", "",
    paste("Input status:", if (official) "both files match the recorded UCI reference checksums." else
      "CUSTOM INPUTS, not checksum-verified UCI reference files."),
    sprintf("Final training sample: %s records. Evaluation sample: %s records. Test positive prevalence: %.2f%%.",
      nrow(bundle$fold_assignments), metrics$n[1], 100 * metrics$n_positive[1] / metrics$n[1]),
    "Exact repeated training records are collapsed. Predictor profiles with conflicting training labels remain",
    "in the sample and in the same CV fold. Test rows matching original training raw predictor signatures are",
    "excluded under the predeclared policy. Internal test repetitions remain; uncertainty resamples their clusters.", "",
    sprintf("Model selection used %s approximately class-stratified folds grouped by all 14 raw predictor fields.", options$folds),
    "Imputation, categorical encoding, and scaling were learned inside each analysis fold. Capital gain and loss",
    "received a fixed log1p transformation. Redundant text education and fnlwgt were excluded; sample weights were not used.",
    "The primary selection metric was mean fold balanced accuracy, with declaration order breaking ties.",
    "Thresholds remained probability >0.5 and oriented SVM margin >0. No test-based threshold tuning occurred.",
    "Selected settings were refitted on all eligible training records. Ridge logistic regression uses glmnet;",
    "the forest uses ranger leaf probabilities on the common encoded feature matrix. SVM scores are margins.", "",
    "Actual settings, deviations, and the historical reference plan are in [the recorded methodology](methodology.md).",
    if (any(income_run_settings(options)$changed))
      "**This run changes settings from the historical reference plan; consult the recorded comparison table.**" else
      "The four recorded settings match the reference plan; source and input hashes identify this execution.", "",
    "## Cross-validation and selected settings", "",
    "| Model | Selected setting | Mean balanced accuracy | Fold SD |",
    "|---|---|---:|---:|", cv_rows, "",
    sprintf("The training-CV selection rule preferred **%s** before evaluating the test set.", labels[preferred]),
    "Fold SD describes variation among dependent folds; it is not a confidence interval. CV scores used for",
    "selection are optimistic as performance estimates. They should not be presented as external validation.", "",
    "![Grouped training cross-validation](cv_comparison.png)", "",
    "## Grid position of the selected settings", "",
    "| Model | Selected setting | Grid position | Bracketed | Adjacent candidate | Mean fold margin | Folds higher, tied | Label |",
    "|---|---|---|---|---|---:|---|---|", grid_rows, "", grid_text,
    "[Grid position](grid_position.csv) records these values; [all candidates](cv_summary.csv) have fold means.", "",
    if (official) "## Reused-test results" else "## Custom-input evaluation results", "",
    "| Model | Accuracy | Balanced accuracy | Precision >50K | Recall >50K | ROC AUC | Average precision |",
    "|---|---:|---:|---:|---:|---:|---:|", metric_rows, "",
    sprintf("The CV-preferred model achieved %.2f%% accuracy, %.2f%% balanced accuracy, and %.2f%% recall for >50K.",
      100 * chosen$accuracy, 100 * chosen$balanced_accuracy, 100 * chosen$recall),
    sprintf("Its balanced-accuracy interval was %s; its ROC-AUC interval was %s.",
      interval(preferred, "balanced_accuracy"), interval(preferred, "roc_auc")),
    sprintf("The majority baseline accuracy was %.2f%% and its balanced accuracy was 50%%.",
      100 * metrics$accuracy[metrics$model == "majority"]),
    "Average precision uses tied-score threshold groups and non-interpolated recall increments; it is not",
    "trapezoidal PR area. Its constant-score baseline equals positive prevalence.", "",
    "![Performance estimates and conditional intervals](model_comparison.png)", "",
    "![ROC and precision-recall curves](roc_pr_curves.png)", "",
    "![Confusion matrices with counts and row percentages](confusion_matrices.png)", "",
    "## Uncertainty and model comparisons", "",
    sprintf("The run used %s paired cluster-bootstrap replicates with 95%% percentile intervals.", options$bootstrap),
    "A cluster is one raw 14-predictor signature; every model uses the same sampled clusters. Intervals condition",
    "on these already-fitted models and this evaluation sample. They do not include training, model-selection,",
    "population-shift, or prior test-exposure uncertainty. Clusters are not verified person identifiers.",
    "[Paired differences](paired_differences.csv) cover all six pairs of trained models. Positive values favor",
    "model_a for the listed metric. These unadjusted exploratory intervals are not multiplicity-corrected tests",
    "and do not establish a universal winning method.", "",
    "## Probability quality", "",
    "| Probability model | Brier score (lower is better) | Log loss (lower is better) | Probabilities clipped for log loss |",
    "|---|---:|---:|---:|", probability_rows, "",
    "Log loss clips probabilities at 1e-15 and 1-1e-15. Calibration plots use ten fixed equal-width bins,",
    "show bin sizes and descriptive Wilson intervals, and do not recalibrate models. Uncalibrated SVM margins",
    "are excluded from Brier score, log loss, and calibration plots.", "",
    "![Probability calibration and bin sample sizes](calibration.png)", "",
    "## Subgroup and profile checks", "",
    "Recorded sex and race remain predictors. Subgroup results show denominators and descriptive error-rate",
    "intervals. Different group distributions, small samples, historical categories, and unknown entities limit",
    "interpretation. These comparisons neither identify causal discrimination nor establish fairness.", "",
    "![Recall by recorded sex and race with descriptive intervals](subgroup_recall.png)", "",
    sprintf("%s test records share the 12 modeled raw predictor values with training; %s have a novel profile.",
      profile$n[profile$profile_status == "seen_in_training"], profile$n[profile$profile_status == "novel_profile"]),
    "These coarse demographic matches do not establish repeated-person leakage. The [profile sensitivity table](profile_sensitivity.csv)",
    "reports the two subsets without changing the primary evaluation or selecting models from those results.", "",
    "## Conclusion", "",
    sprintf("The revised training procedure selected %s using grouped cross-validation.", labels[preferred]),
    sprintf("On this evaluation sample, %s had the highest observed accuracy, %s the highest ROC AUC, and %s the highest average precision.",
      labels[top_accuracy], labels[top_auc], labels[top_ap]),
    sprintf("At its fixed classification threshold, the CV-preferred model missed %s of %s >50K records and generated %s false positives.",
      chosen$fn, chosen$n_positive, chosen$fp),
    "This separates useful ranking from the practical errors made at a chosen threshold. Probability calibration",
    "and subgroup performance add information that accuracy alone cannot supply. The uncertainty estimates",
    "quantify conditional test-sample variability; they do not establish an independent evaluation history.", "",
    "The defensible contribution is a reproducible R comparison with explicit data handling, grouped model selection,",
    "traceable outputs, and multidimensional evaluation. It is not a current-income estimator, a causal study,",
    "a deployment validation, or evidence of universal model superiority. A fresh external or temporal sample",
    "would be required for a stronger generalization claim. Versions 1 and 2 and the historical slide scores are separate",
    "experiments. Version 3 widens four tuning grids at once, so a difference from version 2 cannot be attributed to one change.", "",
    "## Diagnostics and provenance", "",
    if (length(warnings)) paste0("- ", unique(warnings)) else "No model warnings were recorded.",
    "Fitting failures abort the run. [Model diagnostics](diagnostics.csv), [input hashes](input_manifest.csv),",
    "[source and protocol hashes](source_manifest.csv), [package versions](package_versions.csv), and run_config.txt",
    "record the completed run. Public exports contain aggregate evidence; record-level predictions, fold IDs,",
    "and fitted objects remain local. The renv lockfile records package versions for restoration.", "",
    paste(if (official) "Data:" else "Reference task (not attribution of the custom files):",
      "Becker, B. and Kohavi, R. (1996). [Adult, UCI](https://archive.ics.uci.edu/dataset/2/adult)."),
    "DOI: 10.24432/C5XW20. Dataset license: CC BY 4.0.")
  writeLines(text, file.path(options$output, "report.md"), useBytes = TRUE)
}
