# Orchestration keeps test data outside the training/tuning function.
parse_options <- function(args, root = getwd()) {
  options <- list(data_dir = file.path(root, "data", "raw"),
    output = file.path(root, "results", format(Sys.time(), "run-%Y%m%d-%H%M%S", tz = "UTC")),
    seed = 12345L, trees = 200L, validation_fraction = 0.2,
    smoke = FALSE, download = FALSE, help = FALSE, root = root)
  i <- 1L
  while (i <= length(args)) {
    key <- args[[i]]
    if (key %in% c("--smoke", "--download", "--help")) {
      options[[substring(key, 3L)]] <- TRUE
    } else if (key %in% c("--data-dir", "--output", "--seed", "--trees", "--validation-fraction")) {
      i <- i + 1L
      if (i > length(args) || startsWith(args[[i]], "--")) stop("Missing value for ", key)
      name <- gsub("-", "_", substring(key, 3L), fixed = TRUE)
      options[[name]] <- if (name %in% c("seed", "trees", "validation_fraction"))
        suppressWarnings(as.numeric(args[[i]])) else args[[i]]
    } else stop("Unknown option: ", key)
    i <- i + 1L
  }
  validate_income_scalar(options$seed, "seed", upper = .Machine$integer.max - 100L, integer = TRUE)
  validate_income_scalar(options$trees, "trees", lower = 1, upper = .Machine$integer.max, integer = TRUE)
  validate_income_scalar(options$validation_fraction, "validation fraction", lower = 0,
    upper = 1, strict_lower = TRUE)
  if (options$validation_fraction >= 1) stop("Validation fraction must be less than one.")
  options
}

train_income_models <- function(train, validation_fraction = 0.2, seed = 12345L,
                                trees = 200L, smoke = FALSE) {
  validation_index <- stratified_indices(train$incomelevel, validation_fraction, seed)
  analysis <- train[-validation_index, , drop = FALSE]
  validation <- train[validation_index, , drop = FALSE]
  prep <- fit_preprocessor(analysis)
  x <- apply_preprocessor(prep, analysis)
  validation_x <- apply_preprocessor(prep, validation)
  grids <- list(majority = NA_real_, logistic = NA_real_, tree = c(0.001, 0.005, 0.01),
    forest = unique(pmax(1L, c(floor(sqrt(ncol(x))), floor(ncol(x) / 3L)))),
    svm = c(0.1, 1, 10))
  if (smoke) grids <- lapply(grids, function(values) values[1L])
  validation_results <- list()
  selected <- list()
  result_index <- 0L
  for (kind in names(grids)) {
    candidates <- list()
    for (i in seq_along(grids[[kind]])) {
      parameter <- grids[[kind]][i]
      message("Validation: ", kind, if (!is.na(parameter)) paste0(" = ", parameter) else "")
      start <- proc.time()[["elapsed"]]
      model <- fit_income_model(kind, x, analysis$incomelevel,
        parameter = if (is.na(parameter)) NULL else parameter, seed = seed, trees = trees)
      predicted <- predict_income_model(model, validation_x)
      scores <- income_metrics(validation$incomelevel, predicted$class, predicted$score)
      result_index <- result_index + 1L
      row <- cbind(data.frame(model = kind, parameter = parameter, candidate = i), scores,
        elapsed_seconds = proc.time()[["elapsed"]] - start)
      validation_results[[result_index]] <- row
      candidates[[i]] <- row
    }
    results <- do.call(rbind, candidates)
    # Highest balanced accuracy wins; the first declared candidate breaks ties.
    best <- which.max(results$balanced_accuracy)
    selected[[kind]] <- data.frame(model = kind, parameter = results$parameter[best],
      validation_balanced_accuracy = results$balanced_accuracy[best])
  }
  full_prep <- fit_preprocessor(train)
  full_x <- apply_preprocessor(full_prep, train)
  models <- list()
  for (kind in names(selected)) {
    parameter <- selected[[kind]]$parameter
    message("Refit on full training partition: ", kind)
    models[[kind]] <- fit_income_model(kind, full_x, train$incomelevel,
      parameter = if (is.na(parameter)) NULL else parameter, seed = seed, trees = trees)
  }
  assignment <- data.frame(row_id = train$row_id,
    selection_partition = ifelse(seq_len(nrow(train)) %in% validation_index, "validation", "analysis"),
    final_partition = "training")
  list(preprocessor = full_prep, models = models,
    validation_metrics = do.call(rbind, validation_results),
    selected_parameters = do.call(rbind, selected), split_assignments = assignment,
    unseen_categories = unseen_categories(prep, validation, "validation"))
}

