# Publication graphics for the revised R analysis. Every figure is derived from
# the saved evaluation tables; no results, rankings, or intervals are hard-coded.

income_plot_labels <- c(majority = "Majority baseline", logistic = "Ridge logistic",
  tree = "Decision tree", forest = "Random forest", svm = "Linear SVM")
income_plot_colors <- c(majority = "#697586", logistic = "#0072B2",
  tree = "#D55E00", forest = "#009E73", svm = "#7250A2")

chart_subtitle <- function(n, smoke, official = TRUE) {
  provenance <- if (official) "UCI Adult" else "CUSTOM INPUTS: unverified source"
  scope <- if (smoke) "SMOKE CHECK" else "Reused benchmark test"
  sprintf("%s | %s | %s records | Positive class: >50K",
    scope, provenance, format(n, big.mark = ",", scientific = FALSE))
}

income_plot_theme <- function() {
  ggplot2::theme_minimal(base_size = 12, base_family = "sans") +
    ggplot2::theme(
      plot.background = ggplot2::element_rect(fill = "#FAFBFD", color = NA),
      panel.background = ggplot2::element_rect(fill = "#FFFFFF", color = NA),
      text = ggplot2::element_text(color = "#182B3A"),
      plot.title = ggplot2::element_text(size = 21, face = "bold", margin = ggplot2::margin(b = 9)),
      plot.subtitle = ggplot2::element_text(size = 11, color = "#445468", margin = ggplot2::margin(b = 17)),
      plot.caption = ggplot2::element_text(size = 9, color = "#445468", hjust = 0,
        lineheight = 1.15, margin = ggplot2::margin(t = 15)),
      plot.title.position = "plot", plot.caption.position = "plot",
      axis.title = ggplot2::element_text(size = 11),
      axis.text = ggplot2::element_text(color = "#33455A", size = 10),
      axis.ticks = ggplot2::element_blank(),
      panel.grid.minor = ggplot2::element_blank(),
      panel.grid.major = ggplot2::element_line(color = "#E5EAF0", linewidth = 0.35),
      strip.background = ggplot2::element_rect(fill = "#EBF0F5", color = NA),
      strip.text = ggplot2::element_text(size = 11, face = "bold", margin = ggplot2::margin(8, 8, 8, 8)),
      panel.spacing = grid::unit(1.15, "lines"),
      legend.position = "bottom", legend.title = ggplot2::element_blank(),
      legend.text = ggplot2::element_text(size = 10),
      legend.key.width = grid::unit(1.6, "lines"),
      legend.margin = ggplot2::margin(t = 8),
      plot.margin = ggplot2::margin(18, 24, 18, 20)
    )
}

income_color_scale <- function() {
  ggplot2::scale_color_manual(values = income_plot_colors,
    breaks = names(income_plot_labels), labels = unname(income_plot_labels), drop = FALSE)
}

income_model_factor <- function(model, reverse = FALSE) {
  order <- names(income_plot_labels)
  factor(model, levels = if (reverse) rev(order) else order)
}

save_income_figure <- function(plot, directory, name) {
  paths <- c(png = file.path(directory, paste0(name, ".png")),
    pdf = file.path(directory, paste0(name, ".pdf")))
  ggplot2::ggsave(paths[["png"]], plot = plot, width = 12, height = 7.5,
    units = "in", dpi = 200, bg = "#FAFBFD", limitsize = TRUE)
  ggplot2::ggsave(paths[["pdf"]], plot = plot, width = 12, height = 7.5,
    units = "in", device = grDevices::pdf, useDingbats = FALSE, bg = "#FAFBFD")
  paths
}

