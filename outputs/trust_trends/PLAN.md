# Trust trends ("say vs do") — pre-specified analysis plan

Stream: adoption, favourability and trust 2023–2026 (DATA_NOTES §6 questions 1–6).
Written **before** any outcome estimates were computed in this stream (2026-11-04). The only outcome
figures seen beforehand were the unweighted toplines already printed in `docs/DATA_NOTES.md` and
`docs/tables/headline_check_unweighted.csv`. Covariate missingness and category counts were inspected
to define levels; no outcome was inspected. Deviations from this plan are listed at the end of
`FINDINGS.md` ("Deviations from plan").

Data: Stack Overflow Developer Survey 2023–2026 (Stack Exchange Inc., ODbL 1.0). Self-selected,
unweighted, cross-sectional (different people each year). All results are **associations in a
self-selected sample of stated sentiment**, not population estimates, not behaviour, not causal.

## 1. Populations

| Code | Definition (harmonised vars) | Used for |
|---|---|---|
| **P1** | `in_default_base` & `is_professional_dev` & `age_band` ∉ {Under 18, Prefer not to say} | adoption (Q1) |
| **P2** | P1 & `ai_user == TRUE` (current AI users) | favourability, trust, complexity (Q2–Q5) |
| **P3** | P1 & `ai_use_status` ∈ {Using, Plan to use} | job threat (Q6) — the only group asked in both 2024 and 2025 |

`in_default_base` = not QC-excluded (exact duplicate / <10 items / 2023 screened-out) and answered `AISelect`.

## 2. Comparability and series (from `CODEBOOK_AI.md`)

| Concept | Series A (trend) | Series B (separate, after break) | Not compared |
|---|---|---|---|
| Adoption (`ai_use_status`) | 2023, 2024 (C), 2025 (CC: "Yes" split by frequency, later position) | 2026 (NC: at-work multi-select, no "plan", P1 defined via `CodeMain`) | 2026 vs A |
| Favourability (`ai_sent_favorable`) | 2023–2025 among P2 (CC) | 2026 (relabelled 6-pt, "tools **or agents** … at **work**") | — |
| Trust (`ai_trust_5`) | 2023 (`AIBen`, names swapped – mapped by meaning) – 2025 among P2 | none: 2026 `AITrust` is a conditional, non-ordinal item → described only | 2026 |
| Complex tasks (`ai_complex_5`) | 2024–2025 among P2 (CC) | 2026 ("or agents") | — |
| Job threat (`ai_threat`) | 2024 vs 2025 among P3 (CC) | — | 2023, 2026 (not asked) |

2026 is always drawn with a visible break and never joined by a line to Series A. Any "2023→2026"
statement is labelled cross-series and descriptive.

## 3. Estimands (all unweighted, respondent-level; percentage points unless stated)

* **E1 Adoption**: Pr(Using) and Pr(Plan to use) in P1 by year. Contrasts 2023→2024, 2024→2025.
  "Did plan convert into use?" is a cohort-level (not panel) check: is Use(t+1) ≥ Use(t) + Plan(t)
  (the "intent ceiling")? Individual conversion cannot be estimated (no repeated respondents).
* **E2 Favourability**: Pr(Very favourable or Favourable) in P2; primary keeps "Unsure" in the
  denominator (as harmonised); sensitivity excludes "Unsure". Contrasts 2023→24, 24→25.
* **E3 Trust / distrust**: Pr(`ai_trust_5` ≥ 4) ("trust") and Pr(`ai_trust_5` ≤ 2) ("distrust")
  in P2, 2023–2025; net trust = trust − distrust.
* **E4 Paradox**: in P1 adoption rises while in P2 trust falls / distrust rises, 2023→2025.
  "Holds in subgroup g" ⇔ Δadoption > 0 **and** Δtrust < 0 with both 95% CIs excluding 0 and
  BH-adjusted p < 0.05. Subgroups: experience band, role family, region (levels with ≥ 100 users per year).
* **E5 Experience gradient**: experience band from `years_code` (0–4, 5–9, 10–19, 20+; top-coded 50).
  Gradient = adjusted Pr(outcome | 20+) − Pr(outcome | 0–4) within year (trust, distrust,
  favourability). **Widening** = gradient(2025) − gradient(2023); test via LR test of the
  year × experience interaction.
