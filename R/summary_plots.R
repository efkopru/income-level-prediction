# Additional, aggregate-only views of the saved historical benchmark.
# This module never fits models or writes artifacts. R/plots.R supplies its
# established model labels, colors, and theme; summary_statistics.R supplies
# the explicitly named derived tables used below.

summary_plot_count <- function(x) format(x, big.mark = ",", trim = TRUE, scientific = FALSE)

summary_plot_source <- function(tables) {
  n <- unique(tables$model_summary$n)
  if (length(n) != 1L) stop("Summary plots require one shared test denominator.")
  sprintf("UCI Adult | reused historical benchmark | %s test rows", summary_plot_count(n))
}

summary_plot_caption <- function(tables, ...) paste(c(summary_plot_source(tables), ...), collapse = "\n")

summary_plot_theme <- function() {
  income_plot_theme() + ggplot2::theme(
    plot.title = ggplot2::element_text(size = 20, face = "bold", margin = ggplot2::margin(b = 8)),
    plot.subtitle = ggplot2::element_text(size = 11, margin = ggplot2::margin(b = 15)),
    plot.caption = ggplot2::element_text(size = 9, hjust = 0, lineheight = 1.12,
      margin = ggplot2::margin(t = 13)),
    panel.grid.major.y = ggplot2::element_blank(),
    panel.spacing = grid::unit(1.05, "lines"))
}

summary_plot_models <- function(model) income_model_factor(model, reverse = TRUE)

summary_plot_scorecard <- function(tables) {
  data <- tables$model_summary
  metric_labels <- c(accuracy = "Accuracy", balanced_accuracy = "Balanced\naccuracy",
    precision = "Precision", recall = "Recall", f1 = "F1", roc_auc = "ROC AUC",
    average_precision = "Average\nprecision")
  cells <- do.call(rbind, lapply(names(metric_labels), function(metric) {
    data.frame(model = data$model, metric = metric, value = data[[metric]])
  }))
  cells$model <- summary_plot_models(cells$model)
  cells$metric <- factor(cells$metric, levels = names(metric_labels), labels = metric_labels)
  cells$label <- ifelse(is.finite(cells$value), sprintf("%.3f", cells$value), "undefined")
  fill_scale <- ggplot2::scale_fill_gradient(low = "#EDF5F8", high = "#005B87", limits = c(0, 1),
    breaks = c(0, 0.25, 0.5, 0.75, 1), na.value = "#D9DEE5", name = "Metric value")
  fills <- fill_scale$map(cells$value)
  rgb <- grDevices::col2rgb(fills) / 255
  linear_rgb <- ifelse(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055)^2.4)
  luminance <- as.numeric(c(0.2126, 0.7152, 0.0722) %*% linear_rgb)
  # Black/white selection maximizes contrast against each exact mapped fill.
  cells$ink <- ifelse(luminance < sqrt(0.0525) - 0.05, "white", "black")
  ggplot2::ggplot(cells, ggplot2::aes(x = metric, y = model)) +
    ggplot2::geom_tile(ggplot2::aes(fill = value), width = 0.94, height = 0.86, color = "white") +
    ggplot2::geom_text(ggplot2::aes(label = label, color = ink), size = 4.1) +
    ggplot2::scale_color_identity() +
    fill_scale +
    ggplot2::scale_y_discrete(labels = income_plot_labels, expand = ggplot2::expansion(add = 0.15)) +
    ggplot2::scale_x_discrete(position = "top", expand = ggplot2::expansion(add = 0.05)) +
    summary_plot_theme() +
    ggplot2::theme(panel.grid = ggplot2::element_blank(), axis.text.x = ggplot2::element_text(size = 11),
      legend.title = ggplot2::element_text(size = 10)) +
    ggplot2::guides(fill = ggplot2::guide_colorbar(barwidth = grid::unit(8, "cm"),
      barheight = grid::unit(0.3, "cm"))) +
    ggplot2::labs(title = "Seven metrics give complementary views of performance",
      subtitle = "Positive class: >50K | Every cell is a separate metric; higher is better within each column",
      x = NULL, y = NULL,
      caption = summary_plot_caption(tables,
        "Point estimates only. The shared 0-1 color scale does not make different metrics interchangeable; no composite score is calculated.",
        "Gray: majority-baseline precision is undefined because it predicts no >50K rows. Threshold and ranking metrics answer different questions."))
}

