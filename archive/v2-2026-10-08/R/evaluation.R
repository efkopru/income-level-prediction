# Aggregate evaluation. Test outcomes are used here only after fitting is complete.

probability_metrics <- function(truth, score) {
  validate_income_scores(truth, score)
  if (any(score < 0 | score > 1)) stop("Probability scores must lie between zero and one.")
  y <- as.numeric(truth == ">50K")
  epsilon <- 1e-15
  clipped <- pmax(epsilon, pmin(1 - epsilon, score))
  data.frame(brier_score = mean((score - y)^2),
    log_loss = -mean(y * log(clipped) + (1 - y) * log1p(-clipped)),
    probability_clipped_n = sum(score != clipped))
}

wilson_interval <- function(successes, total, confidence = 0.95) {
  if (length(successes) != 1L || length(total) != 1L || !is.finite(successes) ||
      !is.finite(total) || total < 0 || successes < 0 || successes > total)
    stop("Invalid binomial counts.")
  if (total == 0) return(c(lower = NA_real_, upper = NA_real_))
  z <- stats::qnorm(1 - (1 - confidence) / 2)
  rate <- successes / total
  denominator <- 1 + z^2 / total
  center <- (rate + z^2 / (2 * total)) / denominator
  half <- z * sqrt(rate * (1 - rate) / total + z^2 / (4 * total^2)) / denominator
  c(lower = max(0, center - half), upper = min(1, center + half))
}

model_health_table <- function(models) {
  do.call(rbind, lapply(names(models), function(name) {
    model <- models[[name]]
    logistic <- identical(model$kind, "logistic")
    data.frame(model = name, fit_ok = isTRUE(model$fit_ok),
      converged = if (logistic) isTRUE(model$converged) else NA,
      solver_status = if (logistic) model$model$jerr else NA_integer_,
      finite_parameters = if (logistic) all(is.finite(model$coefficients)) else NA,
      n_training = model$n_training, n_features = model$n_features)
  }))
}

calibration_table <- function(predictions) {
  output <- list()
  index <- 0L
  for (model in unique(predictions$model)) {
    data <- predictions[predictions$model == model, , drop = FALSE]
    if (!identical(unique(data$score_type), "probability")) next
    if (any(data$score < 0 | data$score > 1)) stop("Invalid probabilities for calibration.")
    bin <- cut(data$score, breaks = seq(0, 1, 0.1), include.lowest = TRUE, labels = FALSE)
    for (value in sort(unique(bin))) {
      rows <- bin == value
      positive <- sum(data$truth[rows] == ">50K")
      bounds <- wilson_interval(positive, sum(rows))
      index <- index + 1L
      output[[index]] <- data.frame(model = model, bin = value, n = sum(rows),
        n_positive = positive, mean_probability = mean(data$score[rows]),
        observed_rate = positive / sum(rows), lower = bounds[["lower"]], upper = bounds[["upper"]])
    }
  }
  if (!length(output)) return(data.frame(model = character(), bin = integer(), n = integer(),
    n_positive = integer(), mean_probability = numeric(), observed_rate = numeric(),
    lower = numeric(), upper = numeric()))
  do.call(rbind, output)
}

prepare_weighted_metric <- function(data) {
  positive <- data$truth == ">50K"
  predicted <- data$prediction == ">50K"
  ordering <- order(data$score, decreasing = TRUE)
  list(positive = positive, predicted = predicted, ordering = ordering,
    tie_group = rep.int(seq_along(rle(data$score[ordering])$lengths),
      rle(data$score[ordering])$lengths))
}

