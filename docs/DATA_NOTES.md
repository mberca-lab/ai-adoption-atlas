# DATA NOTES — AI Adoption Atlas

## 1. Sources

| Year | Official archive | Public results | Results file (rows × cols) | SHA-256 (results) |
|---|---|---|---|---|
| 2023 | https://github.com/StackExchange/Survey/tree/main/packages/archive/2023 | https://survey.stackoverflow.co/2023 | 89,184 × 84 | `828874a3…` |
| 2024 | https://github.com/StackExchange/Survey/tree/main/packages/archive/2024 | https://survey.stackoverflow.co/2024 | 65,437 × 114 | `7f2c2dbf…` |
| 2025 | https://github.com/StackExchange/Survey/tree/main/packages/archive/2025 | https://survey.stackoverflow.co/2025 | 49,191 × 172 | `2d1f6530…` |
| 2026 | https://github.com/StackExchange/Survey/tree/main/packages/archive/2026 | https://survey.stackoverflow.co/2026 | 30,903 × 212 | `ad520b4d…` |

Full hashes are in `scripts/01_harmonise.R` (`RAWFILES`); the script refuses to run on a file whose
hash, shape or year-specific "signature" columns don't match.

### File verification (done before any analysis)
* Every file is the year its name says — confirmed by row/column counts, year-only questions
  (2023 `Q120`/`AIDev*`; 2024 `Check`/`AIEthics`/`AIChallenges`; 2025 `AIAgents`/`AIFrustration`;
  2026 `CodeMain`/`AISentiment`/`AITrust`) and by matching SHA-256 against the official Git LFS pointers.
  No renames were needed.
* **`2024_results.csv` as supplied was truncated** (51.5 MB of 159.5 MB; 19,348 complete rows, last row
  cut mid-field). It was replaced by the official file from
  `https://media.githubusercontent.com/media/StackExchange/Survey/main/packages/archive/2024/results.csv`
  (hash verified). The truncated copy is kept in `data_raw/_quarantine/` — do not use.
* The 2023 file being "large" (151 MB) is genuine: it has the most respondents.

## 2. Licence & attribution (ODbL)

* Database: **Open Database License (ODbL) 1.0** — https://opendatacommons.org/licenses/odbl/1-0/ ;
  individual contents: **Database Contents License (DbCL) 1.0** — https://opendatacommons.org/licenses/dbcl/1-0/
* Attribute in every public output: *"Data: Stack Overflow Developer Survey 2023–2026, Stack Exchange
  Inc., licensed under ODbL 1.0."* with links to the licence and https://survey.stackoverflow.co/.
* **Never commit or redistribute raw data** (`data_raw/`) or the respondent-level derivative
  (`data_clean/`) in this repo; both are gitignored. Only aggregate tables (`docs/tables/`) are committed.
  If a derived *database* is ever published it must itself be released under ODbL (share-alike)
  **[VERIFY with licence text before any such release]**.

## 3. How each survey was collected

All years: online Qualtrics questionnaire, self-selected, recruited mainly through Stack Overflow-owned
channels (onsite banners/messaging, blog, email lists, social media). **No sampling frame, no
weights** — none of the four files contains a weight column (checked).

| Year | Field dates | Qualification rule (from methodology) | Notes |
|---|---|---|---|
| 2023 | 8–19 May 2023 | consent + required questions; ~2,000 dropped | sections 2–5 in random order (AI section position varies); median ~18 min |
| 2024 | 19/20 May–20 Jun 2024 | attention check (`Check`), consent, `MainBranch`; ~20K dropped | median ~21 min |
| 2025 | 29 May–23 Jun 2025 | age, consent, `MainBranch`; ~15K dropped | <2% recruited via Reddit ads; no Under-18 in public file |
| 2026 | opened 23 Jun 2026; close date listed as "2025-07-31" in archive README **[VERIFY — typo]** | consent + employment + Qualtrics bot/duplicate/straight-lining/duration checks, **or** answered all 10 core questions | promoted as "for human developers only"; bot screen can be overridden by the completion rule |

## 4. Data quality — findings and handling

Raw profile (`docs/tables/profile_raw_by_year.csv`): overall cell missingness 34.0 / 39.1 / 52.8 / 70.9 %
(2023→2026); countries 185 / 185 / 177 / 169.

