#!/usr/bin/env Rscript
# Read-only, offline verification of the additional version 2 results summary.
verify_results_summary <- function(root = getwd(), quiet = FALSE) {
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  old_libraries <- .libPaths()
  on.exit(.libPaths(old_libraries), add = TRUE)
  if (dir.exists(file.path(root, ".R-library"))) .libPaths(c(file.path(root, ".R-library"), old_libraries))
  module <- new.env(parent = globalenv())
  for (file in c("scripts/verify_evidence.R", "R/summary_statistics.R", "R/summary_plots.R"))
    sys.source(file.path(root, file), envir = module)
  label <- "results summary"
  reject <- function(message) module$evidence_stop(label, message)
  destination <- file.path(root, "docs/figures/v2-results-summary")
  source_prefix <- "docs/evidence/v2-full-2026-10-08"
  source_directory <- file.path(root, source_prefix)
  inputs <- c("metrics", "data_audit", "cv_summary", "cv_metrics", "calibration", "subgroup_metrics",
    "profile_sensitivity", "profile_overlap", "paired_differences", "metric_intervals", "bootstrap_design")
  outputs <- c("model_summary", "error_composition", "class_balance", "data_flow", "calibration_summary",
    "calibration_gaps", "cv_candidates", "cv_selected_folds", "subgroup_rates", "profile_comparison", "headline_statistics")
  figure_names <- c("01_performance_scorecard", "02_classification_errors", "03_improvement_over_baseline",
    "04_precision_recall_tradeoff", "05_probability_quality", "06_calibration_gaps",
    "07_hyperparameter_search", "08_subgroup_errors", "09_profile_sensitivity", "10_sample_composition")
  files <- c(paste0(figure_names, ".png"), paste0(outputs, ".csv"), "results_summary.pdf", "index.html", "README.md",
    "figure_catalog.csv", "provenance.csv", "package_versions.csv", "render_context.txt", "artifact_manifest.csv")
  module$verify_public_evidence(root, quiet = TRUE)
  module$verify_evidence_manifest(destination, "artifact_manifest.csv", expected = setdiff(files, "artifact_manifest.csv"),
    complete = TRUE, label = label)
  provenance <- module$evidence_csv(file.path(destination, "provenance.csv"), c("role", "file", "bytes", "md5"),
    "results summary provenance")
  sources <- c("scripts/create_results_summary.R", "scripts/verify_evidence.R", "scripts/render_evidence_figures.R",
    "R/plots.R", "R/summary_statistics.R", "R/summary_plots.R", "R/summary_report.R", "renv.lock")
  provenance_files <- c(paste0(source_prefix, "/", inputs, ".csv"),
    paste0(source_prefix, "/public_artifact_manifest.csv"), sources)
  provenance_roles <- c(rep("published_aggregate", length(inputs)), "published_manifest", rep("summary_source", length(sources)))
  if (nrow(provenance) != 20L) reject("expected exactly 20 provenance records.")
  module$evidence_set(provenance$file, provenance_files, "results summary provenance")
  if (!identical(provenance$role[match(provenance_files, provenance$file)], provenance_roles))
    reject("unexpected provenance roles.")
  module$verify_evidence_records(provenance, root, label = "results summary provenance")
  module$verify_evidence_packages(destination, root, 2L, "results summary package versions")

  # Compare stored tables with fresh arithmetic on the canonical published CSVs.
  # Missing values and column order are part of the contract; no figures are built.
  raw_tables <- setNames(lapply(file.path(source_directory, paste0(inputs, ".csv")),
    utils::read.csv, stringsAsFactors = FALSE, check.names = FALSE), inputs)
  expected_tables <- module$build_results_summary(raw_tables)
  if (!identical(names(expected_tables), outputs)) reject("unexpected derived-table contract.")
  compare_table <- function(actual, expected, name) {
    if (!identical(names(actual), names(expected)) || nrow(actual) != nrow(expected))
      reject(paste0(name, ": schema or row count mismatch."))
    for (column in names(expected)) {
      a <- actual[[column]]; e <- expected[[column]]
      if (!identical(is.na(a), is.na(e))) reject(paste0(name, "/", column, ": missing-value mismatch."))
      present <- !is.na(e)
      if (is.numeric(e)) {
        if ((!is.numeric(a) && any(present)) || any(!is.finite(a[present])) ||
            any(abs(a[present] - e[present]) > 1e-12))
          reject(paste0(name, "/", column, ": numeric mismatch."))
      } else if (!identical(a[present], e[present])) {
        reject(paste0(name, "/", column, ": value or type mismatch."))
      }
    }
    invisible(TRUE)
  }
  for (name in outputs) {
    actual <- utils::read.csv(file.path(destination, paste0(name, ".csv")),
      stringsAsFactors = FALSE, check.names = FALSE)
    compare_table(actual, expected_tables[[name]], name)
  }
  catalog <- module$summary_figure_catalog()
  if (nrow(catalog) != 10L || !identical(catalog$file, figure_names)) reject("unexpected figure catalog order.")
  stored_catalog <- utils::read.csv(file.path(destination, "figure_catalog.csv"),
    stringsAsFactors = FALSE, check.names = FALSE)
  compare_table(stored_catalog, catalog, "figure_catalog")
  if (!quiet) cat("Verified 29 summary files (28 manifest hashes/sizes), 20 provenance records, 11 derived tables, and 10 catalog entries.\n")
  invisible(TRUE)
}

if (sys.nframe() == 0L) {
  invocation <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  root <- if (length(invocation)) dirname(dirname(normalizePath(sub("^--file=", "", invocation[1L])))) else getwd()
  args <- commandArgs(TRUE)
  if (length(args)) {
    if (length(args) != 2L || args[1L] != "--root") stop("Usage: verify_results_summary.R [--root PATH]", call. = FALSE)
    root <- args[2L]
  }
  verify_results_summary(root)
}
