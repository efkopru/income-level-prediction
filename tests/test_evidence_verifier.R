#!/usr/bin/env Rscript
# Standalone offline verifier checks. Mutations are confined to temporary fixtures.
invocation <- grep("^--file=", commandArgs(FALSE), value = TRUE)
root <- if (length(invocation)) dirname(dirname(normalizePath(sub("^--file=", "", invocation[1L])))) else getwd()
if (dir.exists(file.path(root, ".R-library"))) .libPaths(c(file.path(root, ".R-library"), .libPaths()))
source(file.path(root, "scripts/verify_evidence.R"))

run_evidence_verifier_tests <- function(root) {
  passed <- 0L
  failures <- character()
  fixtures <- tempfile("income-evidence-tests-", tmpdir = tempdir())
  stopifnot(dir.create(fixtures))
  on.exit({
    resolved <- normalizePath(fixtures, winslash = "/", mustWork = TRUE)
    temporary <- normalizePath(tempdir(), winslash = "/", mustWork = TRUE)
    if (identical(dirname(resolved), temporary) && startsWith(basename(resolved), "income-evidence-tests-"))
      unlink(resolved, recursive = TRUE)
  }, add = TRUE)
  test <- function(name, code) {
    tryCatch({
      force(code)
      passed <<- passed + 1L
      cat("PASS:", name, "\n")
    }, error = function(error) {
      failures <<- c(failures, paste0(name, ": ", conditionMessage(error)))
      cat("FAIL:", tail(failures, 1L), "\n")
    })
  }
  rejects <- function(code, message) {
    error <- tryCatch({ force(code); NULL }, error = identity)
    if (is.null(error)) stop("Expected verifier rejection: ", message)
    if (!grepl(message, conditionMessage(error), fixed = TRUE))
      stop("Expected rejection containing '", message, "'; received: ", conditionMessage(error))
  }
  simple <- function() {
    path <- tempfile("manifest-", tmpdir = fixtures)
    stopifnot(dir.create(path))
    writeBin(charToRaw("published evidence\n"), file.path(path, "artifact.txt"))
    manifest <- data.frame(file = "artifact.txt", bytes = file.info(file.path(path, "artifact.txt"))$size,
      md5 = unname(tools::md5sum(file.path(path, "artifact.txt"))))
    utils::write.csv(manifest, file.path(path, "manifest.csv"), row.names = FALSE)
    path
  }
  edit_manifest <- function(path, change) {
    manifest <- utils::read.csv(file.path(path, "manifest.csv"), stringsAsFactors = FALSE,
      colClasses = "character", check.names = FALSE)
    utils::write.csv(change(manifest), file.path(path, "manifest.csv"), row.names = FALSE)
  }
  check <- function(path, ...) verify_evidence_manifest(path, "manifest.csv", label = "fixture", ...)
  published <- function() {
    path <- tempfile("published-", tmpdir = fixtures)
    stopifnot(dir.create(path), dir.create(file.path(path, "docs")))
    stopifnot(file.copy(file.path(root, "archive"), path, recursive = TRUE))
    stopifnot(file.copy(file.path(root, "docs/evidence"), file.path(path, "docs"), recursive = TRUE))
    path
  }
  supplemental <- function() {
    path <- published()
    stopifnot(file.copy(file.path(root, "docs/figures"), file.path(path, "docs"), recursive = TRUE),
      dir.create(file.path(path, "scripts")), dir.create(file.path(path, "R")),
      file.copy(file.path(root, "scripts/render_evidence_figures.R"), file.path(path, "scripts")),
      file.copy(file.path(root, "R/plots.R"), file.path(path, "R")))
    path
  }
  corrupt_same_size <- function(path) {
    bytes <- readBin(path, "raw", n = file.info(path)$size)
    bytes[1L] <- as.raw(bitwXor(as.integer(bytes[1L]), 1L))
    writeBin(bytes, path)
  }
  checked_files <- c(list.files(file.path(root, "archive"), recursive = TRUE, all.files = TRUE, full.names = TRUE),
    list.files(file.path(root, "docs/evidence"), recursive = TRUE, all.files = TRUE, full.names = TRUE),
    list.files(file.path(root, "docs/figures"), recursive = TRUE, all.files = TRUE, full.names = TRUE),
    file.path(root, c("scripts/render_evidence_figures.R", "R/plots.R")))
  before <- tools::md5sum(checked_files)

  test("published repository evidence verifies", stopifnot(verify_public_evidence(root, quiet = TRUE)))
  test("committed supplemental figures and provenance verify", stopifnot(verify_supplemental_evidence(root, quiet = TRUE)))
  test("valid minimal manifest verifies", check(simple(), expected = "artifact.txt", complete = TRUE))
  test("same-size artifact corruption is rejected", {
    path <- simple(); corrupt_same_size(file.path(path, "artifact.txt"))
    rejects(check(path), "md5 mismatch: artifact.txt")
  })
  test("artifact byte-size changes are rejected", {
    path <- simple(); cat("extra", file = file.path(path, "artifact.txt"), append = TRUE)
    rejects(check(path), "byte size mismatch: artifact.txt")
  })
  test("missing artifact is rejected", {
    path <- simple(); unlink(file.path(path, "artifact.txt"))
    rejects(check(path), "missing file: artifact.txt")
  })
  test("missing manifest is rejected", {
    path <- simple(); unlink(file.path(path, "manifest.csv"))
    rejects(check(path), "missing file: manifest.csv")
  })
  test("unexpected schema is rejected", {
    path <- simple(); edit_manifest(path, function(x) { names(x)[3L] <- "hash"; x })
    rejects(check(path), "invalid schema")
  })
  test("empty manifest is rejected", {
    path <- simple(); edit_manifest(path, function(x) x[FALSE, ])
    rejects(check(path), "invalid schema")
  })
  test("duplicate manifest paths are rejected", {
    path <- simple(); edit_manifest(path, function(x) rbind(x, x))
    rejects(check(path), "duplicate file paths")
  })
  test("case-alias manifest paths are rejected", {
    path <- simple(); edit_manifest(path, function(x) { y <- x; y$file <- toupper(x$file); rbind(x, y) })
    rejects(check(path), "duplicate file paths")
  })
  for (unsafe in c("../artifact.txt", "/artifact.txt", "C:/artifact.txt", "R\\artifact.txt",
                   "R/../artifact.txt", "./artifact.txt", "R//artifact.txt", "NUL.txt", "artifact.txt/")) {
    test(paste("unsafe path rejected:", unsafe), {
      path <- simple(); edit_manifest(path, function(x) { x$file <- unsafe; x })
      rejects(check(path), "unsafe or noncanonical file path")
    })
  }
  test("self-referencing manifest is rejected", {
    path <- simple(); edit_manifest(path, function(x) { x$file <- "manifest.csv"; x })
    rejects(check(path), "manifest must not include itself")
  })
  test("malformed digest is rejected", {
    path <- simple(); edit_manifest(path, function(x) { x$md5 <- "invalid"; x })
    rejects(check(path), "invalid md5 digest")
  })
  test("fractional byte size is rejected", {
    path <- simple(); edit_manifest(path, function(x) { x$bytes <- "18.5"; x })
    rejects(check(path), "invalid byte size")
  })
  test("missing expected manifest entry is rejected", {
    path <- simple()
    rejects(check(path, expected = c("artifact.txt", "missing.txt")), "inventory mismatch; missing: missing.txt")
  })
  test("unmanifested artifact is rejected", {
    path <- simple(); writeLines("unlisted", file.path(path, "extra.txt"))
    rejects(check(path, complete = TRUE), "unexpected: extra.txt")
  })
  test("preserved v2 source mismatch is rejected", {
    path <- published(); corrupt_same_size(file.path(path, "archive/v2-2026-10-08/R/plots.R"))
    rejects(verify_public_evidence(path, quiet = TRUE), "v2 source provenance: source snapshot md5 mismatch: R/plots.R")
  })
  test("missing preserved v2 source is rejected", {
    path <- published(); unlink(file.path(path, "archive/v2-2026-10-08/R/plots.R"))
    rejects(verify_public_evidence(path, quiet = TRUE), "v2 source provenance: missing file: R/plots.R")
  })
  test("preserved v1 snapshot corruption is rejected", {
    path <- published(); corrupt_same_size(file.path(path, "archive/v1-2026-10-08/R/models.R"))
    rejects(verify_public_evidence(path, quiet = TRUE), "v1 SHA-256 snapshot: sha256 mismatch: R/models.R")
  })
  test("original script corruption is rejected", {
    path <- published(); corrupt_same_size(file.path(path, "archive/IncomeLevelPrediction_original.R"))
    rejects(verify_public_evidence(path, quiet = TRUE), "original script: published SHA-256 mismatch")
  })
  test("edited current sources do not change historical verification", {
    path <- published(); stopifnot(dir.create(file.path(path, "R")))
    writeLines("Current source deliberately differs", file.path(path, "R/plots.R"))
    writeLines("Current entry point deliberately differs", file.path(path, "IncomeLevelPrediction.R"))
    writeLines("Current lockfile deliberately differs", file.path(path, "renv.lock"))
    stopifnot(verify_public_evidence(path, quiet = TRUE))
  })
  test("incorrect declared input checksum is rejected", {
    path <- published(); evidence <- file.path(path, "docs/evidence/v2-full-2026-10-08")
    input <- utils::read.csv(file.path(evidence, "input_manifest.csv"), stringsAsFactors = FALSE)
    input$md5[1L] <- strrep("0", 32L)
    utils::write.csv(input, file.path(evidence, "input_manifest.csv"), row.names = FALSE)
    rejects(verify_evidence_inputs(evidence, file.path(path, "archive/v2-2026-10-08"), "fixture inputs"),
      "differs from declared UCI reference")
  })
  test("package version inconsistent with preserved lockfile is rejected", {
    path <- published(); evidence <- file.path(path, "docs/evidence/v2-full-2026-10-08")
    packages <- utils::read.csv(file.path(evidence, "package_versions.csv"), stringsAsFactors = FALSE)
    packages$version[packages$package == "ggplot2"] <- "0.0.0"
    utils::write.csv(packages, file.path(evidence, "package_versions.csv"), row.names = FALSE)
    rejects(verify_evidence_packages(evidence, file.path(path, "archive/v2-2026-10-08"), 2L, "fixture packages"),
      "package version differs from preserved lockfile: ggplot2")
  })
  test("committed supplemental output corruption is rejected", {
    path <- supplemental()
    corrupt_same_size(file.path(path, "docs/figures/v2-uncertainty-review/paired_differences.png"))
    rejects(verify_supplemental_evidence(path, quiet = TRUE), "supplemental figures: md5 mismatch: paired_differences.png")
  })
  test("supplemental provenance detects rendering source drift", {
    path <- supplemental(); corrupt_same_size(file.path(path, "R/plots.R"))
    rejects(verify_supplemental_evidence(path, quiet = TRUE), "supplemental provenance: md5 mismatch: R/plots.R")
  })
  test("missing supplemental manifest is rejected", {
    path <- supplemental(); unlink(file.path(path, "docs/figures/v2-uncertainty-review/figure_manifest.csv"))
    rejects(verify_supplemental_evidence(path, quiet = TRUE), "supplemental figures: missing file: figure_manifest.csv")
  })
  test("repository source snapshots and public evidence remain byte-identical", {
    stopifnot(identical(before, tools::md5sum(checked_files)))
  })
  cat("\n", passed, "evidence verifier checks passed;", length(failures), "failed.\n")
  if (length(failures)) stop(paste(failures, collapse = "\n"), call. = FALSE)
  invisible(passed)
}

run_evidence_verifier_tests(root)
