# Trust trends — "say vs do" findings (AI Adoption Atlas)

Stream: adoption, favourability and trust among professional developers, Stack Overflow Developer Survey
2023–2026. Pre-specified plan: [`PLAN.md`](PLAN.md). Code: `scripts/02_trust_trends_lib.R`,
`scripts/02_trust_trends.R` (tables), `scripts/02_trust_trends_figs.R` (figures + `site_data/trust_trends.json`),
`scripts/02_trust_trends_verify.R` (checks every number below against `tables/*.csv`).

**Read every number with these caveats.** The sample is **unweighted and self-selected** (Stack Overflow-engaged
developers), so these are sample shares, not population estimates. All results are **associations, not causal effects**.
Items measure **stated sentiment, not behaviour**. Confidence intervals (95%; Wilson for proportions, Newcombe for
differences, simulation for standardised estimates) reflect sampling noise only, not self-selection or dropout.
**2026 is a separate series (B)**: question wording, the user definition and the professional-developer definition all
changed, so 2026 is never joined to 2023–2025 by a trend line or tested as a year-on-year change.

Populations:
- **P1**: professional developers aged 18+ in the default analysis base. n = 66,684 / 46,296 / 25,974 / 13,243 for 2023–2026.
- **P2**: current AI users within P1. Favourability, trust and complexity are measured here.
- **P3**: users + planners within P1. Job threat is measured here, the only population asked in both 2024 and 2025.

---

## Finding 1 — Adoption nearly doubled 2023→2025, and it is not just a change in who responds (DATA_NOTES Q1)

- **Use rose**: 44.1% [43.7, 44.4] (2023) → 63.3% [62.8, 63.7] (2024) → 80.8% [80.3, 81.3] (2025). 2023→2025 is
  +36.8 pp [36.1, 37.4]; Cohen's h = 0.783 (large); OR = 6.286 [6.065, 6.515] (`t01`, `t07`, `t08`).
- **Composition does not explain it.** Holding role, experience, region and org size at the pooled mix
  (g-computation), use is 43.9% → 62.5% → 82.0%, a standardised +19.5 pp [18.9, 20.1] for 2024→2025 (`t06`, `t07`).
  The random-country-intercept model gives the same 2023→2025 OR (6.275), and country ICC is only 0.010 (`t08`, `t09`).
- **Planning shares fell; individual conversion is not observed.** "Plan to use" fell 26.0% → 13.4% → 4.6%. In 2024, use was 6.8 pp *below* the 2023
  use + plan ceiling (70.1%). In 2025 it was 4.1 pp *above* the 2024 ceiling (76.7%), so by 2025 adoption had outrun
  stated intent (`t03`).
- **2026 (series B)**: 86.1% [85.5, 86.7] use AI at work. This is not comparable to 2023–2025.

**Robustness**
- **2023→2024: robust.** The rise holds across all checks, and the worst-case dropout (Manski) bounds are +16.3 to +20.8 pp (`t22`).
- **2024→2025: direction robust to modelling, QC and IPW, but FRAGILE to dropout.**
  - Only 76.9% of eligible 2025 respondents reached the AI question (2024: 95.5%).
  - The Manski bounds for the change are [-2.8, 24.9] pp and include zero.
  - Completion-propensity weighting (IPW) gives +17.6 pp [17.0, 18.3]. It can only correct for observed age and
    employment, not for AI-related reasons for quitting (`t17`, `t18`, `t21`).
- 2026 use bounds span 56.4–90.9% (completion 65.5%).

## Finding 2 — Favourability among users fell in every subgroup (Q2)

- **Overall**: favourable or very favourable fell 84.9% [84.5, 85.3] → 76.8% [76.3, 77.3] → 73.1% [72.5, 73.7].
  - 2023→2025: -11.7 pp [-12.5, -11.0]; h = -0.291 (small-to-medium); OR = 0.49 [0.468, 0.513].
  - The ordinal model on the full 5-point scale gives a cumulative OR of 0.572 [0.552, 0.592] (`t01`, `t07`, `t08`).
