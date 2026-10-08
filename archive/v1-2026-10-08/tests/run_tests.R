# Offline regression tests. Run: Rscript --vanilla tests/run_tests.R
arguments <- commandArgs(trailingOnly = FALSE)
file_argument <- grep("^--file=", arguments, value = TRUE)
if (length(file_argument)) {
  root <- dirname(dirname(normalizePath(sub("^--file=", "", file_argument[1L]),
                                       mustWork = TRUE)))
} else {
  root <- normalizePath(".", mustWork = TRUE)
}
if (dir.exists(file.path(root, ".R-library"))) {
  .libPaths(c(file.path(root, ".R-library"), .libPaths()))
}
source(file.path(root, "R", "data.R"))
source(file.path(root, "R", "models.R"))
source(file.path(root, "R", "pipeline.R"))

run_income_tests <- function() {
  passed <- 0L
  failed <- character()
  fixture_files <- character()
  fixture_directories <- character()
  on.exit(unlink(fixture_files), add = TRUE)
  on.exit({
    temporary_root <- normalizePath(tempdir(), winslash = "/", mustWork = TRUE)
    for (directory in fixture_directories) {
      resolved <- normalizePath(directory, winslash = "/", mustWork = TRUE)
      if (identical(dirname(resolved), temporary_root) &&
          startsWith(basename(resolved), "income-export-test-")) {
        unlink(resolved, recursive = TRUE)
      }
    }
  }, add = TRUE)

  check <- function(name, code) {
    tryCatch({
      force(code)
      passed <<- passed + 1L
      cat("PASS ", name, "\n", sep = "")
    }, error = function(error) {
      failed <<- c(failed, paste0(name, ": ", conditionMessage(error)))
      cat("FAIL ", name, ": ", conditionMessage(error), "\n", sep = "")
    })
  }
  expect_error <- function(code, pattern = NULL) {
    error <- tryCatch({ force(code); NULL }, error = identity)
    if (!inherits(error, "error")) stop("Expected an error, but the operation succeeded.")
    if (!is.null(pattern) && !grepl(pattern, conditionMessage(error), ignore.case = TRUE)) {
      stop("Unexpected error: ", conditionMessage(error))
    }
    invisible(error)
  }
  equal <- function(actual, expected, tolerance = 1e-10) {
    difference <- all.equal(actual, expected, tolerance = tolerance)
    if (!isTRUE(difference)) stop(paste(difference, collapse = "; "))
    invisible(TRUE)
  }
  write_fixture <- function(lines) {
    path <- tempfile("income-regression-", fileext = ".data")
    fixture_files <<- c(fixture_files, path)
    writeLines(lines, path, useBytes = TRUE)
    path
  }
  fixture_directory <- function() {
    path <- tempfile("income-export-test-", tmpdir = tempdir())
    if (!dir.create(path)) stop("Could not create an export fixture directory.")
    fixture_directories <<- c(fixture_directories, path)
    path
  }
  export_allowlist <- c("report.md", "metrics.csv", "validation_metrics.csv", "selected_parameters.csv",
    "subgroup_metrics.csv", "data_audit.csv", "input_manifest.csv", "source_manifest.csv",
    "package_versions.csv", "run_config.txt", "warnings.txt", "unseen_categories.csv",
    "model_comparison.png", "roc_curves.png")
  refresh_export_manifest <- function(directory) {
    paths <- list.files(directory, full.names = TRUE)
    paths <- paths[basename(paths) != "artifact_manifest.csv"]
    utils::write.csv(data.frame(file = basename(paths), bytes = file.info(paths)$size,
      md5 = unname(tools::md5sum(paths))), file.path(directory, "artifact_manifest.csv"),
      row.names = FALSE)
  }
  export_fixture <- function(mode = "full", verified = TRUE) {
    directory <- fixture_directory()
    omitted <- c("predictions.csv", "split_assignments.csv", "models.rds", "session_info.txt")
    for (name in c(export_allowlist, omitted)) {
      writeLines(paste("Synthetic export fixture:", name), file.path(directory, name))
    }
    writeLines(paste("mode:", mode), file.path(directory, "run_config.txt"))
    utils::write.csv(data.frame(file = c("adult.data", "adult.test"),
      md5 = c("5d7c39d7b8804f071cdd1f2a7c460872", "35238206dfdf7f1fe215bbb874adecdc"),
      matches_uci_reference = rep(verified, 2)), file.path(directory, "input_manifest.csv"),
      row.names = FALSE)
    refresh_export_manifest(directory)
    directory
  }
  adult_line <- function(...) {
    values <- c(age = "39", workclass = "State-gov", fnlwgt = "77516",
      education = "Bachelors", educationnum = "13", maritalstatus = "Never-married",
      occupation = "Adm-clerical", relationship = "Not-in-family", race = "White",
      sex = "Male", capitalgain = "2174", capitalloss = "0", hoursperweek = "40",
      nativecountry = "United-States", incomelevel = "<=50K")
    replacements <- list(...)
    for (name in names(replacements)) values[name] <- replacements[[name]]
    paste(values, collapse = ", ")
  }
  synthetic_adult <- function(n = 240L, seed = 901L, prefix = "synthetic") {
    set.seed(seed)
    data <- data.frame(
      age = sample(20:70, n, replace = TRUE),
      workclass = sample(c("Private", "Self-emp-not-inc", "State-gov"), n, TRUE),
      fnlwgt = 100000 + seq_len(n),
      education = sample(c("Bachelors", "HS-grad", "Masters"), n, TRUE),
      educationnum = sample(8:16, n, TRUE),
      maritalstatus = sample(c("Never-married", "Married-civ-spouse", "Divorced"), n, TRUE),
      occupation = sample(c("Adm-clerical", "Craft-repair", "Exec-managerial"), n, TRUE),
      relationship = sample(c("Not-in-family", "Husband", "Wife"), n, TRUE),
      race = sample(c("White", "Black", "Asian-Pac-Islander"), n, TRUE),
      sex = sample(c("Female", "Male"), n, TRUE),
      capitalgain = sample(c(0, 500, 2500), n, TRUE),
      capitalloss = sample(c(0, 200), n, TRUE),
      hoursperweek = sample(20:60, n, TRUE),
      nativecountry = sample(c("United-States", "Canada", "Mexico"), n, TRUE),
      stringsAsFactors = FALSE
    )
    probability <- plogis(-0.4 + 0.035 * (data$age - 40) +
      0.18 * (data$educationnum - 11) + 0.015 * (data$hoursperweek - 40))
    data$incomelevel <- factor(ifelse(runif(n) < probability, ">50K", "<=50K"),
                               levels = income_levels)
    data$row_id <- sprintf("%s:%05d", prefix, seq_len(n))
    data
  }

  check("UCI parser handles header, whitespace, missing values, and terminal label periods", {
    path <- write_fixture(c("|1x3 Cross validator", "", adult_line(),
      paste0("  ", adult_line(age = "?", workclass = "?", incomelevel = ">50K."), "  ")))
    data <- read_adult(path, "fixture")
    stopifnot(nrow(data) == 2L, identical(names(data), c(adult_columns, "row_id")),
      identical(levels(data$incomelevel), income_levels),
      identical(as.character(data$incomelevel), income_levels),
      data$age[1] == 39, is.na(data$age[2]), is.na(data$workclass[2]),
      identical(data$row_id, c("fixture:00001", "fixture:00002")))
  })
  check("UCI parser rejects missing files, empty files, and malformed schemas", {
    expect_error(read_adult(tempfile("absent-income-data-"), "bad"), "Missing")
    expect_error(read_adult(write_fixture(c("", "| only a header")), "bad"), "Empty")
    fields <- strsplit(adult_line(), ",", fixed = TRUE)[[1L]]
    expect_error(read_adult(write_fixture(paste(fields[-1L], collapse = ",")), "bad"), "15 columns")
    expect_error(read_adult(write_fixture(paste(c(fields, "extra"), collapse = ",")), "bad"), "15 columns")
  })
  check("UCI parser rejects invalid labels and invalid numeric values", {
    for (label in c("unknown", "?", ">50K..")) {
      expect_error(read_adult(write_fixture(adult_line(incomelevel = label)), "bad"), "Income labels")
    }
    for (value in c("forty", "Inf", "NaN", "-1")) {
      expect_error(read_adult(write_fixture(adult_line(age = value)), "bad"), "numeric")
    }
  })

  check("Duplicate policy removes train conflicts and overlaps without test outcome leakage", {
    core <- synthetic_adult(5L)
    train <- core[c(1, 1, 2, 2, 3), , drop = FALSE]
    train$incomelevel <- factor(c("<=50K", "<=50K", "<=50K", ">50K", ">50K"),
                                levels = income_levels)
    train$row_id <- paste0("train:", seq_len(nrow(train)))
    test <- core[c(1, 2, 4, 4, 5), , drop = FALSE]
    test$incomelevel <- factor(c("<=50K", ">50K", "<=50K", ">50K", "<=50K"),
                               levels = income_levels)
    test$row_id <- paste0("test:", seq_len(nrow(test)))
    prepared <- prepare_partitions(train, test)
    stopifnot(identical(prepared$train$row_id, c("train:1", "train:5")),
      identical(prepared$test$row_id, c("test:3", "test:4", "test:5")),
      !any(predictor_signature(prepared$test) %in% predictor_signature(train)))
    audit <- setNames(prepared$audit$value, prepared$audit$item)
    stopifnot(audit[["training_conflicting_signatures"]] == 1,
      audit[["training_conflict_rows_excluded"]] == 2,
      audit[["training_duplicate_rows_excluded"]] == 1,
      audit[["test_train_overlap_rows_excluded"]] == 2,
      audit[["test_internal_duplicate_rows_retained"]] == 1)
    changed <- test
    changed$incomelevel <- factor(ifelse(test$incomelevel == ">50K", "<=50K", ">50K"),
                                  levels = income_levels)
    again <- prepare_partitions(train, changed)
    equal(again$train, prepared$train)
    equal(again$test$row_id, prepared$test$row_id)
    equal(again$audit, prepared$audit)
  })
  check("Stratified split is deterministic, disjoint, complete, and preserves both classes", {
    y <- factor(c(rep("<=50K", 81), rep(">50K", 19)), levels = income_levels)
    selected <- stratified_indices(y, 0.2, 912L)
    equal(selected, stratified_indices(y, 0.2, 912L))
    other <- setdiff(seq_along(y), selected)
    stopifnot(!anyDuplicated(selected), !length(intersect(selected, other)),
      identical(sort(c(selected, other)), seq_along(y)),
      all(table(y[selected]) > 0), all(table(y[other]) > 0),
      sum(y[selected] == "<=50K") == 16, sum(y[selected] == ">50K") == 3)
    expect_error(stratified_indices(y, 0, 1L), "fraction")
    expect_error(stratified_indices(y, 1, 1L), "fraction")
    expect_error(stratified_indices(y[1:5], 0.2, 1L), "Both")
    too_small <- factor(c("<=50K", "<=50K", ">50K"), levels = income_levels)
    expect_error(stratified_indices(too_small, 0.2, 1L), "two rows")
  })

  check("Preprocessing uses training medians and scaling, drops constants, and maps unseen categories", {
    train <- synthetic_adult(6L)
    train$age <- c(10, 20, NA, 40, 50, 60)
    train$educationnum <- rep(10, 6)
    train$capitalgain <- rep(0, 6)
    train$workclass <- c("Private", "Private", "State-gov", NA, "Private", "State-gov")
    spec <- fit_preprocessor(train)
    transformed <- apply_preprocessor(spec, train)
    equal(spec$numeric$age$median, 40)
    equal(spec$numeric$age$center, mean(c(10, 20, 40, 40, 50, 60)))
    equal(unname(transformed[3, "age"]), (40 - spec$numeric$age$center) / spec$numeric$age$scale)
    stopifnot(!"educationnum" %in% colnames(transformed),
      !"capitalgain" %in% colnames(transformed),
      !any(grepl("^(incomelevel|education($|_)|fnlwgt)", colnames(transformed))),
      !any(c("incomelevel", "education", "fnlwgt") %in% predictor_columns),
      typeof(transformed) == "double", all(is.finite(transformed)))
    saved <- serialize(spec, NULL)
    holdout <- train[1:2, , drop = FALSE]
    holdout$age <- c(1000000, NA)
    holdout$workclass <- c("Previously-unseen", "Private")
    result <- apply_preprocessor(spec, holdout)
    equal(unname(result[1, "age"]), (1000000 - spec$numeric$age$center) / spec$numeric$age$scale)
    equal(unname(result[2, "age"]), (40 - spec$numeric$age$center) / spec$numeric$age$scale)
    category_columns <- grep("^workclass_", colnames(result))
    stopifnot(length(category_columns) > 0L, all(result[, category_columns, drop = FALSE] == 0),
      identical(saved, serialize(spec, NULL)),
      identical(colnames(result), colnames(transformed)))
    unseen <- unseen_categories(spec, holdout, "holdout")
    stopifnot(unseen$unseen_rows[unseen$feature == "workclass"] == 1L)
    single <- apply_preprocessor(spec, holdout[1, , drop = FALSE])
    stopifnot(is.matrix(single), nrow(single) == 1L, ncol(single) == ncol(result))
  })
  check("Preprocessing rejects empty numeric information and learns nothing from outcomes", {
    data <- synthetic_adult(50L)
    spec <- fit_preprocessor(data)
    changed <- data
    changed$incomelevel <- factor(ifelse(data$incomelevel == ">50K", "<=50K", ">50K"),
                                  levels = income_levels)
    changed$education <- "Excluded education text"
    changed$fnlwgt <- 999999999
    equal(fit_preprocessor(changed), spec)
    equal(apply_preprocessor(spec, changed), apply_preprocessor(spec, data))
    data$age <- NA_real_
    expect_error(fit_preprocessor(data), "no observed values")
  })

  check("Confusion metrics and ties-correct ROC AUC match known values", {
    truth <- factor(c("<=50K", ">50K", "<=50K", ">50K"), levels = income_levels)
    prediction <- factor(c("<=50K", "<=50K", ">50K", ">50K"), levels = income_levels)
    scores <- c(0.1, 0.2, 0.2, 0.9)
    result <- income_metrics(truth, prediction, scores)
    stopifnot(result$n == 4, result$tp == 1, result$tn == 1, result$fp == 1, result$fn == 1)
    for (name in c("accuracy", "balanced_accuracy", "precision", "recall", "specificity", "f1")) {
      equal(result[[name]], 0.5)
    }
    equal(result$roc_auc, 0.875)
    points <- roc_points(truth, scores)
    equal(points$fpr, c(0, 0, 0.5, 1))
    equal(points$tpr, c(0, 0.5, 1, 1))
    equal(sum(diff(points$fpr) * (head(points$tpr, -1) + tail(points$tpr, -1)) / 2), 0.875)
    equal(income_metrics(truth, truth, rep(0.5, 4))$roc_auc, 0.5)
    stopifnot(nrow(roc_points(truth, rep(0.5, 4))) == 2L)
  })
  check("Undefined metrics stay NA and invalid evaluation inputs are rejected", {
    negative <- factor(rep("<=50K", 4), levels = income_levels)
    result <- income_metrics(negative, negative, rep(0.1, 4))
    stopifnot(is.na(result$roc_auc), is.na(result$balanced_accuracy),
      is.na(result$precision), is.na(result$recall), is.na(result$f1),
      result$accuracy == 1, result$specificity == 1,
      nrow(roc_points(negative, rep(0.1, 4))) == 0L)
    truth <- factor(income_levels, levels = income_levels)
    predicted <- factor(rep("<=50K", 2), levels = income_levels)
    result <- income_metrics(truth, predicted, c(0.1, 0.2))
    stopifnot(is.na(result$precision), result$recall == 0, result$f1 == 0)
    expect_error(income_metrics(truth, predicted, c(NA_real_, 1)), "finite")
    expect_error(income_metrics(truth, predicted, c(Inf, 1)), "finite")
    expect_error(income_metrics(as.character(truth), predicted, c(0, 1)), "factor")
    expect_error(income_metrics(truth, predicted[1], c(0, 1)), "lengths")
  })

  check("Logistic scores are probabilities, handle aliases, and use a probability cutoff", {
    set.seed(271L)
    signal <- rnorm(240)
    x <- cbind(signal = signal, alias = signal, constant = 0)
    y <- factor(ifelse(runif(240) < plogis(0.1 + 0.6 * signal), ">50K", "<=50K"),
                 levels = income_levels)
    model <- fit_income_model("logistic", x, y)
    predicted <- predict_income_model(model, x)
    reference <- glm(I(y == ">50K") ~ signal, family = binomial())
    equal(predicted$score, unname(predict(reference, type = "response")))
    stopifnot(model$converged, length(model$dropped_columns) == 2L,
      all(predicted$score >= 0 & predicted$score <= 1))
    model$coefficients[] <- 0
    model$coefficients["(Intercept)"] <- qlogis(0.55)
    probe <- predict_income_model(model, x[1:3, , drop = FALSE])
    equal(probe$score, rep(0.55, 3))
    stopifnot(all(probe$class == ">50K"))
    model$coefficients["(Intercept)"] <- 0
    stopifnot(all(predict_income_model(model, x[1:3, , drop = FALSE])$class == "<=50K"))
  })
  check("All five model families preserve schema, score single rows, and repeat deterministically", {
    data <- synthetic_adult()
    x <- apply_preprocessor(fit_preprocessor(data), data)
    y <- data$incomelevel
    for (kind in c("majority", "logistic", "tree", "forest", "svm")) {
      set.seed(92L)
      random_state <- .Random.seed
      model <- fit_income_model(kind, x, y, trees = 10L, seed = 42L)
      stopifnot(identical(random_state, .Random.seed))
      predicted <- predict_income_model(model, x)
      again <- predict_income_model(fit_income_model(kind, x, y, trees = 10L, seed = 42L), x)
      equal(predicted, again)
      stopifnot(length(predicted$score) == nrow(x), all(is.finite(predicted$score)),
        identical(levels(predicted$class), income_levels),
        length(predict_income_model(model, x[1, , drop = FALSE])$score) == 1L)
      if (kind == "majority") {
        equal(predicted$score, rep(mean(y == ">50K"), length(y)))
      }
    }
  })
  check("SVM margins are oriented correctly for either internal class ordering", {
    x <- cbind(signal = c(-3, -2, -1, 1, 2, 3), other = c(0, 1, 0, 0, 1, 0))
    y <- factor(c(rep("<=50K", 3), rep(">50K", 3)), levels = income_levels)
    directions <- numeric()
    for (first in income_levels) {
      ordering <- c(which(y == first), which(y != first))
      model <- fit_income_model("svm", x[ordering, , drop = FALSE], y[ordering])
      predicted <- predict_income_model(model, x)
      native <- predict(model$model, x)
      stopifnot(all(predicted$class == y), all(predicted$score[y == ">50K"] > 0),
        all(predicted$score[y == "<=50K"] < 0), income_metrics(y, predicted$class, predicted$score)$roc_auc == 1)
      equal(as.character(predicted$class), as.character(native))
      directions <- c(directions, model$margin_direction)
    }
    stopifnot(identical(sort(directions), c(-1, 1)))
  })
  check("Model boundaries reject invalid matrices, labels, and tuning parameters", {
    x <- cbind(a = c(-1, 0, 1, 2), b = c(1, 0, 2, 3))
    y <- factor(rep(income_levels, 2), levels = income_levels)
    expect_error(fit_income_model("unknown", x, y), "kind")
    expect_error(fit_income_model("tree", as.data.frame(x), y), "matrix")
    bad <- x; bad[1, 1] <- NA_real_
    expect_error(fit_income_model("tree", bad, y), "finite")
    expect_error(fit_income_model("tree", x, as.character(y)), "factor")
    expect_error(fit_income_model("svm", x, y, parameter = 0), "cost")
    expect_error(fit_income_model("forest", x, y, parameter = 3), "mtry")
    expect_error(fit_income_model("tree", x, y, parameter = -0.1), "cp")
    model <- fit_income_model("majority", x, y)
    expect_error(predict_income_model(model, x[, 2:1, drop = FALSE]), "columns")
    expect_error(fit_income_model("svm", x, factor(rep("<=50K", 4), levels = income_levels)), "both")
  })

  check("Command options validate seed, trees, fractions, and unknown arguments", {
    options <- parse_options(c("--seed", "23", "--trees", "10", "--validation-fraction", "0.3",
      "--smoke", "--data-dir", "input-fixture", "--output", "output-fixture"), root)
    stopifnot(options$seed == 23, options$trees == 10, options$validation_fraction == 0.3,
      options$smoke, options$data_dir == "input-fixture", options$output == "output-fixture")
    for (value in c("-1", "1.5", "NaN", "Inf", "not-a-number", "2147483647")) {
      expect_error(parse_options(c("--seed", value), root), "seed")
    }
    for (value in c("0", "-1", "1.2", "Inf")) {
      expect_error(parse_options(c("--trees", value), root), "trees")
    }
    for (value in c("0", "1", "-0.1", "1.1", "NA")) {
      expect_error(parse_options(c("--validation-fraction", value), root), "fraction")
    }
    expect_error(parse_options("--unknown", root), "Unknown")
    expect_error(parse_options("--seed", root), "Missing")
    expect_error(parse_options(c("--seed", "--smoke"), root), "Missing")
  })
  check("Sourcing the entry point defines main without running the project", {
    entry_environment <- new.env(parent = globalenv())
    working_directory <- getwd()
    libraries <- .libPaths()
    globals <- ls(envir = .GlobalEnv, all.names = TRUE)
    random_state <- .Random.seed
    files <- list.files(file.path(root, "results"), recursive = TRUE, all.files = TRUE)
    output <- capture.output(sys.source(file.path(root, "IncomeLevelPrediction.R"),
                                        envir = entry_environment))
    stopifnot(identical(ls(entry_environment, all.names = TRUE), "main"),
      is.function(entry_environment$main), !length(output),
      identical(getwd(), working_directory), identical(.libPaths(), libraries),
      identical(ls(envir = .GlobalEnv, all.names = TRUE), globals),
      identical(.Random.seed, random_state),
      identical(list.files(file.path(root, "results"), recursive = TRUE, all.files = TRUE), files))
  })

  check("Validation fits use analysis-only preprocessing and selection uses recorded scores", {
    module <- new.env(parent = globalenv())
    for (file in c("data.R", "models.R", "pipeline.R")) {
      sys.source(file.path(root, "R", file), envir = module)
    }
    real_fit <- module$fit_income_model
    calls <- list()
    module$fit_income_model <- function(kind, x, y, parameter = NULL,
                                       seed = 12345L, trees = 200L) {
      calls[[length(calls) + 1L]] <<- list(kind = kind, x = x, y = y, parameter = parameter)
      real_fit(kind, x, y, parameter, seed, trees)
    }
    train <- synthetic_adult(240L, 814L, "selection-train")
    selected_index <- stratified_indices(train$incomelevel, 0.2, 335L)
    analysis <- train[-selected_index, , drop = FALSE]
    analysis_x <- apply_preprocessor(fit_preprocessor(analysis), analysis)
    full_x <- apply_preprocessor(fit_preprocessor(train), train)
    bundle <- suppressMessages(module$train_income_models(train,
      validation_fraction = 0.2, seed = 335L, trees = 10L, smoke = FALSE))
    candidate_count <- nrow(bundle$validation_metrics)
    stopifnot(candidate_count > 5L, length(calls) == candidate_count + 5L)
    for (i in seq_len(candidate_count)) {
      equal(calls[[i]]$x, analysis_x)
      equal(calls[[i]]$y, analysis$incomelevel)
    }
    for (i in seq.int(candidate_count + 1L, length(calls))) {
      equal(calls[[i]]$x, full_x)
      equal(calls[[i]]$y, train$incomelevel)
    }
    for (kind in names(bundle$models)) {
      candidates <- bundle$validation_metrics[bundle$validation_metrics$model == kind, , drop = FALSE]
      best <- which.max(candidates$balanced_accuracy)
      chosen <- bundle$selected_parameters[bundle$selected_parameters$model == kind, , drop = FALSE]
      equal(chosen$parameter, candidates$parameter[best])
      equal(chosen$validation_balanced_accuracy, candidates$balanced_accuracy[best])
      if (!is.na(chosen$parameter)) equal(bundle$models[[kind]]$parameter, chosen$parameter)
    }
    assignments <- bundle$split_assignments
    stopifnot(identical(assignments$row_id, train$row_id),
      identical(which(assignments$selection_partition == "validation"), selected_index),
      all(assignments$final_partition == "training"))
  })

  check("Run output protection rejects files and nonempty directories before writing", {
    protected_file <- write_fixture("Keep this existing content.")
    original <- readLines(protected_file)
    options <- parse_options(character(), root)
    options$output <- protected_file
    expect_error(run_income_pipeline(options), "path is a file")
    equal(readLines(protected_file), original)
    options$output <- dirname(protected_file)
    expect_error(run_income_pipeline(options), "not empty")
    equal(readLines(protected_file), original)
  })

  check("Chart subtitles distinguish official, custom, and smoke evidence", {
    official <- chart_subtitle(1234L, smoke = FALSE, official = TRUE)
    custom <- chart_subtitle(1234L, smoke = FALSE, official = FALSE)
    smoke <- chart_subtitle(599L, smoke = TRUE, official = TRUE)
    custom_smoke <- chart_subtitle(599L, smoke = TRUE, official = FALSE)
    stopifnot(grepl("UCI Adult", official, fixed = TRUE),
      grepl("1,234 held-out records", official, fixed = TRUE),
      !grepl("SMOKE", official, fixed = TRUE),
      grepl("CUSTOM INPUTS (unverified source)", custom, fixed = TRUE),
      !grepl("UCI Adult", custom, fixed = TRUE),
      grepl("SMOKE CHECK", smoke, fixed = TRUE),
      grepl("UCI Adult", smoke, fixed = TRUE),
      grepl("SMOKE CHECK", custom_smoke, fixed = TRUE),
      grepl("CUSTOM INPUTS", custom_smoke, fixed = TRUE),
      !grepl("UCI Adult", custom_smoke, fixed = TRUE))
  })

  check("Provenance guard accepts unchanged files and rejects modified or missing files", {
    first <- write_fixture("First original input.")
    second <- write_fixture("Second original input.")
    paths <- c(first, second)
    expected <- tools::md5sum(paths)
    stopifnot(isTRUE(verify_unchanged(paths, expected, "Test inputs")))
    writeLines("Changed first input.", first)
    expect_error(verify_unchanged(paths, expected, "Test inputs"), "Test inputs changed")
    writeLines("First original input.", first)
    stopifnot(isTRUE(verify_unchanged(paths, expected, "Test inputs")))
    expect_error(verify_unchanged(rev(paths), expected, "Test inputs"), "changed")
    unlink(second)
    expect_error(verify_unchanged(paths, expected, "Test inputs"), "not finalized")
  })

  check("Sourcing the evidence exporter defines its function without exporting", {
    exporter <- new.env(parent = globalenv())
    working_directory <- getwd()
    globals <- ls(envir = .GlobalEnv, all.names = TRUE)
    output <- capture.output(sys.source(file.path(root, "scripts", "export_evidence.R"),
                                        envir = exporter))
    stopifnot(identical(ls(exporter, all.names = TRUE), "export_evidence"),
      is.function(exporter$export_evidence), !length(output),
      identical(getwd(), working_directory),
      identical(ls(envir = .GlobalEnv, all.names = TRUE), globals))
  })
  check("Evidence export copies only aggregate allowlisted files and verifies its public manifest", {
    source <- export_fixture()
    destination <- fixture_directory()
    published <- suppressMessages(exporter$export_evidence(source, destination))
    equal(sort(published), sort(c(export_allowlist, "README.md")))
    equal(sort(list.files(destination)),
      sort(c(export_allowlist, "README.md", "public_artifact_manifest.csv")))
    stopifnot(!any(c("predictions.csv", "split_assignments.csv", "models.rds", "session_info.txt",
      "adult.data", "adult.test", "artifact_manifest.csv") %in% list.files(destination)))
    public <- utils::read.csv(file.path(destination, "public_artifact_manifest.csv"),
                              stringsAsFactors = FALSE)
    equal(unname(tools::md5sum(file.path(destination, public$file))), public$md5)
    equal(unname(tools::md5sum(file.path(source, export_allowlist))),
      unname(tools::md5sum(file.path(destination, export_allowlist))))
  })
  check("Evidence export rejects smoke and custom inputs, including missing or false provenance fields", {
    expect_error(exporter$export_evidence(export_fixture(mode = "smoke"), fixture_directory()), "full runs")
    expect_error(exporter$export_evidence(export_fixture(verified = FALSE), fixture_directory()), "reference inputs")
    for (defect in c("missing_flag", "wrong_hash", "wrong_name", "duplicate_name")) {
      source <- export_fixture()
      path <- file.path(source, "input_manifest.csv")
      inputs <- utils::read.csv(path, stringsAsFactors = FALSE)
      if (defect == "missing_flag") inputs$matches_uci_reference <- NULL
      if (defect == "wrong_hash") inputs$md5[1] <- paste(rep("0", 32), collapse = "")
      if (defect == "wrong_name") inputs$file[1] <- "custom.data"
      if (defect == "duplicate_name") inputs$file[2] <- inputs$file[1]
      utils::write.csv(inputs, path, row.names = FALSE)
      refresh_export_manifest(source)
      expect_error(exporter$export_evidence(source, fixture_directory()), "reference inputs")
    }
  })
  check("Evidence export rejects changed artifacts, unsafe manifests, and occupied destinations", {
    source <- export_fixture()
    writeLines("Changed report after completion.", file.path(source, "report.md"))
    expect_error(exporter$export_evidence(source, fixture_directory()), "recorded hashes")
    source <- export_fixture()
    manifest_path <- file.path(source, "artifact_manifest.csv")
    manifest <- utils::read.csv(manifest_path, stringsAsFactors = FALSE)
    manifest$file[1] <- "../outside.txt"
    utils::write.csv(manifest, manifest_path, row.names = FALSE)
    expect_error(exporter$export_evidence(source, fixture_directory()), "Invalid run artifact")
    source <- export_fixture()
    destination <- fixture_directory()
    sentinel <- file.path(destination, "keep.txt")
    writeLines("Existing evidence.", sentinel)
    expect_error(exporter$export_evidence(source, destination), "preserved")
    equal(readLines(sentinel), "Existing evidence.")
    occupied_file <- write_fixture("Existing file.")
    expect_error(exporter$export_evidence(source, occupied_file), "existing file")
    equal(readLines(occupied_file), "Existing file.")
    expect_error(exporter$export_evidence(fixture_directory(), fixture_directory()), "completed run")
  })

  check("Training pipeline uses only its training partition and evaluation cannot mutate it", {
    train <- synthetic_adult(240L, 814L, "pipeline-train")
    test <- synthetic_adult(60L, 915L, "pipeline-test")
    bundle <- train_income_models(train, validation_fraction = 0.2,
      seed = 335L, trees = 10L, smoke = TRUE)
    stopifnot(length(bundle$models) == 5L)
    kinds <- vapply(bundle$models, function(model) model$kind, character(1))
    equal(sort(unname(kinds)), sort(c("majority", "logistic", "tree", "forest", "svm")))
    equal(bundle$preprocessor, fit_preprocessor(train))
    saved_bundle <- serialize(bundle, NULL)
    original <- evaluate_income_models(bundle, test)
    changed <- test
    changed$incomelevel <- factor(ifelse(test$incomelevel == ">50K", "<=50K", ">50K"),
                                  levels = income_levels)
    flipped <- evaluate_income_models(bundle, changed)
    stopifnot(identical(saved_bundle, serialize(bundle, NULL)),
      nrow(original$metrics) == 5L, nrow(flipped$metrics) == 5L,
      !isTRUE(all.equal(original$metrics, flipped$metrics)))
    x <- apply_preprocessor(bundle$preprocessor, test)
    changed_x <- apply_preprocessor(bundle$preprocessor, changed)
    equal(x, changed_x)
    for (model in bundle$models) {
      equal(predict_income_model(model, x), predict_income_model(model, changed_x))
    }
    # The returned prediction table may carry actual labels for auditing.
    # Remove only outcome fields before comparing the evaluation artifacts.
    outcome_names <- c("truth", "actual", "incomelevel", "actual_class", "observed", "outcome")
    prediction_columns <- setdiff(names(original$predictions), outcome_names)
    equal(original$predictions[prediction_columns], flipped$predictions[prediction_columns])
    second <- train_income_models(train, validation_fraction = 0.2,
      seed = 335L, trees = 10L, smoke = TRUE)
    equal(bundle$selected_parameters, second$selected_parameters)
    deterministic_columns <- setdiff(names(bundle$validation_metrics), "elapsed_seconds")
    equal(bundle$validation_metrics[deterministic_columns],
          second$validation_metrics[deterministic_columns])
    equal(bundle$split_assignments, second$split_assignments)
    equal(original$predictions, evaluate_income_models(second, test)$predictions)
  })

  cat("\n", passed, " tests passed; ", length(failed), " failed.\n", sep = "")
  if (length(failed)) stop(paste(failed, collapse = "\n"), call. = FALSE)
  invisible(passed)
}

run_income_tests()