summary_plot_errors <- function(tables) {
  data <- tables$error_composition
  data <- data[data$outcome %in% c("FP", "FN"), , drop = FALSE]
  data$model <- summary_plot_models(data$model)
  data$outcome <- factor(data$outcome, levels = c("FP", "FN"),
    labels = c("False positives", "False negatives"))
  data$label <- summary_plot_count(data$count)
  extent <- max(data$count)
  denominators <- tables$model_summary[1L, , drop = FALSE]
  ggplot2::ggplot(data, ggplot2::aes(x = count, y = model, fill = outcome)) +
    ggplot2::geom_col(width = 0.6) +
    ggplot2::geom_text(ggplot2::aes(x = count + extent * 0.025, label = label),
      hjust = 0, size = 4, color = "#182B3A") +
    ggplot2::facet_wrap(~outcome, nrow = 1) +
    ggplot2::scale_y_discrete(labels = income_plot_labels) +
    ggplot2::scale_x_continuous(limits = c(0, extent * 1.2),
      labels = summary_plot_count, expand = ggplot2::expansion(mult = 0)) +
    ggplot2::scale_fill_manual(values = c("False positives" = "#B66524", "False negatives" = "#425F94")) +
    summary_plot_theme() + ggplot2::theme(legend.position = "none") +
    ggplot2::labs(title = "False negatives outnumber false positives in every model",
      subtitle = "False positive: <=50K predicted >50K | False negative: >50K predicted <=50K",
      x = "Misclassified test rows (shared count scale)", y = NULL,
      caption = summary_plot_caption(tables,
        sprintf("All five models use the same %s test rows: %s actual positives and %s actual negatives. Counts are not error rates.",
          summary_plot_count(denominators$n), summary_plot_count(denominators$n_positive),
          summary_plot_count(denominators$n_negative)),
        "Decisions use the saved fixed thresholds. The majority baseline has zero false positives and misses every actual positive."))
}

summary_plot_baseline_gain <- function(tables) {
  data <- tables$model_summary
  values <- rbind(
    data.frame(model = data$model, panel = "Accuracy gain\npercentage points", value = data$accuracy_gain_pp),
    data.frame(model = data$model, panel = "Relative error reduction\npercent of baseline errors", value = data$error_reduction_pct))
  values$model <- summary_plot_models(values$model)
  values$panel <- factor(values$panel, levels = unique(values$panel))
  values$label <- ifelse(values$value == 0, "0.00", sprintf("%+.2f", values$value))
  ggplot2::ggplot(values, ggplot2::aes(x = value, y = model, color = model)) +
    ggplot2::geom_vline(xintercept = 0, color = "#7F8C98", linewidth = 0.6) +
    ggplot2::geom_segment(ggplot2::aes(x = 0, xend = value, yend = model), linewidth = 1.1) +
    ggplot2::geom_point(size = 3.3) +
    ggplot2::geom_text(ggplot2::aes(label = label), nudge_x = 0, hjust = -0.24,
      size = 4, show.legend = FALSE) +
    ggplot2::facet_wrap(~panel, scales = "free_x", nrow = 1) +
    ggplot2::scale_x_continuous(expand = ggplot2::expansion(mult = c(0.025, 0.27))) +
    ggplot2::scale_y_discrete(labels = income_plot_labels) + income_color_scale() +
    summary_plot_theme() + ggplot2::theme(legend.position = "none") +
    ggplot2::labs(title = "Every trained model improves on the majority baseline",
      subtitle = "Each panel uses its own stated units; zero means no improvement over the majority baseline",
      x = NULL, y = NULL,
      caption = summary_plot_caption(tables,
        "Accuracy gain = 100 x (model accuracy - baseline accuracy). Relative error reduction = 100 x (baseline errors - model errors) / baseline errors.",
        "Descriptive point differences on the reused test sample. These panels add no uncertainty intervals or significance claims."))
}

