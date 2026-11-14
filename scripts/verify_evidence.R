#!/usr/bin/env Rscript
# Read-only integrity checks for published evidence and its preserved source.
# Run from any directory: Rscript --vanilla scripts/verify_evidence.R

evidence_stop <- function(label, message) stop(label, ": ", message, call. = FALSE)

evidence_paths <- function(paths, label) {
  if (!length(paths) || anyNA(paths) || any(!nzchar(paths)))
    evidence_stop(label, "file paths must be nonempty.")
  if (anyDuplicated(tolower(paths))) evidence_stop(label, "duplicate file paths (case-insensitive).")
  # Use a deliberately narrow portable grammar. Reject traversal, absolute paths,
  # Windows drive/stream syntax, backslashes, and noncanonical path components.
  for (path in paths) {
    parts <- strsplit(path, "/", fixed = TRUE)[[1L]]
    if (!grepl("^[A-Za-z0-9._/-]+$", path) || startsWith(path, "/") ||
        endsWith(path, "/") || any(!nzchar(parts) | parts %in% c(".", "..")) ||
        any(grepl("[.]$", parts)) ||
        any(grepl("^(con|prn|aux|nul|com[1-9]|lpt[1-9])([.]|$)", parts, ignore.case = TRUE)))
      evidence_stop(label, paste0("unsafe or noncanonical file path: ", path))
  }
  invisible(paths)
}

evidence_file <- function(directory, path, label) {
  evidence_paths(path, label)
  if (!dir.exists(directory)) evidence_stop(label, paste0("missing directory: ", directory))
  base <- normalizePath(directory, winslash = "/", mustWork = TRUE)
  file <- file.path(base, path)
  if (!file.exists(file) || dir.exists(file)) evidence_stop(label, paste0("missing file: ", path))
  resolved <- normalizePath(file, winslash = "/", mustWork = TRUE)
  compare <- if (.Platform$OS.type == "windows") tolower else identity
  if (!startsWith(compare(resolved), paste0(compare(base), "/")))
    evidence_stop(label, paste0("file resolves outside its root: ", path))
  # Symlinks must not silently change which preserved bytes are checked.
  components <- strsplit(path, "/", fixed = TRUE)[[1L]]
  for (i in seq_along(components)) {
    link <- Sys.readlink(file.path(base, paste(components[seq_len(i)], collapse = "/")))
    if (!is.na(link) && nzchar(link)) evidence_stop(label, paste0("symbolic link is not allowed: ", path))
  }
  file
}

evidence_csv <- function(path, columns, label, empty = FALSE) {
  if (!file.exists(path) || dir.exists(path)) evidence_stop(label, "missing manifest.")
  value <- tryCatch(utils::read.csv(path, colClasses = "character", check.names = FALSE,
    stringsAsFactors = FALSE, na.strings = NULL, strip.white = FALSE, fill = FALSE,
    blank.lines.skip = FALSE, comment.char = "", row.names = NULL),
    error = function(error) evidence_stop(label, paste0("invalid CSV: ", conditionMessage(error))))
  # Result tables write missing values as empty fields; manifests may not.
  if (!identical(names(value), columns) || !nrow(value) || anyNA(value) ||
      (!empty && any(!nzchar(as.matrix(value)))))
    evidence_stop(label, paste0("invalid schema; expected ", if (empty) "" else "nonempty ",
      "columns: ", paste(columns, collapse = ", ")))
  value
}

evidence_set <- function(actual, expected, label) {
  missing <- setdiff(expected, actual)
  extra <- setdiff(actual, expected)
  if (length(missing) || length(extra)) evidence_stop(label, paste0(
    "inventory mismatch; missing: ", paste(missing, collapse = ", "),
    "; unexpected: ", paste(extra, collapse = ", ")))
  invisible(TRUE)
}

