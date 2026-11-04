# Modelling recovery: exploratory, not confirmatory

## Status and intended use

This stream describes predictive associations in the public Stack Overflow
Developer Survey; it does not support individual decisions, causal intervention,
or population estimates. The deterministic **12% subsample** contains **23,969**
of **199,743** default-base rows. Sampling occurs before outcome filtering, without
replacement, seed **20261104**. This is a bounded exploratory analysis, not a
full-data result or preregistered study. All default-base ages are retained;
denominators need not match other chapters' additional age exclusions.

The interrupted full-data job's partial logs are not results. Its metrics were
never exported and are not combined with this run. The old 12% export has been
replaced by the corrected complete run.

**Verified 2026-11-04:** final modelling run completed successfully in **133.0
seconds (2.2 minutes)**, at most two CPU threads. All **14 focused tests pass**;
all seven figures were regenerated from the final tables. Five substantive
aggregate files matched byte-for-byte across the two seeded executions. The
execution log contains LightGBM API deprecation warnings, but no convergence
warnings, runtime warnings or tracebacks. The obsolete interrupted full-run log
was removed to avoid contradictory provenance.

## Denominators

Outcome-specific missing labels are excluded; nothing is imputed into outcomes.
Favourability and trust concern **current AI users**, not all respondents.
Favourability counts unsure/non-favourable answers as negative. Trust in 2023–25
means somewhat/highly trusts accuracy. Trust 2026 uses a different, conditional
scale: the two broad-trust categories are positive; not-sure/non-use is excluded.

| Outcome | 2023 | 2024 | 2025 | 2026 |
|---|---:|---:|---:|---:|
| Favourability among users | 4,704 | 4,451 | 3,253 | 1,671 |
| Accuracy trust among users | 4,694 | 4,436 | 3,243 | Not comparable |
| Conditional broad trust among users | — | — | — | 1,643 |
| AI-use label, default base | 10,582 | 7,236 | 4,125 | 2,026 |

Use-status prediction uses 2023–25 only. See `tables/sample_sizes.csv` for
prevalences. Every model within an experiment uses the same labelled test rows.
Primary 2025 favourability/trust test prevalences are 73.501% and 39.007%.

## Splits, tuning and calibration

- Primary temporal experiment: fit initially on 2023; split 2024 validation
  respondents deterministically, stratified by label, into tuning and calibration
  halves. Select configuration by tuning-half log-loss, refit on 2023 plus the
  tuning half, then calibrate on the **unused calibration half**.
- Final base-model fitting denominators are 6,929 (favourability), 6,912 (trust),
  and 14,200 (AI use). Calibration labels train the calibrators only and are
  deliberately excluded from those denominators.
- The 2026 favourability sensitivity experiment initially fits on 2023–24, uses
  2025 for tuning/calibration, and evaluates on 2026. It is a measurement-break
  stress test, **not** a comparable trend or ordinary forecast.
- Five-fold country-grouped CV evaluates held-out countries, pooling 2023–25
  with year as a predictor. The inner country holdout is split into tuning and
  calibration respondents. Outer test countries never enter fitting, tuning or
  calibration. The inner halves can share countries; inference concerns outer
  country generalisation, not independently held-out calibration countries.
  Trust26 is grouped CV within 2026 without year as a predictor.
- `tables/split_audit.csv` records each exact fit/tune/calibration/test denominator
  and checked outer overlaps. Grouped metrics' `n_train` is the **mean actual
  per-fold refit size**, not the nominal 80% of pooled rows.
- Logistic: five C values, L2 regularisation, cubic splines for experience and
  log compensation, train-fit one-hot encoding, numeric median imputation and
  missingness indicators. Numeric clipping is fixed, not test-derived.
- Random forest: two configurations, 100 trees, 60% row subsampling per tree.
  XGBoost and LightGBM: two seeded random configurations each, at most 350 rounds,
  early-stopping patience 50. Final refit uses the selected best iteration, with
  no arbitrary extra trees. These deliberately small budgets **do not establish
  the best possible performance of any algorithm**.
- Ensemble: fixed equal mean of logistic/XGBoost/LightGBM, followed by Platt
  calibration. Single-model logistic and LightGBM receive the same held-out
  calibration opportunity. Compare the ensemble with **`logit_recal`**, not raw
  logistic, to separate calibration gains from algorithmic complexity.
- Native categorical vocabularies and all preprocessing are fitted on training
  data; previously unseen test categories cannot alter the fitted vocabulary.
  Country is a grouping field; region, not country, is a predictor.

## Simple versus complex: primary context-only results

Test year 2025; values are rounded from `tables/model_metrics.csv`.