summary_plot_precision_recall <- function(tables) {
  data <- tables$model_summary
  data <- data[data$model != "majority", , drop = FALSE]
  # Four deterministic callouts keep the tightly clustered observed decisions
  # readable without a repel dependency or stochastic label placement.
  xmid <- mean(range(data$recall))
  ymid <- mean(range(data$precision))
  left <- c(logistic = TRUE, tree = TRUE, forest = FALSE, svm = FALSE)
  top <- c(logistic = FALSE, tree = TRUE, forest = TRUE, svm = FALSE)
  data$label_x <- xmid + ifelse(left[data$model], -0.125, 0.125)
  data$label_y <- ymid + ifelse(top[data$model], 0.087, -0.087)
  data$label <- sprintf("%s\nrecall %.3f | precision %.3f", income_plot_labels[data$model],
    data$recall, data$precision)
  ggplot2::ggplot(data, ggplot2::aes(x = recall, y = precision, color = model)) +
    ggplot2::geom_segment(ggplot2::aes(xend = label_x, yend = label_y),
      color = "#AAB4C0", linewidth = 0.6) +
    ggplot2::geom_point(ggplot2::aes(shape = model), size = 4) +
    ggplot2::geom_label(ggplot2::aes(x = label_x, y = label_y, label = label),
      fill = "#FAFBFD", linewidth = 0, size = 3.9, lineheight = 1.15, show.legend = FALSE) +
    ggplot2::scale_x_continuous(limits = xmid + c(-0.24, 0.24),
      breaks = seq(0, 1, 0.1), expand = ggplot2::expansion(mult = 0)) +
    ggplot2::scale_y_continuous(limits = ymid + c(-0.16, 0.16),
      breaks = seq(0, 1, 0.05), expand = ggplot2::expansion(mult = 0)) +
    ggplot2::scale_shape_manual(values = c(logistic = 16, tree = 17, forest = 15, svm = 18)) +
    income_color_scale() + summary_plot_theme() +
    ggplot2::theme(legend.position = "none", panel.grid.major.y = ggplot2::element_line(color = "#E5EAF0", linewidth = 0.35)) +
    ggplot2::labs(title = "Precision and recall describe the saved decisions",
      subtitle = "Fixed thresholds: probability 0.5; linear SVM margin 0 | Axes focus on the observed region",
      x = "Recall: share of actual >50K rows detected", y = "Precision: share of >50K predictions that are correct",
      caption = summary_plot_caption(tables,
        "Each point is one fitted model at its saved threshold, not a threshold-search curve. Higher and further right is better on these two metrics.",
        "Majority baseline omitted from the scatter: recall = 0, precision undefined (no positive predictions). No threshold is tuned here."))
}

