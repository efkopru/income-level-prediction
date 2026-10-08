# Version 2: grouped cross-validation, fixed thresholds, reused-test evaluation.
income_sources <- function() c("IncomeLevelPrediction.R", file.path("R",
  c("data.R", "models.R", "evaluation.R", "plots.R", "reporting.R", "pipeline.R")),
  "renv.lock", "docs/METHODOLOGY_V2.md")

write_income_csv <- function(data, path) {
  # write.csv formats numeric columns to about 15 significant digits. That can
  # merge adjacent scores, changing tied-score ranking metrics after reloading.
  # Seventeen digits preserve IEEE doubles; keep missing values as empty fields.
  for (name in names(data)) if (is.double(data[[name]])) {
    values <- data[[name]]
    data[[name]] <- ifelse(is.na(values), NA_character_, sprintf("%.17g", values))
  }
  utils::write.csv(data, path, row.names = FALSE, na = "")
}

parse_options <- function(args, root = getwd()) {
  result <- list(data_dir = file.path(root, "data", "raw"),
    output = file.path(root, "results", format(Sys.time(), "v2-%Y%m%d-%H%M%S", tz = "UTC")),
    seed = 12345L, trees = 500L, folds = 5L, bootstrap = 1000L,
    smoke = FALSE, download = FALSE, help = FALSE, root = root)
  i <- 1L
  while (i <= length(args)) {
    key <- args[[i]]
    if (key %in% c("--smoke", "--download", "--help")) result[[substring(key, 3L)]] <- TRUE
    else if (key %in% c("--data-dir", "--output", "--seed", "--trees", "--folds", "--bootstrap")) {
      i <- i + 1L
      if (i > length(args) || startsWith(args[[i]], "--")) stop("Missing value for ", key)
      name <- gsub("-", "_", substring(key, 3L), fixed = TRUE)
      result[[name]] <- if (name %in% c("seed", "trees", "folds", "bootstrap"))
        suppressWarnings(as.numeric(args[[i]])) else args[[i]]
    } else stop("Unknown option: ", key)
    i <- i + 1L
  }
  validate_income_scalar(result$seed, "seed", upper = .Machine$integer.max - 10000L, integer = TRUE)
  validate_income_scalar(result$trees, "trees", lower = 1, upper = 100000L, integer = TRUE)
  validate_income_scalar(result$folds, "folds", lower = 2, upper = 20, integer = TRUE)
  validate_income_scalar(result$bootstrap, "bootstrap replicates", lower = 20, upper = 10000, integer = TRUE)
  result
}

candidate_grid <- function(smoke = FALSE) {
  grid <- rbind(
    data.frame(model = "majority", candidate = "prevalence", parameter_rule = "none", parameter = NA_real_),
    data.frame(model = "logistic", candidate = paste0("lambda=", c(.1, .01, .001, .0001)),
      parameter_rule = "lambda", parameter = c(.1, .01, .001, .0001)),
    data.frame(model = "tree", candidate = paste0("cp=", c(.01, .005, .001, .0005)),
      parameter_rule = "cp", parameter = c(.01, .005, .001, .0005)),
    data.frame(model = "forest", candidate = c("mtry=sqrt", "mtry=third"),
      parameter_rule = c("sqrt", "third"), parameter = NA_real_),
    data.frame(model = "svm", candidate = paste0("cost=", c(.1, 1, 10)),
      parameter_rule = "cost", parameter = c(.1, 1, 10)))
  grid$order <- seq_len(nrow(grid))
  if (smoke) grid <- grid[!duplicated(grid$model), , drop = FALSE]
  grid
}

resolve_parameter <- function(candidate, p) {
  if (candidate$parameter_rule == "none") return(NULL)
  if (candidate$parameter_rule == "sqrt") return(max(1L, floor(sqrt(p))))
  if (candidate$parameter_rule == "third") return(max(1L, floor(p / 3L)))
  candidate$parameter
}