income_metric_plot <- function(evaluation, subtitle) {
  metric_names <- c(accuracy = "Accuracy", balanced_accuracy = "Balanced accuracy",
    roc_auc = "ROC AUC", average_precision = "Average precision")
  metrics <- evaluation$metrics
  values <- do.call(rbind, lapply(names(metric_names), function(metric) {
    data.frame(model = metrics$model, metric = metric, estimate = metrics[[metric]])
  }))
  values$lower <- NA_real_
  values$upper <- NA_real_
  intervals <- evaluation$metric_intervals
  if (!is.null(intervals) && nrow(intervals)) {
    key <- paste(values$model, values$metric)
    index <- match(key, paste(intervals$model, intervals$metric))
    values$lower <- intervals$lower[index]
    values$upper <- intervals$upper[index]
  }
  values$model <- income_model_factor(values$model, reverse = TRUE)
  values$metric <- factor(values$metric, levels = names(metric_names), labels = metric_names)
  values$value_label <- ifelse(is.finite(values$estimate), sprintf("%.3f", values$estimate), "NA")
  ggplot2::ggplot(values, ggplot2::aes(x = estimate, y = model, color = model)) +
    ggplot2::geom_errorbar(ggplot2::aes(xmin = lower, xmax = upper),
      orientation = "y", width = 0.18, linewidth = 0.8, na.rm = TRUE) +
    ggplot2::geom_point(size = 3.4, na.rm = TRUE) +
    ggplot2::geom_text(ggplot2::aes(x = 1.045, label = value_label),
      size = 3.4, hjust = 0, show.legend = FALSE) +
    ggplot2::facet_wrap(~metric, ncol = 2) +
    ggplot2::scale_y_discrete(labels = income_plot_labels) +
    ggplot2::scale_x_continuous(limits = c(0, 1.17), breaks = seq(0, 1, 0.25),
      labels = function(x) sprintf("%.2f", x), expand = ggplot2::expansion(mult = 0)) +
    income_color_scale() + income_plot_theme() +
    ggplot2::theme(legend.position = "none", panel.grid.major.y = ggplot2::element_blank()) +
    ggplot2::labs(title = "Performance across four complementary metrics", subtitle = subtitle,
      x = "Metric value", y = NULL,
      caption = paste("Dots: point estimates. Lines: 95% cluster-bootstrap intervals when available.",
        "Intervals describe this reused test sample, conditional on the fitted models; they do not include training variability.", sep = "\n"))
}

income_curve_plot <- function(evaluation, subtitle) {
  predictions <- evaluation$predictions
  roc_panel <- "ROC curve\nx: false positive rate | y: recall"
  pr_panel <- "Precision-recall curve\nx: recall | y: precision"
  curves <- do.call(rbind, lapply(evaluation$metrics$model, function(model) {
    rows <- predictions$model == model
    truth <- factor(predictions$truth[rows], levels = c("<=50K", ">50K"))
    scores <- predictions$score[rows]
    roc <- roc_points(truth, scores)
    pr <- pr_points(truth, scores)
    rbind(data.frame(model = model, panel = roc_panel, x = roc$fpr, y = roc$tpr),
      data.frame(model = model, panel = pr_panel, x = pr$recall, y = pr$precision))
  }))
  curves$panel <- factor(curves$panel, levels = c(roc_panel, pr_panel))
  curves$model <- income_model_factor(curves$model)
  prevalence <- mean(predictions$truth[predictions$model == evaluation$metrics$model[1L]] == ">50K")
  chance <- data.frame(panel = factor(roc_panel, levels = c(roc_panel, pr_panel)), slope = 1, intercept = 0)
  prevalence_line <- data.frame(panel = factor(pr_panel, levels = c(roc_panel, pr_panel)), prevalence = prevalence)
  ggplot2::ggplot(curves, ggplot2::aes(x = x, y = y, color = model, group = model)) +
    ggplot2::geom_abline(data = chance, ggplot2::aes(slope = slope, intercept = intercept),
      color = "#9CA8B6", linetype = "dashed", linewidth = 0.55) +
    ggplot2::geom_hline(data = prevalence_line, ggplot2::aes(yintercept = prevalence),
      color = "#9CA8B6", linetype = "dashed", linewidth = 0.55, inherit.aes = FALSE) +
    ggplot2::geom_path(data = curves[curves$panel == roc_panel, ], linewidth = 0.85, na.rm = TRUE) +
    ggplot2::geom_step(data = curves[curves$panel == pr_panel, ], direction = "vh",
      linewidth = 0.8, na.rm = TRUE) +
    ggplot2::facet_wrap(~panel, nrow = 1) +
    ggplot2::scale_x_continuous(limits = c(0, 1), breaks = seq(0, 1, 0.2),
      expand = ggplot2::expansion(mult = 0.01)) +
    ggplot2::scale_y_continuous(limits = c(0, 1), breaks = seq(0, 1, 0.2),
      expand = ggplot2::expansion(mult = 0.01)) + income_color_scale() +
    income_plot_theme() + ggplot2::labs(title = "Ranking quality across decision thresholds",
      subtitle = subtitle, x = NULL, y = NULL,
      caption = sprintf(paste("SVM uses decision margins; other models use predicted probabilities. Curves include all tied-score thresholds.",
        "Dashed references: chance ROC and positive-class prevalence (%.1f%%). Precision-recall uses steps consistent with average precision.", sep = "\n"),
        100 * prevalence)) + ggplot2::guides(color = ggplot2::guide_legend(nrow = 1))
}

