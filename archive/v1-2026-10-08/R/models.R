# Model fitting and evaluation. Preprocessing must be fitted on training data
# before calling these functions. Higher scores always mean evidence for >50K.

income_class_levels <- c("<=50K", ">50K")

validate_income_matrix <- function(x, expected_columns = NULL) {
  if (!is.matrix(x) || !is.numeric(x) || nrow(x) < 1L || ncol(x) < 1L) {
    stop("x must be a nonempty numeric matrix.", call. = FALSE)
  }
  if (anyNA(x) || any(!is.finite(x))) {
    stop("x must contain only finite, nonmissing values.", call. = FALSE)
  }
  columns <- colnames(x)
  if (is.null(columns) || anyNA(columns) || anyDuplicated(columns) ||
      !identical(make.names(columns, unique = TRUE), columns)) {
    stop("x must have unique, syntactically valid column names.", call. = FALSE)
  }
  if (".income_response" %in% columns) {
    stop(".income_response is reserved for the model outcome.", call. = FALSE)
  }
  if (!is.null(expected_columns) && !identical(columns, expected_columns)) {
    stop("Prediction columns and their order must match the training matrix.",
         call. = FALSE)
  }
  storage.mode(x) <- "double"
  x
}

validate_income_labels <- function(y, name = "y", require_both = FALSE) {
  if (!is.factor(y) || !identical(levels(y), income_class_levels) ||
      !length(y) || anyNA(y)) {
    stop(name, " must be a nonmissing factor with levels c('<=50K', '>50K').",
         call. = FALSE)
  }
  if (require_both && any(tabulate(as.integer(y), nbins = 2L) == 0L)) {
    stop(name, " must contain observations from both income classes.",
         call. = FALSE)
  }
  invisible(y)
}

validate_income_scalar <- function(value, name, lower = 0, upper = Inf,
                                   integer = FALSE, strict_lower = FALSE) {
  if (!is.numeric(value) || length(value) != 1L || is.na(value) ||
      !is.finite(value) || value < lower || value > upper ||
      (strict_lower && value == lower) ||
      (integer && value != floor(value))) {
    stop("Invalid ", name, ".", call. = FALSE)
  }
  invisible(value)
}

