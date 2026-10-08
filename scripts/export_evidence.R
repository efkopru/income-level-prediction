#!/usr/bin/env Rscript
# Export only aggregate artifacts from a completed methodology-v2 reference run.
export_evidence <- function(source, destination) {
  manifest_path <- file.path(source, "artifact_manifest.csv")
  if (!file.exists(manifest_path)) stop("Source must be a completed run with an artifact manifest.")
  if (file.exists(destination) && !dir.exists(destination)) stop("Destination is an existing file.")
  if (dir.exists(destination) && length(list.files(destination, all.files = TRUE, no.. = TRUE)))
    stop("Destination must be new or empty; existing evidence is preserved.")

  manifest <- utils::read.csv(manifest_path, stringsAsFactors = FALSE)
  if (!all(c("file", "md5", "bytes") %in% names(manifest)) || !nrow(manifest) ||
      !is.character(manifest$file) || anyNA(manifest$file) || anyDuplicated(manifest$file) ||
      any(!nzchar(manifest$file)) || any(manifest$file != basename(manifest$file)) ||
      any(grepl("[/\\\\]", manifest$file)) || any(manifest$file %in% c(".", "..")) ||
      !is.character(manifest$md5) || anyNA(manifest$md5) ||
      any(!grepl("^[0-9a-f]{32}$", manifest$md5)) || !is.numeric(manifest$bytes) ||
      anyNA(manifest$bytes) || any(!is.finite(manifest$bytes)) ||
      any(manifest$bytes < 0 | manifest$bytes != floor(manifest$bytes)))
    stop("Invalid run artifact manifest.")
  paths <- file.path(source, manifest$file)
  info <- file.info(paths)
  actual <- unname(tools::md5sum(paths))
  if (anyNA(actual) || anyNA(info$size) || any(info$isdir) ||
      !identical(actual, manifest$md5) || !all(info$size == manifest$bytes))
    stop("Run artifacts no longer match their recorded hashes and byte sizes.")

  plots <- c("model_comparison", "roc_pr_curves", "confusion_matrices", "calibration",
             "subgroup_recall", "cv_comparison")
  files <- c("report.md", "metrics.csv", "cv_metrics.csv", "cv_summary.csv",
    "selected_parameters.csv", "diagnostics.csv", "subgroup_metrics.csv", "metric_intervals.csv",
    "paired_differences.csv", "bootstrap_design.csv", "calibration.csv", "profile_overlap.csv", "profile_sensitivity.csv",
    "data_audit.csv", "input_manifest.csv", "source_manifest.csv", "package_versions.csv",
    "run_config.txt", "warnings.txt", "unseen_categories.csv", "methodology.md",
    paste0(plots, ".png"), paste0(plots, ".pdf"))
  if (!all(files %in% manifest$file)) stop("Run lacks expected methodology-v2 evidence files.")
  config <- readLines(file.path(source, "run_config.txt"), warn = FALSE)
  for (entry in c("mode: full", "methodology_version: 2", "status: complete")) {
    key <- sub(":.*$", "", entry)
    if (sum(startsWith(config, paste0(key, ":"))) != 1L || !entry %in% config)
      stop("Only complete methodology-v2 full runs can be exported as portfolio evidence.")
  }
  inputs <- utils::read.csv(file.path(source, "input_manifest.csv"), stringsAsFactors = FALSE)
  reference_hashes <- c(adult.data = "5d7c39d7b8804f071cdd1f2a7c460872",
    adult.test = "35238206dfdf7f1fe215bbb874adecdc")
  if (!all(c("file", "md5", "matches_uci_reference") %in% names(inputs)) ||
      nrow(inputs) != 2L || anyNA(inputs$file) || anyDuplicated(inputs$file) ||
      !setequal(inputs$file, names(reference_hashes)) ||
      !all(inputs$matches_uci_reference %in% TRUE) || anyNA(inputs$md5) ||
      !identical(inputs$md5, unname(reference_hashes[inputs$file])))
    stop("Portfolio evidence export requires checksum-verified reference inputs.")

  diagnostics <- utils::read.csv(file.path(source, "diagnostics.csv"), stringsAsFactors = FALSE)
  needed <- c("model", "stage", "fit_ok", "converged", "solver_status",
              "finite_parameters", "n_training", "n_features")
  kinds <- c("majority", "logistic", "tree", "forest", "svm")
  if (!all(needed %in% names(diagnostics)) || !nrow(diagnostics) ||
      anyNA(diagnostics$model) || any(!diagnostics$model %in% kinds) ||
      anyNA(diagnostics$stage) || !all(diagnostics$fit_ok %in% TRUE) ||
      anyNA(diagnostics$n_training) || anyNA(diagnostics$n_features) ||
      !is.numeric(diagnostics$n_training) || !is.numeric(diagnostics$n_features) ||
      any(!is.finite(diagnostics$n_training) | diagnostics$n_training < 1) ||
      any(!is.finite(diagnostics$n_features) | diagnostics$n_features < 1))
    stop("Run model diagnostics are incomplete or contain unsuccessful fits.")
  final <- diagnostics[diagnostics$stage == "final", , drop = FALSE]
  logistic <- diagnostics[diagnostics$model == "logistic", , drop = FALSE]
  if (nrow(final) != length(kinds) || anyDuplicated(final$model) ||
      !setequal(final$model, kinds) || !nrow(logistic) ||
      !all(logistic$converged %in% TRUE) || !all(logistic$finite_parameters %in% TRUE) ||
      anyNA(logistic$solver_status) || any(logistic$solver_status != 0))
    stop("Run model diagnostics lack successful final models or a converged finite ridge fit.")

  if (!dir.exists(destination) && !dir.create(destination, recursive = TRUE, showWarnings = FALSE))
    stop("Cannot create evidence destination.")
  if (!all(file.copy(file.path(source, files), file.path(destination, files), overwrite = FALSE)))
    stop("Could not copy every evidence artifact.")
  copied_hashes <- unname(tools::md5sum(file.path(destination, files)))
  match_rows <- match(files, manifest$file)
  if (anyNA(copied_hashes) || !identical(copied_hashes, manifest$md5[match_rows]) ||
      !all(file.info(file.path(destination, files))$size == manifest$bytes[match_rows]))
    stop("Copied artifacts do not match the completed run; evidence was not finalized.")
  writeLines(c("# Reviewed aggregate evidence: methodology version 2", "",
    "This folder contains aggregate outputs from one completed full reference-data run.",
    "The report describes additional local artifacts intentionally omitted here:",
    "record-level predictions, out-of-fold predictions, split/fold identifiers, fitted model objects,",
    "and machine-specific session details. Input files are downloaded separately.", "",
    "See methodology.md for the evaluation protocol, run_config.txt for settings and completion,",
    "source_manifest.csv for code hashes, input_manifest.csv for source checksums, and",
    "package_versions.csv for observed dependency versions. The exporter verifies file integrity",
    "and recorded model health; these checks do not replace substantive result review.", "",
    "The official test benchmark was reused after prior project iterations. Results describe",
    "historical records and are not a fresh confirmatory test or a current-population estimate."),
    file.path(destination, "README.md"))
  public_files <- c(files, "README.md")
  utils::write.csv(data.frame(file = public_files,
    bytes = file.info(file.path(destination, public_files))$size,
    md5 = unname(tools::md5sum(file.path(destination, public_files)))),
    file.path(destination, "public_artifact_manifest.csv"), row.names = FALSE)
  message("Exported aggregate evidence: ", normalizePath(destination))
  invisible(public_files)
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) != 2L)
    stop("Usage: Rscript --vanilla scripts/export_evidence.R RESULTS_DIRECTORY NEW_EVIDENCE_DIRECTORY")
  export_evidence(args[[1L]], args[[2L]])
}
