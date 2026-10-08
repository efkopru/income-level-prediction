# Data source and handling

This project uses the official training and test files from the [UCI Adult dataset](https://archive.ics.uci.edu/dataset/2/adult).

| Input | Official URL | Original record count |
| --- | --- | ---: |
| `adult.data` | <https://archive.ics.uci.edu/ml/machine-learning-databases/adult/adult.data> | 32,561 |
| `adult.test` | <https://archive.ics.uci.edu/ml/machine-learning-databases/adult/adult.test> | 16,281 |

The test file includes an initial comment line and labels with trailing periods. The parser normalizes these formats and treats `?` as a missing-value marker.

Run `Rscript IncomeLevelPrediction.R --download --output results/full` from the repository root to fetch the two data files and UCI's `adult.names` metadata into `data/raw`. Downloads and existing inputs supplied with `--download` must match the recorded UCI MD5 checksums. Alternatively, place the two data files in a local directory and supply `--data-dir PATH` without `--download`. No dataset download occurs merely by loading the project functions.

Without `--download`, compatible custom inputs can run even if their checksums differ from the UCI reference files. The generated input manifest, report, and charts identify that difference. Do not present results from changed inputs as the official Adult comparison. The workflow records input and source checksums before fitting and refuses to finalize a run if those files change before the final checks.

## Processing policy

- Preserve the official training/test boundary.
- Identify duplicate signatures using all 14 raw predictor fields. Exclude every training row for signatures with conflicting training labels, then keep the first row for each remaining training signature. Remove test rows whose predictor signature appears anywhere in the original training file. Test labels do not determine which records are retained. Retain the remaining within-test duplicate multiplicities and report counts. These signatures are not identity keys or proof of independent individuals.
- Use a stratified split of the retained training data for parameter selection. Learn imputation, category handling, scaling, and feature encoding from the corresponding training partition only.
- Retain the numeric education field and exclude its redundant text counterpart.
- Exclude `fnlwgt` from both predictors and evaluation weights. Metrics describe this sample and are not survey-weighted population estimates.
- Record input checksums and source information in each run's `input_manifest.csv`; record input and exclusion counts in `data_audit.csv`.

The target describes whether recorded historical annual income exceeded $50,000. It is not adjusted to current dollars. The data do not support current individual eligibility, lending, employment, or benefit decisions. Recorded sex and race fields are historical categories; subgroup metrics are descriptive and do not establish fairness or causal effects.

The default `data/raw/` and `results/` directories are excluded from version control; fitted `.rds` model files are also excluded. Review any custom output directory separately. Distribute only explicitly reviewed aggregate outputs with source attribution.

After completing and inspecting a full run, use `Rscript scripts/export_evidence.R RESULTS_DIRECTORY NEW_EVIDENCE_DIRECTORY` from the repository root. The exporter requires unchanged artifact hashes, full-run mode, and the recorded official UCI input checksums. It copies only an allowlist of reports, aggregate tables, figures, and provenance files. Raw inputs, record-level predictions, split identifiers, model objects, and machine-specific session details remain local. The export includes its own checksum manifest.

## Attribution

Becker, B. and Kohavi, R. (1996). *Adult*. UCI Machine Learning Repository. [doi:10.24432/C5XW20](https://doi.org/10.24432/C5XW20).

License: [Creative Commons Attribution 4.0 International](https://creativecommons.org/licenses/by/4.0/). See the dataset's current UCI page for source metadata and attribution requirements. No code license is implied by this data license.
