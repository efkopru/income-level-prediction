# Income Level Prediction Using R

A reproducible R classification study using the [UCI Adult dataset](https://archive.ics.uci.edu/dataset/2/adult). The project compares a majority-class baseline, logistic regression, a decision tree, a random forest, and a linear support vector machine for the historical income categories `<=50K` and `>50K`.

This repository modernizes Esad Kopru's original independent learning project. The [unchanged historical script](archive/IncomeLevelPrediction_original.R) remains available for provenance. The new workflow separates model selection from final evaluation and writes inspectable results rather than relying on an interactive R session.

**Scope:** an educational model comparison on historical census-derived data. This is not a deployed income assessment system, a current population income estimate, or a fairness certification.

## Run the project

Install R 4.2 or later, then run these commands from the repository directory. `Rscript` must be available on your command path.

```sh
Rscript scripts/install_dependencies.R
Rscript tests/run_tests.R
Rscript IncomeLevelPrediction.R --download --smoke --output results/smoke
Rscript IncomeLevelPrediction.R --download --output results/full
```

The dependency installer uses the ignored project-local `.R-library` directory. The modeling packages are `rpart`, `randomForest`, and `e1071`; `proxy` is an `e1071` dependency. The installer requires internet access. A run records the R and package versions actually used; dependencies are not locked to an immutable environment.

Downloading is explicit. `--download` fetches the official UCI data and metadata files into `data/raw` and verifies their recorded checksums. Existing files must also match those checksums when this flag is used. Subsequent runs can use those local inputs:

```sh
Rscript IncomeLevelPrediction.R --data-dir data/raw --output results/local
```

Use `--help` for options, including `--seed` (default `12345`), `--trees` (default `200`), and `--validation-fraction` (default `0.2`). A smoke run uses at most 1,200 training and 600 test rows, at most 30 forest trees, and the first candidate from each parameter grid to check execution. It is not evidence for the full-data model comparison.

The default input directory is the project's `data/raw` directory. With no `--output`, the workflow creates a project-local `results/run-YYYYMMDD-HHMMSS` directory using a UTC timestamp. Explicit relative `--data-dir` and `--output` paths resolve from the directory where the command is invoked. Nonempty output directories are refused so earlier runs remain intact; choose a new output directory for every rerun.

## Evaluation design

1. Read the official `adult.data` training file and `adult.test` evaluation file. Before cleaning, these contain 32,561 and 16,281 records respectively. Normalize whitespace, missing-value markers, and the trailing punctuation on test labels.
2. Build duplicate signatures from the 14 raw predictor fields, without using test labels. Exclude all training rows for signatures with conflicting training labels, then retain the first training row for each remaining duplicate signature. Remove test rows whose signature occurs anywhere in the original training file, including excluded conflicting rows. Preserve duplicate multiplicities within the remaining test data and save exclusion counts in the audit. Predictor signatures are not identity keys and do not establish unique-person independence.
3. Split the retained official training data into stratified training and validation partitions, 80/20 by default. The official test data do not participate in tuning.
4. Fit preprocessing only on the internal training partition. Impute numeric values with training medians, scale with training statistics, and learn categories using a missing-value marker. Map any category absent from the training partition, including a previously unseen missing marker, to the training mode. Use treatment-coded categorical predictors and drop constant columns.
5. Compare tree complexity values `0.001`, `0.005`, and `0.01`; random-forest candidate predictor counts based on the square root and one third of the encoded feature count; and linear-SVM cost values `0.1`, `1`, and `10`. Choose each model's parameters using validation balanced accuracy, keeping the first candidate on a tie.
6. Refit preprocessing and each selected model on the full retained official training data. Evaluate each model once on the retained official test data.

The official-file audit retains 32,535 training and 16,255 test records: two training rows with conflicting labels and 24 additional training duplicates are excluded, along with 26 test rows overlapping original training predictors. Six duplicate test rows remain after overlap removal. The smoke run uses a further sample of these eligible partitions.

The redundant text `education` field is excluded in favor of its numeric counterpart. `fnlwgt` is excluded from predictors and is not used as an observation weight. All reported evaluation metrics are unweighted sample metrics.

The positive class is `>50K`. Reported metrics include accuracy, balanced accuracy, precision, recall, specificity, F1, ROC AUC, and confusion-matrix counts. Classification thresholds are fixed: probabilities greater than `0.5` or oriented SVM margins greater than `0` predict `>50K`; ties predict `<=50K`. SVM ROC AUC uses oriented decision scores, which are margins rather than calibrated probabilities. Undefined metrics appear as blank CSV fields and `NA` in the report. Recorded `sex` and `race` are included predictors; aggregate metrics by these fields are descriptive checks. Small groups, historical sampling, and label limitations restrict their interpretation. A single validation split and small parameter grids do not establish statistical superiority or broad optimality.

## Outputs and evidence

Each completed run creates an output directory containing:

| File | Purpose |
| --- | --- |
| `report.md` | Run summary, method, metrics, and limitations |
| `metrics.csv` | Final evaluation metrics for all five models |
| `validation_metrics.csv` | Tuning results from the internal validation split |
| `selected_parameters.csv` | Selected model settings |
| `subgroup_metrics.csv` | Descriptive evaluation by recorded sex and race |
| `data_audit.csv` | Input, missingness, and exclusion counts |
| `predictions.csv` | Record-level labels, predictions, and scores |
| `split_assignments.csv` | Reproducible internal split assignments |
| `input_manifest.csv` | Source-file provenance and checksums |
| `source_manifest.csv` | Checksums of the R entry point and analysis source files |
| `unseen_categories.csv` | Counts of categorical values mapped to training modes |
| `package_versions.csv`, `session_info.txt` | Runtime and dependency evidence |
| `run_config.txt`, `warnings.txt` | Run settings and captured warnings |
| `models.rds` | Fitted preprocessing and model objects |
| `model_comparison.png`, `roc_curves.png` | Aggregate comparison figures |
| `artifact_manifest.csv` | Output inventory and checksums |

The workflow records source and input checksums before fitting and refuses to finalize a run if those files change before its final checks. The manifests identify the inputs, code, packages, and settings used for that run; they are not a locked dependency environment.

The default `results/` and `data/raw/` directories, local dependencies, and fitted `.rds` models are ignored by Git. Custom output directories require the same publication review. Use the aggregate-evidence exporter to prepare documentation from a completed, inspected full run:

```sh
Rscript scripts/export_evidence.R results/full-2026-10-08 docs/evidence/full-2026-10-08
```

Replace the dated source and destination when exporting a different run. The exporter verifies the completed run's artifact checksums, requires the official input checksums and full-run mode, and copies a fixed list of aggregate reports, metrics, figures, and provenance files into a new or empty destination. It excludes raw records, predictions, split identifiers, model objects, and machine-specific session details. It also writes a separate public artifact manifest and checks copied files against their source hashes. Inspect the export before committing it.

A generated report describes one run; it does not establish performance on other populations or guarantee future package compatibility. The completed update includes a [full-run report](docs/evidence/full-2026-10-08/report.md), [aggregate metrics](docs/evidence/full-2026-10-08/metrics.csv), and [validation record](docs/VALIDATION.md).

## Verified local results

The full run completed on October 8, 2026 using R 4.6.1, seed `12345`, 32,535 retained training records, and 16,255 retained test records. The internal training/validation split contained 26,029 and 6,506 records. Selected settings were tree `cp = 0.001`, forest `mtry = 9` with 200 trees, and SVM `cost = 1`.

| Model | Accuracy | Balanced accuracy | ROC AUC |
| --- | ---: | ---: | ---: |
| Majority baseline | 76.38% | 50.00% | 0.5000 |
| Logistic regression | 85.27% | 76.57% | 0.9040 |
| Decision tree | 85.89% | 75.63% | 0.8862 |
| Random forest | 86.40% | 77.69% | 0.8922 |
| Linear SVM | 85.27% | 76.34% | 0.9027 |

The random forest had the highest accuracy and balanced accuracy among these models on this split; logistic regression had the highest ROC AUC. These results do not establish a universally best model. The original slide values are not directly comparable because the evaluation design changed.

**Validation:** 24 offline checks passed with zero failures; the final smoke run, full run, aggregate export, and visual inspection of both figures completed. Logistic regression converged but reported fitted probabilities numerically equal to zero or one; the warning remains in the evidence. GitHub Actions is configured for Windows and Linux but has not been executed remotely. See the [validation record](docs/VALIDATION.md) for diagnostics and verification limits.

## What changed from the historical code

The original script used a placeholder working directory, relied on packages and objects not consistently initialized, selected split indices from cleaned rows but applied them to the uncleaned data, and trained some models on the complete dataset before evaluation. It also applied a probability-style threshold to logistic-regression link predictions and used SVM class labels for a ROC calculation.

The replacement provides explicit input handling, a command-line entry point, consistent preprocessing, a majority baseline, isolated validation and test evaluation, probability or decision-score ROC inputs, and saved evidence for each run. These repairs change the experiment. Historical presentation screenshots are retained as records of the original study, not as validation of the revised implementation.

## Repository layout

```text
IncomeLevelPrediction.R       Command-line entry point
R/                            Data, model, and reporting functions
scripts/install_dependencies.R
scripts/export_evidence.R     Allowlisted aggregate evidence export
tests/                        Offline regression checks
data/README.md                Data source, license, and handling
archive/                      Unchanged original script and provenance
docs/PORTFOLIO_HANDOFF.md      Evidence-bounded publication copy and assets
docs/VALIDATION.md             Observed checks, run diagnostics, and limits
docs/evidence/full-2026-10-08/ Reviewed aggregate results and figures
.github/workflows/check.yml   Linux and Windows automated checks
```

The current [portfolio page](https://www.ekopru.com/income-level-prediction-using-r/index.html) documents the historical project and links to [efkopru/ILPrediction](https://github.com/efkopru/ILPrediction). This local modernization does not itself update either remote location.

## Data attribution and code rights

Becker, B. and Kohavi, R. (1996). *Adult*. UCI Machine Learning Repository. [doi:10.24432/C5XW20](https://doi.org/10.24432/C5XW20). The dataset is offered under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Its historical income threshold and recorded demographic categories require context when interpreting results.

No code license has been selected for this repository. The dataset license does not license the project's code. Public availability alone does not grant an open-source license.
