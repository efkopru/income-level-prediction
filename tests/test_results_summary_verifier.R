#!/usr/bin/env Rscript
# Offline verifier rejection tests; all mutations stay in one temporary copy.
run_results_summary_verifier_tests <- function(root) {
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  old_libraries <- .libPaths()
  on.exit(.libPaths(old_libraries), add = TRUE)
  if (dir.exists(file.path(root, ".R-library")))
    .libPaths(c(file.path(root, ".R-library"), old_libraries))
  source(file.path(root, "scripts/verify_results_summary.R"), local = TRUE)
  source(file.path(root, "scripts/verify_evidence.R"), local = TRUE)

  fixture <- tempfile("income-summary-verifier-", tmpdir = tempdir())
  stopifnot(dir.create(fixture))
  on.exit({
    resolved <- normalizePath(fixture, winslash = "/", mustWork = TRUE)
    temporary <- normalizePath(tempdir(), winslash = "/", mustWork = TRUE)
    if (identical(dirname(resolved), temporary) &&
        startsWith(basename(resolved), "income-summary-verifier-"))
      unlink(resolved, recursive = TRUE)
  }, add = TRUE)
  stopifnot(dir.create(file.path(fixture, "docs")),
    dir.create(file.path(fixture, "scripts")), dir.create(file.path(fixture, "R")),
    file.copy(file.path(root, "archive"), fixture, recursive = TRUE),
    file.copy(file.path(root, "docs/evidence"), file.path(fixture, "docs"), recursive = TRUE),
    file.copy(file.path(root, "docs/figures"), file.path(fixture, "docs"), recursive = TRUE))
  source_files <- c("scripts/create_results_summary.R", "scripts/verify_evidence.R",
    "scripts/render_evidence_figures.R", "R/plots.R", "R/summary_statistics.R",
    "R/summary_plots.R", "R/summary_report.R", "renv.lock")
  for (file in source_files)
    stopifnot(file.copy(file.path(root, file), file.path(fixture, file)))

  preserved <- c(list.files(file.path(root, "archive"), recursive = TRUE,
      all.files = TRUE, full.names = TRUE),
    list.files(file.path(root, "docs/evidence"), recursive = TRUE,
      all.files = TRUE, full.names = TRUE),
    list.files(file.path(root, "docs/figures"), recursive = TRUE,
      all.files = TRUE, full.names = TRUE), file.path(root, source_files))
  before <- tools::md5sum(preserved)
  destination <- file.path(fixture, "docs/figures/v2-results-summary")
  manifest_path <- file.path(destination, "artifact_manifest.csv")
  canonical_manifest <- readBin(manifest_path, "raw", n = file.info(manifest_path)$size)
  passed <- 0L
  check <- function(name, code) {
    force(code)
    passed <<- passed + 1L
    cat("PASS ", name, "\n", sep = "")
  }
  expect_error <- function(code, pattern) {
    error <- tryCatch({ force(code); NULL }, error = identity)
    if (!inherits(error, "error")) stop("Expected verifier rejection: ", pattern)
    if (!grepl(pattern, conditionMessage(error), fixed = TRUE))
      stop("Expected rejection containing '", pattern, "'; received: ", conditionMessage(error))
  }
  corrupt_table <- function(name, change, pattern) {
    path <- file.path(destination, paste0(name, ".csv"))
    original <- readBin(path, "raw", n = file.info(path)$size)
    on.exit({ writeBin(original, path); writeBin(canonical_manifest, manifest_path) }, add = TRUE)
    writeLines(change(readLines(path, warn = FALSE)), path, useBytes = TRUE)
    # Refresh the hash and size so the test exercises CSV parsing and schema
    # checks rather than stopping at ordinary byte-corruption detection.
    manifest <- utils::read.csv(manifest_path, stringsAsFactors = FALSE,
      check.names = FALSE, colClasses = "character")
    row <- match(basename(path), manifest$file)
    stopifnot(!is.na(row))
    manifest$bytes[row] <- as.character(file.info(path)$size)
    manifest$md5[row] <- unname(tools::md5sum(path))
    utils::write.csv(manifest, manifest_path, row.names = FALSE)
    verify_evidence_manifest(destination, "artifact_manifest.csv",
      complete = TRUE, label = "valid refreshed fixture")
    expect_error(verify_results_summary(fixture, quiet = TRUE), pattern)
  }
  leading_field <- function(lines) {
    lines[-1L] <- paste0("injected", seq_along(lines[-1L]), ",", lines[-1L])
    lines
  }

  check("Committed results and published missing-value semantics verify", {
    stopifnot(verify_results_summary(root, quiet = TRUE))
  })
  check("Exact temporary copy verifies before corruption", {
    stopifnot(verify_results_summary(fixture, quiet = TRUE))
  })
  check("Extra leading derived-table fields cannot become inferred row names", {
    corrupt_table("class_balance", leading_field, "class_balance: schema or row count mismatch")
  })
  check("Extra leading catalog fields cannot become inferred row names", {
    corrupt_table("figure_catalog", leading_field, "figure_catalog: schema or row count mismatch")
  })
  check("Duplicate derived-table header is rejected without name repair", {
    corrupt_table("class_balance", function(lines) {
      lines[1L] <- sub('"class"', '"partition"', lines[1L], fixed = TRUE)
      lines
    }, "class_balance: schema or row count mismatch")
  })
  check("Blank data rows remain visible and are rejected", {
    corrupt_table("class_balance", function(lines) append(lines, "", after = 2L),
      "class_balance: invalid CSV")
  })
  check("Truncated data rows fail instead of receiving implicit missing fields", {
    corrupt_table("class_balance", function(lines) {
      lines[2L] <- sub(",[^,]*$", "", lines[2L])
      lines
    }, "class_balance: invalid CSV")
  })
  check("Fixture verifies after every corruption has been restored", {
    stopifnot(verify_results_summary(fixture, quiet = TRUE))
  })
  check("Published evidence, archives, summary assets, and source bytes are unchanged", {
    stopifnot(identical(before, tools::md5sum(preserved)))
  })
  cat(passed, " results summary verifier checks passed.\n", sep = "")
  invisible(passed)
}

if (sys.nframe() == 0L) {
  invocation <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  root <- dirname(dirname(normalizePath(sub("^--file=", "", invocation[1L]))))
  run_results_summary_verifier_tests(root)
}