summary_plot_probability_quality <- function(tables) {
  data <- tables$calibration_summary
  data <- data[is.finite(data$brier_score) & is.finite(data$log_loss), , drop = FALSE]
  values <- rbind(data.frame(model = data$model, metric = "Brier score", value = data$brier_score),
    data.frame(model = data$model, metric = "Log loss", value = data$log_loss))
  values$model <- summary_plot_models(values$model)
  values$metric <- factor(values$metric, levels = c("Brier score", "Log loss"))
  values$label <- sprintf("%.4f", values$value)
  clipped <- data[data$clipped_n > 0, , drop = FALSE]
  clipping_note <- if (nrow(clipped)) paste(sprintf("%s %s", income_plot_labels[clipped$model],
    summary_plot_count(clipped$clipped_n)), collapse = "; ") else "none"
  ggplot2::ggplot(values, ggplot2::aes(x = value, y = model, fill = model)) +
    ggplot2::geom_col(width = 0.58) +
    ggplot2::geom_text(ggplot2::aes(label = label), hjust = -0.18, size = 4) +
    ggplot2::facet_wrap(~metric, nrow = 1, scales = "free_x") +
    ggplot2::scale_x_continuous(limits = c(0, NA), expand = ggplot2::expansion(mult = c(0, 0.27))) +
    ggplot2::scale_y_discrete(labels = income_plot_labels) +
    ggplot2::scale_fill_manual(values = income_plot_colors) +
    summary_plot_theme() + ggplot2::theme(legend.position = "none") +
    ggplot2::labs(title = "Probability quality improves beyond the constant baseline",
      subtitle = "Lower is better in each panel | Both axes start at zero; the two scores have different units",
      x = NULL, y = NULL,
      caption = summary_plot_caption(tables,
        "Brier score and log loss measure overall probability quality, including discrimination and calibration. SVM margins are not probabilities.",
        paste0("Log loss uses clipping to [1e-15, 1 - 1e-15]. Rows clipped: ", clipping_note, ". Brier scores use original probabilities.")))
}

summary_plot_calibration_gaps <- function(tables) {
  data <- tables$calibration_gaps
  data <- data[data$model != "svm", , drop = FALSE]
  data$model_label <- factor(data$model, levels = names(income_plot_labels), labels = income_plot_labels)
  extent <- max(abs(unlist(data[c("gap", "gap_lower", "gap_upper")])), na.rm = TRUE)
  extent <- max(0.025, ceiling(extent * 1.12 / 0.025) * 0.025)
  ggplot2::ggplot(data, ggplot2::aes(x = mean_probability, y = gap, color = model)) +
    ggplot2::geom_hline(yintercept = 0, color = "#5C6C7E", linetype = "dashed", linewidth = 0.7) +
    ggplot2::geom_point(ggplot2::aes(size = n), alpha = 0.75) +
    ggplot2::geom_errorbar(ggplot2::aes(ymin = gap_lower, ymax = gap_upper),
      width = 0.015, linewidth = 0.6) +
    ggplot2::facet_wrap(~model_label, ncol = 2) +
    ggplot2::scale_x_continuous(limits = c(0, 1), breaks = seq(0, 1, 0.25),
      expand = ggplot2::expansion(mult = 0.025)) +
    ggplot2::scale_y_continuous(limits = c(-extent, extent),
      labels = function(x) ifelse(x == 0, "0", sprintf("%+.2f", x))) +
    ggplot2::scale_size_area(max_size = 7, name = "Rows per occupied bin", labels = summary_plot_count) +
    income_color_scale() + summary_plot_theme() +
    ggplot2::theme(panel.grid.major.y = ggplot2::element_line(color = "#E5EAF0", linewidth = 0.35),
      legend.title = ggplot2::element_text(size = 10)) +
    ggplot2::guides(color = "none", size = ggplot2::guide_legend(nrow = 1)) +
    ggplot2::labs(title = "Calibration gaps show overprediction and underprediction",
      subtitle = "Gap = mean predicted probability - observed >50K rate | Positive = overprediction; negative = underprediction",
      x = "Mean predicted probability in each occupied bin", y = "Probability gap (signed proportion)",
      caption = summary_plot_caption(tables,
        "Ten fixed-width bins; empty bins omitted. Bars reflect saved 95% Wilson rate intervals; they assume independent rows and hold predictions fixed.",
        "Zero marks agreement. Baseline agreement reflects prevalence, not discrimination. SVM excluded; no recalibration is fitted on this test set."))
}