* **E6 Complexity (Q5)**: Pr(`ai_complex_5` ≥ 4) in P2 among those giving a rating (excludes "don't use
  for complex"), 2024–2025 (A), 2026 (B); within-year adjusted OR of favourability per +1 complexity point.
* **E7 Job threat (Q6)**: Pr(`ai_threat` = Yes) in P3, 2024 vs 2025, overall and by role family and region.

## 4. Estimation

1. **Raw proportions** with **Wilson 95% CIs**; differences with **Newcombe** (hybrid Wilson) CIs.
2. **Adjusted year effects**: logistic regression `y ~ year + exp_band + role_family + region + org_size`
   (missing covariate values kept as an explicit "Missing" level so no rows are dropped). Year ORs with
   Wald CIs. **Marginal (direct) standardisation / g-computation**: predicted Pr(y) for each year
   averaged over the pooled 2023–2025 covariate distribution of the relevant population (P1 or P2);
   2026 standardised to the same target (own model) for reference only. CIs by simulation from the
   coefficient sampling distribution (2,000 draws; model-based).
3. **Ordinal logit** (`ordinal::clm`) for 5-point trust and 5-point sentiment (Unsure excluded) with the
   same covariates: cumulative OR for year.
4. **Multilevel**: random country intercept (`lme4::glmer`; countries with < 30 respondents pooled to
   "Other <region>") as robustness check; considered justified if the country ICC (latent scale) ≥ 0.01.
   Compare year ORs to the fixed-effects model.
5. **Effect sizes**: pp differences, ORs, Cohen's h for headline year contrasts.

## 5. Multiple comparisons

* **Primary family (Holm)**: 8 year contrasts — adoption, favourability, trust, distrust × (2023→24, 2024→25).
* **Subgroup families (Benjamini–Hochberg, q = 0.05)**: each subgroup table (paradox subgroups,
  favourability-decline subgroups, gradient widening, threat by role/region) is its own BH family.

## 6. Sensitivity analyses (pre-specified)

* **S1 Quality exclusions**: (a) re-include QC-excluded rows that answered `AISelect`; (b) strict base
  additionally dropping `qc_years_implausible`, `qc_ai_inconsistent`, `qc_straightline`.
* **S2 Dropout / missingness**: (a) **Manski worst/best-case bounds** for adoption treating P1-eligible
  respondents (professional, adult, not QC-excluded) who did not answer `AISelect` as all non-users / all
  users; same for favourability/trust among users who skipped the item; (b) **inverse-probability-of-
  completion weighting (IPW)**: logistic model for answering `AISelect` using only early-asked items
  (age band, experience band, employment, education; others only if ≥ 90% observed among
  non-completers), weights trimmed at 1st/99th percentile. IPW corrects only dropout explained by
  observed early covariates (MAR); it cannot correct dropout related to unobserved attitudes (MNAR) —
  the bounds show that range.
* **S3 2023 column mislabelling**: verify from the raw 2023 file (aggregated counts only) that `AIBen`
  holds the 5 trust levels and `AIAcc` holds benefits; show what naive name-based mapping would yield;
  2023 trust on the routed base (users + planners) vs users only.
* **S4 Routing**: 2025 favourability/trust among users vs everyone asked.
* **S5 Favourability denominator**: exclude "Unsure".
* **S6 Model**: fixed-effects logit vs multilevel; binary vs ordinal.

## 7. Robustness verdict rule

**Robust**: sign holds and 95% CI excludes 0 in raw, standardised, multilevel, S1a/S1b and IPW versions,
and the Manski bounds (noted, often wide) do not trivially contradict it. **Fragile**: any of those flips
the sign or loses significance, or the result rests on a CC/NC comparison. **[VERIFY]** for items that
depend on unconfirmed documentation.

## 8. Outputs

Aggregated CSVs in `outputs/trust_trends/tables/`; 6–8 PNG figures with alt text in
`outputs/trust_trends/figures/figures_manifest.csv`; `FINDINGS.md`; `site_data/trust_trends.json`.
No row-level data are written. Scripts: `scripts/02_trust_trends.R` (analysis) and
`scripts/02_trust_trends_verify.R` (checks every number in FINDINGS.md against the tables).