verify_evidence_records <- function(manifest, directory, algorithm = "md5", sizes = TRUE, label = directory) {
  evidence_paths(manifest$file, label)
  pattern <- if (identical(algorithm, "sha256")) "^[0-9a-fA-F]{64}$" else "^[0-9a-fA-F]{32}$"
  if (any(!grepl(pattern, manifest[[algorithm]]))) evidence_stop(label, paste0("invalid ", algorithm, " digest."))
  if (sizes && any(!grepl("^(0|[1-9][0-9]*)$", manifest$bytes) |
                   !is.finite(suppressWarnings(as.numeric(manifest$bytes)))))
    evidence_stop(label, "invalid byte size.")
  files <- vapply(manifest$file, function(path) evidence_file(directory, path, label), character(1))
  if (sizes) {
    invalid <- which(file.info(files)$size != as.numeric(manifest$bytes))
    if (length(invalid)) evidence_stop(label, paste0("byte size mismatch: ", manifest$file[invalid[1L]]))
  }
  hash <- if (identical(algorithm, "sha256")) tools::sha256sum else tools::md5sum
  actual <- unname(hash(files))
  invalid <- which(is.na(actual) | tolower(actual) != tolower(manifest[[algorithm]]))
  if (length(invalid)) evidence_stop(label, paste0(algorithm, " mismatch: ", manifest$file[invalid[1L]]))
  invisible(manifest)
}

verify_evidence_manifest <- function(directory, manifest_name, algorithm = "md5",
                                     sizes = TRUE, expected = NULL, complete = FALSE,
                                     label = directory) {
  columns <- c("file", if (sizes) "bytes", algorithm)
  manifest <- evidence_csv(evidence_file(directory, manifest_name, label), columns, label)
  evidence_paths(manifest$file, label)
  if (manifest_name %in% manifest$file) evidence_stop(label, "manifest must not include itself.")
  if (!is.null(expected)) evidence_set(manifest$file, expected, label)
  if (complete) {
    actual <- list.files(directory, all.files = TRUE, recursive = TRUE, include.dirs = FALSE,
      no.. = TRUE)
    evidence_set(actual, c(manifest$file, manifest_name), label)
  }
  verify_evidence_records(manifest, directory, algorithm, sizes, label)
}

verify_evidence_sources <- function(evidence, snapshot, expected, label) {
  manifest <- evidence_csv(evidence_file(evidence, "source_manifest.csv", label), c("file", "md5"), label)
  evidence_paths(manifest$file, label)
  evidence_set(manifest$file, expected, label)
  if (any(!grepl("^[0-9a-fA-F]{32}$", manifest$md5))) evidence_stop(label, "invalid md5 digest.")
  files <- vapply(manifest$file, function(path) evidence_file(snapshot, path, label), character(1))
  invalid <- which(is.na(tools::md5sum(files)) |
    tolower(unname(tools::md5sum(files))) != tolower(manifest$md5))
  if (length(invalid)) evidence_stop(label, paste0("source snapshot md5 mismatch: ", manifest$file[invalid[1L]]))
  invisible(nrow(manifest))
}

# Read literal declarations without sourcing or evaluating archived R code.
evidence_literal <- function(path, name, label) {
  expressions <- parse(path, keep.source = FALSE)
  matches <- Filter(function(expression) is.call(expression) &&
    identical(expression[[1L]], as.name("<-")) && identical(expression[[2L]], as.name(name)),
    as.list(expressions))
  if (length(matches) != 1L) evidence_stop(label, paste0("missing or duplicate declaration: ", name))
  value <- matches[[1L]][[3L]]
  if (is.character(value) && length(value) == 1L) return(value)
  if (!is.call(value) || !identical(value[[1L]], as.name("c")))
    evidence_stop(label, paste0("expected literal declaration: ", name))
  values <- as.list(value)[-1L]
  if (!length(values) || !all(vapply(values, function(x) is.character(x) && length(x) == 1L, logical(1))))
    evidence_stop(label, paste0("expected string literals: ", name))
  unlist(values, use.names = TRUE)
}