summary_plot_hyperparameters <- function(raw_tables, tables) {
  candidates <- tables$cv_candidates
  candidates <- candidates[candidates$model != "majority", , drop = FALSE]
  folds <- raw_tables$cv_metrics
  folds <- folds[folds$model != "majority", , drop = FALSE]
  candidates <- candidates[order(candidates$order), , drop = FALSE]
  label <- paste0(candidates$candidate, ifelse(candidates$selected, "  [selected]", ""))
  key <- paste(candidates$model, candidates$candidate)
  candidates$key <- factor(key, levels = rev(key), labels = rev(label))
  folds$key <- factor(paste(folds$model, folds$candidate), levels = rev(key), labels = rev(label))
  candidates$family <- factor(candidates$model, levels = names(income_plot_labels), labels = income_plot_labels)
  folds$family <- factor(folds$model, levels = names(income_plot_labels), labels = income_plot_labels)
  candidates$selection <- ifelse(candidates$selected, "Selected mean", "Other candidate mean")
  candidates$mean_label <- sprintf("%.3f", candidates$mean_balanced_accuracy)
  observed <- range(folds$balanced_accuracy)
  limits <- c(max(0, floor((observed[1L] - 0.015) * 100) / 100),
    min(1, ceiling((observed[2L] + 0.045) * 100) / 100))
  label_x <- observed[2L] + 0.014
  ggplot2::ggplot(folds, ggplot2::aes(x = balanced_accuracy, y = key, color = model)) +
    ggplot2::geom_point(position = ggplot2::position_jitter(width = 0, height = 0.10, seed = 341),
      size = 2.5, alpha = 0.5, shape = 16) +
    ggplot2::geom_point(data = candidates,
      ggplot2::aes(x = mean_balanced_accuracy, shape = selection, fill = selection),
      size = 3.7, stroke = 0.8) +
    ggplot2::geom_text(data = candidates, ggplot2::aes(x = label_x, label = mean_label),
      size = 3.5, hjust = 0, show.legend = FALSE) +
    ggplot2::facet_wrap(~family, ncol = 2, scales = "free_y") +
    ggplot2::scale_x_continuous(limits = limits, breaks = seq(0, 1, 0.04),
      expand = ggplot2::expansion(mult = 0)) +
    ggplot2::scale_y_discrete(expand = ggplot2::expansion(add = 0.5)) +
    ggplot2::scale_shape_manual(values = c("Selected mean" = 23, "Other candidate mean" = 23)) +
    ggplot2::scale_fill_manual(values = c("Selected mean" = "#182B3A", "Other candidate mean" = "white")) +
    income_color_scale() + summary_plot_theme() +
    ggplot2::theme(axis.text.y = ggplot2::element_text(size = 9.5),
      legend.key.width = grid::unit(1.1, "lines")) +
    ggplot2::guides(color = "none", fill = ggplot2::guide_legend(order = 1),
      shape = ggplot2::guide_legend(order = 1)) +
    ggplot2::labs(title = "All 13 trained configurations in the validation search",
      subtitle = "Training folds only | Circles: five fold scores; diamonds and right labels: arithmetic means",
      x = "Validation balanced accuracy (axis focuses on the observed range)", y = NULL,
      caption = summary_plot_caption(tables,
        "This chart uses training cross-validation, not the 16,255-row test set. Filled diamonds and [selected] identify each family's chosen configuration.",
        "Fold spread is descriptive, not a confidence interval. Selection reuses these folds; tested grid boundaries do not establish a global optimum."))
}

