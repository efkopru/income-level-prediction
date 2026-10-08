#!/usr/bin/env Rscript
# Author: Esad Kopru
# Version 2. Historical sources and version 1 remain under archive/.
main <- function(args = commandArgs(trailingOnly = TRUE)) {
  invocation <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  root <- if (length(invocation)) dirname(normalizePath(sub("^--file=", "", invocation[[1]]))) else getwd()
  if (dir.exists(file.path(root, ".R-library"))) .libPaths(c(file.path(root, ".R-library"), .libPaths()))
  modules <- c("data.R", "models.R", "evaluation.R", "plots.R", "reporting.R", "pipeline.R")
  paths <- file.path(root, c("IncomeLevelPrediction.R", file.path("R", modules),
    "renv.lock", "docs/METHODOLOGY_V2.md"))
  hashes <- unname(tools::md5sum(paths))
  environment <- new.env(parent = globalenv())
  for (file in modules) sys.source(file.path(root, "R", file), envir = environment)
  options <- environment$parse_options(args, root)
  options$source_hash <- hashes
  if (options$help) {
    cat(paste(
      "Usage: Rscript --vanilla IncomeLevelPrediction.R [options]",
      "  --download       Fetch checksum-verified public UCI inputs if absent",
      "  --data-dir PATH  Input folder (default: project data/raw)",
      "  --output PATH    New output folder; existing non-empty folders refused",
      "  --seed INTEGER   Fixed RNG seed, default 12345",
      "  --trees INTEGER  Probability-forest trees, default 500",
      "  --folds INTEGER  Grouped training CV folds, default 5",
      "  --bootstrap N    Paired cluster-bootstrap replicates, default 1000",
      "  --smoke          Small execution check, not reportable study results",
      "  --help           Print usage", sep = "\n"), "\n")
    return(invisible(NULL))
  }
  environment$run_income_pipeline(options)
}
if (sys.nframe() == 0L) main()