weighted_income_metrics <- function(specification, weights) {
  positive <- specification$positive
  predicted <- specification$predicted
  positive_n <- sum(weights[positive])
  negative_n <- sum(weights[!positive])
  tp <- sum(weights[positive & predicted])
  tn <- sum(weights[!positive & !predicted])
  recall <- if (positive_n) tp / positive_n else NA_real_
  specificity <- if (negative_n) tn / negative_n else NA_real_
  ordering <- specification$ordering
  ordered_weight <- weights[ordering]
  ordered_positive <- positive[ordering]
  grouped <- rowsum(cbind(positive = ordered_weight * ordered_positive,
    negative = ordered_weight * !ordered_positive), specification$tie_group, reorder = FALSE)
  group_positive <- grouped[, "positive"]
  group_negative <- grouped[, "negative"]
  cumulative_positive <- cumsum(group_positive)
  cumulative_negative <- cumsum(group_negative)
  cumulative_total <- cumulative_positive + cumulative_negative
  auc <- if (positive_n && negative_n)
    sum(group_positive * (negative_n - cumulative_negative + 0.5 * group_negative)) /
      (as.double(positive_n) * as.double(negative_n)) else NA_real_
  ap <- if (positive_n) sum(group_positive[cumulative_total > 0] / positive_n *
    cumulative_positive[cumulative_total > 0] / cumulative_total[cumulative_total > 0]) else NA_real_
  c(accuracy = (tp + tn) / sum(weights), balanced_accuracy = (recall + specificity) / 2,
    recall = recall, roc_auc = auc, average_precision = ap)
}

bootstrap_income_metrics <- function(predictions, clusters, reps = 1000L, seed = 12345L) {
  validate_income_scalar(reps, "bootstrap replicates", lower = 2,
    upper = .Machine$integer.max, integer = TRUE)
  validate_income_scalar(seed, "bootstrap seed", upper = .Machine$integer.max, integer = TRUE)
  required <- c("row_id", "model", "truth", "prediction", "score")
  if (!all(required %in% names(predictions)) || !nrow(predictions)) stop("Missing prediction data.")
  models <- unique(as.character(predictions$model))
  records <- lapply(models, function(model) predictions[predictions$model == model, , drop = FALSE])
  reference <- records[[1L]]
  if (length(clusters) != nrow(reference) || anyNA(clusters) || anyDuplicated(reference$row_id))
    stop("Bootstrap clusters must match unique prediction row identifiers.")
  for (data in records) {
    if (!identical(as.character(data$row_id), as.character(reference$row_id)) ||
        !identical(as.character(data$truth), as.character(reference$truth)))
      stop("Paired bootstrap requires identical rows, row order, and truth for every model.")
    validate_income_scores(factor(data$truth, levels = income_class_levels), data$score)
    validate_income_labels(factor(data$prediction, levels = income_class_levels))
  }
  cluster_index <- match(clusters, unique(clusters))
  cluster_n <- max(cluster_index)
  specifications <- lapply(records, prepare_weighted_metric)
  metric_names <- c("accuracy", "balanced_accuracy", "recall", "roc_auc", "average_precision")
  point <- vapply(specifications, weighted_income_metrics, numeric(5L), weights = rep(1, nrow(reference)))
  dimnames(point) <- list(metric_names, models)
  replicates <- array(NA_real_, dim = c(as.integer(reps), length(metric_names), length(models)),
    dimnames = list(NULL, metric_names, models))
  had_seed <- exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
  if (had_seed) old_seed <- get(".Random.seed", envir = .GlobalEnv)
  old_kind <- RNGkind()
  on.exit({
    do.call(RNGkind, as.list(old_kind))
    if (had_seed) assign(".Random.seed", old_seed, envir = .GlobalEnv) else
      if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) rm(".Random.seed", envir = .GlobalEnv)
  }, add = TRUE)
  RNGkind("Mersenne-Twister", "Inversion", "Rejection")
  set.seed(as.integer(seed))
  for (replicate in seq_len(reps)) {
    # All models share each cluster draw; entire raw predictor groups travel together.
    counts <- tabulate(sample.int(cluster_n, cluster_n, replace = TRUE), nbins = cluster_n)
    weights <- as.double(counts[cluster_index])
    for (model in seq_along(models))
      replicates[replicate, , model] <- weighted_income_metrics(specifications[[model]], weights)
  }
  bounds <- function(values) {
    finite <- is.finite(values)
    if (!any(finite)) return(c(lower = NA_real_, upper = NA_real_, valid_replicates = 0))
    limits <- stats::quantile(values[finite], c(0.025, 0.975), names = FALSE, type = 7)
    c(lower = limits[1L], upper = limits[2L], valid_replicates = sum(finite))
  }
  interval_rows <- list()
  index <- 0L
  for (model in seq_along(models)) for (metric in seq_along(metric_names)) {
    interval <- bounds(replicates[, metric, model])
    index <- index + 1L
    interval_rows[[index]] <- data.frame(model = models[model], metric = metric_names[metric],
      estimate = point[metric, model], lower = interval[["lower"]], upper = interval[["upper"]],
      valid_replicates = as.integer(interval[["valid_replicates"]]))
  }
  trained <- which(models != "majority")
  paired <- data.frame(model_a = character(), model_b = character(), metric = character(),
    estimate = numeric(), lower = numeric(), upper = numeric(), valid_replicates = integer())
  if (length(trained) >= 2L) {
    pairs <- utils::combn(trained, 2L)
    rows <- list()
    index <- 0L
    for (pair in seq_len(ncol(pairs))) for (metric in seq_along(metric_names)) {
      a <- pairs[1L, pair]; b <- pairs[2L, pair]
      interval <- bounds(replicates[, metric, a] - replicates[, metric, b])
      index <- index + 1L
      rows[[index]] <- data.frame(model_a = models[a], model_b = models[b], metric = metric_names[metric],
        estimate = point[metric, a] - point[metric, b], lower = interval[["lower"]],
        upper = interval[["upper"]], valid_replicates = as.integer(interval[["valid_replicates"]]))
    }
    paired <- do.call(rbind, rows)
  }
  list(metric_intervals = do.call(rbind, interval_rows), paired_differences = paired,
    bootstrap_design = data.frame(replicates = reps, seed = seed, n_rows = nrow(reference),
      n_clusters = cluster_n, method = "paired_raw_predictor_cluster_percentile",
      confidence = 0.95, conditional_on_fitted_models = TRUE))
}