income_confusion_plot <- function(evaluation, subtitle) {
  cells <- do.call(rbind, lapply(seq_len(nrow(evaluation$metrics)), function(i) {
    m <- evaluation$metrics[i, ]
    count <- c(m$tn, m$fp, m$fn, m$tp)
    denominator <- c(rep(m$tn + m$fp, 2L), rep(m$fn + m$tp, 2L))
    data.frame(model = m$model, truth = rep(c("<=50K", ">50K"), each = 2L),
      prediction = rep(c("<=50K", ">50K"), 2L), count = count,
      fraction = ifelse(denominator > 0, count / denominator, NA_real_))
  }))
  cells$model <- factor(cells$model, levels = names(income_plot_labels), labels = income_plot_labels)
  cells$truth <- factor(cells$truth, levels = c(">50K", "<=50K"))
  cells$prediction <- factor(cells$prediction, levels = c("<=50K", ">50K"))
  cells$label <- paste0(format(cells$count, big.mark = ",", trim = TRUE), "\n",
    ifelse(is.finite(cells$fraction), sprintf("%.1f%%", 100 * cells$fraction), "NA"))
  ggplot2::ggplot(cells, ggplot2::aes(x = prediction, y = truth, fill = fraction)) +
    ggplot2::geom_tile(color = "#FFFFFF", linewidth = 1.5) +
    ggplot2::geom_text(ggplot2::aes(label = label, color = fraction > 0.55),
      size = 4.6, lineheight = 1.1, show.legend = FALSE) +
    ggplot2::scale_color_manual(values = c("FALSE" = "#182B3A", "TRUE" = "#FFFFFF"), na.value = "#182B3A") +
    ggplot2::scale_fill_gradient(low = "#EFF5FA", high = "#145E8C", limits = c(0, 1),
      breaks = seq(0, 1, 0.25), labels = function(x) paste0(100 * x, "%"), name = "Within actual class") +
    ggplot2::facet_wrap(~model, ncol = 3) + income_plot_theme() +
    ggplot2::theme(panel.grid = ggplot2::element_blank(), legend.title = ggplot2::element_text(size = 10)) +
    ggplot2::labs(title = "Which income classes the models get right", subtitle = subtitle,
      x = "Predicted income class", y = "Actual income class",
      caption = paste("Each cell shows the number of records and the percentage within its actual income class.",
        "Thresholds fixed before evaluation: probability > 0.5 or SVM margin > 0; exact ties predict <=50K.", sep = "\n"))
}

income_calibration_plot <- function(evaluation, subtitle) {
  bins <- evaluation$calibration
  bins <- bins[bins$model != "svm", , drop = FALSE]
  bins$model_label <- factor(bins$model, levels = names(income_plot_labels), labels = income_plot_labels)
  bins$model <- income_model_factor(bins$model)
  line_bins <- bins[ave(bins$n, bins$model, FUN = length) > 1L, , drop = FALSE]
  ggplot2::ggplot(bins, ggplot2::aes(x = mean_probability, y = observed_rate, color = model)) +
    ggplot2::geom_abline(slope = 1, intercept = 0, color = "#8F9CAA", linetype = "dashed", linewidth = 0.6) +
    ggplot2::geom_errorbar(ggplot2::aes(ymin = lower, ymax = upper),
      width = 0.018, linewidth = 0.65, na.rm = TRUE) +
    ggplot2::geom_line(data = line_bins, linewidth = 0.6, na.rm = TRUE) +
    ggplot2::geom_point(ggplot2::aes(size = n), alpha = 0.9, na.rm = TRUE) +
    ggplot2::facet_wrap(~model_label, ncol = 2) +
    ggplot2::scale_x_continuous(limits = c(0, 1), breaks = seq(0, 1, 0.25),
      expand = ggplot2::expansion(mult = 0.025)) +
    ggplot2::scale_y_continuous(limits = c(0, 1), breaks = seq(0, 1, 0.25),
      expand = ggplot2::expansion(mult = 0.025)) +
    ggplot2::scale_size_area(max_size = 6.5, name = "Records per bin",
      labels = function(x) format(x, big.mark = ",", scientific = FALSE)) +
    income_color_scale() + income_plot_theme() +
    ggplot2::theme(legend.title = ggplot2::element_text(size = 10)) +
    ggplot2::guides(color = "none", size = ggplot2::guide_legend(nrow = 1)) +
    ggplot2::labs(title = "How predicted probabilities compare with observed rates", subtitle = subtitle,
      x = "Mean predicted probability of >50K", y = "Observed proportion with income >50K",
      caption = paste("Ten fixed equal-width probability bins; empty bins omitted. Bars: 95% Wilson intervals for each observed rate.",
        "Dashed line: perfect calibration. SVM margins are excluded because they are not probabilities. No calibration is fitted on this test set.", sep = "\n"))
}