verify_evidence_inputs <- function(directory, snapshot, label) {
  manifest <- evidence_csv(file.path(directory, "input_manifest.csv"),
    c("file", "md5", "bytes", "matches_uci_reference", "reference_url"), label)
  evidence_paths(manifest$file, label)
  checksums <- c(adult.data = "5d7c39d7b8804f071cdd1f2a7c460872",
    adult.test = "35238206dfdf7f1fe215bbb874adecdc", adult.names = "1a7cdb3ff7a1b709968b1c7a11def63e")
  sizes <- c(adult.data = "3974305", adult.test = "2003153")
  url <- "https://archive.ics.uci.edu/ml/machine-learning-databases/adult/"
  evidence_set(manifest$file, names(sizes), label)
  data_source <- evidence_file(snapshot, "R/data.R", label)
  declared <- evidence_literal(data_source, "adult_checksums", label)
  if (anyDuplicated(names(declared)) || !setequal(names(declared), names(checksums)) ||
      !identical(unname(declared[names(checksums)]), unname(checksums)) ||
      !identical(evidence_literal(data_source, "adult_base_url", label), url))
    evidence_stop(label, "archived source input declarations differ from published UCI references.")
  if (any(manifest$md5 != unname(checksums[manifest$file])) ||
      any(manifest$bytes != unname(sizes[manifest$file])) ||
      any(manifest$matches_uci_reference != "TRUE") ||
      any(manifest$reference_url != paste0(url, manifest$file)))
    evidence_stop(label, "input checksum, byte size, verification flag, or reference URL differs from declared UCI reference.")
  invisible(TRUE)
}

verify_evidence_packages <- function(directory, snapshot, version, label) {
  packages <- evidence_csv(file.path(directory, "package_versions.csv"), c("package", "version"), label)
  if (anyDuplicated(packages$package) || any(!grepl("^[A-Za-z][A-Za-z0-9.]*$", packages$package)) ||
      any(!grepl("^[0-9]+([.-][0-9]+)*$", packages$version)))
    evidence_stop(label, "invalid or duplicate package records.")
  if (version == 1L) {
    expected <- evidence_literal(evidence_file(snapshot, "scripts/install_dependencies.R", label), "required", label)
    evidence_set(packages$package, expected, label)
    # Version 1 records observed versions only; no historical lockfile exists.
  } else {
    if (!requireNamespace("renv", quietly = TRUE))
      evidence_stop(label, "renv is required to read the preserved lockfile; use the recorded project dependencies.")
    lock <- renv::lockfile_read(evidence_file(snapshot, "renv.lock", label))
    if (!identical(lock$R$Version, "4.6.1")) evidence_stop(label, "preserved lockfile R version must be 4.6.1.")
    if (anyDuplicated(names(lock$Packages))) evidence_stop(label, "duplicate lockfile package records.")
    evidence_set(packages$package, names(lock$Packages), label)
    expected <- vapply(lock$Packages[packages$package], function(package) package$Version, character(1))
    invalid <- which(packages$version != unname(expected))
    if (length(invalid)) evidence_stop(label, paste0("package version differs from preserved lockfile: ",
      packages$package[invalid[1L]]))
  }
  invisible(nrow(packages))
}

evidence_cv_metric_columns <- c("model", "candidate", "parameter_rule", "parameter", "fold", "n_analysis",
  "n_features", "n", "n_positive", "n_negative", "positive_rate", "accuracy", "balanced_accuracy",
  "precision", "recall", "specificity", "f1", "roc_auc", "average_precision", "tp", "tn", "fp", "fn",
  "elapsed_seconds", "selected")
evidence_cv_summary_columns <- c("model", "candidate", "parameter_rule", "parameter", "order",
  "sd_balanced_accuracy", "mean_balanced_accuracy", "nfolds", "selected")
evidence_grid_columns <- c("model", "selected_candidate", "selected_index", "n_candidates", "position",
  "bracketed", "neighbour_side", "neighbour_candidate", "nfolds", "margin", "folds_selection_higher",
  "folds_tied", "margin_label")

# Recomputed means and margins may differ from published ones in the last bits on
# another platform; scripts/verify_results_summary.R uses the same tolerance.
evidence_tolerance <- 1e-12

evidence_numbers <- function(values, label) {
  numbers <- suppressWarnings(as.numeric(values))
  if (!length(numbers) || anyNA(numbers) || any(!is.finite(numbers)))
    evidence_stop(label, "invalid numeric cross-validation field.")
  numbers
}