summary_plot_subgroups <- function(tables) {
  candidates <- tables$cv_candidates
  preferred <- candidates[candidates$selected & candidates$model != "majority", , drop = FALSE]
  preferred <- preferred[order(-preferred$mean_balanced_accuracy, preferred$order), , drop = FALSE]$model[1L]
  data <- tables$subgroup_rates
  data <- data[data$model == preferred & data$attribute %in% c("sex", "race"), , drop = FALSE]
  data$group <- factor(data$group, levels = rev(unique(data$group)))
  data$attribute <- factor(data$attribute, levels = c("sex", "race"), labels = c("Recorded sex", "Recorded race"))
  data$metric <- factor(data$metric, levels = c("recall", "false_positive_rate"),
    labels = c("Recall\nTP / actual >50K", "False positive rate\nFP / actual <=50K"))
  data$label <- sprintf("%.1f%% | n=%s", data$estimate * 100, summary_plot_count(data$denominator))
  ggplot2::ggplot(data, ggplot2::aes(x = estimate, y = group)) +
    ggplot2::geom_errorbar(ggplot2::aes(xmin = lower, xmax = upper),
      orientation = "y", width = 0.16, linewidth = 0.8, color = income_plot_colors[preferred]) +
    ggplot2::geom_point(size = 2.8, color = income_plot_colors[preferred]) +
    ggplot2::geom_text(ggplot2::aes(x = 1.025, label = label), hjust = 0, size = 3.0, color = "#182B3A") +
    ggplot2::facet_grid(attribute ~ metric, scales = "free_y", space = "free_y") +
    ggplot2::scale_x_continuous(limits = c(0, 1.56), breaks = seq(0, 1, 0.25),
      labels = function(x) sprintf("%.0f%%", x * 100), expand = ggplot2::expansion(mult = 0)) +
    summary_plot_theme() + ggplot2::theme(axis.text.y = ggplot2::element_text(size = 9.5),
      strip.text.y = ggplot2::element_text(size = 10), panel.spacing = grid::unit(0.8, "lines")) +
    ggplot2::labs(title = paste(income_plot_labels[preferred], "errors vary across historical groups"),
      subtitle = "Model family preferred by training CV | Points: test estimates; bars: saved 95% Wilson intervals",
      x = "Rate (0-100%); right labels show estimate | metric-specific denominator", y = NULL,
      caption = summary_plot_caption(tables,
        "Recall denominators are actual >50K rows; false-positive-rate denominators are actual <=50K rows. Wide bars expose uncertainty in small groups.",
        "Original historical categories retained. Descriptive, not fairness certification; independent-row Wilson intervals are not multiplicity-adjusted."))
}

summary_plot_profiles <- function(tables) {
  data <- tables$profile_comparison
  values <- rbind(data.frame(model = data$model, profile_status = data$profile_status,
      metric = "Balanced accuracy", estimate = data$balanced_accuracy),
    data.frame(model = data$model, profile_status = data$profile_status, metric = "Recall", estimate = data$recall))
  values$model <- summary_plot_models(values$model)
  values$metric <- factor(values$metric, levels = c("Balanced accuracy", "Recall"))
  values$profile_status <- factor(values$profile_status, levels = c("seen_in_training", "novel_profile"))
  values$label <- sprintf("%.3f", values$estimate)
  statuses <- c("seen_in_training", "novel_profile")
  denominators <- data[match(statuses, data$profile_status), , drop = FALSE]
  status_labels <- sprintf("%s: n=%s; >50K=%s", c("Seen in training", "Novel profile"),
    summary_plot_count(denominators$n), summary_plot_count(denominators$n_positive))
  names(status_labels) <- statuses
  dodge <- ggplot2::position_dodge(width = 0.52)
  ggplot2::ggplot(values, ggplot2::aes(x = estimate, y = model,
    color = profile_status, shape = profile_status, group = profile_status)) +
    ggplot2::geom_point(size = 3.2, position = dodge) +
    ggplot2::geom_text(ggplot2::aes(label = label), hjust = -0.38, size = 3.5,
      position = dodge, show.legend = FALSE) +
    ggplot2::facet_wrap(~metric, nrow = 1) +
    ggplot2::scale_x_continuous(limits = c(0, 1.13), breaks = seq(0, 1, 0.25),
      expand = ggplot2::expansion(mult = c(0.015, 0))) +
    ggplot2::scale_y_discrete(labels = income_plot_labels) +
    ggplot2::scale_color_manual(values = c(seen_in_training = "#B66524", novel_profile = "#0072B2"),
      labels = status_labels) +
    ggplot2::scale_shape_manual(values = c(seen_in_training = 17, novel_profile = 16), labels = status_labels) +
    summary_plot_theme() + ggplot2::theme(legend.text = ggplot2::element_text(size = 10)) +
    ggplot2::guides(color = ggplot2::guide_legend(nrow = 2), shape = ggplot2::guide_legend(nrow = 2)) +
    ggplot2::labs(title = "Test results differ between seen and novel model profiles",
      subtitle = "All five models | Same fitted models and fixed thresholds; two descriptive test subsets",
      x = "Metric value (0-1)", y = NULL,
      caption = summary_plot_caption(tables,
        "Seen means an identical model-input predictor profile occurs in training. It does not establish that rows identify the same person.",
        "The subsets have different prevalence and case mixes. These point estimates do not isolate an overlap effect; no new intervals are inferred."))
}

