#!/usr/bin/env Rscript
# Copy an explicit allowlist of aggregate evidence from a completed reference run.
# Raw records, predictions, split identifiers, model objects, and libraries stay local.
export_evidence <- function(source, destination) {
  manifest_path <- file.path(source, "artifact_manifest.csv")
  if (!file.exists(manifest_path)) stop("Source must be a completed run with an artifact manifest.")
  if (file.exists(destination) && !dir.exists(destination)) stop("Destination is an existing file.")
  if (dir.exists(destination) && length(list.files(destination, all.files = TRUE, no.. = TRUE)))
    stop("Destination must be new or empty; existing evidence is preserved.")
  manifest <- utils::read.csv(manifest_path, stringsAsFactors = FALSE)
  if (!all(c("file", "md5") %in% names(manifest)) || anyDuplicated(manifest$file) ||
      anyNA(manifest$file) || any(manifest$file != basename(manifest$file)) ||
      any(grepl("[/\\\\]", manifest$file)) || any(manifest$file %in% c(".", "..")))
    stop("Invalid run artifact manifest.")
  actual <- unname(tools::md5sum(file.path(source, manifest$file)))
  if (anyNA(actual) || !identical(actual, manifest$md5)) stop("Run artifacts no longer match their recorded hashes.")
  config <- readLines(file.path(source, "run_config.txt"), warn = FALSE)
  if (!"mode: full" %in% config) stop("Only full runs can be exported as portfolio evidence.")
  inputs <- utils::read.csv(file.path(source, "input_manifest.csv"), stringsAsFactors = FALSE)
  reference_hashes <- c(adult.data = "5d7c39d7b8804f071cdd1f2a7c460872",
    adult.test = "35238206dfdf7f1fe215bbb874adecdc")
  if (!all(c("file", "md5", "matches_uci_reference") %in% names(inputs)) ||
      nrow(inputs) != 2L || anyNA(inputs$file) || anyDuplicated(inputs$file) ||
      !setequal(inputs$file, names(reference_hashes)) ||
      !all(inputs$matches_uci_reference %in% TRUE) || anyNA(inputs$md5) ||
      !identical(inputs$md5, unname(reference_hashes[inputs$file])))
    stop("Portfolio evidence export requires checksum-verified reference inputs.")
  files <- c("report.md", "metrics.csv", "validation_metrics.csv", "selected_parameters.csv",
    "subgroup_metrics.csv", "data_audit.csv", "input_manifest.csv", "source_manifest.csv",
    "package_versions.csv", "run_config.txt", "warnings.txt", "unseen_categories.csv",
    "model_comparison.png", "roc_curves.png")
  if (!all(files %in% manifest$file)) stop("Run lacks expected evidence files.")
  dir.create(destination, recursive = TRUE, showWarnings = FALSE)
  if (!all(file.copy(file.path(source, files), file.path(destination, files), overwrite = FALSE)))
    stop("Could not copy every evidence artifact.")
  copied_hashes <- unname(tools::md5sum(file.path(destination, files)))
  if (anyNA(copied_hashes) ||
      !identical(copied_hashes, manifest$md5[match(files, manifest$file)]))
    stop("Copied artifacts do not match the completed run; evidence was not finalized.")
  writeLines(c("# Reviewed aggregate evidence", "",
    "This folder contains aggregate outputs from one completed full reference-data run.",
    "The report describes additional local artifacts that are intentionally omitted here:",
    "record-level predictions, split identifiers, model objects, and machine-specific session details.",
    "Input files are downloaded separately. Regenerate the complete run with the project entry point.", "",
    "See run_config.txt for completion time and settings, source_manifest.csv for code hashes,",
    "input_manifest.csv for source checksums, and package_versions.csv for dependency versions.",
    "These historical-data results are not a production deployment or current-population estimate."),
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
    stop("Usage: Rscript scripts/export_evidence.R RESULTS_DIRECTORY NEW_EVIDENCE_DIRECTORY")
  export_evidence(args[[1L]], args[[2L]])
}