# Recompute each selection and its declared grid position from the published fold
# scores, independently of the pipeline code (docs/METHODOLOGY_V3.md).
verify_evidence_grid_position <- function(directory, label, margin = 0.001,
                                          limits = c(tree = "cp=-1", forest = "mtry=all")) {
  summary <- evidence_csv(evidence_file(directory, "cv_summary.csv", label),
    evidence_cv_summary_columns, label, empty = TRUE)
  metrics <- evidence_csv(evidence_file(directory, "cv_metrics.csv", label),
    evidence_cv_metric_columns, label, empty = TRUE)
  recorded <- evidence_csv(evidence_file(directory, "grid_position.csv", label),
    evidence_grid_columns, label, empty = TRUE)
  expected <- list()
  for (kind in unique(summary$model)) {
    family <- summary[summary$model == kind, , drop = FALSE]
    family <- family[order(evidence_numbers(family$order, label)), , drop = FALSE]
    folds <- lapply(family$candidate, function(candidate) {
      rows <- metrics[metrics$model == kind & metrics$candidate == candidate, , drop = FALSE]
      rows[order(evidence_numbers(rows$fold, label)), , drop = FALSE]
    })
    if (any(vapply(folds, function(rows) !nrow(rows) || !identical(rows$fold, folds[[1L]]$fold), logical(1))))
      evidence_stop(label, paste0("candidates lack scores on the same folds: ", kind))
    means <- vapply(folds, function(rows) mean(evidence_numbers(rows$balanced_accuracy, label)), numeric(1))
    chosen <- which.max(means)
    if (any(abs(evidence_numbers(family$mean_balanced_accuracy, label) - means) > evidence_tolerance) ||
        !identical(family$selected, ifelse(seq_along(means) == chosen, "TRUE", "FALSE")))
      evidence_stop(label, paste0("fold means or selection differ from the fold scores: ", kind))
    if (kind == "majority") next
    n <- nrow(family)
    position <- if (n == 1L) "single_candidate" else if (chosen > 1L && chosen < n) "interior" else
      if (identical(unname(limits[kind]), family$candidate[chosen])) "parameter_limit" else "grid_edge"
    base <- c(kind, family$candidate[chosen], chosen, n, position, if (position == "interior") "TRUE" else "FALSE")
    neighbours <- c(preceding = chosen - 1L, following = chosen + 1L)
    neighbours <- neighbours[neighbours >= 1L & neighbours <= n]
    if (!length(neighbours)) expected[[length(expected) + 1L]] <- c(base, rep("", 7L))
    for (side in names(neighbours)) {
      difference <- evidence_numbers(folds[[chosen]]$balanced_accuracy, label) -
        evidence_numbers(folds[[neighbours[[side]]]]$balanced_accuracy, label)
      value <- mean(difference)
      expected[[length(expected) + 1L]] <- c(base, side, family$candidate[neighbours[[side]]],
        length(difference), sprintf("%.17g", value), sum(difference > 0), sum(difference == 0),
        if (value < margin) "plateau" else "separated")
    }
  }
  expected <- unname(do.call(rbind, expected))
  actual <- unname(as.matrix(recorded))
  if (!identical(dim(expected), dim(actual)))
    evidence_stop(label, "grid position differs from recomputation from the fold scores: different number of records")
  differs <- expected != actual
  # Margins are compared as numbers; every other field must match exactly.
  column <- match("margin", evidence_grid_columns)
  filled <- nzchar(expected[, column]) & nzchar(actual[, column])
  if (any(filled)) differs[filled, column] <- abs(evidence_numbers(expected[filled, column], label) -
    evidence_numbers(actual[filled, column], label)) > evidence_tolerance
  if (any(differs)) {
    where <- which(differs, arr.ind = TRUE)
    evidence_stop(label, paste0("grid position differs from recomputation from the fold scores: row ",
      where[1L, 1L], ", column ", evidence_grid_columns[where[1L, 2L]]))
  }
  invisible(nrow(recorded))
}