evaluate_income_models <- function(bundle, test) {
  x <- apply_preprocessor(bundle$preprocessor, test)
  metrics <- predictions <- subgroups <- list()
  k <- 0L
  for (kind in names(bundle$models)) {
    predicted <- predict_income_model(bundle$models[[kind]], x)
    metrics[[kind]] <- cbind(data.frame(model = kind),
      income_metrics(test$incomelevel, predicted$class, predicted$score))
    predictions[[kind]] <- data.frame(row_id = test$row_id, model = kind,
      truth = test$incomelevel, prediction = predicted$class, score = predicted$score,
      score_type = bundle$models[[kind]]$score_type)
    for (attribute in c("sex", "race")) {
      group <- as.character(test[[attribute]])
      group[is.na(group)] <- "__MISSING__"
      for (value in sort(unique(group))) {
        rows <- which(group == value)
        k <- k + 1L
        subgroups[[k]] <- cbind(data.frame(model = kind, attribute = attribute, group = value),
          income_metrics(test$incomelevel[rows], predicted$class[rows], predicted$score[rows]))
      }
    }
  }
  list(metrics = do.call(rbind, metrics), predictions = do.call(rbind, predictions),
    subgroup_metrics = do.call(rbind, subgroups))
}

chart_subtitle <- function(n, smoke, official) {
  provenance <- if (official) "UCI Adult" else "CUSTOM INPUTS (unverified source)"
  sprintf("%s | %s | %s held-out records | Positive class: >50K",
    if (smoke) "SMOKE CHECK" else "Corrected evaluation", provenance, format(n, big.mark = ","))
}

verify_unchanged <- function(paths, expected, label) {
  current <- unname(tools::md5sum(paths))
  if (anyNA(current) || !identical(current, unname(expected)))
    stop(label, " changed during this run. Results were not finalized; rerun in a new output folder.")
  invisible(TRUE)
}

write_comparison_charts <- function(evaluation, directory, smoke, official = TRUE) {
  labels <- c(majority = "Majority baseline", logistic = "Logistic regression",
    tree = "Decision tree", forest = "Random forest", svm = "Linear SVM")
  metrics <- evaluation$metrics
  subtitle <- chart_subtitle(metrics$n[1L], smoke, official)
  grDevices::png(file.path(directory, "model_comparison.png"), width = 2400, height = 1500, res = 180)
  tryCatch({
    graphics::par(mar = c(6.5, 10, 5, 3), bg = "#FAFBFD", fg = "#182B3A", col.axis = "#182B3A")
    graphics::plot(NA, xlim = c(0, 1.08), ylim = c(0.35, 6), axes = FALSE,
      xlab = "Metric value", ylab = "", main = "Income classification: model comparison", cex.main = 1.45)
    graphics::mtext(subtitle, side = 3, line = 0.7, cex = 0.9)
    graphics::abline(v = seq(0, 1, 0.1), col = "#E0E5EB", lwd = 1)
    graphics::axis(1, at = seq(0, 1, 0.1), labels = sprintf("%.1f", seq(0, 1, 0.1)))
    y <- rev(seq_len(nrow(metrics)))
    graphics::axis(2, at = y, labels = labels[metrics$model], las = 1, tick = FALSE)
    columns <- c("accuracy", "balanced_accuracy", "roc_auc")
    colors <- c("#225EA8", "#167C66", "#B25B24")
    for (j in seq_along(columns)) {
      value <- metrics[[columns[j]]]
      position <- y + c(0.18, 0, -0.18)[j]
      graphics::points(value, position, pch = c(16, 15, 17)[j], col = colors[j], cex = 1.25)
      graphics::text(value + 0.025, position, labels = sprintf("%.3f", value), pos = 4,
        col = colors[j], cex = 0.78)
    }
    graphics::legend("top", legend = c("Accuracy", "Balanced accuracy", "ROC AUC"),
      col = colors, pch = c(16, 15, 17), horiz = TRUE, bty = "n", cex = 0.95)
    graphics::mtext("Settings selected on training validation data; final test data used only for evaluation.",
      side = 1, line = 4.8, cex = 0.85)
  }, finally = grDevices::dev.off())
  grDevices::png(file.path(directory, "roc_curves.png"), width = 2400, height = 1500, res = 180)
  tryCatch({
    graphics::par(mar = c(6.5, 6, 5, 3), bg = "#FAFBFD", fg = "#182B3A", col.axis = "#182B3A")
    graphics::plot(NA, xlim = c(0, 1), ylim = c(0, 1), xaxs = "i", yaxs = "i",
      xlab = "False positive rate", ylab = "True positive rate",
      main = "Income classification: ROC curves", cex.main = 1.45)
    graphics::mtext(subtitle, side = 3, line = 0.7, cex = 0.9)
    graphics::abline(h = seq(0, 1, 0.1), v = seq(0, 1, 0.1), col = "#E0E5EB")
    colors <- c("#73808C", "#225EA8", "#B25B24", "#167C66", "#7851A9")
    for (i in seq_len(nrow(metrics))) {
      rows <- evaluation$predictions$model == metrics$model[i]
      points <- roc_points(factor(evaluation$predictions$truth[rows], levels = income_levels),
        evaluation$predictions$score[rows])
      graphics::lines(points$fpr, points$tpr, col = colors[i], lwd = 2.3, lty = if (i == 1L) 2 else 1)
    }
    graphics::legend("bottomright", inset = 0.03,
      legend = sprintf("%s  |  AUC %.3f", labels[metrics$model], metrics$roc_auc),
      col = colors, lwd = 2.3, lty = c(2, 1, 1, 1, 1), bty = "n", cex = 0.95)
    graphics::mtext("Continuous scores: predicted probabilities for tree/forest/logistic; decision margin for SVM.",
      side = 1, line = 4.8, cex = 0.85)
  }, finally = grDevices::dev.off())
}