train_income_models <- function(train, folds = 5L, seed = 12345L, trees = 500L, smoke = FALSE) {
  original_collation <- Sys.getlocale("LC_COLLATE")
  on.exit(Sys.setlocale("LC_COLLATE", original_collation), add = TRUE)
  Sys.setlocale("LC_COLLATE", "C")
  fold <- stratified_group_folds(train, folds, seed)
  grid <- candidate_grid(smoke)
  records <- oof <- novelty <- diagnostics <- list()
  index <- 0L
  for (f in seq_len(folds)) {
    analysis <- train[fold != f, , drop = FALSE]
    validation <- train[fold == f, , drop = FALSE]
    prep <- fit_preprocessor(analysis)
    x <- apply_preprocessor(prep, analysis)
    vx <- apply_preprocessor(prep, validation)
    novelty[[f]] <- unseen_categories(prep, validation, paste0("fold_", f))
    for (g in seq_len(nrow(grid))) {
      candidate <- grid[g, , drop = FALSE]
      parameter <- resolve_parameter(candidate, ncol(x))
      message("CV fold ", f, "/", folds, ": ", candidate$model, " ", candidate$candidate)
      start <- proc.time()[["elapsed"]]
      model <- fit_income_model(candidate$model, x, analysis$incomelevel, parameter,
        seed = seed + f, trees = trees)
      predicted <- predict_income_model(model, vx)
      scores <- income_metrics(validation$incomelevel, predicted$class, predicted$score)
      index <- index + 1L
      records[[index]] <- cbind(data.frame(model = candidate$model, candidate = candidate$candidate,
        parameter_rule = candidate$parameter_rule, parameter = if (is.null(parameter)) NA_real_ else parameter,
        fold = f, n_analysis = nrow(analysis), n_features = ncol(x)), scores,
        elapsed_seconds = proc.time()[["elapsed"]] - start)
      oof[[index]] <- data.frame(row_id = validation$row_id, model = candidate$model,
        candidate = candidate$candidate, fold = f, truth = validation$incomelevel,
        prediction = predicted$class, score = predicted$score, score_type = model$score_type)
      health <- model_health_table(setNames(list(model), candidate$model))
      health$stage <- paste0("fold_", f)
      health$candidate <- candidate$candidate
      diagnostics[[index]] <- health
    }
  }
  cv <- do.call(rbind, records)
  cv_summary <- grid
  cv_summary$mean_balanced_accuracy <- cv_summary$sd_balanced_accuracy <- NA_real_
  cv_summary$nfolds <- folds
  cv_summary$selected <- FALSE
  for (g in seq_len(nrow(grid))) {
    rows <- cv$model == grid$model[g] & cv$candidate == grid$candidate[g]
    values <- cv$balanced_accuracy[rows]
    if (length(values) != folds || any(!is.finite(values))) stop("Incomplete cross-validation scores.")
    cv_summary$mean_balanced_accuracy[g] <- mean(values)
    cv_summary$sd_balanced_accuracy[g] <- stats::sd(values)
  }
  for (kind in unique(grid$model)) {
    eligible <- which(grid$model == kind)
    selected <- eligible[which.max(cv_summary$mean_balanced_accuracy[eligible])]
    cv_summary$selected[selected] <- TRUE
  }
  selected <- cv_summary[cv_summary$selected, , drop = FALSE]
  cv$selected <- paste(cv$model, cv$candidate) %in% paste(selected$model, selected$candidate)
  all_oof <- do.call(rbind, oof)
  all_oof <- all_oof[paste(all_oof$model, all_oof$candidate) %in%
    paste(selected$model, selected$candidate), , drop = FALSE]
  final_prep <- fit_preprocessor(train)
  x <- apply_preprocessor(final_prep, train)
  models <- list()
  selected$final_parameter <- NA_real_
  for (i in seq_len(nrow(selected))) {
    candidate <- selected[i, , drop = FALSE]
    parameter <- resolve_parameter(candidate, ncol(x))
    selected$final_parameter[i] <- if (is.null(parameter)) NA_real_ else parameter
    message("Final fit: ", candidate$model, " ", candidate$candidate)
    models[[candidate$model]] <- fit_income_model(candidate$model, x, train$incomelevel,
      parameter, seed, trees)
  }
  final_health <- model_health_table(models)
  final_health$stage <- "final"
  final_health$candidate <- selected$candidate[match(final_health$model, selected$model)]
  list(preprocessor = final_prep, models = models, cv_metrics = cv,
    cv_summary = cv_summary, selected_parameters = selected, oof_predictions = all_oof,
    fold_assignments = data.frame(row_id = train$row_id, fold = fold,
      class = train$incomelevel, group_id = match(predictor_signature(train), unique(predictor_signature(train)))),
    unseen_categories = do.call(rbind, novelty), diagnostics = rbind(do.call(rbind, diagnostics), final_health))
}