# Version 3 reran every version 2 candidate on the same folds with the same seeds,
# so each version 2 fold record must reappear unchanged apart from fit time and
# selection, and the tables of the unchanged data handling must match exactly.
verify_evidence_reproduction <- function(previous, current, label) {
  read <- function(directory) evidence_csv(evidence_file(directory, "cv_metrics.csv", label),
    evidence_cv_metric_columns, label, empty = TRUE)
  old <- read(previous); new <- read(current)
  key <- function(x) paste(x$model, x$candidate, x$fold, sep = "\t")
  if (anyDuplicated(key(old)) || anyDuplicated(key(new))) evidence_stop(label, "duplicate fold records.")
  rows <- match(key(old), key(new))
  if (anyNA(rows)) evidence_stop(label, paste0("version 2 fold record missing: ", key(old)[is.na(rows)][1L]))
  for (column in setdiff(evidence_cv_metric_columns, c("elapsed_seconds", "selected"))) {
    differ <- which(old[[column]] != new[[column]][rows])
    if (length(differ)) evidence_stop(label, paste0("version 2 fold result not reproduced: ",
      old$model[differ[1L]], " ", old$candidate[differ[1L]], " fold ", old$fold[differ[1L]], ", ", column))
  }
  for (file in c("data_audit.csv", "profile_overlap.csv", "unseen_categories.csv", "input_manifest.csv",
                 "package_versions.csv"))
    if (!identical(unname(tools::md5sum(evidence_file(previous, file, label))),
                   unname(tools::md5sum(evidence_file(current, file, label)))))
      evidence_stop(label, paste0("table of the unchanged data handling differs from version 2: ", file))
  invisible(length(rows))
}

evidence_diagnostic_columns <- c("model", "fit_ok", "converged", "solver_status", "finite_parameters",
  "n_training", "n_features", "stage", "candidate")

# A published run must record itself as a complete full run of its protocol version. Its
# diagnostics must show one accepted fit for every fold record and for every selected setting.
verify_evidence_run <- function(directory, version, label) {
  config <- readLines(evidence_file(directory, "run_config.txt", label), warn = FALSE)
  for (entry in c(paste("methodology_version:", version), "mode: full", "status: complete")) {
    key <- paste0(sub(":.*$", "", entry), ":")
    if (sum(startsWith(config, key)) != 1L || !entry %in% config)
      evidence_stop(label, paste0("run configuration does not record ", entry))
  }
  fits <- evidence_csv(evidence_file(directory, "diagnostics.csv", label),
    evidence_diagnostic_columns, label, empty = TRUE)
  folds <- evidence_csv(evidence_file(directory, "cv_metrics.csv", label),
    evidence_cv_metric_columns, label, empty = TRUE)
  summary <- evidence_csv(evidence_file(directory, "cv_summary.csv", label),
    evidence_cv_summary_columns, label, empty = TRUE)
  chosen <- summary[summary$selected == "TRUE", , drop = FALSE]
  recorded <- paste(fits$model, fits$candidate, fits$stage, sep = "\t")
  expected <- c(paste(folds$model, folds$candidate, paste0("fold_", folds$fold), sep = "\t"),
    paste(chosen$model, chosen$candidate, "final", sep = "\t"))
  if (anyDuplicated(recorded) || anyDuplicated(expected) || !setequal(recorded, expected))
    evidence_stop(label, "diagnostics do not record one fit for every fold record and every selected setting.")
  ridge <- fits$model == "logistic"
  # Version 2 could not observe the SVM solver's iteration limit; version 3 records it.
  solver <- version >= 3L & fits$model == "svm"
  if (any(fits$fit_ok != "TRUE") || any(fits$converged[ridge | solver] != "TRUE") ||
      any(fits$solver_status[ridge] != "0") || any(fits$finite_parameters[ridge] != "TRUE"))
    evidence_stop(label, "diagnostics record a fit that failed, did not converge, or reached a solver limit.")
  invisible(nrow(fits))
}