fit_income_model <- function(kind, x, y, parameter = NULL,
                             seed = 12345L, trees = 200L) {
  choices <- c("majority", "logistic", "tree", "forest", "svm")
  if (!is.character(kind) || length(kind) != 1L || is.na(kind) ||
      !kind %in% choices) {
    stop("kind must be majority, logistic, tree, forest, or svm.", call. = FALSE)
  }
  x <- validate_income_matrix(x)
  validate_income_labels(y, require_both = kind != "majority")
  if (length(y) != nrow(x)) stop("x and y have different row counts.", call. = FALSE)
  validate_income_scalar(seed, "seed", upper = .Machine$integer.max, integer = TRUE)
  validate_income_scalar(trees, "trees", lower = 1, upper = .Machine$integer.max,
                         integer = TRUE)
  if (kind %in% c("majority", "logistic") && !is.null(parameter)) {
    stop("This model has no tuning parameter.", call. = FALSE)
  }

  # Each fit is reproducible without advancing the caller's random stream.
  had_seed <- exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
  if (had_seed) old_seed <- get(".Random.seed", envir = .GlobalEnv)
  on.exit({
    if (had_seed) {
      assign(".Random.seed", old_seed, envir = .GlobalEnv)
    } else if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) {
      rm(list = ".Random.seed", envir = .GlobalEnv)
    }
  }, add = TRUE)
  set.seed(as.integer(seed))

  wrapper <- list(kind = kind, columns = colnames(x), levels = income_class_levels,
                  parameter = parameter, seed = as.integer(seed),
                  threshold = if (kind == "svm") 0 else 0.5,
                  score_type = if (kind == "svm") "decision_margin" else "probability")
  if (kind == "majority") {
    wrapper$prevalence <- mean(y == ">50K")
  } else if (kind == "logistic") {
    design <- cbind("(Intercept)" = 1, x)
    # Select an estimable basis using training predictors only. This avoids
    # allowing arbitrary aliases to introduce missing predictions at scoring.
    design_qr <- qr(design, tol = 1e-7, LAPACK = FALSE)
    keep <- sort(design_qr$pivot[seq_len(design_qr$rank)])
    wrapper$design_columns <- colnames(design)[keep]
    wrapper$dropped_columns <- colnames(design)[-keep]
    fitted <- stats::glm.fit(
      x = design[, keep, drop = FALSE], y = as.integer(y == ">50K"),
      family = stats::binomial(), control = stats::glm.control(maxit = 100L),
      intercept = TRUE, singular.ok = TRUE
    )
    coefficients <- fitted$coefficients
    # Weighted IRLS can reveal additional aliases after structural QR selection.
    # Their zero contribution defines the same estimable fitted linear predictor.
    wrapper$aliased_columns <- names(coefficients)[is.na(coefficients)]
    coefficients[is.na(coefficients)] <- 0
    if (any(!is.finite(coefficients))) {
      stop("Logistic regression produced nonfinite coefficients.", call. = FALSE)
    }
    wrapper$coefficients <- coefficients
    wrapper$converged <- isTRUE(fitted$converged)
    wrapper$boundary <- isTRUE(fitted$boundary)
    wrapper$iterations <- fitted$iter
    wrapper$rank <- fitted$rank
    if (!wrapper$converged) {
      warning("Logistic regression did not converge; inspect this run before reporting results.",
              call. = FALSE)
    }
  } else if (kind == "tree") {
    if (!requireNamespace("rpart", quietly = TRUE)) {
      stop("Install rpart before fitting a decision tree.", call. = FALSE)
    }
    if (is.null(parameter)) parameter <- 0.01
    validate_income_scalar(parameter, "tree cp")
    frame <- as.data.frame(x)
    frame$.income_response <- y
    wrapper$model <- rpart::rpart(
      stats::as.formula(".income_response ~ .", env = baseenv()),
      data = frame, method = "class",
      control = rpart::rpart.control(cp = parameter, xval = 0L)
    )
  } else if (kind == "forest") {
    if (!requireNamespace("randomForest", quietly = TRUE)) {
      stop("Install randomForest before fitting a random forest.", call. = FALSE)
    }
    if (is.null(parameter)) parameter <- max(1L, floor(sqrt(ncol(x))))
    validate_income_scalar(parameter, "forest mtry", lower = 1,
                           upper = ncol(x), integer = TRUE)
    wrapper$model <- randomForest::randomForest(
      x = x, y = y, mtry = as.integer(parameter), ntree = as.integer(trees),
      importance = FALSE, keep.forest = TRUE
    )
    wrapper$trees <- as.integer(trees)
  } else {
    if (!requireNamespace("e1071", quietly = TRUE)) {
      stop("Install e1071 before fitting a linear SVM.", call. = FALSE)
    }
    if (is.null(parameter)) parameter <- 1
    validate_income_scalar(parameter, "SVM cost", strict_lower = TRUE)
    wrapper$model <- e1071::svm(
      x = x, y = y, kernel = "linear", type = "C-classification",
      cost = parameter, scale = FALSE, probability = FALSE,
      fitted = FALSE, cachesize = 200
    )
    # libsvm's binary margin is positive for labels[1]. The labels index the
    # fitted factor levels, so orientation never consults validation/test labels.
    first_label <- wrapper$model$levels[wrapper$model$labels[1L]]
    if (length(first_label) != 1L || !first_label %in% income_class_levels ||
        wrapper$model$nclasses != 2L) {
      stop("Cannot establish binary SVM score orientation.", call. = FALSE)
    }
    wrapper$margin_direction <- if (first_label == ">50K") 1 else -1
  }
  wrapper$parameter <- parameter
  class(wrapper) <- "income_model"
  wrapper
}

