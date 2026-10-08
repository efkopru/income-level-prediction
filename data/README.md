# Data source and handling

This project uses the official training and test files from the [UCI Adult dataset](https://archive.ics.uci.edu/dataset/2/adult).

| Input | Official URL | Original record count |
| --- | --- | ---: |
| `adult.data` | <https://archive.ics.uci.edu/ml/machine-learning-databases/adult/adult.data> | 32,561 |
| `adult.test` | <https://archive.ics.uci.edu/ml/machine-learning-databases/adult/adult.test> | 16,281 |

The test file includes an initial comment line and labels with trailing periods. The parser normalizes these formats and treats `?` as a missing-value marker.

The current workflow follows the [version 2 protocol](../docs/METHODOLOGY_V2.md). Use R 4.6.1 and restore the 34 package versions recorded in `renv.lock`, then run from the repository root:

```sh
Rscript --vanilla scripts/install_dependencies.R
Rscript --vanilla IncomeLevelPrediction.R --download --output results/v2-full
```

The installer restores the recorded versions into the project-local `.R-library` as needed. The workflow checks all locked package versions before fitting. `--vanilla` starts R without restored workspaces or startup profiles.

The download flag fetches the two data files and UCI's `adult.names` metadata into `data/raw`. Downloads and existing inputs supplied with `--download` must match the recorded UCI MD5 checksums. Alternatively, place the two data files in a local directory and supply `--data-dir PATH` without `--download`. No dataset download occurs merely by loading the project functions.

Without `--download`, compatible custom inputs can run even if their checksums differ from the UCI reference files. The generated input manifest, report, and charts identify that difference. Do not present results from changed inputs as the official Adult comparison. The workflow records input, source, protocol, and lockfile checksums before fitting and refuses to finalize a run if those files change before the final checks.

## Processing policy

- Preserve the official training/test boundary. Build raw predictor signatures from all 14 fields other than the outcome, including `education` and `fnlwgt`.
- Remove only repeated training records with identical raw predictors **and** identical outcomes. Remove 24 duplicates and retain 32,537 training records. Keep the two rows with conflicting labels for one raw signature; conflicting outcomes alone do not establish invalid records.
- Exclude test rows whose raw predictor signature occurs anywhere in the original training file, without inspecting test outcomes. Exclude 26 rows and retain the same 16,255 test records used in version 1. Keep their duplicate multiplicities, including six additional raw-signature duplicate rows.
- Use five grouped cross-validation folds within training by default. Keep each raw predictor signature in one fold and approximately balance class counts. Learn imputation, category handling, scaling, and encoding from each fold's analysis rows; select settings by mean validation-fold balanced accuracy and refit on all eligible training records.
- Apply fixed `log1p` transformations to nonnegative `capitalgain` and `capitalloss` before training-derived imputation and scaling. Retain `educationnum` and exclude its redundant text counterpart. Exclude `fnlwgt` from both predictors and evaluation weights. All models receive the same treatment-coded input columns; ridge logistic regression adds training-only standardization for its penalty.
- Report signatures from the 12 retained model input fields separately. Matching profiles are not proof of duplicate people. Keep them in the primary evaluation and report matched-profile versus novel-profile sensitivity results without treating the subsets as comparable randomized groups.
- Record source checksums in `input_manifest.csv`, processing counts in `data_audit.csv`, and grouped fold assignments in the local run. Metrics describe the retained sample and are not survey-weighted population estimates.

The official test data were already inspected in version 1. Version 2 therefore uses a **reused benchmark test**, not a fresh independent confirmation. Within version 2, test labels do not select preprocessing, hyperparameters, model families, or thresholds. Prior inspection still limits interpretation. Raw signatures and model input profiles are not person identifiers and cannot establish entity independence.

The target describes whether recorded historical annual income exceeded $50,000. It is not adjusted to current dollars. The data do not support current individual eligibility, lending, employment, or benefit decisions. Recorded sex and race fields are historical categories; subgroup metrics are descriptive and do not establish fairness or causal effects.

The default `data/raw/` and `results/` directories are excluded from version control; fitted `.rds` model files are also excluded. Review any custom output directory separately. Distribute only explicitly reviewed aggregate outputs with source attribution.

After completing and inspecting a full run, use `Rscript --vanilla scripts/export_evidence.R RESULTS_DIRECTORY NEW_EVIDENCE_DIRECTORY` from the repository root. The exporter requires unchanged artifact hashes and byte sizes, complete version 2 full-run status, official UCI input checksums, and successful model diagnostics. It copies an allowlist of reports, aggregate tables, figures, and provenance files. Raw inputs, record-level and out-of-fold predictions, split/fold identifiers, model objects, and machine-specific session details remain local. The export includes its own checksum manifest. Version 1 evidence remains preserved separately.

## Attribution

Becker, B. and Kohavi, R. (1996). *Adult*. UCI Machine Learning Repository. [doi:10.24432/C5XW20](https://doi.org/10.24432/C5XW20).

License: [Creative Commons Attribution 4.0 International](https://creativecommons.org/licenses/by/4.0/). See the dataset's current UCI page for source metadata and attribution requirements. No code license is implied by this data license.
