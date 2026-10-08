# Portable HTML and Markdown companions for aggregate-only result summaries.
summary_html_escape <- function(x) {
  x <- as.character(x)
  for (pair in list(c("&", "&amp;"), c("<", "&lt;"), c(">", "&gt;"),
                    c('"', "&quot;"), c("'", "&#39;"))) x <- gsub(pair[1], pair[2], x, fixed = TRUE)
  x
}

summary_display <- function(x, digits = 3, percent = FALSE) {
  ifelse(is.finite(x), paste0(formatC(if (percent) 100 * x else x,
    format = "f", digits = digits), if (percent) "%" else ""), "Not defined")
}

summary_findings <- function(raw, derived) {
  m <- derived$model_summary
  forest <- m[m$model == "forest", ]; tree <- m[m$model == "tree", ]
  cv <- raw$cv_summary[raw$cv_summary$selected, ]
  difference <- raw$paired_differences[raw$paired_differences$model_a == "tree" &
    raw$paired_differences$model_b == "forest" & raw$paired_differences$metric == "balanced_accuracy", ]
  c(
    sprintf("The decision tree made %s classification errors, versus %s for the forest. Its error count was %.1f%% lower than the majority baseline's.",
      format(tree$errors, big.mark = ","), format(forest$errors, big.mark = ","), tree$error_reduction_pct),
    sprintf("The forest had the highest observed ROC AUC (%.4f) and average precision (%.4f). Its %.2f%% recall still left %s of %s >50K records undetected.",
      forest$roc_auc, forest$average_precision, 100 * forest$recall,
      format(forest$fn, big.mark = ","), format(forest$n_positive, big.mark = ",")),
    sprintf("Relative to the tree, the forest found %s additional positive records and produced %s additional false positives at the fixed thresholds.",
      forest$tp - tree$tp, forest$fp - tree$fp),
    sprintf("Training cross-validation preferred the forest by %.3f percentage points of mean balanced accuracy over the tree. These are selection scores, not independent performance estimates.",
      100 * (cv$mean_balanced_accuracy[cv$model == "forest"] - cv$mean_balanced_accuracy[cv$model == "tree"])),
    sprintf("The tree-minus-forest test balanced-accuracy difference was %.3f percentage points; the saved conditional 95%% paired interval was %.3f to %.3f points. It includes zero and does not establish equivalence.",
      100 * difference$estimate, 100 * difference$lower, 100 * difference$upper),
    "Probability error, calibration, classification, and ranking describe different properties. A constant prevalence predictor can have a small binned calibration error while providing no ranking information."
  )
}

summary_html_table <- function(data, caption) {
  header <- paste0("<th scope='col'>", summary_html_escape(names(data)), "</th>", collapse = "")
  rows <- apply(data, 1L, function(row) paste0("<tr>", paste0("<td>",
    summary_html_escape(row), "</td>", collapse = ""), "</tr>"))
  paste0("<div class='table-scroll' tabindex='0' role='region' aria-label='", summary_html_escape(caption),
    "'><table><caption>", summary_html_escape(caption), "</caption><thead><tr>", header,
    "</tr></thead><tbody>", paste(rows, collapse = ""), "</tbody></table></div>")
}