verify_unchanged <- function(paths, expected, label) {
  current <- unname(tools::md5sum(paths))
  if (anyNA(current) || !identical(current, unname(expected)))
    stop(label, " changed during this run. Results were not finalized; use a new output folder.")
  invisible(TRUE)
}

check_locked_packages <- function(root) {
  required <- c("rpart", "e1071", "proxy", "glmnet", "ranger", "ggplot2", "renv")
  if (!all(vapply(required, requireNamespace, logical(1), quietly = TRUE)))
    stop("Missing R packages. Run Rscript --vanilla scripts/install_dependencies.R.")
  lock <- renv::lockfile_read(file.path(root, "renv.lock"))
  packages <- names(lock$Packages)
  versions <- vapply(packages, function(name) {
    if (!requireNamespace(name, quietly = TRUE)) return(NA_character_)
    utils::packageDescription(name)$Version
  }, character(1))
  expected <- vapply(lock$Packages, `[[`, character(1), "Version")
  if (anyNA(versions) || any(versions != expected)) stop("Packages differ from renv.lock; restore the recorded environment first.")
  data.frame(package = packages, version = versions)
}

run_income_pipeline <- function(options) {
  original_collation <- Sys.getlocale("LC_COLLATE")
  on.exit(Sys.setlocale("LC_COLLATE", original_collation), add = TRUE)
  Sys.setlocale("LC_COLLATE", "C")
  sources <- income_sources()
  source_paths <- file.path(options$root, sources)
  hashes <- if (is.null(options$source_hash)) unname(tools::md5sum(source_paths)) else options$source_hash
  verify_unchanged(source_paths, hashes, "Code, protocol, or lockfile")
  package_versions <- check_locked_packages(options$root)
  if (file.exists(options$output) && !dir.exists(options$output)) stop("Output path is a file.")
  if (dir.exists(options$output) && length(list.files(options$output, all.files = TRUE, no.. = TRUE)))
    stop("Output directory is not empty. Choose a new output path to preserve prior results.")
  if (options$download) download_adult(options$data_dir)
  inputs <- file.path(options$data_dir, c("adult.data", "adult.test"))
  input_hash <- unname(tools::md5sum(inputs))
  partitions <- prepare_partitions(read_adult(inputs[1L], "train"), read_adult(inputs[2L], "test"))
  train <- partitions$train; test <- partitions$test
  if (options$smoke) {
    train <- stratified_limit(train, 1200L, options$seed)
    test <- stratified_limit(test, 600L, options$seed + 1L)
    options$trees <- min(options$trees, 30L)
    options$folds <- min(options$folds, 3L)
    options$bootstrap <- min(options$bootstrap, 40L)
  }
  dir.create(options$output, recursive = TRUE, showWarnings = FALSE)
  csv <- function(data, file) write_income_csv(data, file.path(options$output, file))
  warnings <- character()
  started <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  result <- withCallingHandlers({
    bundle <- train_income_models(train, options$folds, options$seed, options$trees, options$smoke)
    message("Evaluate on reused benchmark test and compute cluster-bootstrap uncertainty")
    evaluation <- evaluate_income_models(bundle, test, options$bootstrap, options$seed + 1000L)
    list(bundle = bundle, evaluation = evaluation)
  }, warning = function(w) {
    warnings <<- c(warnings, conditionMessage(w)); message("Recorded warning: ", conditionMessage(w))
    invokeRestart("muffleWarning")
  })
  bundle <- result$bundle; evaluation <- result$evaluation
  # Equal demographic profiles are not evidence of duplicate people. Report the
  # overlap and a descriptive sensitivity without changing the primary sample.
  seen <- model_input_signature(test) %in% model_input_signature(train)
  evaluation$profile_overlap <- data.frame(profile_status = c("seen_in_training", "novel_profile"),
    n = c(sum(seen), sum(!seen)))
  sensitivity <- list()
  for (model in names(bundle$models)) for (status in c(TRUE, FALSE)) {
    subset <- evaluation$predictions[evaluation$predictions$model == model, , drop = FALSE]
    rows <- seen[match(subset$row_id, test$row_id)] == status
    if (any(rows)) sensitivity[[length(sensitivity) + 1L]] <- cbind(
      data.frame(model = model, profile_status = if (status) "seen_in_training" else "novel_profile"),
      income_metrics(factor(subset$truth[rows], levels = income_levels),
        factor(subset$prediction[rows], levels = income_levels), subset$score[rows]))
  }
  evaluation$profile_sensitivity <- do.call(rbind, sensitivity)
  for (name in c("metrics", "predictions", "subgroup_metrics", "metric_intervals", "paired_differences",
                 "calibration", "profile_overlap", "profile_sensitivity", "bootstrap_design")) csv(evaluation[[name]], paste0(name, ".csv"))
  for (name in c("cv_metrics", "cv_summary", "selected_parameters", "oof_predictions", "fold_assignments", "diagnostics"))
    csv(bundle[[name]], paste0(name, ".csv"))
  csv(partitions$audit, "data_audit.csv")
  csv(rbind(data.frame(row_id = train$row_id, partition = "training"),
    data.frame(row_id = test$row_id, partition = "reused_test")), "split_assignments.csv")
  csv(rbind(bundle$unseen_categories, unseen_categories(bundle$preprocessor, test, "reused_test")), "unseen_categories.csv")
  official <- all(input_hash == adult_checksums[basename(inputs)])
  csv(data.frame(file = basename(inputs), md5 = input_hash, bytes = file.info(inputs)$size,
    matches_uci_reference = input_hash == adult_checksums[basename(inputs)],
    reference_url = paste0(adult_base_url, basename(inputs))), "input_manifest.csv")
  csv(data.frame(file = sources, md5 = hashes), "source_manifest.csv")
  csv(package_versions, "package_versions.csv")
  file.copy(file.path(options$root, "docs/METHODOLOGY_V2.md"), file.path(options$output, "methodology.md"))
  saveRDS(bundle, file.path(options$output, "models.rds"))
  writeLines(capture.output(utils::sessionInfo()), file.path(options$output, "session_info.txt"))
  writeLines(if (length(warnings)) unique(warnings) else "No model warnings recorded.", file.path(options$output, "warnings.txt"))
  write_comparison_charts(evaluation, options$output, options$smoke, official, bundle$cv_metrics)
  write_run_report(evaluation, bundle, partitions$audit, options, warnings, official)
  # Finalize provenance after graphics and reports as well as model fitting.
  verify_unchanged(inputs, input_hash, "Input data")
  verify_unchanged(source_paths, hashes, "Code, protocol, or lockfile")
  writeLines(c("methodology_version: 2", "status: complete", paste("started_utc:", started),
    paste("completed_utc:", format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")),
    paste("mode:", if (options$smoke) "smoke" else "full"), paste("seed:", options$seed),
    paste("trees:", options$trees), paste("folds:", options$folds), paste("bootstrap_replicates:", options$bootstrap),
    "selection_metric: mean_fold_balanced_accuracy", "positive_class: >50K", "thresholds: probability>0.5,margin>0",
    "rng: Mersenne-Twister,Inversion,Rejection", "collation: C", "test_status: reused_benchmark",
    "numeric_transform: log1p_capitalgain_capitalloss_then_training_imputation_scaling",
    "excluded_features: education,fnlwgt", "sample_weights: none",
    "bootstrap_unit: raw_14_predictor_signature", "bootstrap_scope: conditional_on_fitted_models"),
    file.path(options$output, "run_config.txt"))
  artifacts <- list.files(options$output, full.names = TRUE)
  csv(data.frame(file = basename(artifacts), bytes = file.info(artifacts)$size,
    md5 = unname(tools::md5sum(artifacts))), "artifact_manifest.csv")
  message("Completed: ", normalizePath(options$output))
  print(evaluation$metrics, row.names = FALSE)
  invisible(list(bundle = bundle, evaluation = evaluation))
}