income_subgroup_plot <- function(evaluation, subtitle) {
  subgroups <- evaluation$subgroup_metrics
  subgroups <- subgroups[subgroups$attribute %in% c("sex", "race"), , drop = FALSE]
  subgroups$group_label <- sprintf("%s\nn = %s; >50K = %s", subgroups$group,
    format(subgroups$n, big.mark = ",", trim = TRUE),
    format(subgroups$n_positive, big.mark = ",", trim = TRUE))
  subgroups$group_label <- factor(subgroups$group_label, levels = rev(unique(subgroups$group_label)))
  subgroups$attribute <- factor(subgroups$attribute, levels = c("sex", "race"), labels = c("Sex", "Race"))
  subgroups$model <- income_model_factor(subgroups$model)
  dodge <- ggplot2::position_dodge(width = 0.68)
  ggplot2::ggplot(subgroups, ggplot2::aes(x = recall, y = group_label, color = model, group = model)) +
    ggplot2::geom_errorbar(ggplot2::aes(xmin = recall_lower, xmax = recall_upper),
      orientation = "y", width = 0.12, linewidth = 0.6, position = dodge, na.rm = TRUE) +
    ggplot2::geom_point(size = 2.4, position = dodge, na.rm = TRUE) +
    ggplot2::facet_grid(attribute ~ ., scales = "free_y", space = "free_y") +
    ggplot2::scale_x_continuous(limits = c(0, 1), breaks = seq(0, 1, 0.1),
      expand = ggplot2::expansion(mult = 0.015)) + income_color_scale() + income_plot_theme() +
    ggplot2::theme(panel.grid.major.y = ggplot2::element_blank(), axis.text.y = ggplot2::element_text(size = 9),
      panel.spacing = grid::unit(0.8, "lines"), legend.text = ggplot2::element_text(size = 9.5)) +
    ggplot2::guides(color = ggplot2::guide_legend(nrow = 1)) +
    ggplot2::labs(title = "Recall varies across recorded demographic groups", subtitle = subtitle,
      x = "Recall for >50K: proportion of actual positives detected", y = NULL,
      caption = paste("Dots: recall. Bars: 95% Wilson intervals; >50K counts are their denominators. Small groups have wider uncertainty.",
        "Descriptive historical-data audit, not a fairness certification. Sex and race remain predictors; intervals are not adjusted for multiple comparisons.", sep = "\n"))
}

