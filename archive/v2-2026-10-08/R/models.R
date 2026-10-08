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
                             seed = 12345L, trees = 500L) {
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
  if (kind == "majority" && !is.null(parameter)) {
    stop("This model has no tuning parameter.", call. = FALSE)
  }

  # Each fit is reproducible without advancing the caller's random stream.
  had_seed <- exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
  if (had_seed) old_seed <- get(".Random.seed", envir = .GlobalEnv)
  old_kind <- RNGkind()
  on.exit({
    do.call(RNGkind, as.list(old_kind))
    if (had_seed) {
      assign(".Random.seed", old_seed, envir = .GlobalEnv)
    } else if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) {
      rm(list = ".Random.seed", envir = .GlobalEnv)
    }
  }, add = TRUE)
  RNGkind("Mersenne-Twister", "Inversion", "Rejection")
  set.seed(as.integer(seed))

  wrapper <- list(kind = kind, columns = colnames(x), levels = income_class_levels,
                  parameter = parameter, seed = as.integer(seed),
                  threshold = if (kind == "svm") 0 else 0.5,
                  score_type = if (kind == "svm") "decision_margin" else "probability")
  if (kind == "majority") {
    wrapper$prevalence <- mean(y == ">50K")
  } else if (kind == "logistic") {
    if (!requireNamespace("glmnet", quietly = TRUE)) {
      stop("Install glmnet before fitting ridge logistic regression.", call. = FALSE)
    }
    if (is.null(parameter)) parameter <- 0.01
    validate_income_scalar(parameter, "ridge lambda", strict_lower = TRUE)
    # glmnet standardizes using only the rows supplied to this fit, including
    # binary indicators, so the ridge penalty uses comparable feature scales.
    wrapper$glmnet_padding <- ncol(x) < 2L
    ridge_x <- if (wrapper$glmnet_padding) cbind(x, .ridge_constant = 0) else x
    wrapper$model <- glmnet::glmnet(ridge_x, as.integer(y == ">50K"),
      family = "binomial", alpha = 0, lambda = parameter, standardize = TRUE,
      intercept = TRUE, control = list(maxit = 100000L, thresh = 1e-7))
    wrapper$converged <- isTRUE(wrapper$model$jerr == 0L)
    wrapper$coefficients <- as.matrix(stats::coef(wrapper$model, s = parameter))[, 1L]
    if (!wrapper$converged || any(!is.finite(wrapper$coefficients)))
      stop("Ridge logistic regression did not converge to finite coefficients.", call. = FALSE)
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
    if (!requireNamespace("ranger", quietly = TRUE)) {
      stop("Install ranger before fitting a probability random forest.", call. = FALSE)
    }
    if (is.null(parameter)) parameter <- max(1L, floor(sqrt(ncol(x))))
    validate_income_scalar(parameter, "forest mtry", lower = 1,
                           upper = ncol(x), integer = TRUE)
    wrapper$model <- ranger::ranger(x = as.data.frame(x), y = y,
      mtry = as.integer(parameter), num.trees = as.integer(trees),
      probability = TRUE, min.node.size = 10L, num.threads = 1L,
      importance = "none", write.forest = TRUE, oob.error = FALSE,
      seed = if (seed == 0L) 1L else as.integer(seed))
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
  wrapper$n_training <- nrow(x)
  wrapper$n_features <- ncol(x)
  wrapper$fit_ok <- TRUE
  class(wrapper) <- "income_model"
  wrapper
}

predict_income_model <- function(wrapper, x) {
  if (!inherits(wrapper, "income_model")) {
    stop("wrapper must be returned by fit_income_model().", call. = FALSE)
  }
  backend <- c(logistic = "glmnet", tree = "rpart", forest = "ranger", svm = "e1071")
  if (wrapper$kind %in% names(backend) &&
      !requireNamespace(backend[[wrapper$kind]], quietly = TRUE)) {
    stop("Install ", backend[[wrapper$kind]], " before predicting with this saved model.", call. = FALSE)
  }
  x <- validate_income_matrix(x, wrapper$columns)
  score <- switch(
    wrapper$kind,
    majority = rep(wrapper$prevalence, nrow(x)),
    logistic = as.numeric(stats::predict(wrapper$model,
      newx = if (isTRUE(wrapper$glmnet_padding)) cbind(x, .ridge_constant = 0) else x,
      s = wrapper$parameter, type = "response")),
    tree = as.numeric(stats::predict(wrapper$model, as.data.frame(x),
                                    type = "prob")[, ">50K"]),
    forest = as.numeric(stats::predict(wrapper$model, data = as.data.frame(x),
      num.threads = 1L, seed = if (wrapper$seed == 0L) 1L else wrapper$seed)$predictions[, ">50K"]),
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
  if (wrapper$score_type == "probability" && any(score < 0 | score > 1))
    stop("The fitted model returned a score outside the probability range.", call. = FALSE)
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
  # Double counts prevent integer overflow for large evaluation samples.
  n_positive <- as.double(sum(positive))
  n_negative <- as.double(sum(!positive))
  auc <- if (n_positive == 0L || n_negative == 0L) {
    NA_real_
  } else {
    # Average ranks award half-credit to ties between positive/negative pairs.
    (sum(rank(score, ties.method = "average")[positive]) -
       n_positive * (n_positive + 1) / 2) / (n_positive * n_negative)
  }
  data.frame(
    n = length(truth), n_positive = n_positive, n_negative = n_negative,
    positive_rate = mean(positive), accuracy = (tp + tn) / length(truth),
    balanced_accuracy = (recall + specificity) / 2,
    precision = divide(tp, tp + fp), recall = recall,
    specificity = specificity, f1 = divide(2 * tp, 2 * tp + fp + fn),
    roc_auc = auc, average_precision = average_precision(truth, score),
    tp = tp, tn = tn, fp = fp, fn = fn
  )
}

pr_points <- function(truth, score) {
  validate_income_scores(truth, score)
  positive <- truth == ">50K"
  n_positive <- sum(positive)
  if (!n_positive) return(data.frame(threshold = numeric(), recall = numeric(), precision = numeric()))
  ordering <- order(score, decreasing = TRUE)
  ordered_score <- score[ordering]
  tie_ends <- cumsum(rle(ordered_score)$lengths)
  true_positive <- cumsum(positive[ordering])[tie_ends]
  data.frame(threshold = c(Inf, ordered_score[tie_ends]),
    recall = c(0, true_positive / n_positive),
    precision = c(1, true_positive / tie_ends))
}

average_precision <- function(truth, score) {
  points <- pr_points(truth, score)
  if (!nrow(points)) return(NA_real_)
  # Stepwise precision-recall integration; ties enter as one score group.
  sum(diff(points$recall) * points$precision[-1L])
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
