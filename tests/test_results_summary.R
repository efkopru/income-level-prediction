# Offline aggregate arithmetic and corruption checks. No fitting or figure rendering.
run_results_summary_tests <- function(root) {
  source(file.path(root, "R", "summary_statistics.R"), local = TRUE)
  source(file.path(root, "scripts", "create_results_summary.R"), local = TRUE)
  source_directory <- file.path(root, "docs", "evidence", "v2-full-2026-10-08")
  table_names <- c("metrics", "data_audit", "cv_summary", "cv_metrics", "calibration", "subgroup_metrics",
    "profile_sensitivity", "profile_overlap", "paired_differences", "metric_intervals", "bootstrap_design")
  source_paths <- file.path(source_directory, paste0(table_names, ".csv"))
  before <- tools::md5sum(source_paths)
  tables <- setNames(lapply(source_paths, read.csv, stringsAsFactors = FALSE), table_names)
  result <- build_results_summary(tables)
  equal <- function(actual, expected) stopifnot(isTRUE(all.equal(actual, expected, check.attributes = FALSE, tolerance = 1e-12)))
  expect_error <- function(code, pattern) {
    failure <- tryCatch({ force(code); NULL }, error = identity)
    stopifnot(inherits(failure, "error"), grepl(pattern, conditionMessage(failure), ignore.case = TRUE))
  }
  passed <- 0L
  check <- function(name, code) {
    force(code)
    passed <<- passed + 1L
    cat("PASS ", name, "\n", sep = "")
  }
  check("Published source columns remain exact and all output tables have stable contracts", {
    equal(result$model_summary[names(tables$metrics)], tables$metrics)
    equal(result$calibration_gaps[names(tables$calibration)], tables$calibration)
    equal(result$profile_comparison[names(tables$profile_sensitivity)], tables$profile_sensitivity)
    stopifnot(length(result) == 11L, all(vapply(result, is.data.frame, logical(1L))))
    equal(result$model_summary$model, c("majority", "logistic", "tree", "forest", "svm"))
  })
  check("Confusion-derived rates use the correct class and sample denominators", {
    # Independent analytic fixture from the published tree confusion matrix.
    tree <- result$model_summary[result$model_summary$model == "tree", ]
    tp <- 2374; tn <- 11673; fp <- 742; fn <- 1466; total <- tp + tn + fp + fn
    equal(tree$predicted_positive_n, tp + fp)
    equal(tree$predicted_positive_rate, (tp + fp) / total)
    equal(tree$false_negative_rate, fn / (tp + fn))
    equal(tree$false_positive_rate, fp / (tn + fp))
    equal(tree$negative_predictive_value, tn / (tn + fn))
    equal(tree$false_discovery_rate, fp / (tp + fp))
    equal(tree$false_omission_rate, fn / (tn + fn))
    equal(tree$errors, fp + fn)
    equal(tree$error_rate, (fp + fn) / total)
    equal(tree$errors_per_1000, 1000 * (fp + fn) / total)
    equal(tree$fn_per_1000, 1000 * fn / total)
    equal(tree$fp_per_1000, 1000 * fp / total)
    equal(tree$mcc, (tp * tn - fp * fn) / sqrt((tp + fp) * (tp + fn) * (tn + fp) * (tn + fn)))
  })
  check("Baseline gains preserve percentage-point versus relative-percent distinctions", {
    model <- result$model_summary
    equal(model$accuracy_gain_pp, 100 * (model$accuracy - 12415 / 16255))
    equal(model$balanced_accuracy_gain_pp, 100 * (model$balanced_accuracy - 0.5))
    equal(model$error_reduction_pct, 100 * (3840 - model$errors) / 3840)
    equal(model$average_precision_lift, model$average_precision / (3840 / 16255))
    equal(model$brier_skill_vs_baseline, 1 - model$brier_score / model$brier_score[1L])
    stopifnot(model$average_precision_lift[1L] == 1, model$error_reduction_pct[1L] == 0,
      is.na(model$mcc[1L]), is.na(model$precision[1L]), is.na(model$false_discovery_rate[1L]),
      is.na(model$brier_skill_vs_baseline[model$model == "svm"]))
  })
  check("Error composition adds to the full sample and 100 percent for every model", {
    for (model in result$model_summary$model) {
      rows <- result$error_composition[result$error_composition$model == model, ]
      equal(rows$outcome, c("TP", "TN", "FP", "FN"))
      equal(sum(rows$count), 16255)
      equal(sum(rows$percent), 100)
    }
  })
  check("Class balance derives training counts from one complete selected CV assessment partition", {
    equal(result$class_balance$count, c(7839, 24698, 3840, 12415))
    equal(result$class_balance$percent, 100 * c(7839 / 32537, 24698 / 32537, 3840 / 16255, 12415 / 16255))
    equal(result$data_flow$rows, c(32561, 32537, 16281, 16255))
    equal(result$data_flow$excluded, c(0, 24, 0, 26))
  })
  check("Calibration weighting is explicit and source Wilson bounds are reused without refitting", {
    for (model in result$calibration_summary$model) {
      source <- tables$calibration[tables$calibration$model == model, ]
      target <- result$calibration_summary[result$calibration_summary$model == model, ]
      gap <- source$mean_probability - source$observed_rate
      equal(target$binned_ece, sum(source$n * abs(gap)) / sum(source$n))
      equal(target$mean_signed_gap, sum(source$n * gap) / sum(source$n))
      equal(target$max_abs_gap, max(abs(gap)))
      equal(target$bin_count, nrow(source))
    }
    equal(result$calibration_gaps$gap_lower, tables$calibration$mean_probability - tables$calibration$upper)
    equal(result$calibration_gaps$gap_upper, tables$calibration$mean_probability - tables$calibration$lower)
    equal(result$calibration_summary$clipped_n, c(0, 0, 127, 2156))
    stopifnot(!"svm" %in% result$calibration_summary$model,
      result$calibration_summary$bin_count[1L] == 1L)
  })
  check("CV statistics retain arithmetic means and flag only actual numeric grid edges", {
    cv <- result$cv_candidates
    equal(cv[names(tables$cv_summary)], tables$cv_summary)
    stopifnot(all(cv$boundary_flag[cv$selected & cv$model %in% c("logistic", "tree", "svm")]),
      all(is.na(cv$boundary_flag[cv$model %in% c("majority", "forest")])),
      all(cv$candidate_rank[cv$selected] == 1L), nrow(result$cv_selected_folds) == 25L,
      all(result$cv_selected_folds$selected))
  })
  check("Subgroup long form preserves rates, denominators, and published endpoints", {
    for (metric in c("recall", "false_positive_rate")) {
      rows <- result$subgroup_rates[result$subgroup_rates$metric == metric, ]
      equal(rows$estimate, tables$subgroup_metrics[[metric]])
      equal(rows$lower, tables$subgroup_metrics[[paste0(metric, "_lower")]])
      equal(rows$upper, tables$subgroup_metrics[[paste0(metric, "_upper")]])
      equal(rows$denominator, tables$subgroup_metrics[[if (metric == "recall") "n_positive" else "n_negative"]])
    }
  })
  check("Profile prevalence retains the different observed case mixes", {
    equal(result$profile_comparison$prevalence, tables$profile_sensitivity$n_positive / tables$profile_sensitivity$n)
    equal(result$profile_comparison$n[1:2], c(2953, 13302))
  })
  check("Headline differences preserve original paired orientation and interval values", {
    value <- function(key) result$headline_statistics$value[match(key, result$headline_statistics$key)]
    equal(value("forest_minus_tree_fp"), 85)
    equal(value("forest_minus_tree_fn"), -23)
    equal(value("forest_minus_tree_errors"), 62)
    source <- subset(tables$paired_differences, model_a == "tree" & model_b == "forest" & metric == "balanced_accuracy")
    for (field in c("estimate", "lower", "upper"))
      equal(value(paste0("tree_minus_forest_balanced_accuracy_", field)), source[[field]])
  })
  check("Notes bound descriptive statistics and avoid unsupported inference", {
    notes <- paste(attr(result, "statistical_notes"), collapse = " ")
    stopifnot(grepl("ten fixed bins", notes), grepl("not confidence intervals", notes),
      grepl("conditional on fitted models", notes), grepl("fairness", notes),
      !any(grepl("p_value", unlist(lapply(result, names)))))
  })
  check("Model output order is independent of source ordering", {
    changed <- tables; changed$metrics <- changed$metrics[c(5, 3, 1, 4, 2), ]
    equal(build_results_summary(changed)$model_summary, result$model_summary)
  })
  check("Missing tables, missing fields, and duplicate models fail clearly", {
    changed <- tables; changed$calibration <- NULL
    expect_error(build_results_summary(changed), "schema")
    changed <- tables; changed$metrics$tp <- NULL
    expect_error(build_results_summary(changed), "schema")
    changed <- tables; changed$metrics$model[2] <- "majority"
    expect_error(build_results_summary(changed), "Duplicate")
  })
  check("Invalid counts and inconsistent published point metrics are rejected", {
    changed <- tables; changed$metrics$tp[2] <- changed$metrics$tp[2] + 1
    expect_error(build_results_summary(changed), "positive counts")
    changed <- tables; changed$metrics$fn[2] <- -1
    expect_error(build_results_summary(changed), "Invalid counts")
    changed <- tables; changed$metrics$accuracy[2] <- 0.9
    expect_error(build_results_summary(changed), "accuracy")
    changed <- tables; changed$metrics$precision[1] <- 0
    expect_error(build_results_summary(changed), "precision")
  })
  check("Audit retention and fold selection inconsistencies are rejected", {
    changed <- tables; changed$data_audit$value[changed$data_audit$item == "eligible_test_rows"] <- 16254
    expect_error(build_results_summary(changed), "audit test")
    changed <- tables; changed$cv_summary$selected[2] <- TRUE
    expect_error(build_results_summary(changed), "one selected")
    changed <- tables; changed$cv_metrics$selected[2] <- TRUE
    expect_error(build_results_summary(changed), "selected CV")
    changed <- tables; changed$cv_summary$mean_balanced_accuracy[2] <- 0.7
    expect_error(build_results_summary(changed), "CV mean")
  })
  check("Calibration, subgroup, and profile denominator corruption is rejected", {
    changed <- tables; changed$calibration$n_positive[2] <- 0
    expect_error(build_results_summary(changed), "calibration observed")
    changed <- tables; changed$calibration$upper[2] <- 0
    expect_error(build_results_summary(changed), "calibration interval")
    changed <- tables; changed$subgroup_metrics$false_positive_rate[2] <- 0.1
    expect_error(build_results_summary(changed), "subgroup false positive")
    changed <- tables; changed$subgroup_metrics$recall_lower[2] <- NA_real_
    expect_error(build_results_summary(changed), "subgroup interval")
    changed <- tables; changed$profile_overlap$n[1] <- 2954
    expect_error(build_results_summary(changed), "profile overlap total")
  })
  check("Published interval point mismatches and impossible bootstrap counts fail", {
    changed <- tables; changed$metric_intervals$estimate[1] <- 0.8
    expect_error(build_results_summary(changed), "published metric estimate")
    changed <- tables; changed$paired_differences$estimate[1] <- 0
    expect_error(build_results_summary(changed), "published paired difference")
    changed <- tables; changed$paired_differences$valid_replicates[1] <- 1001
    expect_error(build_results_summary(changed), "replicate count")
    changed <- tables; changed$bootstrap_design$n_rows <- 1
    expect_error(build_results_summary(changed), "bootstrap row count")
  })
  # These guard checks use normalized path strings only. They create no folders,
  # copy no evidence, and never invoke the summary renderer or its CLI entrypoint.
  normalized_root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  canonical_source <- paste0(normalized_root, "/docs/evidence/v2-full-2026-10-08")
  copied_source <- paste0(normalized_root, "/tmp/copied-summary-evidence")
  check("Destination guard rejects source equality and source descendants", {
    expect_error(check_summary_destination(normalized_root, canonical_source, canonical_source), "outside source evidence")
    expect_error(check_summary_destination(normalized_root, canonical_source,
      paste0(canonical_source, "/new-summary")), "outside source evidence")
    expect_error(check_summary_destination(normalized_root, copied_source,
      paste0(copied_source, "/new-summary")), "outside source evidence")
  })
  check("Copied source cannot bypass canonical evidence destination protection", {
    expect_error(check_summary_destination(normalized_root, copied_source, canonical_source), "preserved evidence")
    expect_error(check_summary_destination(normalized_root, copied_source,
      paste0(normalized_root, "/docs/evidence")), "preserved evidence")
    expect_error(check_summary_destination(normalized_root, copied_source,
      paste0(canonical_source, "/new-summary")), "preserved evidence")
  })
  check("Destination guard protects archives and earlier supplements", {
    for (path in c("archive", "archive/v2-2026-10-08/new-summary",
        "docs/figures/v2-uncertainty-review", "docs/figures/v2-uncertainty-review/new-summary"))
      expect_error(check_summary_destination(normalized_root, canonical_source,
        paste0(normalized_root, "/", path)), "archives, and earlier supplements")
  })
  check("Destination guard allows a distinct new figures directory", {
    stopifnot(isTRUE(check_summary_destination(normalized_root, canonical_source,
      paste0(normalized_root, "/docs/figures/additional-results-summary"))))
  })
  check("Destination guard distinguishes sibling prefixes from descendants", {
    for (path in c("archive-summary", "docs/evidence-summary", "docs/figures/v2-uncertainty-review-summary"))
      stopifnot(isTRUE(check_summary_destination(normalized_root, canonical_source,
        paste0(normalized_root, "/", path))))
    stopifnot(isTRUE(check_summary_destination(normalized_root, copied_source,
      paste0(copied_source, "-summary"))))
  })
  check("Windows destination protection is case insensitive", {
    if (.Platform$OS.type == "windows") {
      expect_error(check_summary_destination(normalized_root, canonical_source,
        toupper(paste0(canonical_source, "/new-summary"))), "outside source evidence")
      expect_error(check_summary_destination(normalized_root, copied_source,
        toupper(paste0(normalized_root, "/docs/evidence/new-summary"))), "preserved evidence")
      expect_error(check_summary_destination(normalized_root, copied_source,
        toupper(paste0(normalized_root, "/archive/new-summary"))), "archives")
      expect_error(check_summary_destination(normalized_root, copied_source,
        toupper(paste0(normalized_root, "/docs/figures/v2-uncertainty-review/new-summary"))), "earlier supplements")
    }
  })
  check("Source evidence bytes remain unchanged", equal(tools::md5sum(source_paths), before))
  cat(passed, " results summary checks passed.\n", sep = "")
  invisible(passed)
}

if (sys.nframe() == 0L) {
  invocation <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  root <- dirname(dirname(normalizePath(sub("^--file=", "", invocation[1L]))))
  run_results_summary_tests(root)
}
