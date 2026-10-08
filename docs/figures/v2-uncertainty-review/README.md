# Supplemental v2 uncertainty figures

These figures re-render already published aggregate evidence. No models were refitted, no bootstrap draws were made, and no intervals were recomputed.
The original v2 full-run evidence, plots, reports, and manifests remain unchanged.

- `model_comparison.png` and `.pdf`: all five models across the original four comparison metrics, with small hollow markers and foreground interval bars on a common 0-1 metric scale.
- `paired_differences.png` and `.pdf`: all six trained-model pairs across all five declared bootstrap metrics, with a shared symmetric scale centered at zero.
- PNGs are 2400 x 1500 pixels. PDFs are 12 x 7.5 inches.

## Interpretation

Paired differences are `model_a - model_b`; each row names `model_a` first. Positive differences favor the first model for every displayed metric.
Differences retain raw metric units: 0.01 is one percentage point for accuracy, balanced accuracy, and recall; it is 0.01 score units for ROC AUC and average precision.
Intervals are conditional 95% percentile intervals from 1,000 shared bootstrap draws of 16,249 raw-predictor clusters in the 16,255-record reused benchmark test sample.
They condition on the fitted models, exclude training variability, and are not adjusted for multiple comparisons. A zero-crossing interval does not establish equivalence. These are historical benchmark results, not population estimates or a new confirmatory test.

## Reproduction and provenance

From the repository root, use a new or empty output directory:

```text
Rscript --vanilla scripts/render_evidence_figures.R docs/evidence/v2-full-2026-10-08 docs/figures/NEW-EMPTY-DIRECTORY
```

The renderer verifies all four source aggregate hashes and byte sizes against the source public manifest before reading aggregate tables. It refuses nonempty destinations and paths inside the published evidence source, resolving new paths through their existing parent directories. It does not access raw inputs or saved models.
`provenance.csv` records the exact aggregate inputs, published manifest, rendering script, and current plotting-code hashes. `render_context.txt` records the observed R/ggplot2 versions and locale. `figure_manifest.csv` checks the supplemental outputs.
The original evidence's source manifest continues to describe its original full run; this folder's plotting provenance is separate.