verify_public_evidence <- function(root = getwd(), quiet = FALSE) {
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  if (!"sha256sum" %in% getNamespaceExports("tools")) evidence_stop("runtime", "R 4.6.1 with tools::sha256sum is required.")
  old_libraries <- .libPaths()
  on.exit(.libPaths(old_libraries), add = TRUE)
  if (dir.exists(file.path(root, ".R-library"))) .libPaths(c(file.path(root, ".R-library"), old_libraries))
  v1 <- file.path(root, "docs/evidence/full-2026-10-08")
  v2 <- file.path(root, "docs/evidence/v2-full-2026-10-08")
  v3 <- file.path(root, "docs/evidence/v3-full-2026-11-14")
  snapshot1 <- file.path(root, "archive/v1-2026-10-08")
  snapshot2 <- file.path(root, "archive/v2-2026-10-08")
  snapshot3 <- file.path(root, "archive/v3-2026-11-14")
  v1_files <- c("report.md", "metrics.csv", "validation_metrics.csv", "selected_parameters.csv",
    "subgroup_metrics.csv", "data_audit.csv", "input_manifest.csv", "source_manifest.csv",
    "package_versions.csv", "run_config.txt", "warnings.txt", "unseen_categories.csv",
    "model_comparison.png", "roc_curves.png", "README.md")
  v2_files <- c("report.md", "metrics.csv", "cv_metrics.csv", "cv_summary.csv", "selected_parameters.csv",
    "diagnostics.csv", "subgroup_metrics.csv", "metric_intervals.csv", "paired_differences.csv",
    "bootstrap_design.csv", "calibration.csv", "profile_overlap.csv", "profile_sensitivity.csv",
    "data_audit.csv", "input_manifest.csv", "source_manifest.csv", "package_versions.csv",
    "run_config.txt", "warnings.txt", "unseen_categories.csv", "methodology.md",
    paste0(rep(c("model_comparison", "roc_pr_curves", "confusion_matrices", "calibration",
      "subgroup_recall", "cv_comparison"), 2L), rep(c(".png", ".pdf"), each = 6L)), "README.md")
  sources1 <- c("IncomeLevelPrediction.R", "R/data.R", "R/models.R", "R/pipeline.R")
  sources2 <- c("IncomeLevelPrediction.R", "R/data.R", "R/models.R", "R/evaluation.R", "R/plots.R",
    "R/reporting.R", "R/pipeline.R", "renv.lock", "docs/METHODOLOGY_V2.md")
  # Version 3 publishes the version 2 files plus its grid-position table.
  v3_files <- c(v2_files, "grid_position.csv")
  sources3 <- c(setdiff(sources2, "docs/METHODOLOGY_V2.md"), "docs/METHODOLOGY_V3.md")
  snapshot1_files <- c(".gitignore", "IncomeLevelPrediction.R", "README.md", ".github/workflows/check.yml",
    "data/README.md", "docs/CODE_REVIEW.md", "docs/PORTFOLIO_HANDOFF.md", "docs/VALIDATION.md",
    paste0("docs/evidence/full-2026-10-08/", c(v1_files, "public_artifact_manifest.csv")),
    "R/data.R", "R/models.R", "R/pipeline.R", "scripts/export_evidence.R", "scripts/install_dependencies.R",
    "tests/run_tests.R")
  verify_evidence_manifest(v1, "public_artifact_manifest.csv", expected = v1_files,
    complete = TRUE, label = "v1 public artifacts")
  verify_evidence_manifest(v2, "public_artifact_manifest.csv", expected = v2_files,
    complete = TRUE, label = "v2 public artifacts")
  verify_evidence_manifest(v3, "public_artifact_manifest.csv", expected = v3_files,
    complete = TRUE, label = "v3 public artifacts")
  verify_evidence_manifest(snapshot1, "snapshot_manifest.csv", algorithm = "sha256", sizes = FALSE,
    expected = snapshot1_files, complete = TRUE, label = "v1 SHA-256 snapshot")
  archived_v1 <- file.path(snapshot1, "docs/evidence/full-2026-10-08")
  verify_evidence_manifest(archived_v1, "public_artifact_manifest.csv", expected = v1_files,
    complete = TRUE, label = "archived v1 public artifacts")
  verify_evidence_sources(v1, snapshot1, sources1, "v1 source provenance")
  verify_evidence_sources(archived_v1, snapshot1, sources1, "archived v1 source provenance")
  verify_evidence_sources(v2, snapshot2, sources2, "v2 source provenance")
  verify_evidence_sources(v3, snapshot3, sources3, "v3 source provenance")
  original <- evidence_file(file.path(root, "archive"), "IncomeLevelPrediction_original.R", "original script")
  expected_original <- "3ad3bb786273ca05425185d9cffe789960ce00d0feb317fcaa2aa246978dbb5f"
  if (!identical(tolower(unname(tools::sha256sum(original))), expected_original))
    evidence_stop("original script", "published SHA-256 mismatch.")
  verify_evidence_inputs(v1, snapshot1, "v1 input provenance")
  verify_evidence_inputs(v2, snapshot2, "v2 input provenance")
  verify_evidence_inputs(v3, snapshot3, "v3 input provenance")
  packages1 <- verify_evidence_packages(v1, snapshot1, 1L, "v1 package evidence")
  packages2 <- verify_evidence_packages(v2, snapshot2, 2L, "v2 package evidence")
  packages3 <- verify_evidence_packages(v3, snapshot3, 3L, "v3 package evidence")
  # Selections are recomputed first, so the run record is checked against verified selections.
  positions <- verify_evidence_grid_position(v3, "v3 grid position")
  fits2 <- verify_evidence_run(v2, 2L, "v2 run record")
  fits3 <- verify_evidence_run(v3, 3L, "v3 run record")
  reproduced <- verify_evidence_reproduction(v2, v3, "v3 reproduction of v2 folds")
  if (!quiet) {
    cat("Verified", length(v1_files), "v1,", length(v2_files), "v2, and", length(v3_files),
      "v3 public artifact hashes/sizes; 30 v1 snapshot SHA-256 hashes.\n")
    cat("Verified v1 (4 files), v2 (9 files), and v3 (9 files) source provenance against preserved snapshots.\n")
    cat("Verified original script SHA-256, declared input references,", packages1, "v1 package records,",
      packages2, "v2 and", packages3, "v3 package versions against the preserved lockfiles.\n")
    cat("Verified complete full-run records with", fits2, "accepted v2 fits and", fits3, "accepted v3 fits.\n")
    cat("Recomputed every v3 selection and", positions, "grid-position records from the published fold scores;",
      reproduced, "v2 fold records reproduced exactly in v3.\n")
    cat("Read-only verification complete. No model fitting, downloading, or historical evidence rewriting.\n")
  }
  invisible(TRUE)
}