summary_plot_composition <- function(tables) {
  flow <- tables$data_flow
  balance <- tables$class_balance
  raw_n <- setNames(flow$rows[flow$stage == "raw"], flow$partition[flow$stage == "raw"])
  flow$panel <- ifelse(flow$partition == "training", "Training retention", "Test retention")
  flow$category <- ifelse(flow$stage == "raw", "Raw rows", "Retained rows")
  flow$label <- sprintf("%s | %.2f%% of raw", summary_plot_count(flow$rows),
    100 * flow$rows / raw_n[flow$partition])
  balance$panel <- ifelse(balance$partition == "training", "Retained training classes", "Retained test classes")
  balance$category <- balance$class
  balance$label <- sprintf("%s | %.2f%% retained", summary_plot_count(balance$count), balance$percent)
  values <- rbind(data.frame(panel = flow$panel, category = flow$category, count = flow$rows, label = flow$label),
    data.frame(panel = balance$panel, category = balance$category, count = balance$count, label = balance$label))
  values$panel <- factor(values$panel, levels = c("Training retention", "Test retention",
    "Retained training classes", "Retained test classes"))
  values$category <- factor(values$category, levels = c(">50K", "<=50K", "Retained rows", "Raw rows"))
  # Exclusions are read separately because the raw and eligible rows coexist.
  eligible <- flow[flow$stage == "eligible", , drop = FALSE]
  removals <- eligible$excluded[match(c("training", "test"), eligible$partition)]
  ggplot2::ggplot(values, ggplot2::aes(x = count, y = category, fill = category)) +
    ggplot2::geom_col(width = 0.58) +
    ggplot2::geom_text(ggplot2::aes(label = label), hjust = -0.08, size = 3.5, color = "#182B3A") +
    ggplot2::facet_wrap(~panel, ncol = 2, scales = "free") +
    ggplot2::scale_x_continuous(limits = c(0, NA), labels = summary_plot_count,
      expand = ggplot2::expansion(mult = c(0, 0.72)), breaks = function(x) {
        b <- pretty(x, n = 3); b[b >= 0 & b <= max(x) * 0.72]
      }) +
    ggplot2::scale_fill_manual(values = c("Raw rows" = "#AEB8C5", "Retained rows" = "#0072B2",
      "<=50K" = "#65768A", ">50K" = "#B66524")) +
    summary_plot_theme() + ggplot2::theme(legend.position = "none") +
    ggplot2::labs(title = "Sample retention and class balance define the denominators",
      subtitle = sprintf("Exclusions: %s repeated labeled training rows; %s test rows sharing raw predictor signatures with training",
        summary_plot_count(removals[1L]), summary_plot_count(removals[2L])),
      x = "Rows (separate count scales, each starting at zero)", y = NULL,
      caption = summary_plot_caption(tables,
        "Retention percentages use each raw partition as denominator. Income percentages use each retained partition; the panels are not additive.",
        "Missing values are handled by fold-fitted preprocessing, not complete-case deletion. Profile matches are not confirmed person identities."))
}