income_cv_plot <- function(cv_summary, smoke) {
  subtitle <- paste(if (smoke) "SMOKE CHECK |" else "Training data only |",
    "Selected configuration for each model | Positive class: >50K")
  if (is.null(cv_summary) || !nrow(cv_summary)) {
    return(ggplot2::ggplot(data.frame(x = 0.5, y = 0.5), ggplot2::aes(x, y)) +
      ggplot2::geom_text(label = "Fold-level validation results were not supplied.", size = 5) +
      income_plot_theme() + ggplot2::theme(axis.text = ggplot2::element_blank(),
        panel.grid = ggplot2::element_blank()) + ggplot2::labs(title = "Cross-validation stability",
        subtitle = subtitle, x = NULL, y = NULL,
        caption = "No validation values or uncertainty intervals have been inferred."))
  }
  folds <- cv_summary
  if ("selected" %in% names(folds)) folds <- folds[!is.na(folds$selected) & folds$selected, , drop = FALSE]
  if (!nrow(folds)) stop("No selected cross-validation rows were supplied to the plot writer.")
  if ("candidate" %in% names(folds) && any(vapply(split(folds$candidate, folds$model),
      function(x) length(unique(x)) > 1L, logical(1)))) {
    stop("CV comparison must contain only the selected configuration for each model.")
  }
  if (anyDuplicated(paste(folds$model, folds$fold))) stop("Duplicate model/fold rows in the CV plot input.")
  summaries <- do.call(rbind, lapply(split(folds, folds$model), function(d) {
    values <- d$balanced_accuracy[is.finite(d$balanced_accuracy)]
    data.frame(model = d$model[1L], mean = if (length(values)) mean(values) else NA_real_,
      lower = if (length(values)) min(values) else NA_real_,
      upper = if (length(values)) max(values) else NA_real_)
  }))
  folds$model <- income_model_factor(folds$model, reverse = TRUE)
  summaries$model <- income_model_factor(summaries$model, reverse = TRUE)
  # Deterministic vertical offsets expose folds without consuming the run's RNG.
  folds$position <- as.numeric(folds$model) + ave(as.numeric(factor(folds$fold)), folds$model,
    FUN = function(x) if (length(x) == 1L) 0 else seq(-0.16, 0.16, length.out = length(x)))
  summaries$position <- as.numeric(summaries$model)
  summaries$label <- sprintf("%.3f", summaries$mean)
  observed <- folds$balanced_accuracy[is.finite(folds$balanced_accuracy)]
  if (!length(observed)) stop("No finite cross-validation scores were supplied to the plot writer.")
  left_limit <- max(0, min(observed) - 0.035)
  right_limit <- min(1.08, max(observed) + 0.10)
  label_position <- max(observed) + 0.045
  axis_breaks <- pretty(c(left_limit, min(1, max(observed) + 0.025)), n = 6)
  axis_breaks <- axis_breaks[axis_breaks >= left_limit & axis_breaks <= min(1, max(observed) + 0.025)]
  ggplot2::ggplot(folds, ggplot2::aes(x = balanced_accuracy, y = position, color = model)) +
    ggplot2::geom_segment(data = summaries,
      ggplot2::aes(x = lower, xend = upper, y = position, yend = position), linewidth = 1,
      inherit.aes = FALSE, color = "#6B7D8F", na.rm = TRUE) +
    ggplot2::geom_point(ggplot2::aes(shape = "Individual fold"), size = 3, alpha = 0.7, na.rm = TRUE) +
    ggplot2::geom_point(data = summaries, ggplot2::aes(x = mean, shape = "Fold mean"),
      size = 4.4, na.rm = TRUE) +
    ggplot2::geom_text(data = summaries, ggplot2::aes(x = label_position, label = label),
      hjust = 0, size = 4, na.rm = TRUE, show.legend = FALSE) +
    ggplot2::scale_shape_manual(values = c("Individual fold" = 16, "Fold mean" = 18), name = NULL) +
    ggplot2::scale_y_continuous(breaks = seq_along(income_plot_labels),
      labels = rev(unname(income_plot_labels)), limits = c(0.5, 5.5)) +
    ggplot2::scale_x_continuous(limits = c(left_limit, right_limit), breaks = axis_breaks,
      expand = ggplot2::expansion(mult = 0)) + income_color_scale() + income_plot_theme() +
    ggplot2::theme(panel.grid.major.y = ggplot2::element_blank()) +
    ggplot2::guides(color = "none", shape = ggplot2::guide_legend(override.aes = list(alpha = 1, color = "#33455A"))) +
    ggplot2::labs(title = "Cross-validation stability of the selected configurations", subtitle = subtitle,
      x = "Balanced accuracy on validation folds (axis focuses on observed scores)", y = NULL,
      caption = paste("Circles: validation-fold scores. Diamonds: arithmetic fold means. Lines: observed minimum to maximum, not confidence intervals.",
        "Preprocessing is fitted inside each training fold. Selection and evaluation on the same CV folds can favor the winning configuration.", sep = "\n"))
}

write_comparison_charts <- function(evaluation, directory, smoke, official = TRUE,
                                    cv_summary = NULL) {
  if (!requireNamespace("ggplot2", quietly = TRUE)) {
    stop("Install ggplot2 before writing result graphics.", call. = FALSE)
  }
  if (!dir.exists(directory)) dir.create(directory, recursive = TRUE)
  subtitle <- chart_subtitle(evaluation$metrics$n[1L], smoke, official)
  plots <- list(model_comparison = income_metric_plot(evaluation, subtitle),
    roc_pr_curves = income_curve_plot(evaluation, subtitle),
    confusion_matrices = income_confusion_plot(evaluation, subtitle),
    calibration = income_calibration_plot(evaluation, subtitle),
    subgroup_recall = income_subgroup_plot(evaluation, subtitle),
    cv_comparison = income_cv_plot(cv_summary, smoke))
  paths <- lapply(names(plots), function(name) save_income_figure(plots[[name]], directory, name))
  names(paths) <- names(plots)
  invisible(paths)
}