verify_supplemental_evidence <- function(root = getwd(), quiet = FALSE) {
  directory <- file.path(root, "docs/figures/v2-uncertainty-review")
  outputs <- c("README.md", "model_comparison.pdf", "model_comparison.png",
    "paired_differences.pdf", "paired_differences.png", "provenance.csv", "render_context.txt")
  verify_evidence_manifest(directory, "figure_manifest.csv", expected = outputs,
    complete = TRUE, label = "supplemental figures")
  provenance <- evidence_csv(evidence_file(directory, "provenance.csv", "supplemental provenance"),
    c("role", "file", "bytes", "md5"), "supplemental provenance")
  inputs <- c(paste0("docs/evidence/v2-full-2026-10-08/",
    c("metrics.csv", "metric_intervals.csv", "paired_differences.csv", "bootstrap_design.csv",
      "public_artifact_manifest.csv")), "scripts/render_evidence_figures.R", "R/plots.R")
  expected_roles <- c(rep("published_aggregate", 4L), "published_manifest", rep("render_source", 2L))
  evidence_set(provenance$file, inputs, "supplemental provenance")
  if (!identical(provenance$role[match(inputs, provenance$file)], expected_roles))
    evidence_stop("supplemental provenance", "unexpected input roles.")
  verify_evidence_records(provenance, root, label = "supplemental provenance")
  if (!quiet) cat("Verified 7 supplemental output hashes/sizes and 7 provenance records against published aggregates and current rendering sources.\n")
  invisible(TRUE)
}

if (sys.nframe() == 0L) {
  # R's Unix front end passes each space in the script path as "~+~".
  invocation <- gsub("~+~", " ", grep("^--file=", commandArgs(FALSE), value = TRUE), fixed = TRUE)
  root <- if (length(invocation)) dirname(dirname(normalizePath(sub("^--file=", "", invocation[1L])))) else getwd()
  args <- commandArgs(TRUE)
  if (length(args)) {
    if (length(args) != 2L || args[1L] != "--root") stop("Usage: verify_evidence.R [--root PATH]", call. = FALSE)
    root <- args[2L]
  }
  verify_public_evidence(root)
  verify_supplemental_evidence(root)
}