- **The decline is slowing**: -8.1 pp (2023→24), then -3.7 pp (2024→25).
- **Standardised**: 84.8% → 76.7% → 73.4% (-11.4 pp [-12.2, -10.6]). Composition explains almost none of it.
- **Subgroups**: favourability fell significantly (BH) in **23 of 23** age, experience, role and region subgroups (`t11c`).
  - Range: -2.7 pp [-5.0, -0.5] (South Asia) to -17.9 pp [-24.7, -11.0] (Student).
  - Steepest in North America (-15.6 pp [-17.2, -14.0]) and among 18–24s (-14.4 pp).
- **2026 (series B)**: 62.5% [61.6, 63.4] (standardised 60.9%). The options were relabelled, so the drop from 73.1% is
  consistent in direction but **is not** a measured change.

**Robustness: ROBUST.**
- The change agrees in sign and significance across raw, standardised, QC-inclusive, strict-QC, IPW, fixed-effects,
  multilevel and ordinal estimates (`t22`).
- Excluding "Unsure" gives 86.4% → 73.8% (`t01`).
- Item non-response bounds are narrow: 2025 72.5–73.4% (`t17b`).

## Finding 3 — The trust paradox is real in the data: use goes up while trust goes down (Q3)

- **Trust in AI accuracy among users fell**: 46.2% [45.6, 46.8] → 41.4% → 38.4% [37.7, 39.1].
  - 2023→2025: -7.8 pp [-8.7, -6.9]; h = -0.158; OR = 0.75 [0.722, 0.779]; standardised -6.8 pp [-7.7, -5.9].
  - Ordinal 5-point OR: 0.656.
- **Active distrust rose faster**: 25.1% → 31.3% → 37.9%; +12.8 pp [12.0, 13.6]; h = 0.277; OR = 1.779 [1.708, 1.852].
- **By 2025, trusting and distrusting users are about equal in number.** As a share of *all* professional developers,
  "uses AI but distrusts its accuracy" rose 11.0% → 19.7% → 30.6%, matching "uses and trusts" (31.0%) (`t02`).
- **Within subgroups** (2023→2025, BH across 54 tests; `t11`, `t11b`):
  - **Distrust rose significantly in 18 of 18** experience, role and region subgroups.
  - **The full paradox** (use up *and* trust down, both significant) holds in **12 of 18**.
  - It does not hold where the trust fall is not significant: 0–4 yrs (-2.6 pp [-5.9, 0.7]), Students,
    Management/exec, Ops/infra, MENA and South Asia (-1.8 pp [-4.9, 1.4]).
  - Strongest in North America: trust -11.4 pp, distrust +17.0 pp.
- **Country clustering is modest** (trust ICC 0.017; distrust 0.037). The multilevel OR is 0.737 versus 0.75 fixed-effects (`t09`, `t08`).

**Robustness**
- **The direction is ROBUST.** All checks agree, and the Manski item-non-response bounds exclude zero: trust
  [-8.5, -6.9] pp (`t22`).
- **The 2023 column swap** (`AIBen` holds the trust scale, `AIAcc` holds the multi-select benefits) is handled by meaning, as the codebook requires.
  - `AIBen` has 5 distinct values, 100% on the trust scale.
  - `AIAcc` has 60 distinct values, 0% on the trust scale (`t19`).
  - Naively using 2023 users + planners (as routed) would give 40.1% trust, not 46.2%. That would understate the decline (`t20`).
- **The interpretation is FRAGILE.** "Developers are losing trust" is not established. The user pool more than
  doubled, and new users plausibly trust less.
  - If 2023 users had kept their 46.2% trust, the extra users added by 2025 would need only 29.0% trust to
    produce the observed 38.4% (`t23`).
  - In 2025, trust is 48.0% among daily users but 15.3% among monthly or less frequent users (distrust 27.6% vs 65.4%) (`t23b`).
  - Cross-sectional repeated surveys cannot separate within-person loss of trust from broadening of the user pool,
    and the frequency gradient is itself an association.

