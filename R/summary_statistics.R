# Descriptive arithmetic from preserved aggregate evidence only. No fitting,
# record-level reconstruction, significance tests, or new uncertainty estimates.
# Group and calibration interval endpoints are copied from published tables.
build_results_summary <- function(tables) {
  fail <- function(message) stop(message, call. = FALSE)
  required <- list(
    metrics = c("model", "n", "n_positive", "n_negative", "positive_rate", "accuracy",
      "balanced_accuracy", "precision", "recall", "specificity", "f1", "roc_auc",
      "average_precision", "tp", "tn", "fp", "fn", "brier_score", "log_loss", "probability_clipped_n"),
    data_audit = c("item", "value"),
    cv_summary = c("model", "candidate", "parameter_rule", "parameter", "order",
      "sd_balanced_accuracy", "mean_balanced_accuracy", "nfolds", "selected"),
    cv_metrics = c("model", "candidate", "fold", "n_analysis", "n", "n_positive", "n_negative",
      "positive_rate", "accuracy", "balanced_accuracy", "precision", "recall", "specificity",
      "f1", "tp", "tn", "fp", "fn", "selected"),
    calibration = c("model", "bin", "n", "n_positive", "mean_probability", "observed_rate", "lower", "upper"),
    subgroup_metrics = c("model", "attribute", "group", "n", "n_positive", "n_negative",
      "positive_rate", "accuracy", "balanced_accuracy", "precision", "recall", "specificity", "f1",
      "tp", "tn", "fp", "fn", "false_positive_rate", "recall_lower", "recall_upper",
      "false_positive_rate_lower", "false_positive_rate_upper"),
    profile_sensitivity = c("model", "profile_status", "n", "n_positive", "n_negative",
      "positive_rate", "accuracy", "balanced_accuracy", "precision", "recall", "specificity", "f1", "tp", "tn", "fp", "fn"),
    profile_overlap = c("profile_status", "n"),
    paired_differences = c("model_a", "model_b", "metric", "estimate", "lower", "upper", "valid_replicates"),
    metric_intervals = c("model", "metric", "estimate", "lower", "upper", "valid_replicates"),
    bootstrap_design = c("replicates", "seed", "n_rows", "n_clusters", "method", "confidence", "conditional_on_fitted_models"))
  if (!is.list(tables) || anyDuplicated(names(tables))) fail("Expected uniquely named aggregate tables.")
  for (name in names(required)) {
    if (!is.data.frame(tables[[name]]) || !nrow(tables[[name]]) ||
        !all(required[[name]] %in% names(tables[[name]])))
      fail(paste("Missing required schema or rows:", name))
  }
  equal <- function(actual, expected, label) {
    if (length(actual) != length(expected) || any(is.na(actual) != is.na(expected)) ||
        any(abs(actual - expected) > 1e-10, na.rm = TRUE))
      fail(paste("Inconsistent", label))
  }
  counts <- function(x, label, positive = FALSE) {
    if (!is.numeric(x) || anyNA(x) || any(!is.finite(x)) || any(x < 0 | x != floor(x)) ||
        (positive && any(x == 0))) fail(paste("Invalid counts:", label))
  }
  rate <- function(x, label, allow_na = FALSE) {
    if ((!is.numeric(x) && !(is.logical(x) && all(is.na(x)))) ||
        (!allow_na && anyNA(x)) || any(!is.finite(x[!is.na(x)])) ||
        any(x < -1e-12 | x > 1 + 1e-12, na.rm = TRUE)) fail(paste("Invalid rate:", label))
  }
  divide <- function(a, b) { result <- a / b; result[b == 0] <- NA_real_; result }
  unique_key <- function(data, columns, label) {
    if (anyNA(data[columns]) || anyDuplicated(data[columns])) fail(paste("Duplicate or missing key:", label))
  }
  validate_confusion <- function(data, label) {
    for (field in c("n", "n_positive", "n_negative", "tp", "tn", "fp", "fn"))
      counts(data[[field]], paste(label, field), positive = field == "n")
    equal(data$n_positive, data$tp + data$fn, paste(label, "positive counts"))
    equal(data$n_negative, data$tn + data$fp, paste(label, "negative counts"))
    equal(data$n, data$n_positive + data$n_negative, paste(label, "total counts"))
    expected <- list(positive_rate = data$n_positive / data$n,
      accuracy = (data$tp + data$tn) / data$n, recall = divide(data$tp, data$n_positive),
      specificity = divide(data$tn, data$n_negative), precision = divide(data$tp, data$tp + data$fp),
      f1 = divide(2 * data$tp, 2 * data$tp + data$fp + data$fn))
    expected$balanced_accuracy <- (expected$recall + expected$specificity) / 2
    for (field in names(expected)) {
      rate(data[[field]], paste(label, field), allow_na = TRUE)
      equal(data[[field]], expected[[field]], paste(label, field))
    }
  }
  metrics <- tables$metrics
  unique_key(metrics, "model", "metrics model")
  model_order <- c("majority", "logistic", "tree", "forest", "svm")
  if (!setequal(metrics$model, model_order)) fail("Expected the five published model families.")
  metrics <- metrics[match(model_order, metrics$model), , drop = FALSE]
  rownames(metrics) <- NULL
  validate_confusion(metrics, "metrics")
  for (field in c("n", "n_positive", "n_negative"))
    equal(metrics[[field]], rep(metrics[[field]][1L], nrow(metrics)), paste("shared test", field))
  for (field in c("roc_auc", "average_precision")) rate(metrics[[field]], field)
  n_test <- metrics$n[1L]
  n_positive <- metrics$n_positive[1L]
  if (n_positive == 0 || n_positive == n_test) fail("Both test classes are required.")
  for (name in c("cv_summary", "cv_metrics", "calibration", "subgroup_metrics", "profile_sensitivity", "metric_intervals"))
    if (anyNA(tables[[name]]$model) || any(!tables[[name]]$model %in% model_order))
      fail(paste("Unknown model:", name))
  audit <- tables$data_audit
  unique_key(audit, "item", "data audit")
  audit_items <- c("raw_training_rows", "raw_test_rows", "training_duplicate_rows_excluded",
    "test_train_overlap_rows_excluded", "eligible_training_rows", "eligible_test_rows")
  if (!all(audit_items %in% audit$item)) fail("Missing required data audit counts.")
  counts(audit$value, "data audit")
  audit_value <- function(item) audit$value[match(item, audit$item)]
  n_train <- audit_value("eligible_training_rows")
  equal(audit_value("eligible_test_rows"), n_test, "audit test rows")
  equal(audit_value("raw_training_rows") - audit_value("training_duplicate_rows_excluded"), n_train, "training retention")
  equal(audit_value("raw_test_rows") - audit_value("test_train_overlap_rows_excluded"), n_test, "test retention")

  cv <- tables$cv_summary
  folds <- tables$cv_metrics
  unique_key(cv, c("model", "candidate"), "CV candidate")
  unique_key(folds, c("model", "candidate", "fold"), "CV fold")
  validate_confusion(folds, "CV folds")
  if (!is.logical(cv$selected) || anyNA(cv$selected) || !is.logical(folds$selected) || anyNA(folds$selected))
    fail("CV selected flags must be logical and nonmissing.")
  if (any(table(factor(cv$model[cv$selected], levels = model_order)) != 1L))
    fail("Exactly one selected candidate per model is required.")
  fold_candidate <- match(paste(folds$model, folds$candidate), paste(cv$model, cv$candidate))
  if (anyNA(fold_candidate) || any(folds$selected != cv$selected[fold_candidate]))
    fail("Inconsistent selected CV candidates.")
  counts(cv$nfolds, "CV number of folds", positive = TRUE)
  counts(folds$fold, "CV fold", positive = TRUE)
  counts(folds$n_analysis, "CV analysis rows", positive = TRUE)
  equal(folds$n_analysis + folds$n, rep(n_train, nrow(folds)), "CV analysis and assessment totals")
  rate(cv$mean_balanced_accuracy, "CV mean")
  rate(cv$sd_balanced_accuracy, "CV standard deviation")
  for (i in seq_len(nrow(cv))) {
    values <- folds$balanced_accuracy[fold_candidate == i]
    equal(length(values), cv$nfolds[i], "CV fold count")
    equal(mean(values), cv$mean_balanced_accuracy[i], "CV mean")
    equal(stats::sd(values), cv$sd_balanced_accuracy[i], "CV standard deviation")
  }
  selected_folds <- folds[folds$selected, , drop = FALSE]
  selected_folds <- selected_folds[order(match(selected_folds$model, model_order), selected_folds$fold), , drop = FALSE]
  reference_folds <- selected_folds[selected_folds$model == "majority", , drop = FALSE]
  equal(sum(reference_folds$n), n_train, "CV training assessment coverage")
  for (model in model_order) {
    current <- selected_folds[selected_folds$model == model, , drop = FALSE]
    for (field in c("fold", "n", "n_positive", "n_negative"))
      equal(current[[field]], reference_folds[[field]], paste("shared CV", field))
  }
  cv$candidate_rank <- NA_integer_
  cv$family <- cv$model
  cv$boundary_flag <- NA
  for (model in model_order) {
    rows <- which(cv$model == model)
    cv$candidate_rank[rows] <- as.integer(rank(-cv$mean_balanced_accuracy[rows], ties.method = "min"))
    parameters <- cv$parameter[rows]
    if (length(unique(parameters[is.finite(parameters)])) > 1L && all(is.finite(parameters)))
      cv$boundary_flag[rows] <- parameters == min(parameters) | parameters == max(parameters)
  }
  cv <- cv[order(match(cv$model, model_order), cv$order), , drop = FALSE]

  summary <- metrics
  summary$predicted_positive_n <- metrics$tp + metrics$fp
  summary$predicted_positive_rate <- summary$predicted_positive_n / n_test
  summary$false_negative_rate <- metrics$fn / metrics$n_positive
  summary$false_positive_rate <- metrics$fp / metrics$n_negative
  summary$negative_predictive_value <- divide(metrics$tn, metrics$tn + metrics$fn)
  summary$false_discovery_rate <- divide(metrics$fp, metrics$tp + metrics$fp)
  summary$false_omission_rate <- divide(metrics$fn, metrics$tn + metrics$fn)
  summary$errors <- metrics$fp + metrics$fn
  summary$error_rate <- summary$errors / n_test
  summary$errors_per_1000 <- 1000 * summary$error_rate
  summary$fn_per_1000 <- 1000 * metrics$fn / n_test
  summary$fp_per_1000 <- 1000 * metrics$fp / n_test
  summary$accuracy_gain_pp <- 100 * (metrics$accuracy - metrics$accuracy[1L])
  summary$balanced_accuracy_gain_pp <- 100 * (metrics$balanced_accuracy - metrics$balanced_accuracy[1L])
  summary$error_reduction_pct <- 100 * divide(summary$errors[1L] - summary$errors, rep(summary$errors[1L], nrow(summary)))
  summary$average_precision_lift <- metrics$average_precision / metrics$positive_rate
  summary$brier_skill_vs_baseline <- 1 - divide(metrics$brier_score, rep(metrics$brier_score[1L], nrow(metrics)))
  mcc_denominator <- sqrt(as.double(metrics$tp + metrics$fp) * (metrics$tp + metrics$fn) *
    (metrics$tn + metrics$fp) * (metrics$tn + metrics$fn))
  summary$mcc <- divide(as.double(metrics$tp) * metrics$tn - as.double(metrics$fp) * metrics$fn, mcc_denominator)
  error_composition <- do.call(rbind, lapply(seq_len(nrow(metrics)), function(i) {
    values <- as.numeric(metrics[i, c("tp", "tn", "fp", "fn")])
    data.frame(model = metrics$model[i], outcome = c("TP", "TN", "FP", "FN"), count = values,
      percent = 100 * values / n_test)
  }))
  train_positive <- sum(reference_folds$n_positive)
  class_balance <- data.frame(partition = rep(c("training", "test"), each = 2L),
    class = rep(c(">50K", "<=50K"), 2L), count = c(train_positive, n_train - train_positive, n_positive, n_test - n_positive))
  class_balance$percent <- 100 * class_balance$count / rep(c(n_train, n_test), each = 2L)
  data_flow <- data.frame(partition = rep(c("training", "test"), each = 2L), stage = rep(c("raw", "eligible"), 2L),
    rows = c(audit_value("raw_training_rows"), n_train, audit_value("raw_test_rows"), n_test),
    excluded = c(0, audit_value("training_duplicate_rows_excluded"), 0, audit_value("test_train_overlap_rows_excluded")))

  calibration <- tables$calibration
  unique_key(calibration, c("model", "bin"), "calibration bins")
  for (field in c("n", "n_positive", "bin")) counts(calibration[[field]], paste("calibration", field), positive = field != "n_positive")
  if (any(calibration$bin > 10L) || any(calibration$n_positive > calibration$n)) fail("Invalid calibration bin counts.")
  for (field in c("mean_probability", "observed_rate", "lower", "upper")) rate(calibration[[field]], paste("calibration", field))
  equal(calibration$observed_rate, calibration$n_positive / calibration$n, "calibration observed rate")
  if (any(calibration$lower > calibration$observed_rate + 1e-12 | calibration$upper < calibration$observed_rate - 1e-12))
    fail("Invalid calibration interval endpoints.")
  probability_models <- metrics$model[!is.na(metrics$brier_score)]
  if (!setequal(unique(calibration$model), probability_models)) fail("Calibration models do not match available probabilities.")
  calibration$gap <- calibration$mean_probability - calibration$observed_rate
  calibration$gap_lower <- calibration$mean_probability - calibration$upper
  calibration$gap_upper <- calibration$mean_probability - calibration$lower
  calibration_summary <- do.call(rbind, lapply(probability_models, function(model) {
    rows <- calibration[calibration$model == model, , drop = FALSE]
    equal(sum(rows$n), n_test, "calibration total rows")
    equal(sum(rows$n_positive), n_positive, "calibration positive rows")
    source <- metrics[metrics$model == model, , drop = FALSE]
    rate(source$brier_score, "Brier score")
    if (!is.finite(source$log_loss) || source$log_loss < 0) fail("Invalid log loss.")
    counts(source$probability_clipped_n, "clipped probability count")
    if (source$probability_clipped_n > n_test) fail("Invalid clipped probability count.")
    data.frame(model = model, brier_score = source$brier_score, log_loss = source$log_loss,
      clipped_n = source$probability_clipped_n, clipped_percent = 100 * source$probability_clipped_n / n_test,
      bin_count = nrow(rows), binned_ece = sum(rows$n * abs(rows$gap)) / n_test,
      mean_signed_gap = sum(rows$n * rows$gap) / n_test, max_abs_gap = max(abs(rows$gap)))
  }))
  subgroup <- tables$subgroup_metrics
  unique_key(subgroup, c("model", "attribute", "group"), "subgroup")
  validate_confusion(subgroup, "subgroup")
  equal(subgroup$false_positive_rate, divide(subgroup$fp, subgroup$n_negative), "subgroup false positive rate")
  subgroup_rates <- do.call(rbind, lapply(c("recall", "false_positive_rate"), function(metric) {
    denominator <- if (metric == "recall") subgroup$n_positive else subgroup$n_negative
    lower <- subgroup[[paste0(metric, "_lower")]]
    upper <- subgroup[[paste0(metric, "_upper")]]
    rate(lower, paste(metric, "lower"), TRUE); rate(upper, paste(metric, "upper"), TRUE)
    if (any(is.na(lower) != (denominator == 0)) || any(is.na(upper) != (denominator == 0)) ||
        any(lower > subgroup[[metric]] + 1e-12 | upper < subgroup[[metric]] - 1e-12, na.rm = TRUE))
      fail("Invalid subgroup interval endpoints or denominators.")
    data.frame(model = subgroup$model, attribute = subgroup$attribute, group = subgroup$group,
      metric = metric, estimate = subgroup[[metric]], lower = lower, upper = upper, denominator = denominator, n = subgroup$n)
  }))
  for (attribute in unique(subgroup$attribute)) for (model in model_order) {
    rows <- subgroup[subgroup$attribute == attribute & subgroup$model == model, , drop = FALSE]
    for (field in c("n", "n_positive", "n_negative", "tp", "tn", "fp", "fn"))
      equal(sum(rows[[field]]), metrics[[field]][metrics$model == model], paste("subgroup total", field))
  }
  profiles <- tables$profile_sensitivity
  overlap <- tables$profile_overlap
  unique_key(profiles, c("model", "profile_status"), "profile sensitivity")
  unique_key(overlap, "profile_status", "profile overlap")
  counts(overlap$n, "profile overlap", TRUE)
  equal(sum(overlap$n), n_test, "profile overlap total")
  validate_confusion(profiles, "profile sensitivity")
  for (model in model_order) {
    rows <- profiles[profiles$model == model, , drop = FALSE]
    if (!setequal(rows$profile_status, overlap$profile_status)) fail("Missing profile partitions.")
    equal(rows$n, overlap$n[match(rows$profile_status, overlap$profile_status)], "profile partition counts")
    for (field in c("n", "n_positive", "n_negative", "tp", "tn", "fp", "fn"))
      equal(sum(rows[[field]]), metrics[[field]][metrics$model == model], paste("profile total", field))
  }
  profiles$prevalence <- profiles$positive_rate

  design <- tables$bootstrap_design
  if (nrow(design) != 1L || !identical(design$conditional_on_fitted_models, TRUE)) fail("Invalid conditional bootstrap design.")
  for (field in c("replicates", "n_rows", "n_clusters")) counts(design[[field]], paste("bootstrap", field), TRUE)
  equal(design$n_rows, n_test, "bootstrap row count")
  if (design$n_clusters > n_test || design$confidence <= 0 || design$confidence >= 1) fail("Invalid bootstrap design.")
  intervals <- tables$metric_intervals
  paired <- tables$paired_differences
  unique_key(intervals, c("model", "metric"), "metric intervals")
  unique_key(paired, c("model_a", "model_b", "metric"), "paired differences")
  for (data in list(intervals, paired)) {
    if (any(!is.finite(data$estimate)) || any(!is.finite(data$lower)) || any(!is.finite(data$upper)) || any(data$lower > data$upper))
      fail("Invalid published interval endpoints.")
    counts(data$valid_replicates, "valid bootstrap replicates", TRUE)
    if (any(data$valid_replicates > design$replicates)) fail("Invalid bootstrap replicate count.")
  }
  if (any(!intervals$metric %in% names(metrics)) || any(!paired$metric %in% names(metrics)) ||
      any(!paired$model_a %in% model_order) || any(!paired$model_b %in% model_order) || any(paired$model_a == paired$model_b))
    fail("Unknown interval model or metric.")
  for (i in seq_len(nrow(intervals)))
    equal(intervals$estimate[i], metrics[[intervals$metric[i]]][match(intervals$model[i], metrics$model)], "published metric estimate")
  for (i in seq_len(nrow(paired)))
    equal(paired$estimate[i], metrics[[paired$metric[i]]][match(paired$model_a[i], metrics$model)] -
      metrics[[paired$metric[i]]][match(paired$model_b[i], metrics$model)], "published paired difference")
  headline <- data.frame(key = c("eligible_training_rows", "eligible_test_rows", "test_positive_rows", "test_prevalence",
      "bootstrap_replicates", "bootstrap_clusters"),
    value = c(n_train, n_test, n_positive, n_positive / n_test, design$replicates, design$n_clusters),
    unit = c("rows", "rows", "rows", "proportion", "replicates", "clusters"))
  tree_forest <- paired[paired$model_a == "tree" & paired$model_b == "forest", , drop = FALSE]
  for (i in seq_len(nrow(tree_forest))) for (field in c("estimate", "lower", "upper"))
    headline <- rbind(headline, data.frame(key = paste("tree_minus_forest", tree_forest$metric[i], field, sep = "_"),
      value = tree_forest[[field]][i], unit = "proportion_difference"))
  for (field in c("fp", "fn", "errors"))
    headline <- rbind(headline, data.frame(key = paste("forest_minus_tree", field, sep = "_"),
      value = summary[[field]][summary$model == "forest"] - summary[[field]][summary$model == "tree"], unit = "rows"))
  result <- list(model_summary = summary, error_composition = error_composition, class_balance = class_balance,
    data_flow = data_flow, calibration_summary = calibration_summary, calibration_gaps = calibration,
    cv_candidates = cv, cv_selected_folds = selected_folds, subgroup_rates = subgroup_rates,
    profile_comparison = profiles, headline_statistics = headline)
  result <- lapply(result, function(data) { rownames(data) <- NULL; data })
  attr(result, "statistical_notes") <- c(
    "All additional statistics are descriptive arithmetic on preserved published aggregates; original results are unchanged.",
    "Calibration ECE is weighted absolute error in the original ten fixed bins (occupied bin count is reported); a constant baseline can have low ECE despite no discrimination.",
    "CV standard deviations describe five overlapping training-fold fits, not confidence intervals; boundary flags concern only the tested numeric grid.",
    "Subgroup and calibration bounds reuse existing Wilson intervals; calibration gap bounds hold the bin mean probability fixed and reflect observed-rate uncertainty only.",
    "Published paired bootstrap bounds are conditional on fitted models and resample raw-predictor clusters; no new tests, intervals, or p-values are computed.",
    "Profile, subgroup, and historical sample comparisons do not establish causal effects, fairness, or performance in current populations.",
    "Training class counts sum assessment counts from the selected majority candidate over all recorded CV folds; they are not reconstructed raw records.")
  result
}
