#!/usr/bin/env Rscript
# Re-render aggregate evidence only. This script never fits models or resamples data.
resolve_figure_destination <- function(path) {
  if (length(path) != 1L || is.na(path) || !nzchar(path)) stop("Destination must be one nonempty path.")
  path <- path.expand(path)
  current <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
  if (.Platform$OS.type == "windows") {
    path <- chartr("\\", "/", path)
    if (grepl("^[A-Za-z]:[^/]", path) || grepl("^[A-Za-z]:$", path))
      stop("Drive-relative destinations are unsupported; use an absolute or working-directory-relative path.")
    if (startsWith(path, "/") && !startsWith(path, "//")) {
      if (!grepl("^[A-Za-z]:/", current)) stop("Root-relative destination needs an explicit drive or share.")
      path <- paste0(substr(current, 1L, 2L), path)
    }
  }
  absolute <- startsWith(path, "/") ||
    (.Platform$OS.type == "windows" && grepl("^[A-Za-z]:/", path))
  if (!absolute) path <- file.path(current, path)
  # normalizePath(mustWork=FALSE) can leave nonexistent relative paths unchanged.
  # Resolve an existing ancestor first, including symlinks, then append the new
  # suffix while applying dot segments to that canonical absolute ancestor.
  suffix <- character()
  ancestor <- path
  while (!dir.exists(ancestor)) {
    if (file.exists(ancestor)) stop("Destination has an existing file in its directory path.")
    parent <- dirname(ancestor)
    if (identical(parent, ancestor)) stop("Destination has no accessible existing parent directory.")
    suffix <- c(basename(ancestor), suffix)
    ancestor <- parent
  }
  resolved <- normalizePath(ancestor, winslash = "/", mustWork = TRUE)
  for (part in suffix) {
    if (part == "." || !nzchar(part)) next
    resolved <- if (part == "..") dirname(resolved) else file.path(resolved, part)
    # Collapsing an absent/.. prefix can expose an existing directory alias.
    # Resolve it now rather than treating the rest of the suffix as lexical.
    if (dir.exists(resolved)) resolved <- normalizePath(resolved, winslash = "/", mustWork = TRUE)
    else if (file.exists(resolved)) stop("Destination has an existing file in its directory path.")
  }
  resolved
}

