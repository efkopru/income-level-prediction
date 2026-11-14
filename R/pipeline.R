# Version 3: version 2's grouped cross-validation, fixed thresholds, and
# reused-test evaluation, with tuning grids widened past every version 2 edge.
income_methodology_version <- function() 3L
income_protocol <- function() "docs/METHODOLOGY_V3.md"
income_sources <- function() c("IncomeLevelPrediction.R", file.path("R",
  c("data.R", "models.R", "evaluation.R", "plots.R", "reporting.R", "pipeline.R")),
  "renv.lock", income_protocol())

income_reference_settings <- function() c(seed = 12345L, trees = 500L, folds = 5L, bootstrap = 1000L)

income_run_settings <- function(options) {
  reference <- income_reference_settings()
  actual <- vapply(names(reference), function(name) options[[name]], numeric(1))
  data.frame(setting = names(reference), reference = unname(reference),
    actual = unname(actual), changed = unname(actual != reference), stringsAsFactors = FALSE)
}

prepare_income_output <- function(path) {
  if (file.exists(path) && !dir.exists(path)) stop("Output path is a file.")
  if (dir.exists(path) && length(list.files(path, all.files = TRUE, no.. = TRUE)))
    stop("Output directory is not empty. Choose a new output path to preserve prior results.")
  if (!dir.exists(path) && !dir.create(path, recursive = TRUE, showWarnings = FALSE))
    stop("Cannot create output directory: ", path)
  probe <- tempfile(".income-write-check-", tmpdir = path)
  on.exit(if (file.exists(probe)) unlink(probe), add = TRUE)
  writable <- tryCatch({ writeLines("output check", probe, useBytes = TRUE); TRUE },
    warning = function(w) FALSE, error = function(e) FALSE)
  if (!writable) stop("Output directory is not writable: ", path)
  if (unlink(probe) != 0L || file.exists(probe))
    stop("Cannot remove the output write-check file: ", probe)
  invisible(path)
}

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
  result <- c(list(data_dir = file.path(root, "data", "raw"),
    output = file.path(root, "results", format(Sys.time(), "v3-%Y%m%d-%H%M%S", tz = "UTC")),
    smoke = FALSE, download = FALSE, help = FALSE, root = root), as.list(income_reference_settings()))
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
  # Every version 2 candidate keeps its order; version 3 values are appended.
  lambda <- c(.1, .01, .001, .0001, .00001, .000001)
  cp <- c(.01, .005, .001, .0005, .0001, .00005, .00001, 0, -1)
  mtry <- c("sqrt", "third", "half", "two_thirds", "all")
  cost <- c(.1, 1, 10, 30)
  grid <- rbind(
    data.frame(model = "majority", candidate = "prevalence", parameter_rule = "none", parameter = NA_real_),
    data.frame(model = "logistic", candidate = paste0("lambda=", lambda), parameter_rule = "lambda", parameter = lambda),
    data.frame(model = "tree", candidate = paste0("cp=", cp), parameter_rule = "cp", parameter = cp),
    data.frame(model = "forest", candidate = paste0("mtry=", mtry), parameter_rule = mtry, parameter = NA_real_),
    data.frame(model = "svm", candidate = paste0("cost=", cost), parameter_rule = "cost", parameter = cost))
  grid$order <- seq_len(nrow(grid))
  if (smoke) grid <- grid[!duplicated(grid$model), , drop = FALSE]
  grid
}

resolve_parameter <- function(candidate, p) {
  rule <- candidate$parameter_rule
  if (rule == "none") return(NULL)
  if (rule == "sqrt") return(max(1L, floor(sqrt(p))))
  if (rule == "third") return(max(1L, floor(p / 3L)))
  if (rule == "half") return(max(1L, floor(p / 2L)))
  if (rule == "two_thirds") return(max(1L, floor(2L * p / 3L)))
  if (rule == "all") return(max(1L, floor(p)))
  candidate$parameter
}

# Declared in docs/METHODOLOGY_V3.md before the version 3 run.
grid_plateau_margin <- function() 0.001
grid_limit_candidates <- function() c(tree = "cp=-1", forest = "mtry=all")