| Check | 2023 | 2024 | 2025 | 2026 | Handling |
|---|---|---|---|---|---|
| Exact duplicates (all cols except `ResponseId`) | 1,203 | 487 | 1,547 | 1,055 | `qc_exact_dup` → **excluded**; all are near-empty partials |
| < 10 items answered | 1,214 | 2,023 | 5,271 | 3,872 | `qc_low_content` → **excluded** |
| Screened out (`MainBranch` = "None of these") | 1,211 | – | – | – | `qc_screened_out` → **excluded** |
| Implausible years (coding years > age−4, pro years > age−12, or > 60) | 68 | 75 | 159 | 130 | `qc_years_implausible` flag; years top-coded at 50 |
| Contradictory AI answers | – | – | 151 (no-plans but uses agents) | 96 (tool + "I don't use") | `qc_ai_inconsistent` flag (kept) |
| Straight-lining on a grid | 915 | 412 | n/a | 2,092 | `qc_straightline` flag, informative only (uniform answers can be genuine) |
| Answered `AISelect` | 87,973 | 60,907 | 33,720 | 17,464 | heavy late-survey dropout in 2025–26 |
| **Default analysis base** (`in_default_base`) | **87,970** | **60,592** | **33,719** | **17,462** | not excluded and answered `AISelect` |

Other issues: 2025–26 `YearsCode`/`WorkExp` are free numbers (2023–24 dropdowns); 2026 `AIToolCount`
contains absurd values (e.g. 999,999,999,999) — never use unbounded; `ConvertedCompYearly` has extreme
outliers in all years (trim/winsorise per analysis); 2025 file has 49,191 rows but the results site
reports 49,009 responses **[VERIFY — 182 difference unexplained]**; country is asked late so missingness
rises to 28–31% in 2025–26 (country estimates are biased toward completers).

## 5. Sampling caveats (read before every chart)

1. **Self-selected, Stack Overflow-engaged sample** — not representative of all developers; heavy SO
   users and English-speakers are over-represented (questionnaire in English only **[VERIFY]**).
2. **No weights** are provided; all estimates are unweighted sample shares. Shifts in who responds
   (e.g. 89K → 31K respondents; falling share of learners) can masquerade as attitude change —
   always compare within subgroups (professional developers, age band, region).
3. **Routing changed every year** (see `CODEBOOK_AI.md`): compare sentiment/trust/complexity **among
   current AI users only**.
4. The "AI user" definition itself shifts (2025 frequency split; 2026 at-work multi-select with no
   "plan" option) — treat 2026 as a series break for adoption.
5. 2025–26 dropout means AI items (late in survey) are answered by a more engaged subset.
6. 2026 is newly fielded with bot controls; 2023–24 relied on attention checks only.
7. Results are descriptive; no causal claims; report n and use uncertainty intervals (e.g. Wilson CIs)
   with the caveat that they ignore self-selection bias.

## 6. Eight most promising analysis questions (given what is truly comparable)

1. **Adoption curve 2023→2024→2025** (`ai_use_status`, CC for 2025): how fast did "using" rise among
   professional developers, and did "plan to" convert into use? (2026 shown separately as series break.)
2. **Favourability among users 2023–2026**: is the decline (≈85% → 77% → 73% → 63% favourable among
   pro-dev users, unweighted) robust within age, experience and region subgroups?
3. **Trust paradox 2023–2025**: trust falls and active *distrust* rises (≈25% → 31% → 38% among
   pro-dev users) even as use rises — who is driving it (experience, role family)?
4. **Experience gradient**: are senior developers (`years_code`) less trusting / less favourable than
   juniors, and is the gap widening year on year?
5. **Complex-task capability 2024–2026** (`ai_complex_5`, users only): has perceived ability on complex
   tasks improved, and does it predict favourability within each year?
6. **Job threat 2024 vs 2025** (`ai_threat`, among users+planners): which roles/regions report rising
   threat perception?
7. **Context of adoption**: adoption and sentiment by `org_size`, `remote_work`, `region` and
   `role_family` within each year (within-year comparisons avoid most cross-year breaks).
8. **Where AI is used in the workflow 2023 vs 2024** (C-CC) with 2025 as a caveated extension: which
   tasks (writing code, debugging, documenting, testing, search) gained most share among users?

Bonus (2026-only, descriptive): agent use, number of tools, cost-driven behaviour, and the new
conditional-trust scale — a cross-section, not a trend.

## 7. Reproducibility

```
"C:\Program Files\R\R-4.6.2\bin\Rscript.exe" scripts/01_harmonise.R
```
Requires R ≥ 4.3 with `data.table`, `arrow`, `countrycode`, `digest`. Outputs
`data_clean/ai_harmonised.parquet` / `.csv` (234,715 rows × 84 cols, gitignored) and
`docs/tables/*.csv` (aggregates). Value maps are strict: any unseen answer option stops the script.
