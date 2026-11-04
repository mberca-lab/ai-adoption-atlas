# Full-base primary model stability follow-up

This post-hoc check increases the original deterministic 12% modelling sample to **all eligible
outcome rows** for the two primary context-only predictions. It leaves all original model tables,
drivers, exploratory feature sets and website charts unchanged.
Data: Stack Overflow Developer Survey 2023-2025, Stack Exchange Inc., ODbL 1.0.

## Design and separation

Population: default-base current AI users with observed outcome, all eligible ages/developer
statuses, **not** the professional-adult trend population. Each outcome has four complete runs:
one unresampled reference (seed 20261104), and three within-block bootstrap refits (seeds
20261105-20261107). Every run retunes, refits and recalibrates.

Fit on 2023; split original 2024 respondent rows equally into tuning and calibration before
any within-block resampling; select on tuning log-loss; refit on 2023 plus tuning; calibrate
on the untouched calibration block; test on the fixed 2025 observations. Bootstrapped calibration
rows are never used to fit or tune base models. No respondent can cross these blocks.

The comparison is calibrated logistic regression versus an equal-weight logistic/XGBoost/LightGBM
ensemble, also Platt-calibrated. Context-only features, training-derived preprocessing and
vocabularies; test-only categories do not enter fitted vocabularies. Five logistic C values,
two seeded configurations per booster, maximum 350 rounds, 50-round early stopping; two threads.
This follows the original bounded recipe, not identical candidate configurations or an exhaustive
search. Numerical covariates use the original clipping/spline/missingness recipe.

| Outcome | 2023 fitting n | 2024 tuning n | 2024 calibration n | Final refit n | 2025 test n |
|---|---:|---:|---:|---:|---:|
| Favourability | 38,945 | 18,680 | 18,680 | 57,625 | 26,230 |
| Accuracy trust | 38,888 | 18,618 | 18,619 | 57,506 | 26,126 |

Bootstrap row counts match the reference, with fewer distinct fitted respondents.
`summary.json` records per-run unique counts, zero cross-block overlaps, tuning scores, versions
and source/data hashes; no respondent-level predictions or identifiers are published.

## Results

All differences are ensemble minus calibrated logistic. Positive AUC and negative relative
log-loss favour the ensemble.

| Outcome | Reference delta AUC | Conditional 95% interval | AUC difference range, four runs | Relative log-loss difference range |
|---|---:|---|---|---|
| Favourability | +0.00120 | [-0.00093, +0.00293] | [-0.00082, +0.00201] | [-0.083%, +0.052%] |
| Accuracy trust | +0.00265 | [+0.00096, +0.00415] | [+0.00154, +0.00293] | [-0.191%, -0.063%] |

The full-base reference trust interval excludes zero: **a small statistically detectable ensemble
gain**, unlike the inconclusive original subset comparison. Do not retain an unqualified claim
that there is no difference. Yet neither the AUC gains nor relative log-loss improvements reach
the original analyst-set practical benchmarks of **0.01 AUC** or **1% relative log-loss** in any
of these runs. This supports a restrained practical conclusion, not statistical equivalence.

## What this does not establish

Per-run intervals use 200 paired bootstraps of the same fixed test predictions and condition on
the fitted pipeline. Three repeated bootstrap refits vary fitting, tuning, partition and
calibration, but are a small descriptive stability check. Their min/max ranges are **not confidence
intervals**. These checks use the same source waves, not an independent external validation.
No population, fairness, causal or production-readiness claim follows; the follow-up was not
preregistered. A larger tuning budget or another model family may behave differently.

Run `python scripts\05_model_stability.py` after the original model export.
`--verify-only` checks saved run structure, hash and nested public export.
`python -B -m unittest discover -s tests -p test_followup.py` tests deterministic separation,
bootstrap overlap guards, unseen categories and paired comparisons on synthetic inputs.