| Outcome | Model | AUC | Log-loss |
|---|---|---:|---:|
| Favourability | Base-rate-only | 0.50000 | 0.60036 |
| | Logistic | 0.56705 | 0.59260 |
| | Random forest | 0.56199 | 0.59622 |
| | XGBoost | 0.56477 | 0.59636 |
| | LightGBM | 0.56515 | 0.59633 |
| | Logistic, calibrated | 0.56705 | 0.57540 |
| | Equal-weight ensemble, calibrated | 0.56916 | 0.57603 |
| Trust | Base-rate-only | 0.50000 | 0.68153 |
| | Logistic | 0.59336 | 0.66344 |
| | Random forest | 0.59196 | 0.66414 |
| | XGBoost | 0.59060 | 0.66533 |
| | LightGBM | 0.59344 | 0.66367 |
| | Logistic, calibrated | 0.59336 | 0.65835 |
| | Equal-weight ensemble, calibrated | 0.59539 | 0.65787 |

Context-only discrimination is modest. The ensemble's primary AUC increments
over equally calibrated logistic are about **0.0021** and **0.0020**, below the
analyst-selected 0.01 point-estimate threshold. Favourability ensemble log-loss is
slightly worse than calibrated logistic; trust log-loss is only slightly lower.
There is **no compelling practical complexity benefit in these primary
comparisons**. This is not a proof of equivalence or a universal ranking.
Full paired intervals and other validation schemes remain in the difference
table and JSON rather than being replaced by a single winner.

| Ensemble minus equally calibrated logistic | AUC difference [conditional 95% interval] | Relative log-loss difference, % [interval] |
|---|---:|---:|
| Favourability | +0.00211 [−0.00504, +0.01158] | +0.109 [−0.103, +0.301] |
| Trust | +0.00203 [−0.00398, +0.00891] | −0.072 [−0.355, +0.177] |

Calibration matters: raw AI-use logistic has log-loss 0.74008 versus 0.70565 for
the base-rate baseline, despite AUC 0.60496. Held-out calibration reduces logistic
log-loss to 0.59480; the calibrated ensemble is 0.59655. AUC alone would miss this
large temporal probability mismatch.

Feature-set sensitivity separates D (demographics/context), B (D plus current AI
tasks), and E (B plus sibling attitudes). B and E can improve discrimination but
use **contemporaneous/co-determined answers**. They are explanatory sensitivity
analyses, not deployable early predictors, and do not establish causal drivers.

## What uncertainty does and does not mean

- Primary metric intervals use **200** paired bootstrap resamples; secondary
  experiments use **100**. They resample fixed predictions: **zero model refits**.
  Temporal intervals resample respondents; grouped-CV intervals resample country
  clusters of pooled out-of-fold predictions. They condition on this selected
  sample, fitted models, splits and tuning. They do not capture training/tuning
  uncertainty or survey-selection bias, and pooled-fold dependence remains.
- Difference intervals are paired using the same resampled rows/clusters.
  AUC and log-loss thresholds (0.01 absolute AUC or 1% relative loss reduction)
  are **analyst-selected in the same session**, with no registered protocol.
  The rule requires a point-estimate threshold and an interval excluding zero,
  **not** the entire interval exceeding the practical threshold.
- Many outcomes, algorithms, schemes and feature sets are explored, without
  multiplicity correction. Verdicts are descriptive exploratory flags, not
  hypothesis-test conclusions. Choosing the highest observed AUC and then quoting
  its ordinary interval does not account for winner selection. Neither
  non-significance nor a small point estimate establishes equivalence.
- Difference-table `bootstrap_fraction_*_improved` columns are bootstrap
  improvement fractions, **not p-values or posterior probabilities**; they are
  not exported as tests. Opposing interval-supported metric directions are
  labelled as mixed trade-offs rather than an overall win.
- Driver stability uses only **8** bootstrap training refits at fixed chosen
  tuning. The 2.5/97.5 percentiles and rank ranges are **descriptive ranges, not
  95% confidence intervals**; top-three shares have 1/8 resolution. Logistic
  transformed-basis linear contributions and TreeSHAP have different background
  conventions, so absolute magnitudes are not causal or interchangeable.
- Per-year driver fits reuse tuning selected in the temporal experiment.
  Their 80/20 holdout AUCs and rank patterns are descriptive, not independently
  nested performance estimates. Correlated predictors can split importance.
- PDPs average hypothetical replacements over test covariates, can create
  unrealistic age/experience combinations, and have no causal interpretation.