predict_income_model <- function(wrapper, x) {
  if (!inherits(wrapper, "income_model")) {
    stop("wrapper must be returned by fit_income_model().", call. = FALSE)
  }
  x <- validate_income_matrix(x, wrapper$columns)
  score <- switch(
    wrapper$kind,
    majority = rep(wrapper$prevalence, nrow(x)),
    logistic = {
      design <- cbind("(Intercept)" = 1, x)
      stats::plogis(as.vector(design[, wrapper$design_columns, drop = FALSE] %*%
                              wrapper$coefficients))
    },
    tree = as.numeric(stats::predict(wrapper$model, as.data.frame(x),
                                    type = "prob")[, ">50K"]),
    forest = as.numeric(stats::predict(wrapper$model, x, type = "prob")[, ">50K"]),
    svm = {
      result <- stats::predict(wrapper$model, x, decision.values = TRUE)
      margin <- attr(result, "decision.values")
      if (!is.matrix(margin) || ncol(margin) != 1L || nrow(margin) != nrow(x)) {
        stop("The fitted SVM did not return one margin per observation.", call. = FALSE)
      }
      as.numeric(margin[, 1L]) * wrapper$margin_direction
    },
    stop("Unknown fitted model kind.", call. = FALSE)
  )
  if (length(score) != nrow(x) || anyNA(score) || any(!is.finite(score))) {
    stop("The fitted model returned invalid scores.", call. = FALSE)
  }
  # Exact ties go to the lower-income class for every model, including SVM.
  prediction <- factor(ifelse(score > wrapper$threshold, ">50K", "<=50K"),
                       levels = income_class_levels)
  list(class = prediction, score = as.numeric(score))
}

validate_income_scores <- function(truth, score) {
  validate_income_labels(truth, "truth")
  if (!is.numeric(score) || !is.null(dim(score)) ||
      length(score) != length(truth) || anyNA(score) || any(!is.finite(score))) {
    stop("score must be one finite numeric value per observation.", call. = FALSE)
  }
  invisible(score)
}

income_metrics <- function(truth, prediction, score) {
  validate_income_scores(truth, score)
  validate_income_labels(prediction, "prediction")
  if (length(prediction) != length(truth)) {
    stop("truth and prediction have different lengths.", call. = FALSE)
  }
  positive <- truth == ">50K"
  predicted_positive <- prediction == ">50K"
  tp <- sum(positive & predicted_positive)
  tn <- sum(!positive & !predicted_positive)
  fp <- sum(!positive & predicted_positive)
  fn <- sum(positive & !predicted_positive)
  divide <- function(a, b) if (b == 0) NA_real_ else a / b
  recall <- divide(tp, tp + fn)
  specificity <- divide(tn, tn + fp)
  n_positive <- sum(positive)
  n_negative <- sum(!positive)
  auc <- if (n_positive == 0L || n_negative == 0L) {
    NA_real_
  } else {
    # Average ranks award half-credit to ties between positive/negative pairs.
    (sum(rank(score, ties.method = "average")[positive]) -
       n_positive * (n_positive + 1) / 2) / (n_positive * n_negative)
  }
  data.frame(
    n = length(truth), accuracy = (tp + tn) / length(truth),
    balanced_accuracy = (recall + specificity) / 2,
    precision = divide(tp, tp + fp), recall = recall,
    specificity = specificity, f1 = divide(2 * tp, 2 * tp + fp + fn),
    roc_auc = auc, tp = tp, tn = tn, fp = fp, fn = fn
  )
}

roc_points <- function(truth, score) {
  validate_income_scores(truth, score)
  positive <- truth == ">50K"
  n_positive <- sum(positive)
  n_negative <- sum(!positive)
  if (n_positive == 0L || n_negative == 0L) {
    return(data.frame(threshold = numeric(), fpr = numeric(), tpr = numeric()))
  }
  ordering <- order(score, decreasing = TRUE)
  ordered_score <- score[ordering]
  ordered_positive <- positive[ordering]
  # A point is emitted only after all observations with a tied score enter.
  tie_ends <- cumsum(rle(ordered_score)$lengths)
  data.frame(
    threshold = c(Inf, ordered_score[tie_ends]),
    fpr = c(0, cumsum(!ordered_positive)[tie_ends] / n_negative),
    tpr = c(0, cumsum(ordered_positive)[tie_ends] / n_positive)
  )
}