evaluate_income_models <- function(bundle, test, bootstrap_reps = 1000L, seed = 12345L) {
  x <- apply_preprocessor(bundle$preprocessor, test)
  metrics <- predictions <- subgroups <- list()
  index <- 0L
  for (kind in names(bundle$models)) {
    model <- bundle$models[[kind]]
    predicted <- predict_income_model(model, x)
    probability <- if (model$score_type == "probability") probability_metrics(test$incomelevel, predicted$score) else
      data.frame(brier_score = NA_real_, log_loss = NA_real_, probability_clipped_n = NA_integer_)
    metrics[[kind]] <- cbind(data.frame(model = kind),
      income_metrics(test$incomelevel, predicted$class, predicted$score), probability)
    predictions[[kind]] <- data.frame(row_id = test$row_id, model = kind,
      truth = test$incomelevel, prediction = predicted$class, score = predicted$score,
      score_type = model$score_type)
    for (attribute in c("sex", "race")) {
      group <- as.character(test[[attribute]])
      group[is.na(group)] <- "__MISSING__"
      for (value in sort(unique(group))) {
        rows <- which(group == value)
        scores <- income_metrics(test$incomelevel[rows], predicted$class[rows], predicted$score[rows])
        recall <- wilson_interval(scores$tp, scores$n_positive)
        fpr <- wilson_interval(scores$fp, scores$n_negative)
        precision <- wilson_interval(scores$tp, scores$tp + scores$fp)
        index <- index + 1L
        subgroups[[index]] <- cbind(data.frame(model = kind, attribute = attribute, group = value), scores,
          data.frame(predicted_positive_rate = mean(predicted$class[rows] == ">50K"),
            false_positive_rate = if (scores$n_negative) scores$fp / scores$n_negative else NA_real_,
            recall_lower = recall[["lower"]], recall_upper = recall[["upper"]],
            false_positive_rate_lower = fpr[["lower"]], false_positive_rate_upper = fpr[["upper"]],
            precision_lower = precision[["lower"]], precision_upper = precision[["upper"]]))
      }
    }
  }
  prediction_table <- do.call(rbind, predictions)
  bootstrap <- bootstrap_income_metrics(prediction_table, predictor_signature(test), reps = bootstrap_reps, seed = seed)
  c(list(metrics = do.call(rbind, metrics), predictions = prediction_table,
    subgroup_metrics = do.call(rbind, subgroups), calibration = calibration_table(prediction_table)), bootstrap)
}