- Subgroup intervals use 100 respondent bootstraps, suppress groups below n=100,
  and do not correct for multiplicity or small positive/negative class counts.
  False-positive/negative counts are exported at a training-prevalence threshold;
  that threshold is descriptive, not cost-optimised. Age, region, experience and
  role audits are **not a fairness certification**; gender/race, intersectional
  disparities and deployment harms are not assessed.
- Repeated cross-sections cannot track the same developer over time. Possible
  cross-year repeat respondents cannot be linked; independence is an assumption.
  Missing-label selection, non-response, geographic composition and 2026 item
  changes limit generalisation. No survey weights are applied.

## Review findings and corrected issues

| Area | Risk / severity | Finding and disposition |
|---|---|---|
| Training, calibration | High | Old code calibrated on the same holdout used for selection and transferred that calibration to a full refit. **No test labels were used**, but calibration evidence was weak. Corrected with a separate calibration half excluded from final base fitting; a focused test checks actual index exclusion and calibration inputs. |
| Category handling | High | Full-sample categorical levels were visible to native learners. Training-only observed vocabularies are now enforced; unseen categories become missing for native models. |
| Model comparison | High | Calibrated ensemble vs raw logistic conflates calibration and complexity. Equally calibrated contrasts remain explicit; frontend must prefer them for ensemble conclusions. |
| Effect claims | Medium | Unsupported preregistration and “statistically better” wording removed; thresholds and flags are explicitly exploratory. |
| Stability and figures | Medium | Five-refit percentile whiskers and hardcoded alt-text conclusions overstated evidence. Eight-refit descriptive ranges are now explicitly labelled; alt text describes the plots without invented data conclusions. |
| Coefficients | Medium | With full one-hot coding and L2, exp(coefficient) is not a reference-category odds ratio. The export names the quantity as an exponentiated penalised coefficient. |
| Reproducibility | High | Full-run logs and old sample exports had conflicting provenance; missing verifier. Replaced with one complete run, input/script SHA256, exact package versions, explicit budgets, figure/source hashes and focused checks. |

Review entry points:
[splits/calibration](../../scripts/03_modelling.py:L298-L359),
[temporal and grouped evaluation](../../scripts/03_modelling.py:L403-L453),
[exploratory flags](../../scripts/03_modelling.py:L473-L485),
[driver explanations](../../scripts/03_modelling.py:L493-L635),
[subgroup audit](../../scripts/03_modelling.py:L637-L691),
[export metadata](../../scripts/03_modelling.py:L693-L768), and
[figure labels](../../scripts/03_modelling_figures.R:L21-L208).

These are safe-to-publish **exploratory aggregate artifacts**, not a production
model approval. Missing deployment decision/cost context is intentional for this
descriptive project; no operational threshold or individual scoring is endorsed.

## Reproduce and integrate

From the repository root in PowerShell:

```powershell
$env:FAST='1'; $env:SAMPLE_FRACTION='0.12'; $env:NJOBS='2'
python scripts\03_modelling.py
& 'C:\Program Files\R\R-4.6.2\bin\Rscript.exe' scripts\03_modelling_figures.R
python scripts\03_modelling_verify.py
```

`SESSION_INFO.txt` records the execution environment; `run_metadata.json` mirrors
JSON `meta`. `run_log.txt` is this completed run's progress; `execution_log.txt`
also retains warnings. `figures/source_table_hashes.csv` and
`figures/figure_hashes.csv` let verification detect stale tables or PNGs.
The verifier checks pure metrics, deterministic paired bootstrapping,
train/calibration exclusion, unknown categories, denominators, tuning budgets,
paired differences, JSON/table equality, subgroup suppression and figure hashes.
It does not rerun or claim to independently reproduce all fitted models.
`repeatability_checks.json` additionally compares exact SHA256 hashes across
two complete seeded executions for metrics, tuning, permutation importance,
partial dependence and sample sizes.

The renamed `tables/logit_penalized_coefficients.csv` replaces the misleading
legacy odds-ratio filename. It contains no inferential standard errors or CIs.

The frontend contract remains `model_metrics`, `diff_vs_logit`,
`calibration_bins`, `shap_drivers`, `driver_ranks_by_year`,
`partial_dependence`, and `subgroup_audit`.
Calibration bins and bootstrap SHAP drivers are specifically **D,
`temporal_2324to25`**, and should be hidden or labelled unavailable under other
feature-set/scheme selections. Per-year ranks are a separate descriptive series.
Display `meta.analysis_note` visibly; retain `meta.analysis_mode`,
sampling/budget/uncertainty metadata, and the equally calibrated ensemble
comparison. Do not silently substitute synthetic fixtures.

Only aggregate CSV/JSON, figures, logs and documentation are persisted here.
Respondent-level source/clean files remain gitignored. No model objects,
row-level predictions, commits or pushes are produced.