render_evidence_figures <- function(source, destination, root) {
  if (!dir.exists(source)) stop("Published source directory does not exist.")
  if (file.exists(destination) && !dir.exists(destination)) stop("Destination is an existing file.")
  if (dir.exists(destination) && length(list.files(destination, all.files = TRUE, no.. = TRUE)))
    stop("Destination must be new or empty; existing figures are preserved.")
  source <- normalizePath(source, winslash = "/", mustWork = TRUE)
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  destination <- resolve_figure_destination(destination)
  path_key <- function(path) if (.Platform$OS.type == "windows") tolower(path) else path
  if (identical(path_key(source), path_key(destination)) ||
      startsWith(path_key(destination), paste0(sub("/+$", "", path_key(source)), "/")))
    stop("Supplemental figures must be separate from the published evidence source.")
  if (file.exists(destination) && !dir.exists(destination)) stop("Destination is an existing file.")
  if (dir.exists(destination) && length(list.files(destination, all.files = TRUE, no.. = TRUE)))
    stop("Destination must be new or empty; existing figures are preserved.")
  required_files <- c("metrics.csv", "metric_intervals.csv", "paired_differences.csv", "bootstrap_design.csv")
  manifest_path <- file.path(source, "public_artifact_manifest.csv")
  if (!file.exists(manifest_path)) stop("Source requires a published public_artifact_manifest.csv.")
  manifest_hash <- unname(tools::md5sum(manifest_path))
  manifest <- utils::read.csv(manifest_path, stringsAsFactors = FALSE)
  if (!all(c("file", "bytes", "md5") %in% names(manifest)) || !nrow(manifest) ||
      !is.character(manifest$file) || anyNA(manifest$file) || anyDuplicated(manifest$file) ||
      any(!nzchar(manifest$file)) || any(manifest$file != basename(manifest$file)) ||
      any(grepl("[/\\\\]", manifest$file)) || any(manifest$file %in% c(".", "..")) ||
      !is.character(manifest$md5) || anyNA(manifest$md5) ||
      any(!grepl("^[0-9a-f]{32}$", manifest$md5)) ||
      !is.numeric(manifest$bytes) || anyNA(manifest$bytes) ||
      any(!is.finite(manifest$bytes) | manifest$bytes < 0 | manifest$bytes != floor(manifest$bytes)))
    stop("Invalid published artifact manifest.")
  if (!all(required_files %in% manifest$file)) stop("Published manifest lacks required aggregate tables.")
  selected <- manifest[match(required_files, manifest$file), , drop = FALSE]
  aggregate_paths <- file.path(source, required_files)
  info <- file.info(aggregate_paths)
  actual <- unname(tools::md5sum(aggregate_paths))
  if (anyNA(actual) || anyNA(info$size) || any(info$isdir) ||
      !identical(actual, selected$md5) || !all(info$size == selected$bytes))
    stop("Published aggregate hashes or byte sizes do not match the source manifest.")

  # No aggregate CSV is parsed until all four hashes and sizes have passed.
  tables <- lapply(aggregate_paths, utils::read.csv, stringsAsFactors = FALSE)
  names(tables) <- sub("[.]csv$", "", required_files)
  metric_names <- c("accuracy", "balanced_accuracy", "recall", "roc_auc", "average_precision")
  models <- c("majority", "logistic", "tree", "forest", "svm")
  metrics <- tables$metrics
  intervals <- tables$metric_intervals
  paired <- tables$paired_differences
  design <- tables$bootstrap_design
  if (!all(c("model", "n", metric_names) %in% names(metrics)) || nrow(metrics) != length(models) ||
      anyNA(metrics$model) || anyDuplicated(metrics$model) || !setequal(metrics$model, models) ||
      !is.numeric(metrics$n) || any(!is.finite(metrics$n) | metrics$n < 1) || length(unique(metrics$n)) != 1L)
    stop("Aggregate metrics must describe all five models on one positive-sized test sample.")
  if (!all(c("model", "metric", "estimate", "lower", "upper", "valid_replicates") %in% names(intervals)) ||
      nrow(intervals) != length(models) * length(metric_names) || anyNA(intervals[c("model", "metric")]) ||
      anyDuplicated(paste(intervals$model, intervals$metric)) ||
      !setequal(paste(intervals$model, intervals$metric), as.vector(outer(models, metric_names, paste))))
    stop("Metric intervals must cover every model and declared metric exactly once.")
  numeric_columns <- c("estimate", "lower", "upper", "valid_replicates")
  for (table in list(intervals, paired)) {
    if (!all(numeric_columns %in% names(table)) ||
        any(!vapply(table[numeric_columns], is.numeric, logical(1))) ||
        any(!is.finite(as.matrix(table[numeric_columns]))))
      stop("Published interval estimates, endpoints, and replicate counts must be finite numeric values.")
  }
  for (metric in metric_names) {
    if (!is.numeric(metrics[[metric]]) || any(!is.finite(metrics[[metric]])))
      stop("Published point metrics must be finite numeric values.")
    rows <- intervals$metric == metric
    expected <- metrics[[metric]][match(intervals$model[rows], metrics$model)]
    if (any(abs(intervals$estimate[rows] - expected) > 1e-12))
      stop("Metric interval point estimates disagree with published metrics.")
  }
  if (any(intervals$lower > intervals$upper) || any(intervals$lower < 0 | intervals$upper > 1))
    stop("Published metric interval bounds must be ordered and within 0-1.")
  if (!all(c("replicates", "n_rows", "n_clusters", "method", "confidence", "conditional_on_fitted_models") %in% names(design)) ||
      nrow(design) != 1L || !isTRUE(design$method == "paired_raw_predictor_cluster_percentile") ||
      !isTRUE(abs(design$confidence - 0.95) < 1e-12) || !isTRUE(design$conditional_on_fitted_models) ||
      !isTRUE(design$n_rows == metrics$n[1L]) || !isTRUE(design$n_clusters > 0) ||
      !isTRUE(design$replicates >= 2) || any(intervals$valid_replicates != design$replicates) ||
      any(paired$valid_replicates != design$replicates))
    stop("Bootstrap design must confirm complete conditional 95% paired cluster intervals.")

  code_files <- c("scripts/render_evidence_figures.R", "R/plots.R")
  code_paths <- file.path(root, code_files)
  if (any(!file.exists(code_paths))) stop("Rendering source files are missing.")
  code_hashes <- unname(tools::md5sum(code_paths))
  old_libraries <- .libPaths()
  on.exit(.libPaths(old_libraries), add = TRUE)
  if (dir.exists(file.path(root, ".R-library"))) .libPaths(c(file.path(root, ".R-library"), .libPaths()))
  if (!requireNamespace("ggplot2", quietly = TRUE)) stop("Rendering requires the installed ggplot2 package.")
  plotting <- new.env(parent = globalenv())
  sys.source(file.path(root, "R", "plots.R"), envir = plotting)
  subtitle <- sprintf("SUPPLEMENTAL RE-RENDER | Published v2 aggregates | %s test records | %s paired bootstrap replicates",
    format(design$n_rows, big.mark = ",", scientific = FALSE),
    format(design$replicates, big.mark = ",", scientific = FALSE))
  plots <- list(model_comparison = plotting$income_metric_plot(tables, subtitle),
    paired_differences = plotting$income_paired_difference_plot(tables, subtitle))
  # The plot helper above also requires every pair/metric and consistent sign orientation.
  for (metric in metric_names) {
    rows <- paired$metric == metric
    expected <- metrics[[metric]][match(paired$model_a[rows], metrics$model)] -
      metrics[[metric]][match(paired$model_b[rows], metrics$model)]
    if (any(abs(paired$estimate[rows] - expected) > 1e-12))
      stop("Paired point estimates disagree with model_a minus model_b in published metrics.")
  }
  if (!dir.exists(destination) && !dir.create(destination, recursive = TRUE, showWarnings = FALSE))
    stop("Cannot create supplemental figure destination.")
  for (name in names(plots)) plotting$save_income_figure(plots[[name]], destination, name)
  if (!identical(unname(tools::md5sum(aggregate_paths)), selected$md5) ||
      !identical(unname(tools::md5sum(manifest_path)), manifest_hash) ||
      !identical(unname(tools::md5sum(code_paths)), code_hashes))
    stop("Source evidence or plotting code changed during rendering; figures were not finalized.")
  repo_path <- function(path) {
    normalized <- normalizePath(path, winslash = "/", mustWork = TRUE)
    if (startsWith(tolower(normalized), paste0(tolower(root), "/")))
      substring(normalized, nchar(root) + 2L) else basename(normalized)
  }
  provenance <- data.frame(role = c(rep("published_aggregate", length(aggregate_paths)), "published_manifest", rep("render_source", length(code_paths))),
    file = c(vapply(aggregate_paths, repo_path, character(1)), repo_path(manifest_path), code_files),
    bytes = file.info(c(aggregate_paths, manifest_path, code_paths))$size,
    md5 = c(selected$md5, manifest_hash, code_hashes))
  utils::write.csv(provenance, file.path(destination, "provenance.csv"), row.names = FALSE)
  writeLines(c("operation: supplemental re-render of published aggregate tables", "refit: false",
    "bootstrap_recomputed: false", "published_evidence_modified: false",
    paste0("source_directory: ", repo_path(source)),
    paste0("R_version: ", R.version.string), paste0("ggplot2_version: ", utils::packageVersion("ggplot2")),
    paste0("locale: ", Sys.getlocale()), "PNG_dimensions: 2400 x 1500 pixels",
    "PDF_dimensions: 12 x 7.5 inches", "plot_source_hash_algorithm: MD5",
    "source_validation: all four aggregate CSV hashes and sizes checked against public_artifact_manifest.csv before CSV parsing"),
    file.path(destination, "render_context.txt"))
  writeLines(c("# Supplemental v2 uncertainty figures", "",
    "These figures re-render already published aggregate evidence. No models were refitted, no bootstrap draws were made, and no intervals were recomputed.",
    "The original v2 full-run evidence, plots, reports, and manifests remain unchanged.", "",
    "- `model_comparison.png` and `.pdf`: all five models across the original four comparison metrics, with small hollow markers and foreground interval bars on a common 0-1 metric scale.",
    "- `paired_differences.png` and `.pdf`: all six trained-model pairs across all five declared bootstrap metrics, with a shared symmetric scale centered at zero.",
    "- PNGs are 2400 x 1500 pixels. PDFs are 12 x 7.5 inches.", "",
    "## Interpretation", "",
    "Paired differences are `model_a - model_b`; each row names `model_a` first. Positive differences favor the first model for every displayed metric.",
    "Differences retain raw metric units: 0.01 is one percentage point for accuracy, balanced accuracy, and recall; it is 0.01 score units for ROC AUC and average precision.",
    sprintf("Intervals are conditional 95%% percentile intervals from %s shared bootstrap draws of %s raw-predictor clusters in the %s-record reused benchmark test sample.",
      format(design$replicates, big.mark = ","), format(design$n_clusters, big.mark = ","), format(design$n_rows, big.mark = ",")),
    "They condition on the fitted models, exclude training variability, and are not adjusted for multiple comparisons. A zero-crossing interval does not establish equivalence. These are historical benchmark results, not population estimates or a new confirmatory test.", "",
    "## Reproduction and provenance", "",
    "From the repository root, use a new or empty output directory:", "", "```text",
    paste("Rscript --vanilla scripts/render_evidence_figures.R", repo_path(source), "docs/figures/NEW-EMPTY-DIRECTORY"), "```", "",
    "The renderer verifies all four source aggregate hashes and byte sizes against the source public manifest before reading aggregate tables. It refuses nonempty destinations and paths inside the published evidence source, resolving new paths through their existing parent directories. It does not access raw inputs or saved models.",
    "`provenance.csv` records the exact aggregate inputs, published manifest, rendering script, and current plotting-code hashes. `render_context.txt` records the observed R/ggplot2 versions and locale. `figure_manifest.csv` checks the supplemental outputs.",
    "The original evidence's source manifest continues to describe its original full run; this folder's plotting provenance is separate."),
    file.path(destination, "README.md"))
  outputs <- list.files(destination, full.names = TRUE)
  utils::write.csv(data.frame(file = basename(outputs), bytes = file.info(outputs)$size,
    md5 = unname(tools::md5sum(outputs))), file.path(destination, "figure_manifest.csv"), row.names = FALSE)
  message("Rendered supplemental aggregate figures: ", normalizePath(destination))
  invisible(provenance)
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) != 2L)
    stop("Usage: Rscript --vanilla scripts/render_evidence_figures.R PUBLISHED_EVIDENCE_DIRECTORY NEW_FIGURE_DIRECTORY")
  invocation <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  root <- dirname(dirname(normalizePath(sub("^--file=", "", invocation[1L]))))
  render_evidence_figures(args[[1L]], args[[2L]], root)
}
