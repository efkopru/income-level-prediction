# Portfolio handoff

## Current publication boundary

The [existing portfolio page](https://www.ekopru.com/income-level-prediction-using-r/index.html) presents this as an independent historical R learning project. It links to [efkopru/ILPrediction](https://github.com/efkopru/ILPrediction) and includes 26 original presentation images. Its current wording already states that the historical results are exploratory rather than a validated benchmark or deployed system.

This modernization is local. No GitHub push, repository visibility change, or live portfolio edit is included. Verify the intended repository, its final contents, and the completed run evidence before replacing the existing source link or presenting revised results.

The original script remains unchanged in `archive/IncomeLevelPrediction_original.R`. Keep the historical work's authorship and context intact. Describe the revised evaluation as a later reproducibility update.

## Copy for the updated project page

### Title

Income Level Prediction Using R

### Short description

A reproducible comparison of logistic regression, decision trees, random forests, and a linear SVM on the historical UCI Adult dataset, with a majority-class baseline and a separate final evaluation set.

### My contribution

I built the original R learning project to compare classifiers for a binary income-category task. I later revised the code to correct data-splitting and evaluation problems, make preprocessing depend only on training data, and save model comparisons, data audits, and runtime details in a repeatable workflow.

### What the updated workflow demonstrates

- Reproducible data preparation with explicit data provenance and duplicate handling.
- Parameter selection using an internal validation split while preserving the official test set for final evaluation.
- Comparison of a simple baseline and four model families using both class predictions and ranking metrics.
- Aggregate subgroup reporting with explicit limits on interpretation.
- Automated regression checks and a portable command-line workflow.

### Limitations

This remains an educational study on historical census-derived records. Reported metrics describe the retained sample, use no survey weighting, and do not establish performance on current populations. Subgroup comparisons are descriptive checks, not a fairness certification. The project has not been deployed for individual decisions.

### Results copy

In the revised run completed on October 8, 2026, I evaluated a majority baseline and four model families on 16,255 held-out records after training on 32,535 retained records. The random forest achieved 86.40% accuracy and 77.69% balanced accuracy, the highest values among the models on this split. Logistic regression had the highest ROC AUC at 0.9040. These results describe this evaluation and do not establish a universally best model or performance on current populations.

| Model | Accuracy | Balanced accuracy | ROC AUC |
| --- | ---: | ---: | ---: |
| Majority baseline | 76.38% | 50.00% | 0.5000 |
| Logistic regression | 85.27% | 76.57% | 0.9040 |
| Decision tree | 85.89% | 75.63% | 0.8862 |
| Random forest | 86.40% | 77.69% | 0.8922 |
| Linear SVM | 85.27% | 76.34% | 0.9027 |

Parameter selection used a training-only split of 26,029 analysis and 6,506 validation records, seed `12345`, and validation balanced accuracy. Selected settings were tree `cp = 0.001`, forest `mtry = 9` with 200 trees, and SVM `cost = 1`. Logistic regression converged, with the recorded warning that fitted probabilities numerically reached zero or one. Preserve this diagnostic in the technical details.

The [full-run report](evidence/full-2026-10-08/report.md), [exact metrics](evidence/full-2026-10-08/metrics.csv), and [validation record](VALIDATION.md) support these statements. The 24 offline checks passed with zero failures. Both final figures were inspected at full resolution. Historical screenshot values remain separate from these revised results.

## Prepare aggregate evidence

The completed run was exported into `docs/evidence/full-2026-10-08`. The command used for this export, run from the repository root, is:

```sh
Rscript scripts/export_evidence.R results/full-2026-10-08 docs/evidence/full-2026-10-08
```

The run snapshots source and input checksums before fitting and refuses to finalize if either changes before its final checks. The exporter requires the completed run's artifacts to match their manifest, full-run mode, and official UCI input checksums. It copies a fixed allowlist and verifies the copied hashes, preserving any nonempty existing destination. It creates a public manifest covering the exported files.

The exported folder contains 16 files, including its README and public manifest. It intentionally excludes raw records, predictions, split identifiers, model objects, and machine-specific session details. An unchanged checksum is provenance evidence, not a substitute for checking the content and claims. The existing destination is protected; use a new directory for a subsequent export.

## Figure and screenshot specifications

Keep the 26 existing images labeled **Original historical presentation**. Retain their slide order and existing full-size image viewer. The existing previews use a 1440 x 810 display ratio; preserve their aspect ratio and avoid cropping content.

Add a separate **Reproducibility update** gallery using these inspected full-run assets:

| Source asset | Dimensions | Caption and alt text |
| --- | --- | --- |
| `docs/evidence/full-2026-10-08/model_comparison.png` | 2400 x 1500 pixels | Held-out model comparison for the revised UCI Adult study, showing accuracy, balanced accuracy, and ROC AUC for five classifiers. |
| `docs/evidence/full-2026-10-08/roc_curves.png` | 2400 x 1500 pixels | ROC curves for five classifiers on the retained official UCI Adult test records; SVM ranking uses decision margins. |

These are generated plots from the revised pipeline, not historical screenshots. Their dimensions, labels, legends, and layout were visually checked. Copy these reviewed aggregate assets to the portfolio assets directory. Keep source ownership attributed to this project and dataset attribution visible in the page's technical details.

Use equal card widths, equal preview dimensions, and the same zoom for both new figures. Render previews inside a `16 / 10` container with `object-fit: contain`; preserve the entire chart, including axes and legends. Use two columns above 800 CSS pixels and one column at or below 800 pixels. Set intrinsic image `width="2400"` and `height="1500"`, with `max-width: 100%` and responsive height. Test at 360, 768, and 1280 CSS pixels for overflow and legibility.

Each figure must open the full-resolution source in the keyboard-accessible viewer, with a named close button, Escape to close, focus restored to the launching link, and a visible caption. Include meaningful alt text. Verify axes and legends remain readable in the full-size viewer and that neither preview changes the apparent scale relative to the other.

## Evidence required before publication

- Complete the offline checks and a full official-data run. Inspect `warnings.txt` and the report.
- Confirm the report's dataset counts, selected settings, and metric values against its CSV evidence.
- Inspect both generated figures at their full resolution. Check titles, units, labels, legends, and cropping.
- Use the aggregate-evidence exporter, then inspect its allowlisted output and public manifest. Exclude raw data, row-level predictions, split exports, model objects, local libraries, and temporary files from the staged tree.
- Review the staged tree for personal information, secrets, accidental local paths, and unsupported claims.
- Choose a code license explicitly if open-source reuse is intended. Preserve UCI data attribution separately.
- When publication is requested, verify the remote target, repository visibility, uploaded file list, and commit identity. Confirm the live portfolio uses the final repository URL and the matching revised assets.

Drafted CI configuration is not evidence of successful remote checks. A local successful run is not evidence that GitHub or the portfolio has been updated.