write_run_report <- function(evaluation, bundle, audit, options, warnings, official) {
  metrics <- evaluation$metrics
  row <- function(i) sprintf("| %s | %.4f | %.4f | %.4f | %.4f | %.4f |",
    metrics$model[i], metrics$accuracy[i], metrics$balanced_accuracy[i], metrics$precision[i],
    metrics$recall[i], metrics$roc_auc[i])
  text <- c("# Income classification: verified local run", "",
    if (options$smoke) "**Smoke check only. These sampled results are not portfolio benchmark evidence.**" else
      "Full-data evaluation of the revised R implementation, separate from the historical presentation.", "",
    paste("Data provenance:", if (official) "adult.data and adult.test match the recorded UCI checksums." else
      "CUSTOM INPUTS: file checksums differ from UCI reference data. Do not describe these as the official benchmark."),
    sprintf("Training rows: %s. Test rows: %s. Seed: %s. Forest trees: %s.",
      nrow(bundle$split_assignments), metrics$n[1L], options$seed, options$trees), "",
    "Settings were selected by balanced accuracy on a stratified validation subset of training data,",
    "then each selected model was fitted again on all eligible training rows. The test set did not tune models.", "",
    "| Model | Accuracy | Balanced accuracy | Precision (>50K) | Recall (>50K) | ROC AUC |",
    "|---|---:|---:|---:|---:|---:|", vapply(seq_len(nrow(metrics)), row, character(1)), "",
    "![Model comparison](model_comparison.png)", "", "![ROC curves](roc_curves.png)", "",
    "## Interpretation and limits", "",
    "The majority baseline makes class imbalance visible. All classification thresholds are fixed in advance:",
    "probability >0.5, or an oriented SVM margin >0; exact ties predict <=50K.",
    "The SVM score is not a calibrated probability. ROC AUC uses continuous scores and gives half credit to ties.",
    "Raw training duplicates and conflicting-label signatures are excluded, and test records matching original",
    "training predictors are excluded. Test-internal duplicate counts remain in the evaluation; see data_audit.csv.",
    "No person identifiers are available to establish complete entity independence.", "",
    "This is an unweighted historical 1994 Census learning benchmark. It is not a current income estimator,",
    "causal analysis, fairness certification, or production decision system. Sex and race are included predictors;",
    "subgroup_metrics.csv gives descriptive sample sizes and errors, with NA for undefined metrics.",
    "A single validation split and small search grids do not establish statistical superiority or broad optimality.",
    "Historical slide numbers are not directly comparable because partitions and preprocessing changed.", "",
    "## Run warnings", "", if (length(warnings)) paste0("- ", unique(warnings)) else "No model warnings recorded.", "",
    "## Evidence", "", "See metrics.csv, validation_metrics.csv, selected_parameters.csv, data_audit.csv,",
    "split_assignments.csv, predictions.csv, input_manifest.csv, source_manifest.csv, package_versions.csv,",
    "run_config.txt, session_info.txt, unseen_categories.csv, and artifact_manifest.csv.", "",
    "Source: [UCI Adult](https://archive.ics.uci.edu/dataset/2/adult).",
    "Becker, B. and Kohavi, R. (1996). Adult. DOI: 10.24432/C5XW20. Dataset license: CC BY 4.0.")
  writeLines(text, file.path(options$output, "report.md"), useBytes = TRUE)
}

