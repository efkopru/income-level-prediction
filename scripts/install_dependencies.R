#!/usr/bin/env Rscript
# Restore recorded package versions without activating an automatic .Rprofile.
invocation <- grep("^--file=", commandArgs(FALSE), value = TRUE)
root <- if (length(invocation)) dirname(dirname(normalizePath(sub("^--file=", "", invocation[[1]])))) else getwd()
library_path <- file.path(root, ".R-library")
dir.create(library_path, showWarnings = FALSE)
.libPaths(c(library_path, .libPaths()))
Sys.setenv(RENV_CONFIG_CACHE_ENABLED = "FALSE", RENV_CONFIG_AUTOLOADER_ENABLED = "FALSE")
options(repos = c(CRAN = "https://cloud.r-project.org"))
if (!requireNamespace("renv", quietly = TRUE))
  utils::install.packages("renv", lib = library_path, repos = getOption("repos"))
lockfile <- file.path(root, "renv.lock")
if (!file.exists(lockfile)) stop("Missing renv.lock; restore the project lockfile first.")
lock <- renv::lockfile_read(lockfile)
packages <- names(lock$Packages)
missing <- packages[!vapply(packages, function(name) {
  if (!requireNamespace(name, quietly = TRUE)) return(FALSE)
  identical(utils::packageDescription(name)$Version, lock$Packages[[name]]$Version)
}, logical(1))]
if (length(missing)) renv::restore(project = root, lockfile = lockfile,
  library = library_path, packages = missing, prompt = FALSE, clean = FALSE)
for (name in packages) {
  if (!requireNamespace(name, quietly = TRUE) ||
      !identical(utils::packageDescription(name)$Version, lock$Packages[[name]]$Version))
    stop("Package restoration incomplete: ", name, ". Restart a clean R session and retry.")
}
cat("All", length(packages), "recorded package versions are available.\n")
cat("Lockfile R version:", lock$R$Version, "| current:", as.character(getRversion()), "\n")