## Finding 4 — Senior developers trust AI less, but the gap is stable, not widening (Q4)

Comparisons are standardised for role, region and org mix among users (`t12`, `t13`); 20+ yrs coding is compared with 0–4 yrs.

| Measure | 2023 | 2025 | Change |
|---|---|---|---|
| Trust, 20+ vs 0–4 yrs | 43.2% vs 50.4%; gap -7.2 pp [-9.2, -5.2] | 36.9% vs 46.1%; gap -9.2 pp [-12.2, -6.0] | Widening -2.0 pp [-5.6, 1.8]; interaction LR p = 0.51; BH q = 0.89 |
| Distrust gap | +8.4 pp [6.6, 10.1] | +8.9 pp [5.9, 11.9] | Widening +0.5 pp [-3.1, 3.9] |
| Favourability gap | -1.1 pp [-2.7, 0.4] | -1.2 pp [-4.0, 1.6] | None |

- **The experience gradient is real and roughly constant.** Seniors trust less by about 7–9 pp and distrust more by
  about 8–9 pp. There is **no evidence the gap is widening**.
- Seniors are *not* less favourable in 2023–2025: they use AI while doubting its accuracy.
- **2026 (series B) reversal**: seniors are *more* favourable, 68.2% vs 56.5% (+11.7 pp [7.1, 16.1]). This appears
  only in one year, under new wording and definitions.

**Robustness**
- The trust and distrust gradients are **ROBUST** (significant in every year).
- There is **no clear evidence of widening**, not evidence of equivalence; the CI allows up to about 5.6 pp of widening.
- The 2026 favourability reversal is **FRAGILE** (single year, series break, 2026 completion only 65.5%).

## Finding 5 — Users see AI as somewhat more capable and somewhat more threatening (Q5, Q6)

- **Complex tasks** (P2, among those giving a rating): rated good or very good by 34.2% [33.7, 34.8] (2024) →
  36.8% [36.1, 37.4] (2025).
  - Change: +2.5 pp [1.6, 3.4]; standardised +3.4 pp [2.6, 4.4] (`t01`, `t14b`).
  - 2026 (series B, wording adds "or agents"): 59.2%. This is not comparable.
- **Perceived capability is the strongest correlate of favourability.** Each +1 point on the 5-point complexity rating
  multiplies the adjusted odds of being favourable by 2.17 [2.11, 2.24] (2024), 2.40 [2.32, 2.48] (2025) and
  2.21 [2.12, 2.30] (2026) (`t14`). This is an association within year, not a cause.
- **Job threat** (P3): "Yes, AI threatens my current job" rose 11.5% [11.2, 11.9] → 15.2% [14.7, 15.7], +3.7 pp
  [3.1, 4.3]. Standardised, the rise is identical (+3.7 pp) (`t16`).
  - Significant rises (BH) in 11 of 14 role and region subgroups.
  - Largest rises: Research/education +9.3 pp [4.1, 15.3], Students +7.5 pp, Data/AI +6.3 pp, South Asia +6.2 pp,
    North America +5.6 pp.
  - Not significant: Ops/infra (+0.2 pp), MENA (+2.2 pp) and Sub-Saharan Africa (+2.5 pp).
  - Users and planners report similar threat levels (2025: 15.2% vs 14.8%; `t15`).
  - Threat stays a minority view, about 1 in 7.

**Robustness**
- Complexity +2.5 pp and threat +3.7 pp are **ROBUST to modelling** but small. Both are 2024→2025 contrasts
  affected by 2025 dropout, so they are **moderately fragile**.
- The capability–favourability association is **ROBUST** across 3 years.

---

## Robust vs fragile — summary