write_results_summary_report <- function(raw, derived, catalog, destination) {
  labels <- c(majority = "Majority baseline", logistic = "Ridge logistic", tree = "Decision tree",
    forest = "Random forest", svm = "Linear SVM")
  findings <- summary_findings(raw, derived)
  m <- derived$model_summary
  scorecard <- data.frame(Model = unname(labels[m$model]),
    Accuracy = summary_display(m$accuracy, 2, TRUE),
    `Balanced accuracy` = summary_display(m$balanced_accuracy, 2, TRUE),
    Precision = summary_display(m$precision, 2, TRUE), Recall = summary_display(m$recall, 2, TRUE),
    `ROC AUC` = summary_display(m$roc_auc, 4), `Average precision` = summary_display(m$average_precision, 4),
    Errors = format(m$errors, big.mark = ","), check.names = FALSE)
  additional <- data.frame(Model = unname(labels[m$model]),
    `Errors per 1,000` = summary_display(m$errors_per_1000, 1),
    `Error reduction vs baseline` = paste0(summary_display(m$error_reduction_pct, 1), "%"),
    `Negative predictive value` = summary_display(m$negative_predictive_value, 2, TRUE),
    `MCC` = summary_display(m$mcc, 3),
    `AP / positive prevalence` = summary_display(m$average_precision_lift, 2), check.names = FALSE)
  cals <- derived$calibration_summary
  probabilities <- data.frame(Model = unname(labels[cals$model]),
    `Brier score` = summary_display(cals$brier_score, 4),
    `Log loss` = summary_display(cals$log_loss, 4),
    `Binned ECE` = summary_display(cals$binned_ece, 2, TRUE),
    `Occupied bins` = cals$bin_count, `Clipped probabilities` = cals$clipped_n, check.names = FALSE)
  limits <- paste("These are unweighted summaries of a reused historical UCI Adult benchmark.",
    "No models were fitted and no bootstrap intervals were recalculated for this supplement.",
    "Existing bootstrap intervals condition on fitted models and this sample; they omit training and selection uncertainty.",
    "Group and calibration intervals are the published descriptive Wilson intervals.",
    "Group comparisons do not establish fairness or causal discrimination. Matching profiles do not identify people.")
  definitions <- c(
    "Error reduction: 100 x (baseline errors - model errors) / baseline errors. Accuracy gains are percentage-point differences.",
    "Errors per 1,000: 1,000 x (false positives + false negatives) / evaluation sample size. These are sample summaries, not projected deployment counts.",
    "MCC: (TP x TN - FP x FN) / sqrt((TP+FP)(TP+FN)(TN+FP)(TN+FN)). Undefined denominators remain missing.",
    "Negative predictive value: TN / (TN+FN). False discovery rate: FP / (TP+FP). False omission rate: FN / (TN+FN). These depend on sample prevalence.",
    "Average-precision lift: average precision / observed positive prevalence. The baseline is the constant-score average precision; this is not a top-k lift statistic.",
    "Brier skill versus baseline: 1 - model Brier score / majority-baseline Brier score. It measures relative squared probability error on this sample.",
    "Binned ECE: sum over occupied bins of (bin size / total size) x absolute(mean prediction - observed rate), using the original ten fixed probability bins. It is bin-dependent and can hide within-bin errors; it is not an overall model ranking.",
    "Calibration gap: mean prediction - observed rate. Positive values indicate overprediction in that bin. Displayed limits transform the existing Wilson interval for the observed rate, holding the mean prediction fixed.",
    "CV fold points are dependent selection scores. Fold ranges and standard deviations are not confidence intervals or independent confirmation.",
    "Model-profile subsets have different case mixes. Their score differences do not measure the effect of removing duplicates or prove leakage."
  )
  figure_blocks <- vapply(seq_len(nrow(catalog)), function(i) {
    stem <- catalog$file[i]
    paste0("<section class='figure-section' id='", stem, "'><h2>", summary_html_escape(catalog$title[i]),
      "</h2><p>", summary_html_escape(catalog$interpretation[i]), "</p><figure><a class='image-link' href='", stem,
      ".png' target='_blank' rel='noopener' aria-label='Open full-size chart: ", summary_html_escape(catalog$title[i]),
      "'><img src='", stem, ".png' alt='", summary_html_escape(catalog$alt[i]),
      "' width='2400' height='1500' loading='lazy'></a><figcaption>", summary_html_escape(catalog$alt[i]),
      "</figcaption></figure><p class='meta'><a href='", stem, ".png' download>Download PNG</a> | Source tables: ",
      summary_html_escape(catalog$source_tables[i]), "</p></section>")
  }, character(1))
  csv_links <- paste0("<li><a href='", names(derived), ".csv' download>",
    summary_html_escape(gsub("_", " ", names(derived))), "</a></li>", collapse = "")
  nav <- paste0("<li><a href='#", catalog$file, "'>", summary_html_escape(catalog$title), "</a></li>", collapse = "")
  html <- c("<!doctype html><html lang='en'><head><meta charset='utf-8'>",
    "<meta name='viewport' content='width=device-width, initial-scale=1'><title>Income prediction: results summary</title>",
    "<style>:root{color-scheme:light}*{box-sizing:border-box}body{margin:0;background:#f5f7fa;color:#182b3a;font:17px/1.6 system-ui,sans-serif}main{max-width:1240px;margin:auto;padding:32px 24px 70px}h1{font-size:clamp(2rem,5vw,3.25rem);line-height:1.12;margin:16px 0}h2{font-size:1.6rem;line-height:1.25}a{color:#005b8a;text-underline-offset:3px}a:focus-visible,summary:focus-visible,[tabindex]:focus-visible{outline:3px solid #b96500;outline-offset:4px}.eyebrow{font-size:.85rem;letter-spacing:.08em;text-transform:uppercase;color:#445468}.intro{max-width:900px}.notice{border-left:4px solid #697586;background:#fff;padding:16px 20px}.findings{padding-left:24px}.findings li{margin:12px 0}.table-scroll{max-width:100%;overflow-x:auto;background:#fff;margin:24px 0}table{border-collapse:collapse;width:100%;font-size:.9rem;white-space:nowrap}caption{text-align:left;padding:14px;font-weight:700}th,td{padding:10px 14px;text-align:right;border-bottom:1px solid #dce3ea}th:first-child,td:first-child{text-align:left}th{background:#eaf0f5}figure{margin:20px 0}img{display:block;width:100%;height:auto;aspect-ratio:8/5;object-fit:contain;background:#fafbfd}figcaption,.meta{font-size:.85rem;color:#445468}.figure-section{margin:52px 0;scroll-margin-top:18px;border-top:1px solid #cbd5df;padding-top:24px}.downloads,.chart-nav{columns:2;column-gap:32px}li{break-inside:avoid}details{margin:24px 0}summary{cursor:pointer;font-weight:700}.footer{margin-top:48px;font-size:.9rem}code{font-size:.85em;overflow-wrap:anywhere}@media(max-width:650px){main{padding:22px 14px 50px}body{font-size:16px}.downloads,.chart-nav{columns:1}.notice{padding:12px}.figure-section{margin:34px 0}h2{font-size:1.35rem}}@media print{main{max-width:none;padding:0}.figure-section{break-inside:avoid}.chart-nav,details{display:none}a{color:inherit}}</style></head><body><main>",
    "<header><p class='eyebrow'>R / ggplot2 / historical Adult benchmark</p><h1>What the income classifiers get right and miss</h1>",
    sprintf("<p class='intro'>Ten additional views of the recorded version 2 results: %s test records, %.2f%% in the &gt;50K class, five model families, and fixed classification thresholds.</p>",
      format(m$n[1], big.mark = ","), 100 * m$positive_rate[1]),
    "<p><a href='results_summary.pdf'>Download the ten-page chart book (PDF)</a> | <a href='#statistics'>Summary statistics</a> | <a href='#downloads'>CSV downloads</a></p></header>",
    paste0("<p class='notice'>", summary_html_escape(limits), "</p>"),
    "<section><h2>Findings supported by the saved results</h2><ul class='findings'>",
    paste0("<li>", summary_html_escape(findings), "</li>", collapse = ""), "</ul></section>",
    "<section id='statistics'><h2>Model results and additional statistics</h2>",
    summary_html_table(scorecard, "Fixed-threshold classification and score-based ranking"),
    summary_html_table(additional, "Additional descriptive statistics derived from the saved counts"),
    summary_html_table(probabilities, "Probability quality: lower Brier score and log loss are better"),
    "<p>Undefined baseline precision and MCC remain missing. SVM margins are excluded from probability scores and calibration. Small ECE for the majority baseline reflects prevalence matching, not discrimination.</p></section>",
    paste0("<nav aria-label='Chart contents'><h2>Chart contents</h2><ol class='chart-nav'>", nav, "</ol></nav>"),
    "<p>Charts keep the same proportions at every screen size. Select any chart to open its full-resolution image.</p>",
    figure_blocks,
    paste0("<section id='downloads'><h2>Download the statistics</h2><ul class='downloads'>", csv_links, "</ul></section>"),
    "<details><summary>Definitions and interpretation limits</summary><ul>",
    paste0("<li>", summary_html_escape(definitions), "</li>", collapse = ""), "</ul></details>",
    "<footer class='footer'><p>Data source: <a href='https://archive.ics.uci.edu/dataset/2/adult'>UCI Adult</a>, Becker and Kohavi (1996), DOI 10.24432/C5XW20, CC BY 4.0. The dataset describes historical census-derived records.</p><p><a href='provenance.csv'>Input and source hashes</a> | <a href='artifact_manifest.csv'>Output manifest</a> | <a href='README.md'>Reproduction and file guide</a></p></footer></main></body></html>")
  writeLines(html, file.path(destination, "index.html"), useBytes = TRUE)
  md <- c("# Additional results summary", "",
    "Open `index.html` for the responsive gallery and statistics, or `results_summary.pdf` for the ten-page chart book.",
    "All ten PNGs are 2400 x 1500 pixels; the PDF pages are 12 x 7.5 inches. These additional views use verified published aggregates without changing the original evidence.", "",
    "## Results", "", paste0("- ", findings), "", "## Figures", "",
    "| Figure | Reading purpose |", "| --- | --- |",
    paste0("| [", catalog$title, "](", catalog$file, ".png) | ", catalog$interpretation, " |"), "",
    "## Statistics", "", paste0("- [", names(derived), "](", names(derived), ".csv)"), "",
    "## Definitions", "", paste0("- ", definitions), "", "## Scope", "", limits, "",
    "## Reproduce", "", "Run from the repository root using installed locked dependencies and a new destination:", "", "```sh",
    "Rscript --vanilla scripts/create_results_summary.R docs/evidence/v2-full-2026-10-08 results/new-results-summary", "```", "",
    "The generator supports the preserved published version 2 evidence, or an exact copy. It verifies source artifact hashes before reading tables and rejects nonempty destinations or destinations inside the source evidence. Input, code, environment, and output manifests accompany the results.",
    "The original and earlier supplemental graphics retain their separate provenance. This summary does not rerun training, tune thresholds, recalibrate models, or recompute bootstrap intervals.")
  writeLines(md, file.path(destination, "README.md"), useBytes = TRUE)
}