run_income_pipeline <- function(options) {
  original_collation <- Sys.getlocale("LC_COLLATE")
  on.exit(Sys.setlocale("LC_COLLATE", original_collation), add = TRUE)
  Sys.setlocale("LC_COLLATE", "C")
  sources <- c("IncomeLevelPrediction.R", file.path("R", c("data.R", "models.R", "pipeline.R")))
  source_paths <- file.path(options$root, sources)
  source_hash <- if (is.null(options$source_hash)) unname(tools::md5sum(source_paths)) else options$source_hash
  verify_unchanged(source_paths, source_hash, "Source code")
  required <- c("rpart", "randomForest", "e1071", "proxy")
  if (!all(vapply(required, requireNamespace, logical(1), quietly = TRUE)))
    stop("Missing R packages. Run Rscript scripts/install_dependencies.R first.")
  if (file.exists(options$output) && !dir.exists(options$output)) stop("Output path is a file.")
  if (dir.exists(options$output) && length(list.files(options$output, all.files = TRUE, no.. = TRUE)))
    stop("Output directory is not empty. Choose a new --output path to preserve prior results.")
  if (options$download) download_adult(options$data_dir)
  inputs <- file.path(options$data_dir, c("adult.data", "adult.test"))
  input_hash <- unname(tools::md5sum(inputs))
  train <- read_adult(inputs[1L], "train")
  test <- read_adult(inputs[2L], "test")
  partitions <- prepare_partitions(train, test)
  train <- partitions$train
  test <- partitions$test
  if (options$smoke) {
    train <- stratified_limit(train, 1200L, options$seed)
    test <- stratified_limit(test, 600L, options$seed + 1L)
    options$trees <- min(options$trees, 30L)
  }
  dir.create(options$output, recursive = TRUE, showWarnings = FALSE)
  csv <- function(data, name) utils::write.csv(data, file.path(options$output, name), row.names = FALSE, na = "")
  warnings <- character()
  results <- withCallingHandlers({
    bundle <- train_income_models(train, options$validation_fraction, options$seed, options$trees, options$smoke)
    message("Evaluate final models on the held-out test partition")
    evaluation <- evaluate_income_models(bundle, test)
    list(bundle = bundle, evaluation = evaluation)
  }, warning = function(w) {
    warnings <<- c(warnings, conditionMessage(w))
    message("Recorded warning: ", conditionMessage(w))
    invokeRestart("muffleWarning")
  })
  bundle <- results$bundle
  evaluation <- results$evaluation
  verify_unchanged(inputs, input_hash, "Input data")
  verify_unchanged(source_paths, source_hash, "Source code")
  csv(evaluation$metrics, "metrics.csv")
  csv(evaluation$predictions, "predictions.csv")
  csv(evaluation$subgroup_metrics, "subgroup_metrics.csv")
  csv(bundle$validation_metrics, "validation_metrics.csv")
  csv(bundle$selected_parameters, "selected_parameters.csv")
  csv(partitions$audit, "data_audit.csv")
  csv(rbind(bundle$split_assignments, data.frame(row_id = test$row_id,
    selection_partition = "unused", final_partition = "test")), "split_assignments.csv")
  csv(rbind(bundle$unseen_categories, unseen_categories(bundle$preprocessor, test, "test")), "unseen_categories.csv")
  hash <- input_hash
  official <- all(hash == adult_checksums[basename(inputs)])
  csv(data.frame(file = basename(inputs), md5 = hash, bytes = file.info(inputs)$size,
    matches_uci_reference = hash == adult_checksums[basename(inputs)],
    reference_url = paste0(adult_base_url, basename(inputs))), "input_manifest.csv")
  csv(data.frame(file = sources, md5 = source_hash), "source_manifest.csv")
  csv(data.frame(package = required, version = vapply(required,
    function(x) as.character(utils::packageVersion(x)), character(1))), "package_versions.csv")
  writeLines(c(paste("completed_utc:", format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")),
    paste("mode:", if (options$smoke) "smoke" else "full"), paste("seed:", options$seed),
    paste("trees:", options$trees), paste("validation_fraction:", options$validation_fraction),
    "selection_metric: balanced_accuracy", "positive_class: >50K", "threshold_tie_class: <=50K",
    "numeric: training_median_then_training_mean_sd", "categorical: missing_marker_unseen_to_training_mode",
    "excluded_features: education,fnlwgt", "sample_weights: none", "collation: C"), file.path(options$output, "run_config.txt"))
  writeLines(capture.output(utils::sessionInfo()), file.path(options$output, "session_info.txt"))
  writeLines(if (length(warnings)) unique(warnings) else "No model warnings recorded.",
    file.path(options$output, "warnings.txt"))
  saveRDS(bundle, file.path(options$output, "models.rds"))
  write_comparison_charts(evaluation, options$output, options$smoke, official)
  write_run_report(evaluation, bundle, partitions$audit, options, warnings, official)
  artifacts <- list.files(options$output, full.names = TRUE)
  csv(data.frame(file = basename(artifacts), bytes = file.info(artifacts)$size,
    md5 = unname(tools::md5sum(artifacts))), "artifact_manifest.csv")
  message("Completed: ", normalizePath(options$output))
  print(evaluation$metrics, row.names = FALSE)
  invisible(results)
}