summary_figure_catalog <- function() {
  data.frame(
    file = c("01_performance_scorecard", "02_classification_errors", "03_improvement_over_baseline",
      "04_precision_recall_tradeoff", "05_probability_quality", "06_calibration_gaps",
      "07_hyperparameter_search", "08_subgroup_errors", "09_profile_sensitivity", "10_sample_composition"),
    title = c("Seven metrics give complementary views of performance",
      "False negatives outnumber false positives in every model",
      "Every trained model improves on the majority baseline",
      "Precision and recall describe the saved decisions",
      "Probability quality improves beyond the constant baseline",
      "Calibration gaps show overprediction and underprediction",
      "All 13 trained configurations in the validation search",
      "Random forest errors vary across historical groups",
      "Test results differ between seen and novel model profiles",
      "Sample retention and class balance define the denominators"),
    alt = c(
      "Five-model, seven-metric scorecard with numeric cell labels. Majority-baseline precision is gray and explicitly undefined.",
      "Two zero-based count panels show false positives and false negatives for all five models, including the zero-positive majority baseline.",
      "Separate panels compare accuracy gain in percentage points and relative error reduction in percent against the majority baseline.",
      "Four trained models appear as individually labeled precision-recall points at their saved thresholds. Undefined baseline precision is stated below.",
      "Two zero-based bar panels compare Brier score and log loss for the four models with probability outputs; SVM is explicitly excluded.",
      "Four faceted signed calibration-gap plots show occupied bins, sample-sized points, transformed Wilson intervals, and a zero-reference line.",
      "Four model-family panels show all 13 trained configurations, five fold scores per configuration, their means, and explicit selected labels.",
      "Seven recorded sex and race groups have random-forest recall and false-positive-rate estimates, Wilson intervals, and metric-specific denominators.",
      "Balanced accuracy and recall are compared for seen and novel model-input profiles across all five models, with both subset sample sizes stated.",
      "Four zero-based panels show raw and retained training/test counts and the two income-class counts within each retained partition."),
    interpretation = c(
      "Read a column down to compare models on that metric. Values across unlike metrics are not a composite ranking.",
      "Compare error types within a model, then compare models on the common count scale. Different actual-class sizes prevent reading counts as rates.",
      "The left panel measures absolute accuracy improvement; the right panel measures the fraction of baseline mistakes avoided. Units differ.",
      "Higher precision and recall describe this fixed decision rule. The chart does not tune thresholds or establish a superior threshold policy.",
      "Lower values are better within each score. Probability quality includes both calibration and discrimination; clipping affects log loss.",
      "Positive gaps indicate overprediction and negative gaps underprediction. Large intervals signal sparse bins; a constant baseline can match prevalence.",
      "Selected means maximize the declared training-CV selection metric within each family. Fold spread is descriptive and selection-biased, not a confidence interval.",
      "Group estimates describe this historical sample. Inspect interval width and positive/negative denominators before comparing rates; this is not fairness certification.",
      "The profile subsets differ in case mix and prevalence. Their differences do not isolate causality or show that matching records are the same people.",
      "Each retention share is relative to raw rows, while class shares are relative to retained rows. Counts across these panels should not be summed."),
    source_tables = c("metrics.csv", "metrics.csv", "metrics.csv", "metrics.csv",
      "metrics.csv; calibration.csv", "calibration.csv", "cv_metrics.csv; cv_summary.csv",
      "subgroup_metrics.csv; cv_summary.csv", "profile_sensitivity.csv; profile_overlap.csv",
      "data_audit.csv; cv_metrics.csv; metrics.csv"),
    stringsAsFactors = FALSE)
}

make_results_summary_plots <- function(raw_tables, summary_tables) {
  if (!requireNamespace("ggplot2", quietly = TRUE)) stop("ggplot2 is required for summary figures.")
  plots <- list(
    summary_plot_scorecard(summary_tables), summary_plot_errors(summary_tables),
    summary_plot_baseline_gain(summary_tables), summary_plot_precision_recall(summary_tables),
    summary_plot_probability_quality(summary_tables), summary_plot_calibration_gaps(summary_tables),
    summary_plot_hyperparameters(raw_tables, summary_tables), summary_plot_subgroups(summary_tables),
    summary_plot_profiles(summary_tables), summary_plot_composition(summary_tables))
  stats::setNames(plots, summary_figure_catalog()$file)
}
