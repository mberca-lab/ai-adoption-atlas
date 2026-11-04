# Source, population and frequency follow-up

Post-hoc additions to the original public-data study; profiles and the existing trend estimates
are unchanged. Data: Stack Overflow Developer Survey 2023-2026, Stack Exchange Inc., ODbL 1.0.

## 1. Source audit and missingness

All four local archive hashes and shapes match the publisher's Git LFS pointers at commit
`9dd5c163b7ec09ce5503f711c37a99dbd80ff3c7`. Full checks are in `source_audit.json` and
`source_files.csv`. The verified 2025 archive has **49,191** rows; the
[official methodology](https://survey.stackoverflow.co/2025/methodology/) reports **49,009**.
The **182-record difference remains unexplained**. No arbitrary records were removed to force agreement.
The current 2026 archive README no longer contains its historical invalid close date, but a
replacement close date remains unverified. No close date is used to interpret the series.

| Year | Eligible adult professionals | AI status answered | AI status missing | Current AI users | Trust answered among users | Trust missing among users |
|---|---:|---:|---:|---:|---:|---:|
| 2023 | 66,684 | 66,684 | 0 | 29,381 | 29,283 | 98 |
| 2024 | 48,470 | 46,296 | 2,174 | 29,284 | 29,131 | 153 |
| 2025 | 33,792 | 25,974 | 7,818 | 20,991 | 20,732 | 259 |
| 2026 | 20,205 | 13,243 | 6,962 | 11,400 | Not comparable | Not comparable |

Eligibility is after declared QC exclusions but before AI-status missingness. The current-user
restriction is a change of target population, not an item dropout. Trust-item bounds cover
missing outcomes among identified users; they exclude people with missing AI status.
The original worst-case adoption-change bounds for 2024-2025, **[-2.8, 24.9] pp**, include zero.
They are assumption bounds, not confidence intervals. Existing age/employment completion
weighting cannot recover unobserved AI attitudes. Samples are repeated cross-sections, not a panel.

## 2. Frequency and accuracy trust in 2025

Population: adult professional current AI users in the original trend base. **20,732** answer both
trust and frequency; **259** identified users lack at least one of these outcomes/items.
No outcome or frequency imputation. Missing covariates are explicit categories; implausible coding
experience is marked Missing locally, without changing the historical analysis.

Grouped binomial logistic regression adjusts for coding-experience band, role, region and
organisation size, with main effects only. Marginal probabilities average over this analytic
sample's observed covariate mix, held identical across frequency scenarios.

| AI use frequency | n | Raw trust | Adjusted trust | Model-based 95% interval |
|---|---:|---:|---:|---:|
| Monthly or infrequent | 3,263 | 15.3% | 16.2% | [15.0, 17.6]% |
| Weekly | 4,472 | 27.4% | 28.4% | [27.1, 29.7]% |
| Daily | 12,997 | 48.0% | 47.2% | [46.4, 48.1]% |

Daily minus monthly/infrequent: **31.0 pp**, **[29.4, 32.5] pp** model-based 95% interval.
The raw gap is 32.7 pp; adjustment for these measured covariates leaves a large association.
This does not show that use increases trust: trust may influence use, and other confounding remains.
It cannot explain the cross-year decline: the same frequency measurement is not available in
earlier waves. The comparison was selected after observing the raw pattern, not preregistered.

Complete-covariate sensitivity: **17,804** respondents; difference **31.2 pp**, interval
**[29.5, 32.8] pp**. This subset is standardised over its own mix, so it is not the identical target.
Missing predictor counts (which can overlap): experience 177, role 0, region 8, organisation size
2,780. Unknown organisation size is a substantive response, distinct from Missing.

Both fits converge with full rank. Marginal overlap checks cover 90 frequency-by-covariate cells:
none empty, minimum 1, three below 10. This checks one covariate at a time, **not joint positivity**;
some adjusted predictions may depend on main-effects extrapolation across sparse joint patterns.
Intervals use 4,000 coefficient-normal draws from the fitted covariance, seed 20261104.
They condition on independent responses, the specified model and the observed sample; they do not
include survey-selection bias, unknown confounding or model-selection uncertainty.

## Reproduce and verify

Run `Rscript scripts\05_trust_followup.R` after the original trust export.
`--self-test` checks synthetic confounding removal and rejects unmapped frequency answers.
`--verify-only` checks hashes, diagnostics, denominators, CSV/JSON agreement and the public export.
Only aggregate results are written. Versions are in `SESSION_INFO.txt`.