# Record where each tuned family's selection sits in its declared grid and its
# paired fold margin over every adjacent candidate. Descriptive only: the
# selection itself is unchanged by these labels.
grid_position_table <- function(cv_summary, cv_metrics, margin = grid_plateau_margin()) {
  rows <- list()
  for (kind in setdiff(unique(cv_summary$model), "majority")) {
    family <- cv_summary[cv_summary$model == kind, , drop = FALSE]
    family <- family[order(family$order), , drop = FALSE]
    chosen <- which(family$selected)
    if (length(chosen) != 1L) stop("Each tuned family needs exactly one selected candidate.")
    n <- nrow(family)
    position <- if (n == 1L) "single_candidate" else if (chosen > 1L && chosen < n) "interior" else
      if (family$candidate[chosen] %in% grid_limit_candidates()[kind]) "parameter_limit" else "grid_edge"
    scores <- function(candidate) {
      rows <- cv_metrics[cv_metrics$model == kind & cv_metrics$candidate == candidate, , drop = FALSE]
      rows[order(rows$fold), c("fold", "balanced_accuracy"), drop = FALSE]
    }
    selected <- scores(family$candidate[chosen])
    base <- data.frame(model = kind, selected_candidate = family$candidate[chosen],
      selected_index = chosen, n_candidates = n, position = position, bracketed = position == "interior")
    neighbours <- c(preceding = chosen - 1L, following = chosen + 1L)
    neighbours <- neighbours[neighbours >= 1L & neighbours <= n]
    if (!length(neighbours)) rows[[length(rows) + 1L]] <- cbind(base, neighbour_side = NA_character_,
      neighbour_candidate = NA_character_, nfolds = NA_integer_, margin = NA_real_,
      folds_selection_higher = NA_integer_, folds_tied = NA_integer_, margin_label = NA_character_)
    for (side in names(neighbours)) {
      other <- scores(family$candidate[neighbours[[side]]])
      if (!nrow(selected) || !identical(selected$fold, other$fold))
        stop("Adjacent candidates must have scores on the same validation folds.")
      difference <- selected$balanced_accuracy - other$balanced_accuracy
      rows[[length(rows) + 1L]] <- cbind(base, neighbour_side = side,
        neighbour_candidate = family$candidate[neighbours[[side]]], nfolds = length(difference),
        margin = mean(difference), folds_selection_higher = sum(difference > 0),
        folds_tied = sum(difference == 0), margin_label = if (mean(difference) < margin) "plateau" else "separated")
    }
  }
  result <- do.call(rbind, rows)
  rownames(result) <- NULL
  result
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
    cv_summary = cv_summary, selected_parameters = selected,
    grid_position = grid_position_table(cv_summary, cv), oof_predictions = all_oof,
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
  prepare_income_output(options$output)
  if (options$download) download_adult(options$data_dir)
  inputs <- file.path(options$data_dir, c("adult.data", "adult.test"))
  input_hash <- unname(tools::md5sum(inputs))
  partitions <- prepare_partitions(read_adult(inputs[1L], "train"), read_adult(inputs[2L], "test"))
  official <- all(input_hash == adult_checksums[basename(inputs)])
  test_status <- if (official) "reused_benchmark" else "custom_evaluation_history_unknown"
  test_partition <- if (official) "reused_test" else "custom_test"
  train <- partitions$train; test <- partitions$test
  if (options$smoke) {
    train <- stratified_limit(train, 1200L, options$seed)
    test <- stratified_limit(test, 600L, options$seed + 1L)
    options$trees <- min(options$trees, 30L)
    options$folds <- min(options$folds, 3L)
    options$bootstrap <- min(options$bootstrap, 40L)
  }
  csv <- function(data, file) write_income_csv(data, file.path(options$output, file))
  warnings <- character()
  started <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  result <- withCallingHandlers({
    bundle <- train_income_models(train, options$folds, options$seed, options$trees, options$smoke)
    message("Evaluate the test sample and compute cluster-bootstrap uncertainty")
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
  for (name in c("cv_metrics", "cv_summary", "selected_parameters", "grid_position", "oof_predictions",
                 "fold_assignments", "diagnostics"))
    csv(bundle[[name]], paste0(name, ".csv"))
  csv(partitions$audit, "data_audit.csv")
  csv(rbind(data.frame(row_id = train$row_id, partition = "training"),
    data.frame(row_id = test$row_id, partition = test_partition)), "split_assignments.csv")
  csv(rbind(bundle$unseen_categories, unseen_categories(bundle$preprocessor, test, test_partition)), "unseen_categories.csv")
  csv(data.frame(file = basename(inputs), md5 = input_hash, bytes = file.info(inputs)$size,
    matches_uci_reference = input_hash == adult_checksums[basename(inputs)],
    reference_url = paste0(adult_base_url, basename(inputs))), "input_manifest.csv")
  csv(data.frame(file = sources, md5 = hashes), "source_manifest.csv")
  csv(package_versions, "package_versions.csv")
  write_run_methodology(options, official, nrow(train), nrow(test))
  saveRDS(bundle, file.path(options$output, "models.rds"))
  writeLines(capture.output(utils::sessionInfo()), file.path(options$output, "session_info.txt"))
  writeLines(if (length(warnings)) unique(warnings) else "No model warnings recorded.", file.path(options$output, "warnings.txt"))
  write_comparison_charts(evaluation, options$output, options$smoke, official, bundle$cv_metrics)
  write_run_report(evaluation, bundle, partitions$audit, options, warnings, official)
  # Finalize provenance after graphics and reports as well as model fitting.
  verify_unchanged(inputs, input_hash, "Input data")
  verify_unchanged(source_paths, hashes, "Code, protocol, or lockfile")
  writeLines(c(paste("methodology_version:", income_methodology_version()), "status: complete", paste("started_utc:", started),
    paste("completed_utc:", format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")),
    paste("mode:", if (options$smoke) "smoke" else "full"), paste("seed:", options$seed),
    paste("trees:", options$trees), paste("folds:", options$folds), paste("bootstrap_replicates:", options$bootstrap),
    paste("reference_settings:", if (any(income_run_settings(options)$changed)) "modified" else "matching"),
    "selection_metric: mean_fold_balanced_accuracy", paste("grid_plateau_margin:", grid_plateau_margin()),
    "positive_class: >50K", "thresholds: probability>0.5,margin>0",
    "rng: Mersenne-Twister,Inversion,Rejection", "collation: C",
    # The exported aggregate evidence otherwise names no base R version: package_versions.csv
    # covers the lockfile packages only, and session_info.txt stays local.
    paste("r_version:", as.character(getRversion())), paste("platform:", R.version$platform),
    paste("test_status:", test_status),
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
