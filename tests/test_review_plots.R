# Offline regression checks for supplemental aggregate plots and their provenance.
run_review_plot_tests <- function(root) {
  if (dir.exists(file.path(root, ".R-library"))) .libPaths(c(file.path(root, ".R-library"), .libPaths()))
  source(file.path(root, "R", "plots.R"), local = TRUE)
  source(file.path(root, "scripts", "render_evidence_figures.R"), local = TRUE)
  source_directory <- file.path(root, "docs", "evidence", "v2-full-2026-10-08")
  required_files <- c("metrics.csv", "metric_intervals.csv", "paired_differences.csv", "bootstrap_design.csv")
  tables <- lapply(file.path(source_directory, required_files), read.csv, stringsAsFactors = FALSE)
  names(tables) <- sub("[.]csv$", "", required_files)
  fixture_root <- tempfile("income-review-plots-", tmpdir = tempdir())
  stopifnot(dir.create(fixture_root))
  on.exit({
    resolved <- normalizePath(fixture_root, winslash = "/", mustWork = TRUE)
    temporary <- normalizePath(tempdir(), winslash = "/", mustWork = TRUE)
    if (identical(dirname(resolved), temporary) && startsWith(basename(resolved), "income-review-plots-"))
      unlink(resolved, recursive = TRUE)
  }, add = TRUE)
  equal <- function(x, y) stopifnot(isTRUE(all.equal(x, y, check.attributes = FALSE, tolerance = 1e-12)))
  expect_error <- function(code, pattern) {
    failure <- tryCatch({ force(code); NULL }, error = identity)
    stopifnot(inherits(failure, "error"), grepl(pattern, conditionMessage(failure), ignore.case = TRUE))
  }
  passed <- 0L; skipped <- 0L
  check <- function(name, code) {
    result <- force(code)
    if (inherits(result, "income_plot_test_skip")) {
      skipped <<- skipped + 1L
      cat("SKIP ", name, ": ", as.character(result), "\n", sep = "")
      return(invisible(NULL))
    }
    passed <<- passed + 1L
    cat("PASS ", name, "\n", sep = "")
  }
  fresh_source <- function() {
    path <- tempfile("source-", tmpdir = fixture_root)
    stopifnot(dir.create(path), all(file.copy(file.path(source_directory,
      c(required_files, "public_artifact_manifest.csv")), path)))
    path
  }
  new_destination <- function() tempfile("figures-", tmpdir = fixture_root)

  check("Model comparison preserves every estimate and endpoint with visible foreground intervals", {
    plot <- income_metric_plot(tables, "Test")
    data <- ggplot2::ggplot_build(plot)$data
    stopifnot(inherits(plot$layers[[1]]$geom, "GeomPoint"), inherits(plot$layers[[2]]$geom, "GeomErrorbar"),
      nrow(data[[1]]) == 20L, nrow(data[[2]]) == 20L, all(data[[1]]$size <= 2),
      all(data[[1]]$shape == 21), all(data[[1]]$fill == "white"))
    selected <- subset(tables$metric_intervals, metric != "recall")
    actual <- plot$data
    metric_names <- c(accuracy = "Accuracy", balanced_accuracy = "Balanced accuracy", roc_auc = "ROC AUC", average_precision = "Average precision")
    match_rows <- match(paste(actual$model, actual$metric), paste(selected$model, metric_names[selected$metric]))
    stopifnot(!anyNA(match_rows))
    equal(data[[1]]$x, selected$estimate[match_rows])
    equal(data[[2]]$xmin, selected$lower[match_rows])
    equal(data[[2]]$xmax, selected$upper[match_rows])
  })
  check("Paired chart retains all 30 differences on identical symmetric zero-centered axes", {
    plot <- income_paired_difference_plot(tables, "Test")
    built <- ggplot2::ggplot_build(plot)
    stopifnot(nrow(built$data[[2]]) == 30L, nrow(built$data[[3]]) == 30L,
      nrow(built$layout$layout) == 5L, length(unique(plot$data$pair)) == 6L,
      all(built$data[[1]]$xintercept == 0))
    equal(built$data[[2]]$x, tables$paired_differences$estimate)
    equal(built$data[[3]]$xmin, tables$paired_differences$lower)
    equal(built$data[[3]]$xmax, tables$paired_differences$upper)
    ranges <- lapply(built$layout$panel_params, function(panel) panel$x.range)
    for (range in ranges) {
      equal(range, ranges[[1]])
      equal(range[1], -range[2])
      stopifnot(min(tables$paired_differences$lower) >= range[1], max(tables$paired_differences$upper) <= range[2])
    }
  })
  check("Paired chart rejects omitted, duplicated, or inconsistently oriented comparisons", {
    changed <- tables; changed$paired_differences <- changed$paired_differences[-1, ]
    expect_error(income_paired_difference_plot(changed, "Test"), "all six")
    changed <- tables; changed$paired_differences[1, ] <- changed$paired_differences[2, ]
    expect_error(income_paired_difference_plot(changed, "Test"), "one row")
    changed <- tables
    changed$paired_differences$model_a[1] <- tables$paired_differences$model_b[1]
    changed$paired_differences$model_b[1] <- tables$paired_differences$model_a[1]
    expect_error(income_paired_difference_plot(changed, "Test"), "orientation")
  })
  check("Renderer rejects tampering before parsing aggregate CSVs and refuses unsafe manifests", {
    fixture <- fresh_source()
    writeLines("not,a,valid,aggregate,csv", file.path(fixture, "paired_differences.csv"))
    destination <- new_destination()
    expect_error(render_evidence_figures(fixture, destination, root), "hashes or byte sizes")
    stopifnot(!dir.exists(destination))
    fixture <- fresh_source()
    path <- file.path(fixture, "public_artifact_manifest.csv")
    manifest <- read.csv(path); manifest$file[1] <- "../outside"
    write.csv(manifest, path, row.names = FALSE)
    expect_error(render_evidence_figures(fixture, new_destination(), root), "Invalid published")
  })
  check("Renderer preserves nonempty destinations and requires matching recorded byte sizes", {
    destination <- new_destination(); stopifnot(dir.create(destination))
    sentinel <- file.path(destination, "preserve.txt"); writeLines("preserve", sentinel)
    expect_error(render_evidence_figures(source_directory, destination, root), "new or empty")
    equal(readLines(sentinel), "preserve")
    fixture <- fresh_source()
    path <- file.path(fixture, "public_artifact_manifest.csv")
    manifest <- read.csv(path); row <- match("metrics.csv", manifest$file); manifest$bytes[row] <- manifest$bytes[row] + 1
    write.csv(manifest, path, row.names = FALSE)
    expect_error(render_evidence_figures(fixture, new_destination(), root), "byte sizes")
  })
  check("Renderer rejects new relative, absolute, and parent-directory aliases inside evidence", {
    fixture <- fresh_source()
    before <- list.files(fixture, all.files = TRUE, no.. = TRUE)
    local({
      previous <- getwd(); on.exit(setwd(previous), add = TRUE)
      setwd(fixture_root)
      destinations <- c(file.path(fixture, "absolute-child"),
        file.path(basename(fixture), "relative-child"),
        file.path(basename(fixture), "absent", "..", "relative-alias"),
        file.path(fixture, "absent", "..", "absolute-alias"),
        file.path(fixture_root, "absent", "..", basename(fixture), "ancestor-alias"))
      for (destination in destinations)
        expect_error(render_evidence_figures(fixture, destination, root), "separate from the published")
    })
    equal(list.files(fixture, all.files = TRUE, no.. = TRUE), before)
    stopifnot(!dir.exists(file.path(fixture_root, "absent")))
  })
  check("Evidence destination containment follows host filesystem case semantics", {
    fixture <- fresh_source()
    if (.Platform$OS.type == "windows") {
      expect_error(render_evidence_figures(fixture, file.path(toupper(fixture), "case-child"), root),
        "separate from the published")
      stopifnot(!dir.exists(file.path(fixture, "case-child")))
    } else {
      # Distinct-case siblings on case-sensitive hosts are not descendants.
      destination <- file.path(dirname(fixture), toupper(basename(fixture)))
      stopifnot(!dir.exists(destination))
      suppressMessages(render_evidence_figures(fixture, destination, root))
      stopifnot(file.exists(file.path(destination, "figure_manifest.csv")),
        !file.exists(file.path(fixture, "figure_manifest.csv")))
    }
  })
  check("Renderer resolves directory aliases exposed after collapsing absent parent segments", local({
    fixture <- fresh_source()
    alias <- tempfile("alias-", tmpdir = fixture_root)
    linked <- if (.Platform$OS.type == "windows") suppressWarnings(Sys.junction(fixture, alias)) else file.symlink(fixture, alias)
    if (.Platform$OS.type == "windows" && !isTRUE(linked))
      return(structure("Windows denied directory-junction creation; the Linux symlink fixture remains mandatory.",
        class = "income_plot_test_skip"))
    stopifnot(isTRUE(linked), dir.exists(alias))
    before <- list.files(fixture, all.files = TRUE, no.. = TRUE)
    destinations <- c(file.path(alias, "direct-child"),
      file.path(fixture_root, "absent", "..", basename(alias), "hidden-child"))
    for (destination in destinations)
      expect_error(render_evidence_figures(fixture, destination, root), "separate from the published")
    equal(list.files(fixture, all.files = TRUE, no.. = TRUE), before)
    stopifnot(!dir.exists(file.path(fixture_root, "absent")))
  }))
  check("Supplemental rendering records actual source hashes and output dimensions without altering evidence", {
    source_paths <- list.files(source_directory, full.names = TRUE)
    before <- tools::md5sum(source_paths)
    destination <- new_destination()
    suppressMessages(render_evidence_figures(source_directory, destination, root))
    equal(tools::md5sum(source_paths), before)
    provenance <- read.csv(file.path(destination, "provenance.csv"))
    stopifnot(nrow(provenance) == 7L, sum(provenance$role == "published_aggregate") == 4L,
      sum(provenance$role == "render_source") == 2L)
    equal(unname(tools::md5sum(file.path(root, provenance$file))), provenance$md5)
    manifest <- read.csv(file.path(destination, "figure_manifest.csv"))
    equal(unname(tools::md5sum(file.path(destination, manifest$file))), manifest$md5)
    equal(file.info(file.path(destination, manifest$file))$size, manifest$bytes)
    for (name in c("model_comparison", "paired_differences")) {
      header <- readBin(file.path(destination, paste0(name, ".png")), "raw", n = 24L)
      equal(readBin(header[17:20], integer(), n = 1, size = 4, endian = "big"), 2400L)
      equal(readBin(header[21:24], integer(), n = 1, size = 4, endian = "big"), 1500L)
      stopifnot(identical(readChar(file.path(destination, paste0(name, ".pdf")), 4L), "%PDF"))
    }
  })
  cat(passed, " supplemental plot checks passed; ", skipped, " skipped.\n", sep = "")
  invisible(passed)
}

if (sys.nframe() == 0L) {
  invocation <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  root <- dirname(dirname(normalizePath(sub("^--file=", "", invocation[1L]))))
  run_review_plot_tests(root)
}
