#!/usr/bin/env Rscript
invocation <- grep("^--file=", commandArgs(FALSE), value = TRUE)
root <- if (length(invocation)) dirname(dirname(normalizePath(sub("^--file=", "", invocation[[1]])))) else getwd()
library_path <- file.path(root, ".R-library")
dir.create(library_path, showWarnings = FALSE)
.libPaths(c(library_path, .libPaths()))
required <- c("rpart", "randomForest", "e1071", "proxy")
missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) utils::install.packages(missing, lib = library_path, repos = "https://cloud.r-project.org")
if (!all(vapply(required, requireNamespace, logical(1), quietly = TRUE))) stop("Dependency installation incomplete.")
print(data.frame(package = required, version = vapply(required, function(x) as.character(utils::packageVersion(x)), character(1))))
