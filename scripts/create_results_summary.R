#!/usr/bin/env Rscript
# Additional ggplot2 views and derived statistics from verified public aggregates.
check_summary_destination <- function(root, source, destination) {
  path_key <- function(x) if (.Platform$OS.type == "windows") tolower(x) else x
  protected <- c(source, normalizePath(file.path(root,
    c("docs/evidence", "archive", "docs/figures/v2-uncertainty-review")),
    winslash = "/", mustWork = TRUE))
  candidate <- path_key(destination)
  protected <- path_key(protected)
  if (any(candidate == protected | startsWith(candidate, paste0(protected, "/"))))
    stop("Summary destination must be outside source evidence and preserved evidence, archives, and earlier supplements.")
  invisible(TRUE)
}

create_results_summary <- function(source, destination, root = getwd()) {
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  original_libraries <- .libPaths()
  original_collation <- Sys.getlocale("LC_COLLATE")
  on.exit({ .libPaths(original_libraries); Sys.setlocale("LC_COLLATE", original_collation) }, add = TRUE)
  .libPaths(c(file.path(root, ".R-library"), .libPaths()))
  Sys.setlocale("LC_COLLATE", "C")
  if (!requireNamespace("ggplot2", quietly = TRUE) || !requireNamespace("renv", quietly = TRUE))
    stop("Restore project dependencies with scripts/install_dependencies.R first.")
  sources <- c("scripts/create_results_summary.R", "scripts/verify_evidence.R", "scripts/render_evidence_figures.R",
    "R/plots.R", "R/summary_statistics.R", "R/summary_plots.R", "R/summary_report.R", "renv.lock")
  source_paths <- file.path(root, sources)
  code_hashes <- unname(tools::md5sum(source_paths))
  if (anyNA(code_hashes)) stop("Required summary source files are missing.")
  module <- new.env(parent = globalenv())
  for (name in sources[grepl("[.]R$", sources) & sources != "scripts/create_results_summary.R"])
    sys.source(file.path(root, name), envir = module)
  source <- normalizePath(source, winslash = "/", mustWork = TRUE)
  destination <- module$resolve_figure_destination(destination)
  path_key <- function(x) if (.Platform$OS.type == "windows") tolower(x) else x
  check_summary_destination(root, source, destination)
  if (dir.exists(destination) && length(list.files(destination, all.files = TRUE, no.. = TRUE)))
    stop("Summary destination must be new or empty; previous outputs are preserved.")
  manifest_name <- "public_artifact_manifest.csv"
  manifest_hash <- unname(tools::md5sum(file.path(source, manifest_name)))
  published_manifest <- file.path(root, "docs/evidence/v2-full-2026-10-08", manifest_name)
  module$verify_public_evidence(root, quiet = TRUE)
  if (!identical(manifest_hash, unname(tools::md5sum(published_manifest))))
    stop("This descriptive supplement supports the preserved published version 2 evidence, or an exact copy of it.")
  module$verify_evidence_manifest(source, manifest_name, complete = TRUE, label = "summary source")
  module$verify_evidence_inputs(source, file.path(root, "archive/v2-2026-10-08"), "summary reference inputs")
  config <- readLines(file.path(source, "run_config.txt"), warn = FALSE)
  for (line in c("mode: full", "methodology_version: 2", "status: complete")) {
    key <- sub(":.*", "", line)
    if (sum(startsWith(config, paste0(key, ":"))) != 1L || !line %in% config)
      stop("The summary requires a completed full version 2 reference-data run.")
  }
  table_names <- c("metrics", "data_audit", "cv_summary", "cv_metrics", "calibration", "subgroup_metrics",
    "profile_sensitivity", "profile_overlap", "paired_differences", "metric_intervals", "bootstrap_design")
  inputs <- paste0(table_names, ".csv")
  paths <- file.path(source, inputs)
  input_hashes <- unname(tools::md5sum(paths))
  tables <- setNames(lapply(paths, utils::read.csv, stringsAsFactors = FALSE), table_names)
  summaries <- module$build_results_summary(tables)
  plots <- module$make_results_summary_plots(tables, summaries)
  catalog <- module$summary_figure_catalog()
  if (length(plots) != 10L || !identical(names(plots), catalog$file) ||
      any(!vapply(plots, inherits, logical(1), what = "ggplot")))
    stop("Summary requires the ten declared ggplot figures in reading order.")
  lock <- renv::lockfile_read(file.path(root, "renv.lock"))
  packages <- names(lock$Packages)
  # Read the ASCII version field directly: packageDescription can reject unrelated
  # non-ASCII author metadata under the deterministic C locale on Windows.
  versions <- vapply(packages, function(x) unname(read.dcf(
    file.path(find.package(x), "DESCRIPTION"), fields = "Version")[1L, 1L]), character(1))
  locked <- vapply(lock$Packages, `[[`, character(1), "Version")
  if (any(versions != locked)) stop("Installed packages differ from the recorded lockfile.")
  if (!dir.exists(destination) && !dir.create(destination, recursive = TRUE, showWarnings = FALSE))
    stop("Cannot create summary output directory.")
  probe <- tempfile(".write-check-", tmpdir = destination)
  tryCatch(writeLines("test", probe), finally = if (file.exists(probe)) unlink(probe))
  write_csv <- function(data, name) {
    for (column in names(data)) if (is.double(data[[column]]))
      data[[column]] <- ifelse(is.na(data[[column]]), NA_character_, sprintf("%.17g", data[[column]]))
    utils::write.csv(data, file.path(destination, name), row.names = FALSE, na = "")
  }
  for (name in names(summaries)) write_csv(summaries[[name]], paste0(name, ".csv"))
  for (name in names(plots)) ggplot2::ggsave(file.path(destination, paste0(name, ".png")),
    plot = plots[[name]], width = 12, height = 7.5, units = "in", dpi = 200, bg = "#FAFBFD")
  pdf_open <- FALSE
  on.exit(if (pdf_open) grDevices::dev.off(), add = TRUE)
  grDevices::pdf(file.path(destination, "results_summary.pdf"), width = 12, height = 7.5,
    onefile = TRUE, useDingbats = FALSE, title = "Income prediction: additional results summary",
    author = "", bg = "#FAFBFD")
  pdf_open <- TRUE
  for (plot in plots) print(plot)
  grDevices::dev.off(); pdf_open <- FALSE
  module$write_results_summary_report(tables, summaries, catalog, destination)
  write_csv(catalog, "figure_catalog.csv")
  repo_path <- function(path) {
    full <- normalizePath(path, winslash = "/", mustWork = TRUE)
    if (startsWith(path_key(full), paste0(path_key(root), "/"))) substring(full, nchar(root) + 2L) else basename(full)
  }
  provenance_paths <- c(paths, file.path(source, manifest_name), source_paths)
  provenance <- data.frame(role = c(rep("published_aggregate", length(paths)), "published_manifest",
    rep("summary_source", length(source_paths))),
    file = vapply(provenance_paths, repo_path, character(1)),
    bytes = file.info(provenance_paths)$size, md5 = unname(tools::md5sum(provenance_paths)))
  write_csv(provenance, "provenance.csv")
  write_csv(data.frame(package = packages, version = versions), "package_versions.csv")
  writeLines(c("operation: additional descriptive summaries of published version 2 aggregates",
    "model_refit: false", "new_bootstrap: false", "threshold_tuning: false", "original_evidence_modified: false",
    paste("source_directory:", repo_path(source)), paste("R:", R.version.string),
    paste("ggplot2:", as.character(getNamespaceVersion("ggplot2"))), paste("locale:", Sys.getlocale()),
    "PNG_dimensions: 2400 x 1500 pixels", "PDF: ten pages, 12 x 7.5 inches each",
    "scope: unweighted reused historical benchmark; additional descriptive statistics, no confirmatory testing"),
    file.path(destination, "render_context.txt"))
  if (!identical(unname(tools::md5sum(paths)), input_hashes) ||
      !identical(unname(tools::md5sum(file.path(source, manifest_name))), manifest_hash) ||
      !identical(unname(tools::md5sum(source_paths)), code_hashes))
    stop("Source evidence or summary code changed during generation; outputs were not finalized.")
  module$verify_evidence_manifest(source, manifest_name, complete = TRUE, label = "source after summary")
  files <- list.files(destination, full.names = TRUE)
  write_csv(data.frame(file = basename(files), bytes = file.info(files)$size,
    md5 = unname(tools::md5sum(files))), "artifact_manifest.csv")
  message("Created results summary: ", destination)
  invisible(list(tables = summaries, plots = plots, catalog = catalog))
}

if (sys.nframe() == 0L) {
  args <- commandArgs(TRUE)
  if (length(args) != 2L) stop("Usage: Rscript --vanilla scripts/create_results_summary.R SOURCE_EVIDENCE NEW_OUTPUT_DIRECTORY")
  invocation <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  root <- dirname(dirname(normalizePath(sub("^--file=", "", invocation[1L]))))
  create_results_summary(args[1L], args[2L], root)
}