| Claim | Verdict | Why |
|---|---|---|
| Use rose 2023→2024 | Robust | All 7 checks; Manski [16.3, 20.8] |
| Use rose 2024→2025 | **Fragile** | Manski [-2.8, 24.9] includes 0 (completion 76.9%) |
| Favourability fell 2023→2025 (all subgroups) | Robust | 9 checks agree; 23 of 23 subgroups |
| Trust fell / distrust rose 2023→2025 | Robust (direction) | 8 and 7 checks agree; bounds exclude 0 |
| "Developers are losing trust" (within-person) | **Fragile** | User-pool dilution can explain it (29.0% implied) |
| Paradox in every subgroup | Partly | 12 of 18 (distrust up in 18 of 18) |
| Experience trust gap about 7–9 pp, not widening | Robust | Widening -2.0 [-5.6, 1.8] |
| Seniors more favourable in 2026 | **Fragile** | Series B, single year |
| Complexity / threat rises | Moderately robust | Small effects; 2025 dropout |
| Any 2025→2026 change | **Not estimable** | Series break |

## Sensitivity analyses (pre-specified S1–S6; `t17`–`t22`)

- **S1 quality exclusions**: including QC-excluded rows (S1a) or applying strict QC (S1b) changes no contrast by
  more than a few tenths of a point (e.g. use 2024→2025 S1b +17.9 pp vs raw +17.6). Base sizes are in `t21c`.
- **S2 dropout**
  - (a) Manski bounds:
    - For adoption they are wide in 2025–2026.
    - For attitudes they cover only *item* non-response among users who reached the block (≤1.2%), so they are narrow.
    - They cannot address users who quit before the AI block.
  - (b) IPW by completion propensity:
    - It uses only age and employment, the only covariates ≥90% observed among non-completers (`t18`).
    - It fixes imbalance on those covariates only.
    - It cannot fix selection on AI attitudes, which is the plausible mechanism.
    - IPW estimates are within a few tenths of a point of the raw estimates.
- **S3 2023 column swap**: handled by meaning (Finding 3); verified empirically in `t19`.
- **S4 routing base**: 2025 asked attitudes of all professionals. With all pros instead of users, favourability is 61.3%
  (vs 73.1%) and trust is 32.5% (vs 38.4%) (`t20`). Trend comparisons therefore use users only.
- **S5 "Unsure" excluded**: same direction (`t01`).
- **S6 model form**: fixed-effects, random-country-intercept and ordinal models agree (`t08`, `t22`).
- **Multiple comparisons**:
  - The 8 primary year-on-year contrasts are Holm-adjusted; all are significant (`t07`).
  - Subgroup and widening tests are BH-adjusted within family (`t11`, `t11c`, `t13`, `t16`).
  - Effect sizes (pp differences, Cohen's h, ORs) are reported throughout. With n in the tens of thousands, very small
    p-values are expected and carry little information on their own.

## Deviations from PLAN.md (declared)

1. `glmer` uses `nAGQ = 0` because Laplace fits did not finish in reasonable time. The ORs match the fixed-effects ORs to 2 decimals.
2. IPW uses only age band and employment, because other covariates are mostly missing among dropouts.
3. Added after seeing results:
   - `t02` (use-while-distrusting share of all pros);
   - `t23`/`t23b` (dilution check and trust by 2025 use frequency). These are exploratory, not confirmatory.
4. Manski bounds for attitudes cover item non-response only (see S2a).

## Open items

- [VERIFY] DATA_NOTES gives a 2026 survey close date that appears to be a typo. This does not affect any estimate.
- [UNRESOLVED] 2025 has a 182-row discrepancy between the published row count and the source file. Our 2025 P1 n is
  25,974. Results describe the documented downloaded file; agreement with the published topline is not claimed.
- [CHECKED 4 November 2026] The official `releases/2026` question bank confirms the `CodeMain` primary-job
  definition, the at-work multi-select `AISelect`, and the conditional `AITrust` wording. See `docs/DATA_NOTES.md`.

Data: Stack Overflow Developer Survey 2023–2026, © Stack Exchange Inc., licensed under ODbL 1.0. Only aggregated
tables are published; no row-level data are written by this stream.
