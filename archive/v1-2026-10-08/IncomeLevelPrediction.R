#!/usr/bin/env Rscript
# Author: Esad Kopru
# Reproducible successor to archive/IncomeLevelPrediction_original.R.
main <- function(args = commandArgs(trailingOnly = TRUE)) {
  invocation <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  root <- if (length(invocation)) dirname(normalizePath(sub("^--file=", "", invocation[[1]]))) else getwd()
  local_library <- file.path(root, ".R-library")
  if (dir.exists(local_library)) .libPaths(c(local_library, .libPaths()))
  environment <- new.env(parent = globalenv())
  source_paths <- file.path(root, c("IncomeLevelPrediction.R", file.path("R", c("data.R", "models.R", "pipeline.R"))))
  source_hash <- unname(tools::md5sum(source_paths))
  for (file in c("data.R", "models.R", "pipeline.R"))
    sys.source(file.path(root, "R", file), envir = environment)
  options <- environment$parse_options(args, root)
  options$source_hash <- source_hash
  if (isTRUE(options$help)) {
    cat(paste(
      "Usage: Rscript IncomeLevelPrediction.R [options]",
      "  --download                Fetch checksum-verified public UCI inputs if absent",
      "  --data-dir PATH           Folder containing adult.data and adult.test",
      "  --output PATH             New output folder (existing non-empty folders refused)",
      "  --seed INTEGER            Random seed, default 12345",
      "  --trees INTEGER           Random-forest trees, default 200",
      "  --validation-fraction N   Training validation fraction, default 0.2",
      "  --smoke                   Small 1,200 train / 600 test check; not a benchmark",
      "  --help                    Print this help", sep = "\n"), "\n")
    return(invisible(NULL))
  }
  environment$run_income_pipeline(options)
}
if (sys.nframe() == 0L) main()
